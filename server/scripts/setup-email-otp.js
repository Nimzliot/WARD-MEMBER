// Configures Supabase Auth to email a 6-digit code instead of a magic link.
// Uses the Supabase Management API, which needs a PERSONAL ACCESS TOKEN
// (https://supabase.com/dashboard/account/tokens) from the account that owns
// the project — the service_role key cannot change auth settings.
//
//   SUPABASE_ACCESS_TOKEN=sbp_xxx node scripts/setup-email-otp.js
require('dotenv').config();

const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = new URL(process.env.SUPABASE_URL).hostname.split('.')[0];

const subject = 'Your Ward Budget login code: {{ .Token }}';
const body = `<h2>Your Ward Budget login code</h2>
<p>Enter this code in the app:</p>
<p style="font-size:32px;font-weight:bold;letter-spacing:8px">{{ .Token }}</p>
<p>It expires in 10 minutes. If you didn't request it, ignore this email.</p>`;

async function main() {
  if (!token) throw new Error('Set SUPABASE_ACCESS_TOKEN (sbp_...) first');
  const url = `https://api.supabase.com/v1/projects/${ref}/config/auth`;
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

  const res = await fetch(url, {
    method: 'PATCH',
    headers,
    body: JSON.stringify({
      mailer_otp_length: 6,
      mailer_otp_exp: 600,
      // Existing users → "Magic Link" template; brand-new users → "Confirm signup"
      mailer_subjects_magic_link: subject,
      mailer_templates_magic_link_content: body,
      mailer_subjects_confirmation: subject,
      mailer_templates_confirmation_content: body,
    }),
  });
  if (!res.ok) throw new Error(`Management API ${res.status}: ${await res.text()}`);

  const cfg = await (await fetch(url, { headers })).json();
  console.log(`Project ${ref} updated:`);
  console.log('  mailer_otp_length          =', cfg.mailer_otp_length);
  console.log('  mailer_otp_exp             =', cfg.mailer_otp_exp);
  console.log('  magic link template has code:', cfg.mailer_templates_magic_link_content?.includes('{{ .Token }}'));
  console.log('  confirm signup has code    :', cfg.mailer_templates_confirmation_content?.includes('{{ .Token }}'));
  console.log('  custom SMTP host           =', cfg.smtp_host || '(built-in mailer)');
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
