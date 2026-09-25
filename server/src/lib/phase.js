// Voting window of a ward. null opens_at = already open, null closes_at = no deadline.
//   upcoming → before voting_opens_at (residents can still submit ideas)
//   open     → ballots accepted
//   closed   → results are final
function wardPhase(ward, now = new Date()) {
  const opens = ward.voting_opens_at ? new Date(ward.voting_opens_at) : null;
  const closes = ward.voting_closes_at ? new Date(ward.voting_closes_at) : null;
  if (closes && now >= closes) return 'closed';
  if (opens && now < opens) return 'upcoming';
  return 'open';
}

const fmtDate = (iso) =>
  new Date(iso).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Kolkata' });

module.exports = { wardPhase, fmtDate };
