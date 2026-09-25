// Test helper: logs in with email OTP (like the app will) and saves the
// Supabase access token to server/.token so you can call the API by hand.
//   npm run token -- you@example.com
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const readline = require('readline/promises');
const { createClient } = require('@supabase/supabase-js');

async function main() {
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = process.env;
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error('Set SUPABASE_URL and SUPABASE_ANON_KEY in server/.env');
  }
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  const email = (process.argv[2] || (await rl.question('Email: '))).trim();
  const { error } = await supabase.auth.signInWithOtp({ email });
  if (error) throw error;
  console.log(`Code sent to ${email}. Check your inbox.`);

  const token = (await rl.question('6-digit code: ')).trim();
  rl.close();
  const { data, error: verifyError } = await supabase.auth.verifyOtp({ email, token, type: 'email' });
  if (verifyError) throw verifyError;

  const file = path.join(__dirname, '..', '.token');
  fs.writeFileSync(file, data.session.access_token);
  console.log(`\nLogged in as ${data.user.id}`);
  console.log(`Access token (valid ~1 hour) saved to ${file}`);
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
