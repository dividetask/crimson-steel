// Shared Action Result block (turn_action_stub.md) — the single, uniform
// "what happens when this action is taken" template used by **every** turn
// action (Attack, Cast, Move, Item, …). Each host resolves its action and
// builds the same view-model; this renderer turns it into identical markup so
// the stub reads consistently no matter the action:
//
//   model = {
//     spent:   [ { label, value } ],           // resources spent (Combat Pool, Mana, …)
//     fields:  [ { key, label, value, editable?, min?, suffix?, split? } ],
//                                               // the action's numeric outcomes,
//                                               // editable where the resolver accepts an override
//     notes:   [ { label, value } ],            // read-only outcome lines (effects, sustain, …)
//     reactions: [ { key, target, amount, label } ], // optional toggles (defender reactions)
//     commitLabel: 'Commit attack'
//   }
//
// The same `.ar-*` classes and row structure are emitted every time; only the
// data differs. Hosts read edited values back with `ActionResult.fields(slot)`.
export const ActionResult = {
  render(slot, model) {
    if (!slot) return;
    model = model || {};
    const parts = [];

    const spent = (model.spent || []).filter(Boolean);
    if (spent.length) {
      parts.push('<div class="ar-spent"><span class="ar-spent-label">Spent</span> ' +
        spent.map((s) => `<span class="ar-spent-item">${esc(s.label)} ${esc(s.value)}</span>`).join('') +
        '</div>');
    }

    (model.fields || []).forEach((f) => parts.push(fieldHtml(f)));

    (model.notes || []).filter(Boolean).forEach((n) => {
      parts.push(`<div class="ar-note-row"><span class="ar-note-label">${esc(n.label)}</span>` +
        `<span class="ar-note-value">${esc(n.value)}</span></div>`);
    });

    const reactions = model.reactions || [];
    if (reactions.length) {
      const rx = reactions.map((r) => (
        `<label class="ar-reaction"><input type="checkbox" class="ar-reaction-toggle" data-key="${esc(r.key)}"` +
        ` data-target="${esc(r.target)}" data-amount="${num(r.amount)}"> ${esc(r.label)}</label>`
      )).join('');
      parts.push(`<div class="ar-reactions"><div class="ar-reactions-head">Defender reactions</div>${rx}</div>`);
    }

    if (model.commitLabel) {
      parts.push(`<div class="ar-actions"><button type="button" class="ce-btn ar-commit">${esc(model.commitLabel)}</button></div>`);
    }
    slot.innerHTML = `<div class="ar">${parts.join('')}</div>`;
  },

  // The current value of one editable field, by key.
  field(slot, key) {
    const el = slot && slot.querySelector(`.ar-input[data-key="${cssEscape(key)}"]`);
    return el ? num(el.value) : 0;
  },

  // Every editable field's value, keyed: { damage: 7, 'pool:3': 4, ... }.
  fields(slot) {
    const out = {};
    (slot ? Array.from(slot.querySelectorAll('.ar-input')) : []).forEach((el) => { out[el.dataset.key] = num(el.value); });
    return out;
  },

  // The keys of the checked defender-reaction toggles.
  reactionsChosen(slot) {
    return (slot ? Array.from(slot.querySelectorAll('.ar-reaction-toggle')) : [])
      .filter((c) => c.checked).map((c) => c.dataset.key);
  }
};

function fieldHtml(f) {
  const inner = f.editable === false
    ? `<span class="ar-value">${esc(f.value)}</span>`
    : `<input class="ar-input" type="number" data-key="${esc(f.key)}" value="${num(f.value)}" min="${f.min == null ? 0 : num(f.min)}">`;
  return `<div class="ar-field" data-key="${esc(f.key)}">` +
    `<label>${esc(f.label)} ${inner}</label>` +
    (f.suffix ? ` <span class="ar-dim">${esc(f.suffix)}</span>` : '') +
    (f.split ? ' <span class="ar-split"></span>' : '') +
    '</div>';
}

function num(v) { const n = parseInt(v, 10); return Number.isNaN(n) ? 0 : n; }
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}
function cssEscape(s) { return String(s).replace(/["\\]/g, '\\$&'); }
