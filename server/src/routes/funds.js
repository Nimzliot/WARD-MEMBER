// Ward Fund: every ward has ONE fund. Any ward member can send money to it,
// whenever they like (no fundraisers / goals). Payments go through Razorpay
// (test mode): in-app Checkout on Android, a payment page on the web. A
// contribution only counts once Razorpay confirms it.
//
// Storage: contributions reference a per-ward "fund" row in `campaigns`
// (created automatically, marked with FUND_MARK), so no schema change is needed.
const express = require('express');
const { supabase, must } = require('../supabase');
const razorpay = require('../lib/razorpay');
const { UUID_RE } = require('../lib/proposals');
const mailer = require('../lib/mailer');
const { isRealEmail } = require('./contact');

const router = express.Router();
const MIN_AMOUNT = 10;
const MAX_AMOUNT = 100000;
const FUND_MARK = '__ward_fund__';
const LEVELS = [10000, 50000, 100000, 500000, 1000000, 5000000]; // ₹ milestones the ward grows through
const bad = (res, msg, code = 'INVALID') => res.status(400).json({ error: msg, code });
const baseUrl = (req) => `${req.protocol}://${req.get('host')}`;

/** The ward's single fund row (created on first use). */
async function wardFund(wardId) {
  const found = must(await supabase.from('campaigns').select('*').eq('ward_id', wardId).eq('description', FUND_MARK)
    .order('created_at', { ascending: true }).limit(1));
  if (found.length) return found[0];
  return must(await supabase.from('campaigns').insert({
    ward_id: wardId, title: 'Ward Fund', description: FUND_MARK, goal: 1, status: 'active',
  }).select('*').single());
}

// Emails the payment receipt once, to the contributor's VERIFIED email.
// The row is claimed first (receipt_sent_at) so two confirmations can't send twice;
// a failed send releases the claim so the next status check retries.
async function sendReceiptOnce(c) {
  if (c.status !== 'paid' || c.receipt_sent_at || !c.user_id) return;
  const { data: claimed, error } = await supabase.from('contributions')
    .update({ receipt_sent_at: new Date().toISOString() })
    .eq('id', c.id).is('receipt_sent_at', null).select('*').maybeSingle();
  if (error || !claimed) return;
  try {
    const { data: u } = await supabase.auth.admin.getUserById(c.user_id);
    const email = u?.user?.email;
    if (!isRealEmail(email) || !u.user.email_confirmed_at) return; // no verified email
    const [fund, profile] = await Promise.all([
      supabase.from('campaigns').select('ward_id').eq('id', c.campaign_id).single().then(must),
      supabase.from('profiles').select('full_name').eq('id', c.user_id).single().then(must),
    ]);
    const ward = must(await supabase.from('wards').select('name').eq('id', fund.ward_id).single());
    await mailer.sendReceipt(email, {
      name: profile.full_name || 'Resident',
      amount: c.amount,
      campaign: 'Ward Fund',
      ward: ward.name,
      paymentId: c.razorpay_payment_id || '—',
      paidAt: c.paid_at || new Date().toISOString(),
      receiptNo: 'MB-' + c.id.slice(0, 8).toUpperCase(),
      anonymous: c.anonymous,
      testMode: razorpay.isTestMode(),
    });
    await supabase.from('contributions').update({ receipt_email: email }).eq('id', c.id);
  } catch (e) {
    console.error('Receipt email failed:', e.message);
    await supabase.from('contributions').update({ receipt_sent_at: null }).eq('id', c.id);
  }
}

// In-app Checkout: paid once the order has a captured payment (authorized → captured here).
async function refreshOrder(c) {
  const payments = await razorpay.orderPayments(c.razorpay_link_id);
  let paid = payments.find((p) => p.status === 'captured');
  const authorized = payments.find((p) => p.status === 'authorized');
  if (!paid && authorized) paid = await razorpay.capturePayment(authorized.id, authorized.amount);
  if (!paid || paid.status !== 'captured') return c;
  const updated = must(await supabase.from('contributions')
    .update({ status: 'paid', razorpay_payment_id: paid.id, paid_at: new Date().toISOString() })
    .eq('id', c.id).eq('status', 'created').select('*').maybeSingle()) ?? c;
  sendReceiptOnce(updated).catch((e) => console.error('Receipt:', e.message));
  return updated;
}

// Marks a pending contribution paid/expired by asking Razorpay directly.
async function refreshFromRazorpay(c) {
  if (c.status !== 'created' || !c.razorpay_link_id || !razorpay.configured()) return c;
  if (c.razorpay_link_id.startsWith('order_')) return refreshOrder(c);
  const link = await razorpay.fetchPaymentLink(c.razorpay_link_id);
  let update = null;
  if (link.status === 'paid') {
    const paymentId = link.payments?.find((p) => p.status === 'captured')?.payment_id ?? link.payments?.[0]?.payment_id ?? null;
    update = { status: 'paid', razorpay_payment_id: paymentId, paid_at: new Date().toISOString() };
  } else if (link.status === 'expired' || link.status === 'cancelled') {
    update = { status: 'expired' };
  }
  if (!update) return c;
  const updated = must(await supabase.from('contributions').update(update).eq('id', c.id).eq('status', 'created').select('*').maybeSingle()) ?? c;
  sendReceiptOnce(updated).catch((e) => console.error('Receipt:', e.message));
  return updated;
}

// ---------------------------------------------------------------------------
// Public: Razorpay redirects the payer's browser here after paying (web).
// ---------------------------------------------------------------------------
const callback = express.Router();
callback.get('/callback', async (req, res) => {
  const q = req.query;
  const linkId = String(q.razorpay_payment_link_id || '');
  let ok = false;
  try {
    if (razorpay.configured() && razorpay.verifyCallback({
      linkId,
      referenceId: String(q.razorpay_payment_link_reference_id || ''),
      status: String(q.razorpay_payment_link_status || ''),
      paymentId: String(q.razorpay_payment_id || ''),
      signature: q.razorpay_signature,
    })) {
      const c = must(await supabase.from('contributions').select('*').eq('razorpay_link_id', linkId).maybeSingle());
      if (c) ok = (await refreshFromRazorpay(c)).status === 'paid';
    }
  } catch (e) {
    console.error('Razorpay callback error:', e.message);
  }
  res.type('html').send(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Makkal Budget · Payment</title>
<style>body{margin:0;font-family:system-ui,sans-serif;background:linear-gradient(135deg,#0B5D3B,#06402A);color:#fff;min-height:100vh;display:flex;align-items:center;justify-content:center;text-align:center}
.c{padding:32px;max-width:420px}.i{font-size:64px}h1{margin:.2em 0}p{opacity:.85;line-height:1.5}.t{margin-top:24px;font-size:12px;opacity:.6}</style></head>
<body><div class="c"><div class="i">${ok ? '💚' : '⏳'}</div>
<h1>${ok ? 'Thank you!' : 'Confirming your payment'}</h1>
<p>${ok ? 'Your ward fund received it. Go back to the Makkal Budget app.' : 'Go back to the Makkal Budget app. It confirms with Razorpay in a few seconds.'}</p>
<p class="t">${razorpay.isTestMode() ? 'Razorpay TEST MODE · no real money was charged · ' : ''}SDG 11 prototype</p></div></body></html>`);
});

// ---------------------------------------------------------------------------
// Authenticated
// ---------------------------------------------------------------------------

/** Totals + recent supporters for one ward's fund (shared with admin views). */
async function fundSummary(wardId, userId) {
  const fund = await wardFund(wardId);
  const paid = must(await supabase.from('contributions').select('user_id, amount, anonymous, paid_at')
    .eq('campaign_id', fund.id).eq('status', 'paid').order('paid_at', { ascending: false }));
  const ids = [...new Set(paid.filter((p) => !p.anonymous && p.user_id).map((p) => p.user_id))];
  const names = ids.length
    ? Object.fromEntries(must(await supabase.from('profiles').select('id, full_name').in('id', ids)).map((p) => [p.id, p.full_name]))
    : {};
  const raised = paid.reduce((s, p) => s + Number(p.amount), 0);
  return {
    fund_id: fund.id,
    raised,
    payments: paid.length,
    supporters: new Set(paid.map((p) => p.user_id)).size,
    my_total: userId ? paid.filter((p) => p.user_id === userId).reduce((s, p) => s + Number(p.amount), 0) : 0,
    levels: LEVELS,
    recent: paid.slice(0, 12).map((p) => ({
      name: p.anonymous ? 'Anonymous' : (names[p.user_id] || 'Resident'),
      amount: Number(p.amount),
      paid_at: p.paid_at,
    })),
  };
}

// GET /api/funds → my ward's fund
router.get('/', async (req, res) => {
  const wardId = req.profile.ward_id;
  if (!wardId) return res.status(403).json({ error: 'The Ward Fund is for ward members', code: 'NOT_ELIGIBLE' });
  const ward = must(await supabase.from('wards').select('name').eq('id', wardId).single());
  res.json({
    ward_name: ward.name,
    payments_enabled: razorpay.configured(),
    test_mode: razorpay.isTestMode(),
    ...(await fundSummary(wardId, req.user.id)),
  });
});

// Shared checks for sending money; returns { amount, fund } or sends an error.
async function prepare(req, res) {
  if (!razorpay.configured()) {
    res.status(503).json({ error: 'Payments are not set up on the server yet', code: 'PAYMENTS_NOT_CONFIGURED' });
    return null;
  }
  if (!req.profile.ward_id || !req.profile.resident_id) {
    res.status(403).json({ error: 'Only ward members can send money to a ward', code: 'NOT_ELIGIBLE' });
    return null;
  }
  const amount = Number(req.body?.amount);
  if (!Number.isInteger(amount) || amount < MIN_AMOUNT || amount > MAX_AMOUNT) {
    bad(res, `Choose an amount between ₹${MIN_AMOUNT} and ₹${MAX_AMOUNT.toLocaleString('en-IN')}`);
    return null;
  }
  const fund = await wardFund(req.profile.ward_id);
  const contribution = must(await supabase.from('contributions').insert({
    campaign_id: fund.id, user_id: req.user.id, amount, anonymous: Boolean(req.body?.anonymous),
  }).select('*').single());
  const ward = must(await supabase.from('wards').select('name').eq('id', req.profile.ward_id).single());
  return { amount, contribution, wardName: ward.name };
}

const failed = async (res, contributionId, e) => {
  await supabase.from('contributions').update({ status: 'failed' }).eq('id', contributionId);
  console.error('Razorpay error:', e.response?.status, JSON.stringify(e.response?.data || e.message).slice(0, 300));
  res.status(502).json({ error: 'Razorpay could not start the payment. Please try again.', code: 'PAYMENT_FAILED' });
};

// POST /api/funds/checkout { amount, anonymous } → Razorpay order for in-app Checkout (APK)
router.post('/checkout', async (req, res) => {
  const p = await prepare(req, res);
  if (!p) return;
  try {
    const order = await razorpay.createOrder({
      amount: p.amount,
      receipt: `mb_${p.contribution.id.replace(/-/g, '').slice(0, 30)}`,
      notes: { contribution_id: p.contribution.id, ward: p.wardName.slice(0, 200) },
    });
    must(await supabase.from('contributions').update({ razorpay_link_id: order.id }).eq('id', p.contribution.id).select('id'));
    const email = req.user.email && !req.user.email.endsWith('@phone.wardbudget.app') ? req.user.email : '';
    res.status(201).json({
      contributionId: p.contribution.id,
      orderId: order.id,
      keyId: razorpay.keyId(), // public key id; the secret never leaves the server
      amount: order.amount, // paise
      currency: order.currency,
      name: 'Makkal Budget',
      description: `Ward Fund · ${p.wardName}`.slice(0, 250),
      prefill: { name: req.profile.full_name || '', email, contact: req.profile.phone ? `+91${req.profile.phone}` : '' },
      testMode: razorpay.isTestMode(),
    });
  } catch (e) {
    await failed(res, p.contribution.id, e);
  }
});

// POST /api/funds/contribute { amount, anonymous } → Razorpay payment page (web)
router.post('/contribute', async (req, res) => {
  const p = await prepare(req, res);
  if (!p) return;
  try {
    const email = req.user.email && !req.user.email.endsWith('@phone.wardbudget.app') ? req.user.email : undefined;
    const phone = req.profile.phone ? `+91${req.profile.phone}` : undefined;
    const link = await razorpay.createPaymentLink({
      amount: p.amount,
      description: `Makkal Budget · Ward Fund · ${p.wardName}`,
      referenceId: p.contribution.id,
      callbackUrl: `${baseUrl(req)}/api/funds/callback`,
      customer: { name: req.profile.full_name || 'Resident', ...(email && { email }), ...(phone && { contact: phone }) },
    });
    must(await supabase.from('contributions').update({ razorpay_link_id: link.id }).eq('id', p.contribution.id).select('id'));
    res.status(201).json({ contributionId: p.contribution.id, paymentUrl: link.short_url, testMode: razorpay.isTestMode() });
  } catch (e) {
    await failed(res, p.contribution.id, e);
  }
});

// POST /api/funds/contributions/:id/verify { orderId, paymentId, signature } → after Checkout success
router.post('/contributions/:id/verify', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return bad(res, 'Invalid id');
  const c = must(await supabase.from('contributions').select('*').eq('id', req.params.id).maybeSingle());
  if (!c || c.user_id !== req.user.id) return res.status(404).json({ error: 'Contribution not found', code: 'NOT_FOUND' });
  const { orderId, paymentId, signature } = req.body || {};
  if (orderId !== c.razorpay_link_id || !razorpay.verifyPayment({ orderId, paymentId, signature })) {
    return res.status(400).json({ error: 'Payment signature did not match. Nothing was recorded.', code: 'PAYMENT_FAILED' });
  }
  let fresh = c;
  try {
    fresh = await refreshOrder(c); // signature ok → still confirm capture with Razorpay
  } catch (e) {
    console.error('Razorpay order check failed:', e.message);
  }
  res.json({ contribution: fresh });
});

// GET /api/funds/contributions/:id → my contribution, re-checked with Razorpay while pending
router.get('/contributions/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return bad(res, 'Invalid id');
  const c = must(await supabase.from('contributions').select('*').eq('id', req.params.id).maybeSingle());
  if (!c || c.user_id !== req.user.id) return res.status(404).json({ error: 'Contribution not found', code: 'NOT_FOUND' });
  let fresh = c;
  try {
    fresh = await refreshFromRazorpay(c);
  } catch (e) {
    console.error('Razorpay status check failed:', e.message);
  }
  if (fresh.status === 'paid' && !fresh.receipt_sent_at) {
    await sendReceiptOnce(fresh).catch((e) => console.error('Receipt:', e.message));
    fresh = must(await supabase.from('contributions').select('*').eq('id', fresh.id).single());
  }
  res.json({ contribution: fresh });
});

module.exports = { router, callback, fundSummary, wardFund, FUND_MARK };
