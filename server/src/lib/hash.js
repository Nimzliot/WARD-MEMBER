const crypto = require('crypto');

const GENESIS_HASH = '0'.repeat(64); // prev_hash of the first vote in every ward

const sha256 = (text) => crypto.createHash('sha256').update(String(text)).digest('hex');

// Cryptographically random 6-digit code, e.g. "042917"
const generateOtp = () => crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');

// The user id is mixed in so identical codes for different users hash differently.
const otpHash = (userId, otp) => sha256(`${userId}:${otp}`);

// Constant-time string comparison (avoids timing leaks when checking hashes).
function safeEqual(a, b) {
  const A = Buffer.from(String(a));
  const B = Buffer.from(String(b));
  return A.length === B.length && crypto.timingSafeEqual(A, B);
}

// A ballot's ids in canonical order, joined: 'id1,id2,...'.
// A one-project ballot is just that id, so it hashes exactly like the old single vote.
const ballotKey = (proposalIds) => [...proposalIds].map(String).sort().join(',');

// hash = SHA-256(voter_hash + sorted_proposal_ids.join(',') + timestamp + prev_hash)
const voteHash = ({ voterHash, proposalIds, timestamp, prevHash }) =>
  sha256(voterHash + ballotKey(proposalIds) + timestamp + prevHash);

module.exports = { GENESIS_HASH, sha256, generateOtp, otpHash, safeEqual, ballotKey, voteHash };
