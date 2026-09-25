// Email through SMTP (e.g. Gmail with an App Password). Used for email
// verification codes and payment receipts.
// Without SMTP settings: DEV_MODE prints the email to the console; otherwise
// sending fails with EMAIL_NOT_CONFIGURED.
const nodemailer = require('nodemailer');
const cfg = require('../config');

const smtp = {
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT) || 587,
  user: process.env.SMTP_USER,
  pass: process.env.SMTP_PASS,
  from: process.env.MAIL_FROM || process.env.SMTP_USER,
};
const configured = () => Boolean(smtp.host && smtp.user && smtp.pass);

let transport;
function transporter() {
  transport ??= nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port,
    secure: smtp.port === 465,
    auth: { user: smtp.user, pass: smtp.pass },
  });
  return transport;
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// Green & white email shell with the tricolour strip (tables: works in Gmail/Outlook).
function layout(title, bodyHtml) {
  return `<!doctype html><html><body style="margin:0;background:#F5FAF7;font-family:Segoe UI,Roboto,Arial,sans-serif;color:#10231A">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5FAF7;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#fff;border-radius:18px;overflow:hidden;border:1px solid #D2E9DC">
<tr><td style="height:4px;background:linear-gradient(90deg,#FF9933 0 33%,#fff 33% 66%,#138808 66%);font-size:0">&nbsp;</td></tr>
<tr><td style="background:#0B5D3B;padding:22px 24px;color:#fff">
<div style="font-size:11px;letter-spacing:1.4px;font-weight:700;color:#8FE3B4">TAMIL NADU · PARTICIPATORY BUDGETING</div>
<div style="font-size:22px;font-weight:800;margin-top:6px">${esc(title)}</div></td></tr>
<tr><td style="padding:24px">${bodyHtml}</td></tr>
<tr><td style="padding:14px 24px;background:#E8F5EE;font-size:11px;color:#5A6E63">Makkal Budget · SDG 11 prototype · not an official Government of Tamil Nadu service.</td></tr>
</table></td></tr></table></body></html>`;
}

async function send({ to, subject, html, text }) {
  if (!configured()) {
    if (cfg.devMode) {
      console.log(`\n✉️  [DEV_MODE] Email to ${to}\nSubject: ${subject}\n${text}\n`);
      return 'dev-mode';
    }
    const err = new Error('Email is not set up on the server (SMTP_HOST / SMTP_USER / SMTP_PASS)');
    err.code = 'EMAIL_NOT_CONFIGURED';
    throw err;
  }
  const info = await transporter().sendMail({ from: `"Makkal Budget" <${smtp.from}>`, to, subject, html, text });
  return info.messageId;
}

function sendVerificationCode(to, code) {
  return send({
    to,
    subject: `${code} is your Makkal Budget verification code`,
    text: `Your Makkal Budget verification code is ${code}. It expires in 5 minutes. Don't share it with anyone.`,
    html: layout('Verify your email', `
<p style="margin:0 0 14px">Use this code to add this email to your Makkal Budget account:</p>
<div style="font-size:34px;font-weight:800;letter-spacing:8px;color:#06402A;background:#E8F5EE;border-radius:14px;padding:16px;text-align:center">${esc(code)}</div>
<p style="margin:14px 0 0;font-size:13px;color:#5A6E63">It expires in 5 minutes. Never share this code. The ward office will never ask for it.
If you didn't request it, you can ignore this email.</p>`),
  });
}

function sendReceipt(to, r) {
  const amount = `₹${Number(r.amount).toLocaleString('en-IN')}`;
  const when = new Date(r.paidAt).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Kolkata' });
  const row = (k, v) => `<tr><td style="padding:8px 0;color:#5A6E63;font-size:13px">${esc(k)}</td><td style="padding:8px 0;text-align:right;font-weight:700;font-size:13px">${esc(v)}</td></tr>`;
  return send({
    to,
    subject: `Receipt: ${amount} to ${r.campaign}`,
    text: `Thank you, ${r.name}! We received ${amount} for "${r.campaign}" (${r.ward}).\n`
      + `Razorpay payment ID: ${r.paymentId}\nDate: ${when}\nReceipt no: ${r.receiptNo}\n`
      + `${r.testMode ? 'Razorpay TEST MODE: no real money was charged.\n' : ''}`,
    html: layout('Payment receipt', `
<p style="margin:0 0 6px">Thank you, <b>${esc(r.name)}</b>!</p>
<p style="margin:0 0 16px;color:#5A6E63">Your contribution to your ward's fundraiser was received.</p>
<div style="text-align:center;background:#E8F5EE;border-radius:14px;padding:18px;margin-bottom:16px">
<div style="font-size:12px;letter-spacing:1px;color:#0B5D3B;font-weight:700">AMOUNT</div>
<div style="font-size:32px;font-weight:800;color:#06402A">${esc(amount)}</div></div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #D2E9DC">
${row('Fundraiser', r.campaign)}${row('Ward', r.ward)}${row('Razorpay payment ID', r.paymentId)}${row('Date', when)}${row('Receipt no.', r.receiptNo)}
${row('Shown to residents as', r.anonymous ? 'Anonymous' : r.name)}
</table>
${r.testMode ? '<p style="margin:16px 0 0;font-size:12px;color:#8A5A00;background:#FFF8E1;padding:10px;border-radius:10px">Razorpay TEST MODE: this was a demo payment and no real money was charged.</p>' : ''}`),
  });
}

module.exports = { configured, send, sendVerificationCode, sendReceipt };
