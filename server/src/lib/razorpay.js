// Razorpay Payment Links (test mode). Links open in any browser, so the same
// flow works in the Android app and on the web without a native SDK.
// Payment status is always confirmed server-side with Razorpay before it counts.
const crypto = require('crypto');
const axios = require('axios');
const cfg = require('../config');
const { safeEqual } = require('./hash');

const api = axios.create({ baseURL: 'https://api.razorpay.com/v1', timeout: 20000 });

const configured = () => Boolean(cfg.razorpayKeyId && cfg.razorpayKeySecret);
const auth = () => ({ username: cfg.razorpayKeyId, password: cfg.razorpayKeySecret });
const isTestMode = () => String(cfg.razorpayKeyId || '').startsWith('rzp_test_');

/**
 * Creates a payment link. [amount] in rupees.
 * Returns { id, short_url, status }.
 */
async function createPaymentLink({ amount, description, referenceId, callbackUrl, customer }) {
  const { data } = await api.post(
    '/payment_links',
    {
      amount: Math.round(amount * 100), // paise
      currency: 'INR',
      accept_partial: false,
      description: description.slice(0, 2048),
      reference_id: referenceId.slice(0, 40),
      customer,
      notify: { sms: false, email: false },
      reminder_enable: false,
      callback_url: callbackUrl,
      callback_method: 'get',
      expire_by: Math.floor(Date.now() / 1000) + 60 * 60, // 1 hour
    },
    { auth: auth() },
  );
  return data;
}

async function fetchPaymentLink(id) {
  const { data } = await api.get(`/payment_links/${encodeURIComponent(id)}`, { auth: auth() });
  return data;
}

/** Verifies the signature Razorpay adds to the callback redirect. */
function verifyCallback({ linkId, referenceId, status, paymentId, signature }) {
  const expected = crypto
    .createHmac('sha256', cfg.razorpayKeySecret)
    .update(`${linkId}|${referenceId}|${status}|${paymentId}`)
    .digest('hex');
  return safeEqual(expected, String(signature || ''));
}

module.exports = { configured, isTestMode, createPaymentLink, fetchPaymentLink, verifyCallback };
