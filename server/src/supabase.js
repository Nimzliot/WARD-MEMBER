const { createClient } = require('@supabase/supabase-js');
const cfg = require('./config');

// Service-role client: bypasses RLS. Only ever used on the server.
const supabase = createClient(cfg.supabaseUrl, cfg.serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// supabase-js returns { data, error } instead of throwing; this unwraps it.
function must({ data, error }) {
  if (error) throw error;
  return data;
}

module.exports = { supabase, must };
