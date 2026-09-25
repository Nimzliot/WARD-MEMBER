// End-to-end encrypted chat between a resident and their Ward Admin.
// The server only relays and stores ciphertext: it never sees message text or
// private keys. Each message records which public keys were used, so either
// side can decrypt with X25519(own private key, other party's public key).
const express = require('express');
const { supabase, must } = require('../supabase');
const { UUID_RE } = require('../lib/proposals');

const router = express.Router();
const KEY_RE = /^[A-Za-z0-9+/]{43}=$/; // base64 of a 32-byte X25519 public key
const B64_RE = /^[A-Za-z0-9+/]+={0,2}$/;
const MAX_CIPHERTEXT = 12000; // ≈ 8 KB of text

async function wardOf(id) {
  return must(await supabase.from('wards').select('id, name, admin_user_id').eq('id', id).maybeSingle());
}

// Thread + my role in it ('resident' | 'admin'), or null if I'm not a member.
async function membership(threadId, userId) {
  const t = must(await supabase.from('chat_threads').select('*').eq('id', threadId).maybeSingle());
  if (!t) return null;
  if (t.resident_id === userId) return { thread: t, role: 'resident' };
  const w = await wardOf(t.ward_id);
  if (w?.admin_user_id === userId) return { thread: t, role: 'admin' };
  return null;
}

// POST /api/chat/key { publicKey } → publish my chat public key
router.post('/key', async (req, res) => {
  const publicKey = String(req.body?.publicKey || '');
  if (!KEY_RE.test(publicKey)) return res.status(400).json({ error: 'Invalid public key', code: 'INVALID' });
  must(await supabase.from('profiles').update({ chat_public_key: publicKey }).eq('id', req.user.id).select('id'));
  res.json({ ok: true });
});

// GET /api/chat/peer → resident: my Ward Admin + my thread (created on first use)
router.get('/peer', async (req, res) => {
  const wardId = req.profile.ward_id;
  if (!wardId) return res.json({ admin: null, thread: null, is_ward_admin: false });
  const ward = await wardOf(wardId);
  const isWardAdmin = ward?.admin_user_id === req.user.id;
  if (!ward?.admin_user_id || isWardAdmin) {
    return res.json({ admin: null, thread: null, is_ward_admin: isWardAdmin, ward_name: ward?.name });
  }
  const admin = must(await supabase.from('profiles').select('id, full_name, chat_public_key').eq('id', ward.admin_user_id).maybeSingle());
  let thread = must(await supabase.from('chat_threads').select('*').eq('ward_id', wardId).eq('resident_id', req.user.id).maybeSingle());
  if (!thread) {
    const { data, error } = await supabase.from('chat_threads').insert({ ward_id: wardId, resident_id: req.user.id }).select('*').single();
    if (error?.code === '23505') {
      thread = must(await supabase.from('chat_threads').select('*').eq('ward_id', wardId).eq('resident_id', req.user.id).single());
    } else {
      thread = must({ data, error });
    }
  }
  res.json({
    is_ward_admin: false,
    ward_name: ward.name,
    admin: { id: admin.id, name: admin.full_name || 'Ward Admin', public_key: admin.chat_public_key },
    thread,
  });
});

// GET /api/chat/threads → Ward Admin inbox (their ward's resident threads)
router.get('/threads', async (req, res) => {
  const wards = must(await supabase.from('wards').select('id, name').eq('admin_user_id', req.user.id));
  if (!wards.length) return res.status(403).json({ error: 'Only the Ward Admin has a resident inbox', code: 'ADMIN_ONLY' });
  const threads = must(await supabase.from('chat_threads').select('*').in('ward_id', wards.map((w) => w.id))
    .order('last_message_at', { ascending: false, nullsFirst: false }));
  const residents = threads.length
    ? must(await supabase.from('profiles').select('id, full_name, resident_id, chat_public_key').in('id', threads.map((t) => t.resident_id)))
    : [];
  const byId = Object.fromEntries(residents.map((r) => [r.id, r]));
  res.json({
    wards,
    threads: threads.filter((t) => t.last_message_at).map((t) => ({
      ...t,
      resident_name: byId[t.resident_id]?.full_name || 'Resident',
      resident_ref: byId[t.resident_id]?.resident_id || null,
      resident_key: byId[t.resident_id]?.chat_public_key || null,
    })),
  });
});

// POST /api/chat/threads/:id/messages { ciphertext, nonce, senderKey, recipientKey }
router.post('/threads/:id/messages', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(400).json({ error: 'Invalid thread', code: 'INVALID' });
  const m = await membership(req.params.id, req.user.id);
  if (!m) return res.status(403).json({ error: 'Not your conversation', code: 'NOT_YOUR_WARD' });

  const { ciphertext, nonce, senderKey, recipientKey } = req.body || {};
  if (typeof ciphertext !== 'string' || !B64_RE.test(ciphertext) || ciphertext.length > MAX_CIPHERTEXT) {
    return res.status(400).json({ error: 'Message is empty or too long', code: 'INVALID' });
  }
  if (typeof nonce !== 'string' || !B64_RE.test(nonce) || nonce.length !== 16) {
    return res.status(400).json({ error: 'Invalid nonce', code: 'INVALID' });
  }
  if (!KEY_RE.test(String(senderKey)) || !KEY_RE.test(String(recipientKey))) {
    return res.status(400).json({ error: 'Invalid keys', code: 'INVALID' });
  }
  if (senderKey !== req.profile.chat_public_key) {
    return res.status(409).json({ error: 'Your secure chat key changed. Reopen the chat.', code: 'KEY_CHANGED' });
  }

  const msg = must(await supabase.from('chat_messages').insert({
    thread_id: m.thread.id,
    sender_id: req.user.id,
    ciphertext,
    nonce,
    sender_key: senderKey,
    recipient_key: recipientKey,
  }).select('*').single());

  const counter = m.role === 'resident' ? 'unread_admin' : 'unread_resident';
  must(await supabase.from('chat_threads')
    .update({ last_message_at: msg.created_at, [counter]: (m.thread[counter] || 0) + 1 })
    .eq('id', m.thread.id).select('id'));
  res.status(201).json({ message: msg });
});

// POST /api/chat/threads/:id/read → mark the other side's messages as read
router.post('/threads/:id/read', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) return res.status(400).json({ error: 'Invalid thread', code: 'INVALID' });
  const m = await membership(req.params.id, req.user.id);
  if (!m) return res.status(403).json({ error: 'Not your conversation', code: 'NOT_YOUR_WARD' });
  const now = new Date().toISOString();
  must(await supabase.from('chat_messages').update({ read_at: now })
    .eq('thread_id', m.thread.id).neq('sender_id', req.user.id).is('read_at', null).select('id'));
  must(await supabase.from('chat_threads')
    .update({ [m.role === 'resident' ? 'unread_resident' : 'unread_admin']: 0 })
    .eq('id', m.thread.id).select('id'));
  res.json({ ok: true });
});

module.exports = router;
