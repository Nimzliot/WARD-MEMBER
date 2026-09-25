const express = require('express');
const { supabase, must } = require('../supabase');
const { requireAdmin } = require('../middleware/auth');

const router = express.Router();
router.use(requireAdmin);

/*
POST /api/admin/proposals
{
  "wardId": 1,
  "title": "New bus shelters",
  "description": "Four shelters on Station Road",
  "category": "Roads & Transport",
  "items": [ { "label": "4 steel shelters", "amount": 480000 },
             { "label": "Installation",     "amount": 60000 } ]
}
*/
router.post('/proposals', async (req, res) => {
  const { wardId, title, description = '', category, items } = req.body || {};

  const errors = [];
  if (!Number.isInteger(wardId)) errors.push('wardId must be a number');
  if (typeof title !== 'string' || title.trim().length < 3) errors.push('title is required (min 3 chars)');
  if (typeof category !== 'string' || !category.trim()) errors.push('category is required');
  if (!Array.isArray(items) || items.length < 1 || items.length > 20) {
    errors.push('items must contain 1–20 budget lines');
  } else {
    items.forEach((it, i) => {
      if (!it || typeof it.label !== 'string' || !it.label.trim()) errors.push(`items[${i}].label is required`);
      if (!Number.isInteger(it?.amount) || it.amount <= 0) errors.push(`items[${i}].amount must be a positive whole number of rupees`);
    });
  }
  if (errors.length) return res.status(400).json({ error: errors.join('; ') });

  const ward = must(await supabase.from('wards').select('id').eq('id', wardId).maybeSingle());
  if (!ward) return res.status(404).json({ error: 'Ward not found' });

  const proposal = must(
    await supabase
      .from('proposals')
      .insert({ ward_id: wardId, title: title.trim(), description: String(description).trim(), category: category.trim() })
      .select('id')
      .single(),
  );

  const { error: itemsError } = await supabase
    .from('budget_items')
    .insert(items.map((it) => ({ proposal_id: proposal.id, label: it.label.trim(), amount: it.amount })));
  if (itemsError) {
    await supabase.from('proposals').delete().eq('id', proposal.id); // keep it all-or-nothing
    throw itemsError;
  }

  // Re-read so total_cost (set by the DB trigger) is included.
  const full = must(
    await supabase.from('proposals').select('*, budget_items(*)').eq('id', proposal.id).single(),
  );
  res.status(201).json({ message: 'Proposal created', proposal: full });
});

module.exports = router;
