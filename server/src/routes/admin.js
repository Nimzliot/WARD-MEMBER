// Admin API: full control over wards, proposals, resident ideas, users and ballots.
const express = require('express');
const { supabase, must } = require('../supabase');
const { requireAdmin } = require('../middleware/auth');
const { wardPhase } = require('../lib/phase');
const { UUID_RE, validateProposal, loadProposal, createProposal, replaceItems, writeProposal } = require('../lib/proposals');

const router = express.Router();
router.use(requireAdmin);

const STATUSES = ['pending', 'approved', 'rejected'];
const bad = (res, msg) => res.status(400).json({ error: msg });

// ========================= Wards =========================

// Accepts an ISO date, null (clear) or "now". Returns { ok, value }.
function parseWhen(v) {
  if (v === undefined) return { ok: true, value: undefined };
  if (v === null || v === '') return { ok: true, value: null };
  if (v === 'now') return { ok: true, value: new Date().toISOString() };
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? { ok: false } : { ok: true, value: d.toISOString() };
}

function wardFields(body, { partial }) {
  const { name, budgetPool, votingOpensAt, votingClosesAt } = body || {};
  const fields = {};
  if (name !== undefined || !partial) {
    if (typeof name !== 'string' || name.trim().length < 2) return { error: 'name is required' };
    fields.name = name.trim().slice(0, 80);
  }
  if (budgetPool !== undefined || !partial) {
    if (!Number.isInteger(budgetPool) || budgetPool <= 0) return { error: 'budgetPool must be a positive whole number of rupees' };
    fields.budget_pool = budgetPool;
  }
  const { centerLat, centerLng } = body || {};
  if (centerLat !== undefined || centerLng !== undefined) {
    if (typeof centerLat !== 'number' || typeof centerLng !== 'number') return { error: 'centerLat/centerLng must be numbers' };
    fields.center_lat = centerLat;
    fields.center_lng = centerLng;
  }
  // One Ward Admin per ward: { adminUserId: <uuid> } assigns, null removes.
  const { adminUserId } = body || {};
  if (adminUserId !== undefined) {
    if (adminUserId !== null && !UUID_RE.test(String(adminUserId))) return { error: 'adminUserId must be a user id or null' };
    fields.admin_user_id = adminUserId;
  }
  const opens = parseWhen(votingOpensAt);
  const closes = parseWhen(votingClosesAt);
  if (!opens.ok || !closes.ok) return { error: 'Dates must be ISO timestamps, "now" or null' };
  if (opens.value !== undefined) fields.voting_opens_at = opens.value;
  if (closes.value !== undefined) fields.voting_closes_at = closes.value;
  return { fields };
}

const withPhase = (w) => ({ ...w, phase: wardPhase(w) });

// GET /api/admin/wards → every ward with phase, proposal counts and ballots cast
router.get('/wards', async (req, res) => {
  const [wards, proposals, votes] = await Promise.all([
    supabase.from('wards').select('*').order('id', { ascending: true }).then(must),
    supabase.from('proposals').select('ward_id, status').then(must),
    supabase.from('votes').select('ward_id').then(must),
  ]);
  const adminIds = wards.map((w) => w.admin_user_id).filter(Boolean);
  const admins = adminIds.length
    ? Object.fromEntries(must(await supabase.from('profiles').select('id, full_name').in('id', adminIds)).map((p) => [p.id, p.full_name]))
    : {};
  res.json({
    wards: wards.map((w) => ({
      ...withPhase(w),
      approved: proposals.filter((p) => p.ward_id === w.id && p.status === 'approved').length,
      pending: proposals.filter((p) => p.ward_id === w.id && p.status === 'pending').length,
      ballots: votes.filter((v) => v.ward_id === w.id).length,
      admin_name: w.admin_user_id ? admins[w.admin_user_id] || 'Resident' : null,
    })),
  });
});

// POST /api/admin/wards { name, budgetPool, votingOpensAt?, votingClosesAt? }
router.post('/wards', async (req, res) => {
  const { fields, error } = wardFields(req.body, { partial: false });
  if (error) return bad(res, error);
  const last = must(await supabase.from('wards').select('id').order('id', { ascending: false }).limit(1));
  const { data, error: dbError } = await supabase
    .from('wards').insert({ id: (last[0]?.id ?? 0) + 1, ...fields }).select('*').single();
  if (dbError?.code === '23505') return res.status(409).json({ error: 'A ward with that name already exists' });
  if (dbError?.code === '23514') return bad(res, 'Voting must close after it opens');
  if (dbError) throw dbError;
  res.status(201).json({ message: 'Ward created', ward: withPhase(data) });
});

// PATCH /api/admin/wards/:id { name?, budgetPool?, votingOpensAt?, votingClosesAt? }
// Open now:  { votingOpensAt: "now", votingClosesAt: <future or null> }
// Close now: { votingClosesAt: "now" }
router.patch('/wards/:id', async (req, res) => {
  const id = Number(req.params.id);
  const { fields, error } = wardFields(req.body, { partial: true });
  if (error) return bad(res, error);
  if (!Object.keys(fields).length) return bad(res, 'Nothing to update');

  // "Close now" on a ward that has not opened yet: open it at the same moment minus 1 s
  // so the window stays valid (closes > opens).
  const current = must(await supabase.from('wards').select('*').eq('id', id).maybeSingle());
  if (!current) return res.status(404).json({ error: 'Ward not found' });
  // Ward Admin = a normal resident (never a super admin). Strictly one per ward,
  // and one person can be Ward Admin of only one ward at a time.
  if (fields.admin_user_id) {
    const person = must(await supabase.from('profiles').select('ward_id, resident_id, full_name, role').eq('id', fields.admin_user_id).maybeSingle());
    if (!person) return res.status(404).json({ error: 'User not found' });
    if (person.role === 'admin') return bad(res, 'Super admins can\'t be Ward Admins. Pick a resident.');
    if (!person.ward_id || !person.resident_id) return bad(res, `${person.full_name || 'This person'} hasn't finished their resident profile yet.`);
    const elsewhere = must(await supabase.from('wards').select('id, name').eq('admin_user_id', fields.admin_user_id).neq('id', id).limit(1));
    if (elsewhere.length) {
      return res.status(409).json({
        error: `${person.full_name} is already Ward Admin of ${elsewhere[0].name}. Remove them there first.`,
        code: 'ALREADY_WARD_ADMIN',
      });
    }
  }
  const opens = fields.voting_opens_at !== undefined ? fields.voting_opens_at : current.voting_opens_at;
  const closes = fields.voting_closes_at !== undefined ? fields.voting_closes_at : current.voting_closes_at;
  if (opens && closes && new Date(closes) <= new Date(opens)) {
    if (req.body.votingClosesAt === 'now') fields.voting_opens_at = new Date(Date.parse(closes) - 1000).toISOString();
    else return bad(res, 'Voting must close after it opens');
  }

  const { data, error: dbError } = await supabase.from('wards').update(fields).eq('id', id).select('*').single();
  if (dbError?.code === '23505') return res.status(409).json({ error: 'A ward with that name already exists' });
  if (dbError) throw dbError;
  res.json({ message: 'Ward updated', ward: withPhase(data) });
});

// DELETE /api/admin/wards/:id/votes → empty the ballot box (fresh demo / re-run a vote)
router.delete('/wards/:id/votes', async (req, res) => {
  const id = Number(req.params.id);
  const deleted = must(await supabase.from('votes').delete().eq('ward_id', id).select('id'));
  res.json({ message: `Removed ${deleted.length} ballot${deleted.length === 1 ? '' : 's'}`, removed: deleted.length });
});

// DELETE /api/admin/wards/:id → only when nobody lives or voted there
router.delete('/wards/:id', async (req, res) => {
  const id = Number(req.params.id);
  const [{ count: residents }, { count: ballots }] = await Promise.all([
    supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('ward_id', id),
    supabase.from('votes').select('id', { count: 'exact', head: true }).eq('ward_id', id),
  ]);
  if (residents || ballots) {
    return res.status(409).json({ error: `Ward has ${residents} resident(s) and ${ballots} ballot(s). Move residents and reset votes first.` });
  }
  const deleted = must(await supabase.from('wards').delete().eq('id', id).select('id'));
  if (!deleted.length) return res.status(404).json({ error: 'Ward not found' });
  res.json({ message: 'Ward deleted' });
});

// ========================= Proposals & ideas =========================

/*
POST /api/admin/proposals
{ "wardId": 1, "title": "New bus shelters", "description": "Four shelters on Station Road",
  "category": "Roads & Transport",
  "items": [ { "label": "4 steel shelters", "amount": 480000 }, { "label": "Installation", "amount": 60000 } ] }
*/
router.post('/proposals', async (req, res) => {
  const { wardId } = req.body || {};
  const { errors, value } = validateProposal(req.body);
  if (!Number.isInteger(wardId)) errors.unshift('wardId must be a number');
  if (errors.length) return bad(res, errors.join('; '));

  const ward = must(await supabase.from('wards').select('id').eq('id', wardId).maybeSingle());
  if (!ward) return res.status(404).json({ error: 'Ward not found' });

  const proposal = await createProposal({ ...value, ward_id: wardId, status: 'approved', origin: 'official' });
  res.status(201).json({ message: 'Proposal created', proposal });
});

// PATCH /api/admin/proposals/:id
// { title?, description?, category?, items?, wardId?, status?, reviewNote? }
// Approving / rejecting a resident idea is just { status, reviewNote } (edits allowed in the same call).
router.patch('/proposals/:id', async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) return bad(res, 'Invalid id');
  const existing = await loadProposal(id);
  if (!existing) return res.status(404).json({ error: 'Proposal not found' });

  const { errors, value } = validateProposal(req.body, { partial: true });
  const { wardId, status, reviewNote } = req.body || {};
  if (wardId !== undefined && !Number.isInteger(wardId)) errors.push('wardId must be a number');
  if (status !== undefined && !STATUSES.includes(status)) errors.push(`status must be one of ${STATUSES.join(', ')}`);
  if (errors.length) return bad(res, errors.join('; '));

  const { items, ...fields } = value;
  if (wardId !== undefined && wardId !== existing.ward_id) {
    const ward = must(await supabase.from('wards').select('id').eq('id', wardId).maybeSingle());
    if (!ward) return res.status(404).json({ error: 'Ward not found' });
    fields.ward_id = wardId;
  }
  if (status !== undefined && status !== existing.status) {
    fields.status = status;
    fields.reviewed_at = new Date().toISOString();
  }
  if (reviewNote !== undefined) fields.review_note = reviewNote ? String(reviewNote).trim().slice(0, 500) : null;

  if (Object.keys(fields).length) {
    await writeProposal((f) => supabase.from('proposals').update(f).eq('id', id).select('id'), fields);
  }
  if (items) await replaceItems(id, items);

  res.json({ message: 'Proposal updated', proposal: await loadProposal(id) });
});

// DELETE /api/admin/proposals/:id
// Ballots that included it keep their hashes (the audit still verifies); the
// project simply shows as "(removed proposal)" and no longer counts in results.
router.delete('/proposals/:id', async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) return bad(res, 'Invalid id');
  const deleted = must(await supabase.from('proposals').delete().eq('id', id).select('id, title'));
  if (!deleted.length) return res.status(404).json({ error: 'Proposal not found' });
  const { count } = await supabase.from('votes').select('id', { count: 'exact', head: true }).contains('proposal_ids', [id]);
  res.json({
    message: count ? `Deleted. It was on ${count} ballot(s); those ballots still count for their other projects.` : 'Deleted',
  });
});

// ========================= Funds (all wards) =========================

// GET /api/admin/funds?wardId= → every fundraiser + every contribution (super admin view)
router.get('/funds', async (req, res) => {
  const wardIds = req.query.wardId
    ? [Number(req.query.wardId)]
    : must(await supabase.from('wards').select('id')).map((w) => w.id);
  res.json(await require('./ward_admin').contributionsFor(wardIds));
});

// ========================= Users =========================

// GET /api/admin/users?wardId=1&q=padma → residents (max 200), with whether they voted
router.get('/users', async (req, res) => {
  let query = supabase
    .from('profiles')
    .select('id, full_name, email, phone, phone_verified, ward_id, resident_id, role, created_at')
    .order('created_at', { ascending: false })
    .limit(200);
  if (req.query.wardId) query = query.eq('ward_id', Number(req.query.wardId));
  const q = String(req.query.q || '').trim().replace(/[%,()]/g, '');
  if (q) query = query.or(`full_name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%,resident_id.ilike.%${q}%`);

  const [users, voters, wardAdmins] = await Promise.all([
    query.then(must),
    supabase.from('votes').select('user_id').not('user_id', 'is', null).then(must),
    supabase.from('wards').select('id, admin_user_id').not('admin_user_id', 'is', null).then(must),
  ]);
  const voted = new Set(voters.map((v) => v.user_id));
  const adminOf = Object.fromEntries(wardAdmins.map((w) => [w.admin_user_id, w.id]));
  res.json({
    users: users.map((u) => ({ ...u, has_voted: voted.has(u.id), ward_admin_of: adminOf[u.id] ?? null })),
  });
});

// GET /api/admin/overview → analysis across every ward (super admin dashboard)
router.get('/overview', async (req, res) => {
  const [wards, profiles, votes, proposals] = await Promise.all([
    supabase.from('wards').select('id, name, budget_pool, admin_user_id, voting_opens_at, voting_closes_at').order('id', { ascending: true }).then(must),
    supabase.from('profiles').select('id, ward_id, resident_id, role, full_name').then(must),
    supabase.from('votes').select('ward_id').then(must),
    supabase.from('proposals').select('ward_id, status, total_cost').then(must),
  ]);
  const funds = await require('./ward_admin').contributionsFor(wards.map((w) => w.id));
  const names = Object.fromEntries(profiles.map((p) => [p.id, p.full_name]));
  const rows = wards.map((w) => {
    const residents = profiles.filter((p) => p.ward_id === w.id && p.resident_id && p.role !== 'admin').length;
    const ballots = votes.filter((v) => v.ward_id === w.id).length;
    const fund = funds.wards.find((f) => f.ward_id === w.id) || { raised: 0, supporters: 0, payments: 0 };
    return {
      id: w.id,
      name: w.name,
      phase: wardPhase(w),
      budget_pool: w.budget_pool,
      ward_admin: w.admin_user_id ? names[w.admin_user_id] || 'Resident' : null,
      residents,
      ballots,
      turnout: residents ? ballots / residents : 0,
      approved: proposals.filter((p) => p.ward_id === w.id && p.status === 'approved').length,
      pending_ideas: proposals.filter((p) => p.ward_id === w.id && p.status === 'pending').length,
      requested: proposals.filter((p) => p.ward_id === w.id && p.status === 'approved').reduce((s, p) => s + Number(p.total_cost), 0),
      raised: fund.raised,
      supporters: fund.supporters,
    };
  });
  const sum = (k) => rows.reduce((s, r) => s + r[k], 0);
  res.json({
    totals: {
      wards: rows.length,
      residents: sum('residents'),
      ballots: sum('ballots'),
      pending_ideas: sum('pending_ideas'),
      raised: sum('raised'),
      budget: sum('budget_pool'),
      ward_admins: rows.filter((r) => r.ward_admin).length,
    },
    wards: rows,
  });
});

// PATCH /api/admin/users/:id { role?: 'resident'|'admin', wardId?: number }
router.patch('/users/:id', async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) return bad(res, 'Invalid id');
  const { role, wardId } = req.body || {};
  const fields = {};
  const adminOf = must(await supabase.from('wards').select('id, name').eq('admin_user_id', id).limit(1))[0];
  if (role !== undefined) {
    if (!['resident', 'admin'].includes(role)) return bad(res, 'role must be resident or admin');
    if (id === req.user.id && role !== 'admin') return bad(res, 'You cannot remove your own admin role');
    fields.role = role;
    if (role === 'admin') {
      // Super admins don't belong to a ward and only use the admin panel.
      if (adminOf) {
        return res.status(409).json({ error: `They are Ward Admin of ${adminOf.name}. Remove that first.`, code: 'ALREADY_WARD_ADMIN' });
      }
      fields.ward_id = null;
      fields.resident_id = null;
    }
  }
  if (wardId !== undefined) {
    if (!Number.isInteger(wardId)) return bad(res, 'wardId must be a number');
    if (adminOf && adminOf.id !== wardId) {
      return res.status(409).json({ error: `They are Ward Admin of ${adminOf.name}. Remove that before moving them.`, code: 'ALREADY_WARD_ADMIN' });
    }
    fields.ward_id = wardId;
  }
  if (!Object.keys(fields).length) return bad(res, 'Nothing to update');

  const { data, error } = await supabase.from('profiles').update(fields).eq('id', id).select('*').maybeSingle();
  if (error?.message?.includes('Ward cannot be changed')) {
    return res.status(409).json({ error: 'This resident has voted, so their ward cannot change. Reset that ward\'s votes first.' });
  }
  if (error) throw error;
  if (!data) return res.status(404).json({ error: 'User not found' });
  res.json({ message: 'User updated', user: data });
});

module.exports = router;
