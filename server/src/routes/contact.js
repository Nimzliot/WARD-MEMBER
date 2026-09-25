// Second contact: every resident has BOTH a verified email and a verified
// mobile. They sign in with whichever they choose; this adds the other one.
// Same rules as login codes: SHA-256 hashed, 5-minute expiry, 3 attempts,
// 60 s resend, 5 per hour; an email/number can't be taken from another account.
const express = require('express');
const cfg = require('../config');
const { supabase, must } = require('../supabase');
const { generateOtp, sha256, safeEqual } = require('../lib/hash');
const { sendOtpSms } = require('../lib/fast2sms');
const mailer = require('../lib/mailer');

const router = express.Router();
const PHONE_RE = /^[6-9]\d{9}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PHONE_EMAIL_DOMAIN = 'phone.wardbudget.app';

const normalizePhone = (raw) => String(raw || '').replace(/\D/g, '').replace(/^91(?=\d{10}$)/, '');
const normalizeEmail = (raw) => String(raw || '').trim().toLowerCase();
const codeHash = (userId, channel, target, otp) => sha256(`${userId}:${channel}:${target}:${otp}`);
const isRealEmail = (e) => Boolean(e) && !e.endsWith(`@${PHONE_EMAIL_DOMAIN}`);

function status(user, profile) {
  return {
    email: isRealEmail(user.email) ? user.email : null,
    email_verified: isRealEmail(user.email) && Boolean(user.email_confirmed_at),
    phone: profile.phone || null,
    phone_verified: Boolean(profile.phone && profile.phone_verified),
  };
}

// GET /api/contact → which contacts are verified
router.get('/', (req, res) => res.json(status(req.user, req.profile)));

async function recentCodes(userId, channel) {
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  return must(await supabase.from('contact_otps').select('created_at').eq('user_id', userId).eq('channel', channel)
    .gte('created_at', hourAgo).order('created_at', { ascending: false }));
}

// Shared "send a code" flow for both channels.
async function sendCode(req, res, channel, target, deliver) {
  const recent = await recentCodes(req.user.id, channel);
  if (recent[0] && Date.now() - new Date(recent[0].created_at).getTime() < cfg.otp.resendMs) {
    const wait = Math.ceil((cfg.otp.resendMs - (Date.now() - new Date(recent[0].created_at).getTime())) / 1000);
    return res.status(429).json({ error: `Please wait ${wait} s before requesting another code`, retryAfter: wait });
  }
  if (recent.length >= cfg.otp.maxPerHour) {
    return res.status(429).json({ error: 'Too many codes requested. Try again in an hour.', code: 'RATE_LIMITED', retry_after: 3600 });
  }
  const otp = generateOtp();
  must(await supabase.from('contact_otps').insert({
    user_id: req.user.id,
    channel,
    target,
    otp_hash: codeHash(req.user.id, channel, target, otp),
    expires_at: new Date(Date.now() + cfg.otp.ttlMs).toISOString(),
  }).select('id'));
  try {
    await deliver(otp);
  } catch (e) {
    await supabase.from('contact_otps').delete().eq('user_id', req.user.id).eq('channel', channel).eq('target', target);
    if (e.code === 'EMAIL_NOT_CONFIGURED') return res.status(503).json({ error: e.message, code: 'EMAIL_NOT_CONFIGURED' });
    console.error(`Contact code (${channel}) failed:`, e.message);
    return res.status(502).json({ error: `Could not send the code. Please try again.`, code: channel === 'phone' ? 'SMS_FAILED' : 'EMAIL_FAILED' });
  }
  res.json({ message: 'Code sent', expiresIn: cfg.otp.ttlMs / 1000, resendIn: cfg.otp.resendMs / 1000, devMode: cfg.devMode });
}

// Shared "check the code" flow. Returns true when the code is correct (and consumed).
async function checkCode(req, res, channel, target, otp) {
  if (!/^\d{6}$/.test(otp)) {
    res.status(400).json({ error: 'Enter the 6-digit code' });
    return false;
  }
  const latest = must(await supabase.from('contact_otps').select('*').eq('user_id', req.user.id).eq('channel', channel)
    .eq('target', target).order('created_at', { ascending: false }).limit(1).maybeSingle());
  if (!latest) {
    res.status(400).json({ error: 'No code requested for this yet. Tap "Send code" first.' });
    return false;
  }
  if (new Date(latest.expires_at) < new Date()) {
    res.status(400).json({ error: 'This code has expired. Request a new one.' });
    return false;
  }
  if (latest.attempts >= cfg.otp.maxAttempts) {
    res.status(429).json({ error: 'Too many wrong attempts. Request a new code.', attemptsLeft: 0 });
    return false;
  }
  if (!safeEqual(codeHash(req.user.id, channel, target, otp), latest.otp_hash)) {
    const attempts = latest.attempts + 1;
    must(await supabase.from('contact_otps').update({ attempts }).eq('id', latest.id).select('id'));
    const left = cfg.otp.maxAttempts - attempts;
    res.status(400).json({
      error: left > 0 ? `Incorrect code. ${left} attempt${left === 1 ? '' : 's'} left.` : 'Too many wrong attempts. Request a new code.',
      attemptsLeft: left,
    });
    return false;
  }
  await supabase.from('contact_otps').delete().eq('user_id', req.user.id).eq('channel', channel);
  return true;
}

// POST /api/contact/email/send { email }
router.post('/email/send', async (req, res) => {
  const email = normalizeEmail(req.body?.email);
  if (!EMAIL_RE.test(email) || email.endsWith(`@${PHONE_EMAIL_DOMAIN}`)) {
    return res.status(400).json({ error: 'Enter a valid email address' });
  }
  if (email === normalizeEmail(req.user.email) && req.user.email_confirmed_at) {
    return res.status(409).json({ error: 'This email is already verified on your account' });
  }
  const taken = must(await supabase.from('profiles').select('id').ilike('email', email).neq('id', req.user.id).limit(1));
  if (taken.length) return res.status(409).json({ error: 'This email is already linked to another account', code: 'CONTACT_TAKEN' });
  return sendCode(req, res, 'email', email, (otp) => mailer.sendVerificationCode(email, otp));
});

// POST /api/contact/email/verify { email, otp } → the account's sign-in email becomes this address
router.post('/email/verify', async (req, res) => {
  const email = normalizeEmail(req.body?.email);
  if (!(await checkCode(req, res, 'email', email, String(req.body?.otp || '').trim()))) return;

  const { error } = await supabase.auth.admin.updateUserById(req.user.id, { email, email_confirm: true });
  if (error) {
    if (/already|exists|registered/i.test(error.message)) {
      return res.status(409).json({ error: 'This email is already linked to another account', code: 'CONTACT_TAKEN' });
    }
    throw error;
  }
  must(await supabase.from('profiles').update({ email }).eq('id', req.user.id).select('id'));
  res.json({ message: 'Email verified. You can now also sign in with it.', email });
});

// POST /api/contact/phone/send { phone }
router.post('/phone/send', async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  if (!PHONE_RE.test(phone)) return res.status(400).json({ error: 'Enter a valid 10-digit Indian mobile number' });
  if (req.profile.phone === phone && req.profile.phone_verified) {
    return res.status(409).json({ error: 'This number is already verified on your account' });
  }
  const taken = must(await supabase.from('profiles').select('id').eq('phone', phone).neq('id', req.user.id).limit(1));
  if (taken.length) return res.status(409).json({ error: 'This number is already linked to another account', code: 'CONTACT_TAKEN' });
  return sendCode(req, res, 'phone', phone, (otp) => sendOtpSms(phone, otp));
});

// POST /api/contact/phone/verify { phone, otp } → phone saved + verified (sign-in by SMS now works)
router.post('/phone/verify', async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  if (!(await checkCode(req, res, 'phone', phone, String(req.body?.otp || '').trim()))) return;
  const { error } = await supabase.from('profiles').update({ phone, phone_verified: true }).eq('id', req.user.id);
  if (error?.code === '23505') {
    return res.status(409).json({ error: 'This number is already linked to another account', code: 'CONTACT_TAKEN' });
  }
  if (error) throw error;
  res.json({ message: 'Mobile number verified. You can now also sign in with it.', phone });
});

module.exports = router;
module.exports.isRealEmail = isRealEmail;
