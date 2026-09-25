const express = require('express');
const cfg = require('../config');
const { supabase, must } = require('../supabase');
const { GENESIS_HASH, sha256, voteHash } = require('../lib/hash');

const router = express.Router();
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Hash of the newest vote in the ward. Among the most recent rows, the tip is the
// one whose hash no other row points to (robust even if two votes share a timestamp).
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

// POST /api/votes   { "proposalId": "<uuid>" }
router.post('/', async (req, res) => {
  const { user, profile } = req;
  const proposalId = String(req.body?.proposalId || '');

  // Eligibility: verified by ONE method (email code or SMS code) + completed profile
  if (!user.email_confirmed_at && !profile.phone_verified) {
    return res.status(403).json({ error: 'Verify your email or mobile number first' });
  }
  if (!profile.full_name || !profile.ward_id || !profile.resident_id) {
    return res.status(403).json({ error: 'Complete your profile before voting' });
  }

  if (!UUID_RE.test(proposalId)) return res.status(400).json({ error: 'Invalid proposalId' });
  const proposal = must(
    await supabase.from('proposals').select('id, ward_id, title').eq('id', proposalId).maybeSingle(),
  );
  if (!proposal) return res.status(404).json({ error: 'Proposal not found' });
  if (proposal.ward_id !== profile.ward_id) {
    return res.status(403).json({ error: 'You can only vote on proposals in your own ward' });
  }

  const existing = must(
    await supabase
      .from('votes')
      .select('id')
      .eq('user_id', user.id)
      .eq('ward_id', profile.ward_id)
      .maybeSingle(),
  );
  if (existing) return res.status(409).json({ error: 'You have already voted in this ward' });

  const voterHash = sha256(user.id + cfg.voteSalt);

  // If another vote lands at the same moment, unique(ward_id, prev_hash) rejects
  // one of them. We then re-read the chain tip and try again.
  for (let attempt = 1; attempt <= 5; attempt++) {
    const prevHash = await chainTip(profile.ward_id);
    const timestamp = new Date().toISOString();
    const hash = voteHash({ voterHash, proposalId, timestamp, prevHash });

    const { data, error } = await supabase
      .from('votes')
      .insert({
        user_id: user.id,
        ward_id: profile.ward_id,
        proposal_id: proposalId,
        voter_hash: voterHash,
        prev_hash: prevHash,
        hash,
        created_at: timestamp,
      })
      .select('id, ward_id, proposal_id, voter_hash, prev_hash, hash, created_at')
      .single();

    if (!error) {
      return res.status(201).json({
        message: `Vote recorded for "${proposal.title}"`,
        receipt: { ...data, proposal_title: proposal.title },
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

// GET /api/votes/me → the caller's own vote receipt in their ward (or null)
router.get('/me', async (req, res) => {
  if (!req.profile.ward_id) return res.json({ vote: null });
  const vote = must(
    await supabase
      .from('votes')
      .select('id, ward_id, proposal_id, voter_hash, prev_hash, hash, created_at')
      .eq('user_id', req.user.id)
      .eq('ward_id', req.profile.ward_id)
      .maybeSingle(),
  );
  if (!vote) return res.json({ vote: null });

  const proposal = must(
    await supabase.from('proposals').select('title').eq('id', vote.proposal_id).maybeSingle(),
  );
  res.json({ vote: { ...vote, proposal_title: proposal?.title ?? null } });
});

module.exports = router;
