import { CheckBuilder } from './checkBuilder.js';

// Turn Action panel — Attack (turn_action_stub.md → Attack).
//
// Thin host for the Check Resolution Builder. Combat owns none of the wizard:
// it fetches the precomputed builder blob, mounts the generic CheckBuilder,
// and listens for the builder's `check:confirmed` event — then posts the
// picked choices + resolved Successes to /encounter/resolve_attack. The
// weapon's damage is recomputed server-side from the chosen weapon.
export class TurnAttack {
  static ensureLoaded(container) {
    if (!container || container.dataset.taLoaded) return;
    container.dataset.taLoaded = '1';
    const attackerId = container.getAttribute('data-attacker-id');

    container.addEventListener('check:confirmed', (e) => TurnAttack._resolve(container, attackerId, e.detail));
    container.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.ta-continue')) window.location.reload();
    });

    container.innerHTML = '<p class="ta-attack-loading">Loading attack…</p>';
    fetch('/encounter/attack_builder?attacker_id=' + encodeURIComponent(attackerId), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        container.innerHTML = html;
        const builder = container.querySelector('.check-builder');
        if (builder) CheckBuilder.ensureLoaded(builder);
        else container.innerHTML = '<p class="ta-warn">Could not load the attack.</p>';
      })
      .catch(() => { container.innerHTML = '<p class="ta-warn">Could not load the attack.</p>'; });
  }

  static _resolve(container, attackerId, detail) {
    const choices = detail.choices || {};
    const rolls = detail.rolls || [];
    const weaponType = String(choices.action || '').split('|')[0];
    const atk = rolls.find((r) => r.id === 'attacker') || {};
    const def = rolls.find((r) => r.id === 'defender');
    const declared = def && choices.defense && choices.defense !== 'none';

    const payload = {
      target_id: choices.target,
      weapon_type: weaponType,
      attacker: { id: parseInt(attackerId, 10), dice: atk.dice_count, successes: atk.successes },
      defense: declared
        ? { choice: choices.defense, id: choices.target, dice: def.dice_count, speed: 1, successes: def.successes }
        : { choice: 'none' }
    };

    fetch('/encounter/resolve_attack', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    })
      .then((r) => r.json().catch(() => null))
      .then((res) => TurnAttack._showResult(container, res))
      .catch(() => fail(container, 'Could not resolve the attack.'));
  }

  static _showResult(container, res) {
    if (!res || res.ok === false) return fail(container, (res && res.error) || 'Could not resolve the attack.');
    let body;
    if (res.damage > 0) {
      const sev = res.severity_map || {};
      const parts = ['minor', 'moderate', 'major'].filter((k) => sev[k]).map((k) => `${sev[k]} ${cap(k)}`);
      body = `<p class="ta-hit">Hit for <strong>${res.damage}</strong> ${res.damage_type || ''} damage` +
        (parts.length ? ` <span class="ta-dim">(${parts.join(', ')})</span>` : '') +
        `.</p><p class="ta-dim">Net Degree of Success ${res.net_dos}.</p>`;
    } else {
      body = `<p class="ta-miss">No damage — net Degree of Success ${res.net_dos}.</p>`;
    }
    container.innerHTML = body + `<div class="ta-actions"><button type="button" class="ce-btn ta-continue">Continue</button></div>`;
  }
}

function cap(s) { return String(s).charAt(0).toUpperCase() + String(s).slice(1); }
function fail(container, msg) { container.innerHTML = `<p class="ta-warn">${msg}</p>`; }
