import { ActionBuilder } from './actionBuilder.js';
import { ActionResult } from './actionResult.js';

// Turn Action panel — Special (turn_action_stub.md → Special).
//
// Lets the DM use one of the Acting Combatant's non-Spell, non-Reaction
// Abilities — a Bard's Bardic Performance and the like. The usable list is
// rendered server-side (Encounter::State#special_options), grouped by action
// category. Picking an Ability:
//   - Channeled (a Bardic Performance): mounts the shared Check Resolution
//     Builder — the DM picks how many dice to channel (Main Action Minimum up
//     to Combat Pool Remaining) and rolls the Performance check, exactly like
//     Attack. On confirm the Successes (which fill the Reservoir) and the
//     chosen dice POST to /encounter/use_special.
//   - Otherwise: shows a summary of the change and a Confirm button.
export class TurnSpecial {
  static ensureLoaded(container) {
    if (!container || container.dataset.taLoaded) return;
    container.dataset.taLoaded = '1';
    container._combatantId = container.getAttribute('data-combatant-id');

    container.addEventListener('click', (e) => {
      const opt = e.target.closest && e.target.closest('.ta-special-opt');
      if (opt) { e.preventDefault(); TurnSpecial._pick(container, opt); return; }
      const use = e.target.closest && e.target.closest('.ar-commit');
      if (use && e.target.closest('.ta-special')) { e.preventDefault(); TurnSpecial._use(container, container._pending || {}); }
    });
    // A channeled Performance resolves through the embedded Check Builder.
    // After Confirm, show the Luck points it will grant + a Confirm button;
    // nothing is saved until that second Confirm.
    container.addEventListener('action:confirmed', (e) => {
      const roll = (e.detail.rolls || []).find((r) => r.id === 'performance') || {};
      const successes = roll.successes || 0;
      const luck = successes * (container._ratio || 1);
      // Luck an ally Bard / the DM spent (as a Reaction) on this Performance.
      container._pending = { dice: roll.dice_count, successes: successes,
                             luck: ActionBuilder.luckSpends(e.detail.choices || {}) };
      const commit = container.querySelector('.ta-special-commit');
      if (!commit) return;
      ActionResult.render(commit, {
        notes: [{ label: 'Luck', value: `Gaining ${luck} luck point${luck === 1 ? '' : 's'}` }],
        commitLabel: 'Confirm'
      });
      commit.hidden = false;
    });
  }

  static _pick(container, btn) {
    if (!btn || btn.disabled) return;
    container._ability = btn.dataset.ability;
    container._pending = null;
    container.querySelectorAll('.ta-special-opt').forEach((b) => b.classList.toggle('cr-mod-selected', b === btn));
    // Collapse the action menu to the selected-action row (shared helper).
    const panel = container.closest('.turn-action');
    if (panel && window.__taSelectAction) window.__taSelectAction(panel, btn.textContent.trim());
    const slot = container.querySelector('.ta-special-result');
    if (!slot) return;

    if (btn.dataset.performance === '1') { TurnSpecial._mountBuilder(container, slot); return; }

    // Non-channeled: summary + Confirm, through the shared result renderer.
    ActionResult.render(slot, {
      notes: [{ label: btn.textContent.trim(), value: btn.dataset.summary || '' }],
      commitLabel: 'Confirm'
    });
    slot.hidden = false;
  }

  // Mount the Performance-check builder (same component Attack uses).
  static _mountBuilder(container, slot) {
    slot.hidden = false;
    slot.innerHTML = '<p class="ta-special-loading">Loading performance…</p>';
    fetch('/encounter/special_builder?combatant_id=' + encodeURIComponent(container._combatantId) +
          '&ability=' + encodeURIComponent(container._ability), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        slot.innerHTML = html + '<div class="ta-special-commit" hidden></div>';
        const builder = slot.querySelector('.action-builder');
        if (builder) {
          let blob; try { blob = JSON.parse(builder.dataset.builder); } catch (e) { blob = {}; }
          container._ratio = blob.reservoir_ratio || 1;
          ActionBuilder.ensureLoaded(builder);
        } else {
          slot.innerHTML = '<p class="ta-warn">Could not load the performance.</p>';
        }
      })
      .catch(() => { slot.innerHTML = '<p class="ta-warn">Could not load the performance.</p>'; });
  }

  static _use(container, extra) {
    if (!container._ability) return;
    const payload = Object.assign({
      combatant_id: parseInt(container._combatantId, 10),
      ability: container._ability
    }, extra);
    fetch('/encounter/use_special', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    })
      .then((r) => r.json().catch(() => null))
      .then((res) => {
        if (!res || res.ok === false) {
          const slot = container.querySelector('.ta-special-result');
          if (slot) { slot.hidden = false; slot.innerHTML = '<p class="ta-warn">' + esc((res && res.error) || 'Could not use the ability.') + '</p>'; }
          return;
        }
        // Applied — reload so the tracker reflects the spent Mana / Combat
        // Pool and any new Active Effect or Performance.
        window.location.reload();
      })
      .catch(() => {
        const slot = container.querySelector('.ta-special-result');
        if (slot) { slot.hidden = false; slot.innerHTML = '<p class="ta-warn">Could not use the ability.</p>'; }
      });
  }
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}
