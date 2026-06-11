import { ActionResult } from './actionResult.js';
import { placeCommitProxy, actionRowHtml } from './turnCommit.js';

// Turn Action panel — Move (turn_action_stub.md → Move).
//
// A Main Action that spends a flat Move Cost in Combat Pool dice. It carries no
// roll, so it renders straight into the shared Action Result block: a single
// editable "Combat Pool" field (defaulting to the Move Cost) and a Commit
// button — the same component Attack and Cast use, so Move reads identically.
export class TurnMove {
  static ensureLoaded(container) {
    if (!container || container.dataset.tmLoaded) return;
    container.dataset.tmLoaded = '1';
    container._combatantId = parseInt(container.getAttribute('data-combatant-id'), 10);
    const cost = num(container.getAttribute('data-move-cost'));
    const remaining = num(container.getAttribute('data-pool-remaining'));

    container.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.ar-commit')) { e.preventDefault(); TurnMove._commit(container); }
    });

    // The same "Action" row the builders fold in, then the shared result block —
    // so Move reads identically to Attack / Cast (Action row + editable spend).
    container.innerHTML = actionRowHtml('Move') + '<div class="ta-move-result"></div>';
    TurnMove._render(container, cost, remaining < cost ? `Only ${remaining} Combat Pool remaining` : null);
    placeCommitProxy(container, 'Confirm Move');
  }

  static _render(container, cost, note) {
    ActionResult.render(container.querySelector('.ta-move-result'), {
      fields: [{ key: 'cost', label: 'Combat Pool', value: cost, editable: true }],
      notes: note ? [{ label: 'Note', value: note }] : [],
      commitLabel: 'Confirm Move'
    });
  }

  static _commit(container) {
    const cost = ActionResult.field(container.querySelector('.ta-move-result'), 'cost');
    fetch('/encounter/move', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ combatant_id: container._combatantId, cost: cost })
    })
      .then((r) => r.json().catch(() => null))
      .then((res) => {
        if (!res || res.ok === false) {
          TurnMove._render(container, cost, (res && res.error) || 'Could not move.');
          return;
        }
        window.location.reload();
      })
      .catch(() => { /* leave the block in place for a retry */ });
  }
}

function num(v) { const n = parseInt(v, 10); return Number.isNaN(n) ? 0 : n; }
