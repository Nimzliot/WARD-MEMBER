// "Ward Assistant" — Gemini-powered helpers. Every answer is grounded in the
// ward's own data (proposals, budget lines, votes) and never tells people how to vote.
const express = require('express');
const { supabase, must } = require('../supabase');
const gemini = require('../lib/gemini');

const router = express.Router();

const LANGUAGES = { en: 'English', ta: 'Tamil (தமிழ்)', hi: 'Hindi (हिन्दी)' };
const CATEGORIES = [
  'Roads & Transport', 'Water & Sanitation', 'Parks & Environment', 'Street Lighting',
  'Education', 'Health', 'Waste Management', 'Public Safety',
];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const BASE_RULES = `You are "Ward Assistant", a neutral civic helper inside a participatory budgeting app for an Indian municipal ward.
Rules:
- Use ONLY the data given to you. If something is not in the data, say you don't know and suggest asking the ward office.
- Never tell people how to vote or which proposal is better. Present facts and trade-offs neutrally.
- Write money the Indian way: ₹32,55,000 or ₹32.6 lakh or ₹1.08 crore.
- Use short sentences and everyday words a 12-year-old would understand.`;

const lakh = (n) => `₹${(n / 100000).toFixed(n >= 1000000 ? 1 : 2)} lakh`;
const langOf = (code) => LANGUAGES[code] ? code : 'en';

// ---------- tiny in-memory helpers (fine for a prototype) ----------

const cache = new Map(); // key → { value, at }
function cached(key, ttlMs, fn) {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < ttlMs) return Promise.resolve(hit.value);
  return fn().then((value) => {
    cache.set(key, { value, at: Date.now() });
    if (cache.size > 500) cache.delete(cache.keys().next().value);
    return value;
  });
}

const usage = new Map(); // userId → [timestamps]
router.use((req, res, next) => {
  const since = Date.now() - 10 * 60 * 1000;
  const recent = (usage.get(req.user.id) || []).filter((t) => t > since);
  if (recent.length >= 40) {
    return res.status(429).json({ error: 'Ward Assistant is resting. Try again in a few minutes.', code: 'RATE_LIMITED', retry_after: 300 });
  }
  recent.push(Date.now());
  usage.set(req.user.id, recent);
  next();
});

// ---------- data loaders ----------

function canSeeWard(profile, wardId) {
  return profile.role === 'admin' || profile.ward_id === wardId;
}

// Pending / rejected ideas are visible only to admins and the resident who submitted them.
function canSeeProposal(req, p) {
  if (!canSeeWard(req.profile, p.ward_id)) return false;
  return req.profile.role === 'admin' || p.status === 'approved' || p.submitted_by === req.user.id;
}

async function loadProposalContext(proposalId) {
  const proposal = must(
    await supabase.from('proposals').select('*, budget_items(label, amount)').eq('id', proposalId).maybeSingle(),
  );
  if (!proposal) return null;
  const [ward, others] = await Promise.all([
    supabase.from('wards').select('name, budget_pool').eq('id', proposal.ward_id).single().then(must),
    supabase.from('proposals').select('title, category, total_cost').eq('ward_id', proposal.ward_id)
      .eq('status', 'approved').neq('id', proposalId).then(must),
  ]);
  return { proposal, ward, others };
}

function describeProposal({ proposal, ward, others }) {
  const items = [...proposal.budget_items].sort((a, b) => b.amount - a.amount);
  const requested = others.reduce((s, o) => s + o.total_cost, proposal.total_cost);
  return [
    `WARD: ${ward.name}. Total ward budget pool: ₹${ward.budget_pool} (${lakh(ward.budget_pool)}).`,
    `All ${others.length + 1} proposals together ask for ${lakh(requested)}, so not everything can be funded.`,
    '',
    `PROPOSAL: "${proposal.title}" (category: ${proposal.category})`,
    `Description: ${proposal.description || '(none)'}`,
    `Total cost: ₹${proposal.total_cost} (${lakh(proposal.total_cost)}), which is ${Math.round((proposal.total_cost * 100) / ward.budget_pool)}% of the ward pool.`,
    'Budget lines:',
    ...items.map((i) => `- ${i.label}: ₹${i.amount} (${Math.round((i.amount * 100) / proposal.total_cost)}%)`),
    '',
    'OTHER PROPOSALS IN THIS WARD:',
    ...others.map((o) => `- "${o.title}" (${o.category}): ${lakh(o.total_cost)}`),
  ].join('\n');
}

// ---------- 1. Explain a proposal in the resident's language ----------

router.post('/explain', async (req, res) => {
  const { proposalId } = req.body || {};
  const lang = langOf(req.body?.lang);
  if (!UUID_RE.test(String(proposalId))) return res.status(400).json({ error: 'Invalid proposalId' });

  const ctx = await loadProposalContext(proposalId);
  if (!ctx) return res.status(404).json({ error: 'Proposal not found', code: 'NOT_FOUND' });
  if (!canSeeProposal(req, ctx.proposal)) return res.status(403).json({ error: 'Not your ward', code: 'NOT_YOUR_WARD' });

  const key = `explain:${proposalId}:${ctx.proposal.total_cost}:${lang}`;
  const result = await cached(key, 24 * 60 * 60 * 1000, () =>
    gemini.ask(
      `${BASE_RULES}\n- Write every field in ${LANGUAGES[lang]}.`,
      `Explain this proposal to a resident.\n\n${describeProposal(ctx)}`,
      {
        schema: {
          type: 'OBJECT',
          properties: {
            summary: { type: 'STRING', description: 'What this proposal does, 2 short sentences' },
            who_benefits: { type: 'ARRAY', items: { type: 'STRING' }, description: '2-4 groups of residents who benefit' },
            why_this_cost: { type: 'STRING', description: 'Where most of the money goes, citing the biggest budget lines' },
            tradeoff: { type: 'STRING', description: 'Neutral trade-off: share of the pool and what else could not be funded' },
            key_numbers: {
              type: 'ARRAY',
              items: {
                type: 'OBJECT',
                properties: { label: { type: 'STRING' }, value: { type: 'STRING' } },
                required: ['label', 'value'],
              },
              description: 'Exactly 3 short facts, e.g. {label:"Share of pool", value:"43%"}',
            },
          },
          required: ['summary', 'who_benefits', 'why_this_cost', 'tradeoff', 'key_numbers'],
        },
      },
    ));
  res.json({ ...result, lang });
});

// Whole-ward context for the Assistant tab: every proposal, its lines and live votes.
async function describeWard(wardId) {
  const [ward, proposals, votes] = await Promise.all([
    supabase.from('wards').select('name, budget_pool').eq('id', wardId).maybeSingle().then(must),
    supabase.from('proposals').select('id, title, category, description, total_cost, budget_items(label, amount)')
      .eq('ward_id', wardId).eq('status', 'approved').order('created_at').then(must),
    supabase.from('votes').select('proposal_ids').eq('ward_id', wardId).then(must),
  ]);
  if (!ward) return null;
  const counts = {};
  votes.forEach((v) => v.proposal_ids.forEach((id) => { counts[id] = (counts[id] || 0) + 1; }));
  const requested = proposals.reduce((s, p) => s + p.total_cost, 0);
  return [
    `WARD: ${ward.name}. Total ward budget pool: ₹${ward.budget_pool} (${lakh(ward.budget_pool)}).`,
    `${proposals.length} proposals ask for ${lakh(requested)} in total. Ballots cast so far: ${votes.length}.`,
    'Funding rule: most-voted proposals are funded first, while they still fit in the remaining pool.',
    'Split voting: each resident casts ONE ballot and may back several projects, as long as their picks together fit in the ward pool. Ballots are anonymous and hash-chained (tamper-evident audit log).',
    '',
    ...proposals.flatMap((p, i) => [
      `PROPOSAL ${i + 1}: "${p.title}" (${p.category}) — ${lakh(p.total_cost)}, backed on ${counts[p.id] || 0} ballots so far.`,
      `  ${p.description || ''}`,
      ...[...p.budget_items].sort((a, b) => b.amount - a.amount).map((b) => `  - ${b.label}: ₹${b.amount}`),
    ]),
  ].join('\n');
}

// ---------- 2. Ask a question (about one proposal, or the whole ward) ----------

router.post('/ask', async (req, res) => {
  const { proposalId } = req.body || {};
  const question = String(req.body?.question || '').trim().slice(0, 500);
  const history = Array.isArray(req.body?.history) ? req.body.history.slice(-6) : [];
  if (question.length < 2) return res.status(400).json({ error: 'Type a question' });

  let data;
  if (proposalId) {
    if (!UUID_RE.test(String(proposalId))) return res.status(400).json({ error: 'Invalid proposalId' });
    const ctx = await loadProposalContext(proposalId);
    if (!ctx) return res.status(404).json({ error: 'Proposal not found', code: 'NOT_FOUND' });
    if (!canSeeProposal(req, ctx.proposal)) return res.status(403).json({ error: 'Not your ward', code: 'NOT_YOUR_WARD' });
    data = describeProposal(ctx);
  } else {
    const wardId = Number(req.body?.wardId) || req.profile.ward_id;
    if (!canSeeWard(req.profile, wardId)) return res.status(403).json({ error: 'Not your ward', code: 'NOT_YOUR_WARD' });
    data = await describeWard(wardId);
    if (!data) return res.status(404).json({ error: 'Ward not found' });
  }

  const contents = [
    ...history
      .filter((m) => m && typeof m.text === 'string' && m.text.trim())
      .map((m) => ({ role: m.role === 'user' ? 'user' : 'model', parts: [{ text: m.text.slice(0, 1500) }] })),
    { role: 'user', parts: [{ text: question }] },
  ];

  const answer = await gemini.generate({
    system: `${BASE_RULES}
- Answer in the SAME language the resident writes in (English, Tamil or Hindi).
- Keep answers under 100 words. Use plain text, no markdown headings or **bold**; short bullet lines with "•" are fine.

DATA YOU MAY USE:
${data}`,
    contents,
    temperature: 0.3,
    maxTokens: 512,
  });
  res.json({ answer });
});

// ---------- 3. Draft assistant (admin proposals + resident ideas) ----------

// Admins draft for any ward; residents use it to write up an idea for their own ward.
router.post('/draft', async (req, res) => {
  const idea = String(req.body?.idea || '').trim().slice(0, 400);
  const wardId = (req.profile.role === 'admin' && Number(req.body?.wardId)) || req.profile.ward_id;
  if (idea.length < 5) return res.status(400).json({ error: 'Describe the project in a sentence' });

  const ward = must(await supabase.from('wards').select('name, budget_pool').eq('id', wardId).maybeSingle());
  if (!ward) return res.status(404).json({ error: 'Ward not found' });

  const draft = await gemini.ask(
    `You help municipal officials and residents in India write clear budget proposals for residents to vote on.
- Use realistic 2026 Indian municipal costs in whole rupees.
- 3 to 6 budget lines that add up to the total. Include installation/labour and, where sensible, maintenance.
- The title is short (max 60 characters). The description is 1-2 plain sentences saying who benefits.
- Keep the total well below the ward pool of ₹${ward.budget_pool}.`,
    `Ward: ${ward.name}\nIdea: "${idea}"`,
    {
      temperature: 0.5,
      schema: {
        type: 'OBJECT',
        properties: {
          title: { type: 'STRING' },
          category: { type: 'STRING', enum: CATEGORIES },
          description: { type: 'STRING' },
          items: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: { label: { type: 'STRING' }, amount: { type: 'INTEGER' } },
              required: ['label', 'amount'],
            },
          },
        },
        required: ['title', 'category', 'description', 'items'],
      },
    },
  );

  // Never trust model output blindly.
  res.json({
    title: String(draft.title || '').slice(0, 80),
    category: CATEGORIES.includes(draft.category) ? draft.category : CATEGORIES[0],
    description: String(draft.description || '').slice(0, 500),
    items: (draft.items || [])
      .map((i) => ({ label: String(i.label || '').slice(0, 80), amount: Math.round(Number(i.amount)) }))
      .filter((i) => i.label && Number.isFinite(i.amount) && i.amount > 0)
      .slice(0, 12),
  });
});

// ---------- 4. Results insight ----------

router.post('/insight', async (req, res) => {
  const wardId = Number(req.body?.wardId);
  const lang = langOf(req.body?.lang);
  if (!canSeeWard(req.profile, wardId)) return res.status(403).json({ error: 'Not your ward', code: 'NOT_YOUR_WARD' });

  const [ward, proposals, votes] = await Promise.all([
    supabase.from('wards').select('name, budget_pool').eq('id', wardId).maybeSingle().then(must),
    supabase.from('proposals').select('id, title, category, total_cost').eq('ward_id', wardId).eq('status', 'approved').then(must),
    supabase.from('votes').select('proposal_ids').eq('ward_id', wardId).then(must),
  ]);
  if (!ward) return res.status(404).json({ error: 'Ward not found' });
  if (!votes.length) {
    return res.json({ headline: null, summary: null, highlights: [], total_votes: 0 });
  }

  // Same funding rule as the app: most votes first (ties → cheaper), fund while it fits.
  const counts = {};
  votes.forEach((v) => v.proposal_ids.forEach((id) => { counts[id] = (counts[id] || 0) + 1; }));
  const ranked = proposals
    .map((p) => ({ ...p, votes: counts[p.id] || 0 }))
    .sort((a, b) => b.votes - a.votes || a.total_cost - b.total_cost);
  let remaining = ward.budget_pool;
  ranked.forEach((p) => {
    p.funded = p.votes > 0 && p.total_cost <= remaining;
    if (p.funded) remaining -= p.total_cost;
  });

  const snapshot = [
    `WARD: ${ward.name}. Pool ${lakh(ward.budget_pool)}. Ballots cast so far: ${votes.length} (each ballot can back several projects).`,
    'Funding rule: most-voted first; a proposal is funded only if it still fits in the remaining pool.',
    'CURRENT STANDINGS:',
    ...ranked.map((p, i) => `${i + 1}. "${p.title}" (${p.category}) — on ${p.votes} ballots (${Math.round((p.votes * 100) / votes.length)}% of voters), cost ${lakh(p.total_cost)}, ${p.funded ? 'FUNDED' : 'not funded'}`),
    `Unallocated money: ${lakh(remaining)}.`,
  ].join('\n');

  const key = `insight:${wardId}:${lang}:${ranked.map((p) => p.votes).join(',')}`;
  const result = await cached(key, 60 * 60 * 1000, () =>
    gemini.ask(
      `${BASE_RULES}\n- Write every field in ${LANGUAGES[lang]}.\n- Describe the live results; do not predict the winner or recommend anything.`,
      snapshot,
      {
        schema: {
          type: 'OBJECT',
          properties: {
            headline: { type: 'STRING', description: 'Max 8 words' },
            summary: { type: 'STRING', description: '2-3 sentences on what the numbers mean right now' },
            highlights: { type: 'ARRAY', items: { type: 'STRING' }, description: '3 short factual bullet points' },
          },
          required: ['headline', 'summary', 'highlights'],
        },
      },
    ));
  res.json({ ...result, total_votes: votes.length, lang });
});

module.exports = router;
