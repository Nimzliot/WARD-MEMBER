const express = require('express');
const cors = require('cors');
const cfg = require('./config');
const { requireAuth } = require('./middleware/auth');

const app = express();
app.set('trust proxy', 1); // behind Render / ngrok: req.ip = real client IP (used by the SMS rate limit)
app.use(cors());
app.use(express.json({ limit: '100kb' }));

// Tiny request logger
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => console.log(`${req.method} ${req.originalUrl} → ${res.statusCode} (${Date.now() - start}ms)`));
  next();
});

// Public routes: health check (used by Render) and phone login (the user has no session yet).
app.get('/api/health', (req, res) => res.json({ ok: true, devMode: cfg.devMode, time: new Date().toISOString() }));
app.use('/api/auth/phone', require('./routes/phone'));

// Everything below needs a Supabase JWT.
app.use('/api', requireAuth);
app.use('/api/votes', require('./routes/votes'));
app.use('/api/audit', require('./routes/audit'));
app.use('/api/ideas', require('./routes/ideas'));
app.use('/api/admin', require('./routes/admin'));
app.use('/api/ai', require('./routes/ai'));

app.use((req, res) => res.status(404).json({ error: 'Not found' }));

// Express 5 forwards errors thrown in async handlers here.
app.use((err, req, res, next) => {
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'Invalid JSON body' });
  // Gemini errors (see lib/gemini.js): missing key, quota, blocked, bad JSON
  if (err.status === 503) return res.status(503).json({ error: err.message });
  if (err.config?.url?.includes('generativelanguage') || err.status === 502 || err instanceof SyntaxError) {
    console.error('Gemini error:', err.response?.status, JSON.stringify(err.response?.data || err.message).slice(0, 300));
    const busy = err.response?.status === 429;
    return res.status(502).json({ error: busy ? 'Ward Assistant is busy. Try again in a minute.' : 'Ward Assistant could not answer right now. Please try again.' });
  }
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server' });
});

app.listen(cfg.port, '0.0.0.0', () => {
  console.log(`Ward Budget API listening on http://0.0.0.0:${cfg.port}`);
  if (cfg.devMode) console.log('DEV_MODE is ON — phone OTPs are printed here instead of being sent by SMS');
});
