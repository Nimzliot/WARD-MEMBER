const axios = require('axios');
const cfg = require('../config');

// Sends a 6-digit OTP through Fast2SMS's OTP route.
// With DEV_MODE=true the code is only printed to the console (no SMS credits used).
async function sendOtpSms(phone, otp) {
  if (cfg.devMode) {
    console.log(`\n📱 [DEV_MODE] OTP for +91 ${phone}: ${otp}\n`);
    return 'dev-mode';
  }

  const { data } = await axios.post(
    'https://www.fast2sms.com/dev/bulkV2',
    { route: 'otp', variables_values: otp, numbers: phone },
    {
      headers: { authorization: cfg.fast2smsKey, 'Content-Type': 'application/json' },
      timeout: 10_000,
    },
  );

  if (!data || data.return !== true) {
    throw new Error(`Fast2SMS rejected the request: ${JSON.stringify(data)}`);
  }
  return data.request_id;
}

module.exports = { sendOtpSms };
