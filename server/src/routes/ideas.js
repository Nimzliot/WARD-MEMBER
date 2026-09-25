// Resident ideas: residents propose projects for their own ward; an admin approves
// (→ it goes on the ballot) or rejects them with a note.
const express = require('express');
const { supabase, must } = require('../supabase');
const { wardPhase } = require('../lib/phase');
const { UUID_RE, validateProposal, createProposal } = require('../lib/proposals');

const router = express.Router();
const MAX_PENDING = 3;

// POST /api/ideas   { title, category, description, items: [{label, amount}] }
router.post('/', async (req, res) => {
  const { user, profile } = req;
  if (!profile.full_name || !profile.ward_id || !profile.resident_id) {
    return res.status(403).json({ error: 'Complete your profile before submitting ideas' });
  }

  const { errors, value } = validateProposal(req.body);
  if (errors.length) return res.status(400).json({ error: errors.join('; ') });

  const ward = must(
    await supabase.from('wards').select('voting_opens_at, voting_closes_at').eq('id', profile.ward_id).single(),
  );
  if (wardPhase(ward) === 'closed') {
    return res.status(403).json({ error: 'Voting has closed in your ward, so new ideas are not being accepted' });
  }

  const { count } = await supabase
    .from('proposals')
    .select('id', { count: 'exact', head: true })
    .eq('submitted_by', user.id)
    .eq('status', 'pending');
  if ((count ?? 0) >= MAX_PENDING) {
    return res.status(429).json({ error: `You already have ${MAX_PENDING} ideas waiting for review` });
  }

  const idea = await createProposal({
    ...value,
    ward_id: profile.ward_id,
    status: 'pending',
    origin: 'resident',
    submitted_by: user.id,
  });
  res.status(201).json({ message: 'Idea sent to the ward office for review', idea });
});

// GET /api/ideas/mine → the caller's ideas, newest first, with review status/notes
router.get('/mine', async (req, res) => {
  const ideas = must(
    await supabase
      .from('proposals')
      .select('*, budget_items(id, label, amount)')
      .eq('submitted_by', req.user.id)
      .order('created_at', { ascending: false }),
  );
  res.json({ ideas });
});

// DELETE /api/ideas/:id → withdraw your own idea while it is still pending
router.delete('/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(400).json({ error: 'Invalid id' });
  const idea = must(
    await supabase.from('proposals').select('id, submitted_by, status').eq('id', req.params.id).maybeSingle(),
  );
  if (!idea || idea.submitted_by !== req.user.id) return res.status(404).json({ error: 'Idea not found' });
  if (idea.status !== 'pending') return res.status(409).json({ error: 'Only pending ideas can be withdrawn' });
  must(await supabase.from('proposals').delete().eq('id', idea.id).select('id'));
  res.json({ message: 'Idea withdrawn' });
});

module.exports = router;
