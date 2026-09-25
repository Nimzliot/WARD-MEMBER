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


/** Order for in-app Razorpay Checkout (Android). [amount] in rupees. */
async function createOrder({ amount, receipt, notes }) {
  const { data } = await api.post('/orders', {
    amount: Math.round(amount * 100),
    currency: 'INR',
    receipt: receipt.slice(0, 40),
    notes,
  }, { auth: auth() });
  return data; // { id: 'order_...', amount, currency, status }
}

/** Payments made against an order (newest first). */
async function orderPayments(orderId) {
  const { data } = await api.get(`/orders/${encodeURIComponent(orderId)}/payments`, { auth: auth() });
  return data.items || [];
}

async function capturePayment(paymentId, amountPaise) {
  const { data } = await api.post(`/payments/${encodeURIComponent(paymentId)}/capture`,
    { amount: amountPaise, currency: 'INR' }, { auth: auth() });
  return data;
}

/** Checkout success signature: HMAC_SHA256(order_id + '|' + payment_id, key_secret). */
function verifyPayment({ orderId, paymentId, signature }) {
  const expected = crypto.createHmac('sha256', cfg.razorpayKeySecret).update(`${orderId}|${paymentId}`).digest('hex');
  return safeEqual(expected, String(signature || ''));
}

const keyId = () => cfg.razorpayKeyId;

module.exports = {
  configured, isTestMode, keyId, createPaymentLink, fetchPaymentLink, verifyCallback,
  createOrder, orderPayments, capturePayment, verifyPayment,
};
