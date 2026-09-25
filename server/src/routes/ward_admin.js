// Ward Admin console API: limited control of ONE ward (theirs).
// Super admins (role 'admin') have total control through /api/admin instead;
// they may also act here for any ward with ?wardId=.
// A Ward Admin can: see their ward's overview, review resident ideas, create /
// edit / remove proposals in their ward, and see their ward's contributions.
// They cannot change wards, budgets, voting dates, users or ballots.
const express = require('express');
const { supabase, must } = require('../supabase');
const { wardPhase } = require('../lib/phase');
const {
  UUID_RE, validateProposal, loadProposal, createProposal, replaceItems, writeProposal,
} = require('../lib/proposals');

const router = express.Router();
const STATUSES = ['pending', 'approved', 'rejected'];
const bad = (res, msg) => res.status(400).json({ error: msg, code: 'INVALID' });

// Resolve which ward this request acts on, or refuse.
router.use(async (req, res, next) => {
  const asked = Number(req.query.wardId);
  if (req.profile.role === 'admin' && Number.isInteger(asked) && asked > 0) {
    req.wardId = asked;
    return next();
  }
  const w = must(await supabase.from('wards').select('id').eq('admin_user_id', req.user.id).limit(1));
  if (!w.length) return res.status(403).json({ error: 'Only the Ward Admin can open this page', code: 'ADMIN_ONLY' });
  req.wardId = w[0].id;
  next();
});

// GET /api/ward-admin/overview → headline numbers for the console
router.get('/overview', async (req, res) => {
  const id = req.wardId;
  const [ward, proposals, ballots, residents, campaigns, threads] = await Promise.all([
    supabase.from('wards').select('*').eq('id', id).single().then(must),
    supabase.from('proposals').select('status').eq('ward_id', id).then(must),
    supabase.from('votes').select('id', { count: 'exact', head: true }).eq('ward_id', id),
    supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('ward_id', id).not('resident_id', 'is', null),
    supabase.from('campaigns').select('id, status').eq('ward_id', id).then(must),
    supabase.from('chat_threads').select('unread_admin').eq('ward_id', id).then(must),
  ]);
  const cIds = campaigns.map((c) => c.id);
  const paid = cIds.length
    ? must(await supabase.from('contributions').select('amount').in('campaign_id', cIds).eq('status', 'paid'))
    : [];
  res.json({
    ward: { ...ward, phase: wardPhase(ward) },
    approved: proposals.filter((p) => p.status === 'approved').length,
    pending_ideas: proposals.filter((p) => p.status === 'pending').length,
    ballots: ballots.count ?? 0,
    residents: residents.count ?? 0,
    active_funds: campaigns.filter((c) => c.status === 'active').length,
    raised: paid.reduce((s, p) => s + Number(p.amount), 0),
    unread_messages: threads.reduce((s, t) => s + (t.unread_admin || 0), 0),
  });
});

// GET /api/ward-admin/proposals → every proposal/idea in the ward, any status
router.get('/proposals', async (req, res) => {
  const rows = must(await supabase.from('proposals').select('*, budget_items(id, label, amount)')
    .eq('ward_id', req.wardId).order('created_at', { ascending: false }));
  res.json({ proposals: rows });
});

// POST /api/ward-admin/proposals → new proposal on this ward's ballot
router.post('/proposals', async (req, res) => {
  const { errors, value } = validateProposal(req.body);
  if (errors.length) return bad(res, errors.join('; '));
  const proposal = await createProposal({ ...value, ward_id: req.wardId, status: 'approved', origin: 'official' });
  res.status(201).json({ message: 'Proposal created', proposal });
});

async function ownProposal(req, res) {
  if (!UUID_RE.test(req.params.id)) {
    bad(res, 'Invalid id');
    return null;
  }
  const p = await loadProposal(req.params.id);
  if (!p || p.ward_id !== req.wardId) {
    res.status(404).json({ error: 'Proposal not found in your ward', code: 'NOT_FOUND' });
    return null;
  }
  return p;
}

// PATCH /api/ward-admin/proposals/:id { title?, description?, category?, items?, lat?, lng?, locationName?, status?, reviewNote? }
// (a Ward Admin can't move proposals to another ward)
router.patch('/proposals/:id', async (req, res) => {
  const existing = await ownProposal(req, res);
  if (!existing) return;
  const { errors, value } = validateProposal(req.body, { partial: true });
  const { status, reviewNote } = req.body || {};
  if (status !== undefined && !STATUSES.includes(status)) errors.push(`status must be one of ${STATUSES.join(', ')}`);
  if (errors.length) return bad(res, errors.join('; '));

  const { items, ...fields } = value;
  if (status !== undefined && status !== existing.status) {
    fields.status = status;
    fields.reviewed_at = new Date().toISOString();
  }
  if (reviewNote !== undefined) fields.review_note = reviewNote ? String(reviewNote).trim().slice(0, 500) : null;
  if (Object.keys(fields).length) {
    await writeProposal((f) => supabase.from('proposals').update(f).eq('id', existing.id).select('id'), fields);
  }
  if (items) await replaceItems(existing.id, items);
  res.json({ message: 'Proposal updated', proposal: await loadProposal(existing.id) });
});

// DELETE /api/ward-admin/proposals/:id
router.delete('/proposals/:id', async (req, res) => {
  const existing = await ownProposal(req, res);
  if (!existing) return;
  must(await supabase.from('proposals').delete().eq('id', existing.id).select('id'));
  res.json({ message: 'Deleted' });
});

// GET /api/ward-admin/contributions → every contribution to this ward's fundraisers
router.get('/contributions', async (req, res) => {
  res.json(await contributionsFor([req.wardId]));
});

/** Contributions (all statuses) with campaign + contributor names. Shared with the super-admin view. */
async function contributionsFor(wardIds) {
  const campaigns = must(await supabase.from('campaigns').select('id, ward_id, title, goal, status, created_at')
    .in('ward_id', wardIds).order('created_at', { ascending: false }));
  const ids = campaigns.map((c) => c.id);
  const rows = ids.length
    ? must(await supabase.from('contributions')
      .select('id, campaign_id, user_id, amount, anonymous, status, razorpay_payment_id, created_at, paid_at')
      .in('campaign_id', ids).order('created_at', { ascending: false }).limit(500))
    : [];
  const userIds = [...new Set(rows.map((r) => r.user_id).filter(Boolean))];
  const people = userIds.length
    ? Object.fromEntries(must(await supabase.from('profiles').select('id, full_name, resident_id').in('id', userIds)).map((p) => [p.id, p]))
    : {};
  const byCampaign = Object.fromEntries(campaigns.map((c) => [c.id, c]));
  return {
    campaigns: campaigns.map((c) => {
      const paid = rows.filter((r) => r.campaign_id === c.id && r.status === 'paid');
      return { ...c, raised: paid.reduce((s, r) => s + Number(r.amount), 0), backers: new Set(paid.map((r) => r.user_id)).size };
    }),
    contributions: rows.map((r) => ({
      ...r,
      campaign_title: byCampaign[r.campaign_id]?.title ?? '',
      ward_id: byCampaign[r.campaign_id]?.ward_id ?? null,
      name: people[r.user_id]?.full_name ?? 'Resident',
      resident_ref: people[r.user_id]?.resident_id ?? null,
    })),
  };
}

module.exports = { router, contributionsFor };
