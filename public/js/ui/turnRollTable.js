import { ActionBuilder } from './actionBuilder.js';

// Roll Table Reaction stub (encounter_roll_table_stub.md).
//
// Rides alongside the Attack Action Builder. A bystander (a Combatant other
// than the attacker) who holds a Roll Table Reaction — Kesser's Gambit, from
// Kesser's Ring or a Cleric's Channel Divinity — can answer the attack with
// it. Picking the channeler mounts the channel-check builder (the same
// component Attack uses); on Confirm the rolled Channel Successes + dice POST
// to /encounter/roll_table_reaction, a die is rolled on the table, and the
// matched entry renders for the DM to adjudicate (Combat does not apply it).
export class TurnRollTable {
  // Mount every Roll Table Reaction stub inside the attack container.
  static mount(container) {
    container.querySelectorAll('.ta-roll-table').forEach((stub) => TurnRollTable._wire(stub));
  }

  static _wire(stub) {
    if (!stub || stub.dataset.rtWired) return;
    stub.dataset.rtWired = '1';

    stub.addEventListener('click', (e) => {
      const opt = e.target.closest && e.target.closest('.ta-rt-opt');
      if (opt) { e.preventDefault(); TurnRollTable._pick(stub, opt); return; }
      // Reroll the table effect without spending (a fresh face); Confirm spends
      // the dice + Mana and commits the shown face.
      if (e.target.closest && e.target.closest('.ta-rt-reroll')) { e.preventDefault(); TurnRollTable._fire(stub, { commit: false }); return; }
      if (e.target.closest && e.target.closest('.ta-rt-confirm')) { e.preventDefault(); TurnRollTable._fire(stub, { commit: true, face: stub._face }); return; }
    });
    // The channel check resolves through the embedded Action Builder. Its
    // `action:confirmed` is scoped to this stub (stopPropagation) so the
    // attack container's own listener never sees the channel roll. Confirming
    // the channel roll previews the table entry (no spend yet).
    stub.addEventListener('action:confirmed', (e) => {
      e.stopPropagation();
      const roll = (e.detail.rolls || []).find((r) => r.id === 'channel') || {};
      stub._dice = roll.dice_count;
      stub._successes = roll.successes || 0;
      TurnRollTable._fire(stub, { commit: false });
    });
  }

  static _pick(stub, btn) {
    if (!btn || btn.disabled) return;
    stub._combatantId = btn.dataset.combatantId;
    stub._ability = btn.dataset.ability;
    stub.querySelectorAll('.ta-rt-opt').forEach((b) => b.classList.toggle('cr-mod-selected', b === btn));
    const result = stub.querySelector('.ta-rt-result');
    if (result) { result.hidden = true; result.innerHTML = ''; }

    const slot = stub.querySelector('.ta-rt-builder');
    if (!slot) return;
    slot.hidden = false;
    slot.innerHTML = '<p class="ta-rt-loading">Loading channel…</p>';
    fetch('/encounter/roll_table_builder?combatant_id=' + encodeURIComponent(stub._combatantId) +
          '&ability=' + encodeURIComponent(stub._ability), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        slot.innerHTML = html;
        const builder = slot.querySelector('.action-builder');
        if (builder) ActionBuilder.ensureLoaded(builder);
        else slot.innerHTML = '<p class="ta-warn">Could not load the channel.</p>';
      })
      .catch(() => { slot.innerHTML = '<p class="ta-warn">Could not load the channel.</p>'; });
  }

  // POST the reaction. `opts.commit` distinguishes a preview/reroll (no spend)
  // from the Confirm (spends dice + Mana); `opts.face` locks the previewed entry
  // on Confirm — omit it on a reroll to draw a fresh face.
  static _fire(stub, opts) {
    if (!stub._ability) return;
    opts = opts || {};
    const payload = {
      combatant_id: parseInt(stub._combatantId, 10),
      ability: stub._ability,
      dice: stub._dice,
      successes: stub._successes,
      commit: !!opts.commit
    };
    if (opts.face != null) payload.face = opts.face;
    fetch('/encounter/roll_table_reaction', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    })
      .then((r) => r.json().catch(() => null))
      .then((res) => TurnRollTable._render(stub, res))
      .catch(() => TurnRollTable._render(stub, null));
  }

  static _render(stub, res) {
    const slot = stub.querySelector('.ta-rt-result');
    if (!slot) return;
    slot.hidden = false;
    if (!res || res.ok === false) {
      slot.innerHTML = '<p class="ta-warn">' + esc((res && res.error) || 'Could not channel the reaction.') + '</p>';
      return;
    }
    stub._face = res.face;
    const entry = res.entry || {};
    const committed = !!res.committed;
    // Every Bonus/Penalty on the channel (Evocation/Invocation) check, so the DM
    // can set save TNs against the effect by hand.
    const mods = (res.modifiers || [])
      .map((m) => (m.amount >= 0 ? '+' : '') + m.amount + ' ' + m.type).join(' ') || 'none';
    const spent = committed
      ? ('Spent ' + esc(res.pool_spent) + ' Combat Pool and ' + esc(res.mana_spent) + ' Mana. The DM adjudicates the effect.')
      : ('Will spend ' + esc(res.pool_spent) + ' Combat Pool and ' + esc(res.mana_spent) + ' Mana on Confirm.');
    const actions = committed ? '' :
      '<div class="ta-rt-actions">' +
        '<button type="button" class="cr-mod-btn ta-rt-reroll">Reroll effect</button>' +
        '<button type="button" class="ce-btn ta-rt-confirm">Confirm</button>' +
      '</div>';
    slot.innerHTML =
      '<div class="ta-rt-entry">' +
        '<div class="ta-rt-entry-head">' +
          '<span class="ta-rt-die">d' + esc(res.die) + ' &rarr; ' + esc(res.face) + '</span>' +
          '<span class="ta-rt-entry-name">' + esc(entry.name) + '</span>' +
          '<span class="ta-rt-successes">' + esc(res.successes) + ' Channel Success' + (res.successes === 1 ? '' : 'es') + '</span>' +
        '</div>' +
        '<p class="ta-rt-entry-effect">' + esc(entry.effect) + '</p>' +
        '<p class="ta-rt-mods">' + esc(res.skill_label || 'Check') + ' check: ' + esc(mods) +
          ' &middot; ' + esc(res.successes) + ' successes &mdash; roll any saves against this.</p>' +
        '<p class="ta-rt-note">' + spent + '</p>' +
        actions +
      '</div>';
  }
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}
