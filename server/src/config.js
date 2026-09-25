require('dotenv').config();

const devMode = process.env.DEV_MODE === 'true';

const required = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'VOTE_SALT'];
if (!devMode) required.push('FAST2SMS_API_KEY');

const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error(`Missing environment variables: ${missing.join(', ')} (see .env.example)`);
  process.exit(1);
}

module.exports = {
  port: Number(process.env.PORT) || 3000,
  supabaseUrl: process.env.SUPABASE_URL,
  serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  fast2smsKey: process.env.FAST2SMS_API_KEY,
  voteSalt: process.env.VOTE_SALT,
  devMode,
  geminiKey: process.env.GEMINI_API_KEY, // optional — AI features return 503 without it
  geminiModel: process.env.GEMINI_MODEL || 'gemini-2.5-flash',
  // used when the main model is rate-limited (free tier: ~5 requests/min per model)
  geminiFallbackModels: (process.env.GEMINI_FALLBACK_MODELS || 'gemini-flash-lite-latest,gemini-3.5-flash-lite')
    .split(',').map((m) => m.trim()).filter(Boolean),
  otp: {
    ttlMs: 5 * 60 * 1000, // code valid for 5 minutes
    resendMs: 60 * 1000, // resend allowed after 60 seconds
    maxAttempts: 3, // wrong guesses per code
    maxPerHour: 5, // codes per user per hour (stops SMS bombing)
  },
};
