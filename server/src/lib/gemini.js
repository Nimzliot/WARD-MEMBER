const axios = require('axios');
const cfg = require('../config');

// Minimal Gemini REST client (Google AI Studio key). Returns parsed JSON when a
// responseSchema is given, otherwise plain text.
async function generate({ system, contents, schema, temperature = 0.4, maxTokens = 1024 }) {
  if (!cfg.geminiKey) {
    const err = new Error('AI is not configured on the server (GEMINI_API_KEY missing)');
    err.status = 503;
    throw err;
  }

  const generationConfig = { temperature, maxOutputTokens: maxTokens };
  if (schema) {
    generationConfig.responseMimeType = 'application/json';
    generationConfig.responseSchema = schema;
  }
  // 2.5 models "think" by default; turning it off makes answers ~2x faster.
  if (cfg.geminiModel.startsWith('gemini-2.5')) generationConfig.thinkingConfig = { thinkingBudget: 0 };

  const { data } = await axios.post(
    `https://generativelanguage.googleapis.com/v1beta/models/${cfg.geminiModel}:generateContent`,
    {
      systemInstruction: { parts: [{ text: system }] },
      contents,
      generationConfig,
    },
    { headers: { 'x-goog-api-key': cfg.geminiKey }, timeout: 30_000 },
  );

  const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') || '';
  if (!text) {
    const reason = data?.promptFeedback?.blockReason || data?.candidates?.[0]?.finishReason || 'empty';
    throw Object.assign(new Error(`Gemini returned no text (${reason})`), { status: 502 });
  }
  return schema ? JSON.parse(text) : text.trim();
}

// Shorthand for a single user message.
const ask = (system, prompt, opts = {}) =>
  generate({ system, contents: [{ role: 'user', parts: [{ text: prompt }] }], ...opts });

module.exports = { generate, ask };
