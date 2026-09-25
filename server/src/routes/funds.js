// Ward fundraising: the Ward Admin runs campaigns, residents contribute through
// Razorpay Payment Links (test mode). A contribution only counts once Razorpay
// confirms it (callback signature and/or a server-side status check).
const express = require('express');
const { supabase, must } = require('../supabase');
const razorpay = require('../lib/razorpay');
const { managesWard } = require('../lib/wardAdmin');
const { UUID_RE } = require('../lib/proposals');
const mailer = require('../lib/mailer');
const { isRealEmail } = require('./contact');

const router = express.Router();
const MIN_AMOUNT = 10;
const MAX_AMOUNT = 100000;
const bad = (res, msg, code = 'INVALID') => res.status(400).json({ error: msg, code });
const baseUrl = (req) => `${req.protocol}://${req.get('host')}`;

async function campaignFor(id) {
  return must(await supabase.from('campaigns').select('*').eq('id', id).maybeSingle());
}

// Emails the payment receipt once, to the contributor's VERIFIED email.
// The row is claimed first (receipt_sent_at) so two confirmations can't send twice;
// a failed send releases the claim so the next status check retries.
async function sendReceiptOnce(c) {
  if (c.status !== 'paid' || c.receipt_sent_at || !c.user_id) return;
  const { data: claimed, error } = await supabase.from('contributions')
    .update({ receipt_sent_at: new Date().toISOString() })
    .eq('id', c.id).is('receipt_sent_at', null).select('*').maybeSingle();
  if (error || !claimed) return; // already sent, or migration 005 not run yet
  try {
    const { data: u } = await supabase.auth.admin.getUserById(c.user_id);
    const email = u?.user?.email;
    if (!isRealEmail(email) || !u.user.email_confirmed_at) return; // no verified email: nothing to send to
    const [campaign, profile] = await Promise.all([
      supabase.from('campaigns').select('title, ward_id').eq('id', c.campaign_id).single().then(must),
      supabase.from('profiles').select('full_name').eq('id', c.user_id).single().then(must),
    ]);
    const ward = must(await supabase.from('wards').select('name').eq('id', campaign.ward_id).single());
    await mailer.sendReceipt(email, {
      name: profile.full_name || 'Resident',
      amount: c.amount,
      campaign: campaign.title,
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

// Marks a pending contribution paid/expired by asking Razorpay directly.
async function refreshFromRazorpay(c) {
  if (c.status !== 'created' || !c.razorpay_link_id || !razorpay.configured()) return c;
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
// Public: Razorpay redirects the payer's browser here after paying.
// ---------------------------------------------------------------------------
const callback = express.Router();
callback.get('/callback', async (req, res) => {
  const q = req.query;
  const linkId = String(q.razorpay_payment_link_id || '');
  const referenceId = String(q.razorpay_payment_link_reference_id || '');
  let ok = false;
  try {
    if (razorpay.configured() && razorpay.verifyCallback({
      linkId,
      referenceId,
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
<body><div class="c"><div class="i">${ok ? '✅' : '⏳'}</div>
<h1>${ok ? 'Thank you!' : 'Payment is being confirmed'}</h1>
<p>${ok ? 'Your contribution was received. Go back to the Makkal Budget app to see your receipt.' : 'Go back to the Makkal Budget app. It will confirm the payment with Razorpay in a few seconds.'}</p>
<p class="t">${razorpay.isTestMode() ? 'Razorpay TEST MODE · no real money was charged · ' : ''}SDG 11 prototype</p></div></body></html>`);
});

// ---------------------------------------------------------------------------
// Authenticated routes
// ---------------------------------------------------------------------------

// GET /api/funds?wardId= → campaigns with totals, recent supporters, my contributions
router.get('/', async (req, res) => {
  const wardId = req.profile.role === 'admin' && req.query.wardId ? Number(req.query.wardId) : req.profile.ward_id;
  if (!wardId) return res.json({ campaigns: [], payments_enabled: razorpay.configured(), test_mode: razorpay.isTestMode(), can_manage: false });

  const [campaigns, ward] = await Promise.all([
    supabase.from('campaigns').select('*').eq('ward_id', wardId).order('created_at', { ascending: false }).then(must),
    supabase.from('wards').select('admin_user_id').eq('id', wardId).maybeSingle().then(must),
  ]);
  const ids = campaigns.map((c) => c.id);
  const paid = ids.length
    ? must(await supabase.from('contributions').select('campaign_id, user_id, amount, anonymous, paid_at').in('campaign_id', ids).eq('status', 'paid').order('paid_at', { ascending: false }))
    : [];
  const names = {};
  const userIds = [...new Set(paid.filter((p) => !p.anonymous && p.user_id).map((p) => p.user_id))];
  if (userIds.length) {
    for (const p of must(await supabase.from('profiles').select('id, full_name').in('id', userIds))) names[p.id] = p.full_name;
  }

  res.json({
    payments_enabled: razorpay.configured(),
    test_mode: razorpay.isTestMode(),
    can_manage: req.profile.role === 'admin' || ward?.admin_user_id === req.user.id,
    campaigns: campaigns.map((c) => {
      const mine = paid.filter((p) => p.campaign_id === c.id);
      return {
        ...c,
        raised: mine.reduce((s, p) => s + Number(p.amount), 0),
        backers: new Set(mine.map((p) => p.user_id)).size,
        my_total: mine.filter((p) => p.user_id === req.user.id).reduce((s, p) => s + Number(p.amount), 0),
        recent: mine.slice(0, 8).map((p) => ({
          name: p.anonymous ? 'Anonymous' : (names[p.user_id] || 'Resident'),
          amount: Number(p.amount),
          paid_at: p.paid_at,
        })),
      };
    }),
  });
});

// POST /api/funds { title, description, goal, proposalId?, closesAt?, wardId? }
router.post('/', async (req, res) => {
  const { title, description = '', goal, proposalId, closesAt } = req.body || {};
  const wardId = req.profile.role === 'admin' && Number.isInteger(req.body?.wardId) ? req.body.wardId : req.profile.ward_id;
  if (!wardId || !(await managesWard(req, wardId))) {
    return res.status(403).json({ error: 'Only the Ward Admin can start a fundraiser', code: 'ADMIN_ONLY' });
  }
  if (typeof title !== 'string' || title.trim().length < 3) return bad(res, 'Title is required (min 3 characters)');
  if (!Number.isInteger(goal) || goal < 100) return bad(res, 'Goal must be at least ₹100');
  if (proposalId && !UUID_RE.test(proposalId)) return bad(res, 'Invalid proposal');
  const closes = closesAt ? new Date(closesAt) : null;
  if (closes && Number.isNaN(closes.getTime())) return bad(res, 'Invalid closing date');

  const campaign = must(await supabase.from('campaigns').insert({
    ward_id: wardId,
    title: title.trim().slice(0, 120),
    description: String(description).trim().slice(0, 1000),
    goal,
    proposal_id: proposalId || null,
    closes_at: closes ? closes.toISOString() : null,
    created_by: req.user.id,
  }).select('*').single());
  res.status(201).json({ message: 'Fundraiser started', campaign });
});

// PATCH /api/funds/:id { status?, title?, description?, goal?, closesAt? }
router.patch('/:id', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return bad(res, 'Invalid id');
  const c = await campaignFor(req.params.id);
  if (!c) return res.status(404).json({ error: 'Fundraiser not found', code: 'NOT_FOUND' });
  if (!(await managesWard(req, c.ward_id))) return res.status(403).json({ error: 'Only the Ward Admin can change this', code: 'ADMIN_ONLY' });
  const { status, title, description, goal, closesAt } = req.body || {};
  const fields = {};
  if (status !== undefined) {
    if (!['active', 'closed'].includes(status)) return bad(res, 'status must be active or closed');
    fields.status = status;
  }
  if (title !== undefined) fields.title = String(title).trim().slice(0, 120);
  if (description !== undefined) fields.description = String(description).trim().slice(0, 1000);
  if (goal !== undefined) {
    if (!Number.isInteger(goal) || goal < 100) return bad(res, 'Goal must be at least ₹100');
    fields.goal = goal;
  }
  if (closesAt !== undefined) fields.closes_at = closesAt ? new Date(closesAt).toISOString() : null;
  const campaign = must(await supabase.from('campaigns').update(fields).eq('id', c.id).select('*').single());
  res.json({ message: 'Fundraiser updated', campaign });
});

// POST /api/funds/:id/contribute { amount, anonymous } → { contributionId, paymentUrl }
router.post('/:id/contribute', async (req, res) => {
  if (!razorpay.configured()) {
    return res.status(503).json({ error: 'Payments are not set up on the server yet', code: 'PAYMENTS_NOT_CONFIGURED' });
  }
  if (!UUID_RE.test(req.params.id)) return bad(res, 'Invalid id');
  const amount = Number(req.body?.amount);
  if (!Number.isInteger(amount) || amount < MIN_AMOUNT || amount > MAX_AMOUNT) {
    return bad(res, `Choose an amount between ₹${MIN_AMOUNT} and ₹${MAX_AMOUNT.toLocaleString('en-IN')}`);
  }
  const c = await campaignFor(req.params.id);
  if (!c || c.ward_id !== req.profile.ward_id) return res.status(404).json({ error: 'Fundraiser not found', code: 'NOT_FOUND' });
  if (c.status !== 'active' || (c.closes_at && new Date(c.closes_at) <= new Date())) {
    return res.status(403).json({ error: 'This fundraiser has closed', code: 'FUND_CLOSED' });
  }

  const contribution = must(await supabase.from('contributions').insert({
    campaign_id: c.id,
    user_id: req.user.id,
    amount,
    anonymous: Boolean(req.body?.anonymous),
  }).select('*').single());

  try {
    const email = req.user.email && !req.user.email.endsWith('@phone.wardbudget.app') ? req.user.email : undefined;
    const phone = req.profile.phone ? `+91${req.profile.phone}` : undefined;
    const link = await razorpay.createPaymentLink({
      amount,
      description: `Makkal Budget · ${c.title}`,
      referenceId: contribution.id,
      callbackUrl: `${baseUrl(req)}/api/funds/callback`,
      customer: { name: req.profile.full_name || 'Resident', ...(email && { email }), ...(phone && { contact: phone }) },
    });
    must(await supabase.from('contributions').update({ razorpay_link_id: link.id }).eq('id', contribution.id).select('id'));
    res.status(201).json({
      contributionId: contribution.id,
      paymentUrl: link.short_url,
      testMode: razorpay.isTestMode(),
    });
  } catch (e) {
    await supabase.from('contributions').update({ status: 'failed' }).eq('id', contribution.id);
    console.error('Razorpay error:', e.response?.status, JSON.stringify(e.response?.data || e.message).slice(0, 300));
    res.status(502).json({ error: 'Razorpay could not start the payment. Please try again.', code: 'PAYMENT_FAILED' });
  }
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
    await sendReceiptOnce(fresh).catch((e) => console.error('Receipt:', e.message)); // retry a failed send
    fresh = must(await supabase.from('contributions').select('*').eq('id', fresh.id).single());
  }
  res.json({ contribution: fresh });
});

module.exports = { router, callback };
