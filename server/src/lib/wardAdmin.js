const { supabase, must } = require('../supabase');

/** Super admins (role 'admin') manage every ward; a Ward Admin manages theirs. */
async function managesWard(req, wardId) {
  if (req.profile.role === 'admin') return true;
  const ward = must(await supabase.from('wards').select('admin_user_id').eq('id', wardId).maybeSingle());
  return Boolean(ward && ward.admin_user_id === req.user.id);
}

/** The ward this user is Ward Admin of (or null). */
async function wardAdminOf(userId) {
  const w = must(await supabase.from('wards').select('id').eq('admin_user_id', userId).limit(1));
  return w[0]?.id ?? null;
}

module.exports = { managesWard, wardAdminOf };
