// Shared proposal validation + writes (used by admin routes and resident ideas).
const { supabase, must } = require('../supabase');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FULL_SELECT = '*, budget_items(id, label, amount)';

// Validates { title, description, category, items }. With partial=true, missing
// fields are allowed (PATCH). Returns { errors, value } with trimmed values.
function validateProposal(body, { partial = false } = {}) {
  const { title, description, category, items } = body || {};
  const errors = [];
  const value = {};

  if (title !== undefined || !partial) {
    if (typeof title !== 'string' || title.trim().length < 3 || title.trim().length > 120) {
      errors.push('title must be 3–120 characters');
    } else value.title = title.trim();
  }
  if (description !== undefined) value.description = String(description ?? '').trim().slice(0, 2000);
  else if (!partial) value.description = '';
  if (category !== undefined || !partial) {
    if (typeof category !== 'string' || !category.trim()) errors.push('category is required');
    else value.category = category.trim().slice(0, 60);
  }
  if (items !== undefined || !partial) {
    if (!Array.isArray(items) || items.length < 1 || items.length > 20) {
      errors.push('items must contain 1–20 budget lines');
    } else {
      items.forEach((it, i) => {
        if (!it || typeof it.label !== 'string' || !it.label.trim()) errors.push(`items[${i}].label is required`);
        if (!Number.isInteger(it?.amount) || it.amount <= 0 || it.amount > 1e11) {
          errors.push(`items[${i}].amount must be a positive whole number of rupees`);
        }
      });
      value.items = items.map((it) => ({ label: String(it?.label ?? '').trim().slice(0, 120), amount: it?.amount }));
    }
  }
  return { errors, value };
}

async function loadProposal(id) {
  return must(await supabase.from('proposals').select(FULL_SELECT).eq('id', id).maybeSingle());
}

// Inserts a proposal with its budget lines (all-or-nothing) and returns it in full.
async function createProposal({ items, ...fields }) {
  const proposal = must(await supabase.from('proposals').insert(fields).select('id').single());
  const { error } = await supabase
    .from('budget_items')
    .insert(items.map((it) => ({ proposal_id: proposal.id, ...it })));
  if (error) {
    await supabase.from('proposals').delete().eq('id', proposal.id);
    throw error;
  }
  return loadProposal(proposal.id); // re-read: total_cost is set by the DB trigger
}

// Replaces every budget line of a proposal (total_cost follows via trigger).
async function replaceItems(proposalId, items) {
  const old = must(await supabase.from('budget_items').select('id').eq('proposal_id', proposalId));
  must(await supabase.from('budget_items').insert(items.map((it) => ({ proposal_id: proposalId, ...it }))).select('id'));
  if (old.length) must(await supabase.from('budget_items').delete().in('id', old.map((o) => o.id)).select('id'));
}

module.exports = { UUID_RE, validateProposal, loadProposal, createProposal, replaceItems };
