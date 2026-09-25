const express = require('express');
const cfg = require('../config');
const { supabase, must } = require('../supabase');
const { GENESIS_HASH, sha256, ballotKey, voteHash } = require('../lib/hash');
const { wardPhase, fmtDate } = require('../lib/phase');
const { UUID_RE } = require('../lib/proposals');

const router = express.Router();
const RECEIPT_COLS = 'id, ward_id, proposal_ids, voter_hash, prev_hash, hash, created_at';

// Hash of the newest ballot in the ward. Among the most recent rows, the tip is the
// one whose hash no other row points to (robust even if two ballots share a timestamp).
async function chainTip(wardId) {
  const rows = must(
    await supabase
      .from('votes')
      .select('hash, prev_hash')
      .eq('ward_id', wardId)
      .order('created_at', { ascending: false })
      .limit(10),
  );
  if (!rows.length) return GENESIS_HASH;
  const referenced = new Set(rows.map((r) => r.prev_hash));
  return (rows.find((r) => !referenced.has(r.hash)) || rows[0]).hash;
}

// Adds titles + total cost to a ballot row for the receipt.
async function withTitles(vote) {
  const proposals = must(
    await supabase.from('proposals').select('id, title, total_cost').in('id', vote.proposal_ids),
  );
  const byId = Object.fromEntries(proposals.map((p) => [p.id, p]));
  return {
    ...vote,
    proposal_titles: vote.proposal_ids.map((id) => byId[id]?.title ?? '(removed proposal)'),
    total_cost: vote.proposal_ids.reduce((s, id) => s + (byId[id]?.total_cost ?? 0), 0),
  };
}

// POST /api/votes   { "proposalIds": ["<uuid>", ...] }   (a single "proposalId" also works)
// Split voting: back as many approved projects as you like, as long as their
// combined cost fits in the ward's budget pool. One ballot per resident, final.
router.post('/', async (req, res) => {
  const { user, profile } = req;
  const raw = Array.isArray(req.body?.proposalIds)
    ? req.body.proposalIds
    : req.body?.proposalId ? [req.body.proposalId] : [];
  const proposalIds = [...new Set(raw.map(String))];

  // Eligibility: verified by ONE method (email code or SMS code) + completed profile
  if (!user.email_confirmed_at && !profile.phone_verified) {
    return res.status(403).json({ error: 'Verify your email or mobile number first' });
  }
  if (!profile.full_name || !profile.ward_id || !profile.resident_id) {
    return res.status(403).json({ error: 'Complete your profile before voting' });
  }

  if (!proposalIds.length) return res.status(400).json({ error: 'Pick at least one project' });
  if (proposalIds.length > 50) return res.status(400).json({ error: 'Too many projects on one ballot' });
  if (!proposalIds.every((id) => UUID_RE.test(id))) return res.status(400).json({ error: 'Invalid proposal id' });

  // Voting window
  const ward = must(
    await supabase.from('wards').select('id, budget_pool, voting_opens_at, voting_closes_at')
      .eq('id', profile.ward_id).maybeSingle(),
  );
  if (!ward) return res.status(404).json({ error: 'Ward not found' });
  const phase = wardPhase(ward);
  if (phase === 'upcoming') {
    return res.status(403).json({ error: `Voting opens on ${fmtDate(ward.voting_opens_at)}` });
  }
  if (phase === 'closed') {
    return res.status(403).json({ error: `Voting closed on ${fmtDate(ward.voting_closes_at)}. Results are final.` });
  }

  // Every project must be an approved proposal in the resident's own ward
  const proposals = must(
    await supabase.from('proposals').select('id, ward_id, title, status, total_cost').in('id', proposalIds),
  );
  if (proposals.length !== proposalIds.length) return res.status(404).json({ error: 'A project on your ballot no longer exists' });
  if (proposals.some((p) => p.ward_id !== profile.ward_id)) {
    return res.status(403).json({ error: 'You can only vote on proposals in your own ward' });
  }
  if (proposals.some((p) => p.status !== 'approved')) {
    return res.status(403).json({ error: 'A project on your ballot is not on the ballot any more' });
  }

  // Budget cap: the ballot must be something the ward could actually afford
  const totalCost = proposals.reduce((s, p) => s + p.total_cost, 0);
  if (totalCost > ward.budget_pool) {
    return res.status(400).json({
      error: `Your picks cost ₹${totalCost.toLocaleString('en-IN')}, more than the ward's ₹${ward.budget_pool.toLocaleString('en-IN')} budget`,
    });
  }

  const existing = must(
    await supabase.from('votes').select('id').eq('user_id', user.id).eq('ward_id', profile.ward_id).maybeSingle(),
  );
  if (existing) return res.status(409).json({ error: 'You have already voted in this ward' });

  const voterHash = sha256(user.id + cfg.voteSalt);
  const sortedIds = ballotKey(proposalIds).split(','); // canonical order = the order that is hashed

  // If another ballot lands at the same moment, unique(ward_id, prev_hash) rejects
  // one of them. We then re-read the chain tip and try again.
  for (let attempt = 1; attempt <= 5; attempt++) {
    const prevHash = await chainTip(profile.ward_id);
    const timestamp = new Date().toISOString();
    const hash = voteHash({ voterHash, proposalIds: sortedIds, timestamp, prevHash });

    const { data, error } = await supabase
      .from('votes')
      .insert({
        user_id: user.id,
        ward_id: profile.ward_id,
        proposal_ids: sortedIds,
        voter_hash: voterHash,
        prev_hash: prevHash,
        hash,
        created_at: timestamp,
      })
      .select(RECEIPT_COLS)
      .single();

    if (!error) {
      return res.status(201).json({
        message: `Ballot recorded for ${sortedIds.length} project${sortedIds.length === 1 ? '' : 's'}`,
        receipt: await withTitles(data),
      });
    }
    if (error.code === '23505' && error.message.includes('user_id')) {
      return res.status(409).json({ error: 'You have already voted in this ward' });
    }
    if (error.code !== '23505') throw error;
    // prev_hash collision → chain moved on; retry
  }

  res.status(503).json({ error: 'Too many votes at once. Please try again.' });
});

// GET /api/votes/me → the caller's own ballot receipt in their ward (or null)
router.get('/me', async (req, res) => {
  if (!req.profile.ward_id) return res.json({ vote: null });
  const vote = must(
    await supabase
      .from('votes')
      .select(RECEIPT_COLS)
      .eq('user_id', req.user.id)
      .eq('ward_id', req.profile.ward_id)
      .maybeSingle(),
  );
  res.json({ vote: vote ? await withTitles(vote) : null });
});

module.exports = router;
