const axios = require('axios');
const cfg = require('../config');

const URL = 'https://www.fast2sms.com/dev/bulkV2';

async function post(body) {
  const { data } = await axios.post(URL, body, {
    headers: { authorization: cfg.fast2smsKey, 'Content-Type': 'application/json' },
    timeout: 10_000,
    validateStatus: () => true, // Fast2SMS puts the reason in the body; read it ourselves
  });
  return data;
}

// Sends a 6-digit OTP through Fast2SMS.
// 1) OTP route (cheapest) — needs "website verification" on the Fast2SMS dashboard.
// 2) If the account isn't verified yet (status_code 996), fall back to the Quick SMS
//    route, which works without verification but costs more per SMS.
// With DEV_MODE=true the code is only printed to the console (no SMS credits used).
async function sendOtpSms(phone, otp) {
  if (cfg.devMode) {
    console.log(`\n📱 [DEV_MODE] OTP for +91 ${phone}: ${otp}\n`);
    return 'dev-mode';
  }

  let data = await post({ route: 'otp', variables_values: otp, numbers: phone });
  if (data?.return === true) return data.request_id;

  if (data?.status_code === 996) {
    console.warn('Fast2SMS OTP route needs website verification — using Quick SMS route instead');
    data = await post({
      route: 'q',
      message: `${otp} is your Ward Budget login code. It expires in 5 minutes. Do not share it.`,
      language: 'english',
      flash: 0,
      numbers: phone,
    });
    if (data?.return === true) return data.request_id;
  }

  throw new Error(`Fast2SMS rejected the request: ${JSON.stringify(data)}`);
}

module.exports = { sendOtpSms };
