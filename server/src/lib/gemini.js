const axios = require('axios');
const cfg = require('../config');

// Minimal Gemini REST client. Returns parsed JSON when a responseSchema is given,
// otherwise plain text.
//
// The free tier allows only a few requests per minute *per model*, so we keep a
// chain of models: if one is rate-limited (429) or overloaded (503), we skip it
// for a minute and answer with the next one. Users just see an answer.
const models = [cfg.geminiModel, ...cfg.geminiFallbackModels].filter((m, i, a) => m && a.indexOf(m) === i);
const coolingUntil = new Map(); // model → timestamp

async function callModel(model, { system, contents, schema, temperature, maxTokens }) {
  const generationConfig = { temperature, maxOutputTokens: maxTokens };
  if (schema) {
    generationConfig.responseMimeType = 'application/json';
    generationConfig.responseSchema = schema;
  }
  // 2.5 models "think" by default; turning it off makes answers ~2x faster.
  if (model.startsWith('gemini-2.5')) generationConfig.thinkingConfig = { thinkingBudget: 0 };

  const { data } = await axios.post(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    { systemInstruction: { parts: [{ text: system }] }, contents, generationConfig },
    { headers: { 'x-goog-api-key': cfg.geminiKey }, timeout: 30_000 },
  );

  const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') || '';
  if (!text) {
    const reason = data?.promptFeedback?.blockReason || data?.candidates?.[0]?.finishReason || 'empty';
    throw Object.assign(new Error(`Gemini returned no text (${reason})`), { status: 502 });
  }
  return schema ? JSON.parse(text) : text.trim();
}

async function generate({ system, contents, schema, temperature = 0.4, maxTokens = 1024 }) {
  if (!cfg.geminiKey) {
    throw Object.assign(new Error('AI is not configured on the server (GEMINI_API_KEY missing)'), { status: 503 });
  }

  const now = Date.now();
  const ready = models.filter((m) => (coolingUntil.get(m) || 0) <= now);
  const order = ready.length ? ready : models; // all cooling → try anyway

  let lastError;
  for (const model of order) {
    try {
      return await callModel(model, { system, contents, schema, temperature, maxTokens });
    } catch (err) {
      lastError = err;
      const code = err.response?.status;
      if (code === 429 || code === 503 || code === 404) {
        coolingUntil.set(model, Date.now() + (code === 404 ? 60 * 60_000 : 60_000));
        console.warn(`Gemini ${model} → ${code}, falling back`);
        continue;
      }
      throw err; // bad request, blocked content, invalid JSON… — don't retry
    }
  }
  throw lastError;
}

// Shorthand for a single user message.
const ask = (system, prompt, opts = {}) =>
  generate({ system, contents: [{ role: 'user', parts: [{ text: prompt }] }], ...opts });

module.exports = { generate, ask };
