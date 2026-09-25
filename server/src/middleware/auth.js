const { supabase } = require('../supabase');

// Verifies the Supabase access token (Authorization: Bearer <jwt>) and loads the
// caller's profile. Sets req.user (auth user) and req.profile (profiles row).
async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : null;
  if (!token) return res.status(401).json({ error: 'Missing Authorization: Bearer <token>' });

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) return res.status(401).json({ error: 'Invalid or expired session' });

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', data.user.id)
    .maybeSingle();
  if (profileError) throw profileError;
  if (!profile) return res.status(403).json({ error: 'Profile not found. Re-run schema.sql back-fill.' });

  req.user = data.user;
  req.profile = profile;
  next();
}

function requireAdmin(req, res, next) {
  if (req.profile?.role !== 'admin') return res.status(403).json({ error: 'Admins only' });
  next();
}

module.exports = { requireAuth, requireAdmin };
