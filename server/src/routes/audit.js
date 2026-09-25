const express = require('express');
const { supabase, must } = require('../supabase');
const { GENESIS_HASH, voteHash } = require('../lib/hash');

const router = express.Router();

// GET /api/audit/:wardId → anonymised ballot chain + integrity verdict
router.get('/:wardId', async (req, res) => {
  const wardId = Number(req.params.wardId);
  if (!Number.isInteger(wardId)) return res.status(400).json({ error: 'Invalid ward id' });
  if (req.profile.role !== 'admin' && req.profile.ward_id !== wardId) {
    return res.status(403).json({ error: 'You can only audit your own ward' });
  }

  const ward = must(await supabase.from('wards').select('id, name').eq('id', wardId).maybeSingle());
  if (!ward) return res.status(404).json({ error: 'Ward not found' });

  const [votes, proposals] = await Promise.all([
    supabase
      .from('votes')
      .select('id, proposal_ids, voter_hash, prev_hash, hash, created_at')
      .eq('ward_id', wardId)
      .order('created_at', { ascending: true })
      .then(must),
    supabase.from('proposals').select('id, title').eq('ward_id', wardId).then(must),
  ]);
  const titles = Object.fromEntries(proposals.map((p) => [p.id, p.title]));
  const titleOf = (id) => titles[id] || '(removed proposal)';

  // Order by following the links from the genesis hash; anything unreachable
  // (e.g. after a deleted or edited vote) is appended in time order.
  const byPrev = new Map(votes.map((v) => [v.prev_hash, v]));
  const ordered = [];
  const seen = new Set();
  for (let v = byPrev.get(GENESIS_HASH); v && !seen.has(v.id); v = byPrev.get(v.hash)) {
    seen.add(v.id);
    ordered.push(v);
  }
  ordered.push(...votes.filter((v) => !seen.has(v.id)));

  // Re-compute every hash and check every link.
  let expectedPrev = GENESIS_HASH;
  const chain = ordered.map((v, i) => {
    const recomputed = voteHash({
      voterHash: v.voter_hash,
      proposalIds: v.proposal_ids,
      timestamp: new Date(v.created_at).toISOString(), // same format used when hashing
      prevHash: v.prev_hash,
    });
    const hashOk = recomputed === v.hash;
    const linkOk = v.prev_hash === expectedPrev;
    expectedPrev = v.hash;
    return {
      index: i + 1,
      id: v.id,
      proposal_ids: v.proposal_ids,
      proposal_titles: v.proposal_ids.map(titleOf),
      voter_hash: v.voter_hash,
      prev_hash: v.prev_hash,
      hash: v.hash,
      created_at: v.created_at,
      hash_ok: hashOk,
      link_ok: linkOk,
      valid: hashOk && linkOk,
    };
  });

  const firstBad = chain.find((c) => !c.valid);
  res.json({
    ward_id: ward.id,
    ward_name: ward.name,
    total_votes: chain.length,
    valid: !firstBad,
    broken_at: firstBad ? firstBad.index : null,
    head_hash: expectedPrev,
    verified_at: new Date().toISOString(),
    chain,
  });
});

module.exports = router;
