// Phone login (no email needed): the user picks "Mobile" on the login screen,
// we SMS a 6-digit code through Fast2SMS, and on success hand back a one-time
// Supabase token_hash that the app exchanges for a normal Supabase session.
//
// Phone-only users get a placeholder auth email: 91<phone>@phone.wardbudget.app
// (never mailed — it only exists because Supabase sessions are keyed by user).
const express = require('express');
const cfg = require('../config');
const { supabase, must } = require('../supabase');
const { generateOtp, otpHash, safeEqual } = require('../lib/hash');
const { sendOtpSms } = require('../lib/fast2sms');

const router = express.Router();
const PHONE_RE = /^[6-9]\d{9}$/;
const PHONE_EMAIL_DOMAIN = 'phone.wardbudget.app';

const phoneEmail = (phone) => `91${phone}@${PHONE_EMAIL_DOMAIN}`;

// Accepts "9876543210", "+91 98765 43210", "919876543210" → "9876543210"
const normalizePhone = (raw) =>
  String(raw || '')
    .replace(/\D/g, '')
    .replace(/^91(?=\d{10}$)/, '');

const maskPhone = (phone) => `+91 ${phone.slice(0, 2)}******${phone.slice(-2)}`;

// These routes are public, so cap SMS sends per IP (in-memory, fine for a prototype).
const ipSends = new Map(); // ip → [timestamps]
function ipAllowed(ip) {
  const hourAgo = Date.now() - 60 * 60 * 1000;
  const recent = (ipSends.get(ip) || []).filter((t) => t > hourAgo);
  if (recent.length >= 15) return false;
  recent.push(Date.now());
  ipSends.set(ip, recent);
  return true;
}

// The account for this number: an existing profile that already owns the phone,
// otherwise a phone-only auth user (created on first use).
async function findOrCreatePhoneUser(phone) {
  const owner = must(
    await supabase.from('profiles').select('id').eq('phone', phone).maybeSingle(),
  );
  if (owner) return owner.id;

  const email = phoneEmail(phone);
  const existing = must(
    await supabase.from('profiles').select('id').eq('email', email).maybeSingle(),
  );
  if (existing) return existing.id;

  const { data, error } = await supabase.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { login: 'phone', phone },
  });
  if (error) throw error;
  return data.user.id; // profile row is created by the on_auth_user_created trigger
}

// POST /api/auth/phone/send-otp   { "phone": "9876543210" }
router.post('/send-otp', async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  if (!PHONE_RE.test(phone)) {
    return res.status(400).json({ error: 'Enter a valid 10-digit Indian mobile number' });
  }
  if (!ipAllowed(req.ip)) {
    return res.status(429).json({ error: 'Too many requests from this device. Try again later.' });
  }

  const userId = await findOrCreatePhoneUser(phone);

  // Resend cooldown + hourly cap per account
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const recent = must(
    await supabase
      .from('phone_otps')
      .select('created_at')
      .eq('user_id', userId)
      .gte('created_at', hourAgo)
      .order('created_at', { ascending: false }),
  );
  if (recent.length) {
    const waitMs = cfg.otp.resendMs - (Date.now() - new Date(recent[0].created_at).getTime());
    if (waitMs > 0) {
      const retryAfter = Math.ceil(waitMs / 1000);
      return res
        .status(429)
        .json({ error: `Please wait ${retryAfter}s before requesting a new code`, retryAfter });
    }
  }
  if (recent.length >= cfg.otp.maxPerHour) {
    return res.status(429).json({ error: 'Too many codes requested. Try again in an hour.' });
  }

  // Store only the hash. Only the newest row per user is ever checked.
  const otp = generateOtp();
  const row = must(
    await supabase
      .from('phone_otps')
      .insert({
        user_id: userId,
        phone,
        otp_hash: otpHash(userId, otp),
        expires_at: new Date(Date.now() + cfg.otp.ttlMs).toISOString(),
      })
      .select('id')
      .single(),
  );

  try {
    await sendOtpSms(phone, otp);
  } catch (err) {
    console.error('SMS send failed:', err.response?.data || err.message);
    await supabase.from('phone_otps').delete().eq('id', row.id); // don't burn the cooldown
    return res.status(502).json({ error: 'Could not send the SMS. Please try again.' });
  }

  res.json({
    message: `OTP sent to ${maskPhone(phone)}`,
    expiresIn: cfg.otp.ttlMs / 1000,
    resendIn: cfg.otp.resendMs / 1000,
    devMode: cfg.devMode,
  });
});

// POST /api/auth/phone/verify-otp   { "phone": "9876543210", "otp": "123456" }
// → { token_hash } — the app calls supabase.auth.verifyOTP(type: email, tokenHash)
router.post('/verify-otp', async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  const otp = String(req.body?.otp || '').trim();
  if (!PHONE_RE.test(phone)) return res.status(400).json({ error: 'Invalid mobile number' });
  if (!/^\d{6}$/.test(otp)) return res.status(400).json({ error: 'Enter the 6-digit code' });

  const latest = must(
    await supabase
      .from('phone_otps')
      .select('*')
      .eq('phone', phone)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
  );

  if (!latest) return res.status(400).json({ error: 'No code requested yet. Tap "Send OTP" first.' });
  if (new Date(latest.expires_at) < new Date()) {
    return res.status(400).json({ error: 'This code has expired. Request a new one.' });
  }
  if (latest.attempts >= cfg.otp.maxAttempts) {
    return res.status(429).json({ error: 'Too many wrong attempts. Request a new code.', attemptsLeft: 0 });
  }

  if (!safeEqual(otpHash(latest.user_id, otp), latest.otp_hash)) {
    const attempts = latest.attempts + 1;
    must(await supabase.from('phone_otps').update({ attempts }).eq('id', latest.id));
    const attemptsLeft = cfg.otp.maxAttempts - attempts;
    return res.status(400).json({
      error: attemptsLeft > 0
        ? `Incorrect code. ${attemptsLeft} attempt${attemptsLeft === 1 ? '' : 's'} left.`
        : 'Too many wrong attempts. Request a new code.',
      attemptsLeft,
    });
  }

  const { error: profileError } = await supabase
    .from('profiles')
    .update({ phone, phone_verified: true })
    .eq('id', latest.user_id);
  if (profileError) {
    if (profileError.code === '23505') {
      return res.status(409).json({ error: 'This number is already linked to another account' });
    }
    throw profileError;
  }

  // Mint a one-time login token for this user (no email is sent).
  const { data: userData, error: userError } = await supabase.auth.admin.getUserById(latest.user_id);
  if (userError) throw userError;
  const { data: link, error: linkError } = await supabase.auth.admin.generateLink({
    type: 'magiclink',
    email: userData.user.email,
  });
  if (linkError) throw linkError;

  await supabase.from('phone_otps').delete().eq('user_id', latest.user_id);
  res.json({ message: 'Phone number verified', token_hash: link.properties.hashed_token });
});

module.exports = router;
module.exports.PHONE_EMAIL_DOMAIN = PHONE_EMAIL_DOMAIN;
