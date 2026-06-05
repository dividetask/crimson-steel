import { CheckBuilder } from './checkBuilder.js';

// Turn Action panel — Attack (turn_action_stub.md → Attack).
//
// Thin host for the Check Resolution Builder. Confirm is two-stage so the DM
// can review before anything is saved:
//   1st Confirm  -> non-mutating PREVIEW (commit:false). The result renders
//       beneath the still-present builder with editable Damage / Bleed /
//       Combat-Pool fields; the DM may Change a step and Confirm again.
//   2nd Confirm  -> the "Commit attack" button: applies the (possibly edited)
//       result for real (spends Combat Pool, applies damage + bleed), locks.
export class TurnAttack {
  static ensureLoaded(container) {
    if (!container || container.dataset.taLoaded) return;
    container.dataset.taLoaded = '1';
    const attackerId = container.getAttribute('data-attacker-id');
    container._attackerId = attackerId;

    container.addEventListener('check:confirmed', (e) => TurnAttack._preview(container, e.detail));
    container.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.ta-commit')) { e.preventDefault(); TurnAttack._commit(container); }
    });
    // Editing the Damage field re-buckets the Minor/Moderate/Major split live.
    container.addEventListener('input', (e) => {
      if (e.target.closest && e.target.closest('.ta-dmg-input')) TurnAttack._renderSplit(container);
    });

    container.innerHTML = '<p class="ta-attack-loading">Loading attack…</p><div class="ta-result" hidden></div>';
    fetch('/encounter/attack_builder?attacker_id=' + encodeURIComponent(attackerId), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        container.innerHTML = html + '<div class="ta-result" hidden></div>';
        const builder = container.querySelector('.check-builder');
        if (builder) CheckBuilder.ensureLoaded(builder);
        else container.innerHTML = '<p class="ta-warn">Could not load the attack.</p>';
      })
      .catch(() => { container.innerHTML = '<p class="ta-warn">Could not load the attack.</p>'; });
  }

  // Translate the builder's confirmed choices into a resolve payload.
  static _payload(container, detail, commit) {
    const choices = detail.choices || {};
    const rolls = detail.rolls || [];
    const weaponType = String(choices.action || '').split('|')[0];
    // Defence values are "<type>|<dice>" where <type> may be "parry:<weapon>";
    // the server's defence kind is the base type before any ':'.
    const defenseName = String(choices.defense || 'none').split('|')[0].split(':')[0];
    const atk = rolls.find((r) => r.id === 'attacker') || {};
    const def = rolls.find((r) => r.id === 'defender');
    const declared = def && defenseName !== 'none';
    return {
      target_id: choices.target,
      weapon_type: weaponType,
      commit: commit,
      // Luck spent on this attack (one entry per source; source_id null = DM).
      // The rerolls are already on the chosen Rolls; the server only debits
      // each source's Reservoir / DM pool on commit.
      luck: CheckBuilder.luckSpends(choices),
      attacker: { id: parseInt(container._attackerId, 10), dice: atk.dice_count, speed: atk.speed, successes: atk.successes },
      defense: declared
        ? { choice: defenseName, id: choices.target, dice: def.dice_count, speed: def.speed || 0, successes: def.successes }
        : { choice: 'none' }
    };
  }

  // First Confirm: non-mutating preview. Keep the builder; show the editable
  // result underneath so the DM can still go back.
  static _preview(container, detail) {
    container._lastDetail = detail;
    const payload = TurnAttack._payload(container, detail, false);
    TurnAttack._post(container, payload, (res) => TurnAttack._renderResult(container, res, false));
  }

  // Second Confirm: apply the attack for real, carrying any DM edits.
  static _commit(container) {
    if (!container._lastDetail) return;
    const payload = TurnAttack._payload(container, container._lastDetail, true);
    payload.override = TurnAttack._gatherOverride(container);
    TurnAttack._post(container, payload, (res) => TurnAttack._renderResult(container, res, true));
  }

  // Read the editable result fields into an override the server applies.
  static _gatherOverride(container) {
    const slot = container.querySelector('.ta-result');
    const o = {};
    const dmg = slot && slot.querySelector('.ta-dmg-input');
    const bl = slot && slot.querySelector('.ta-bleed-input');
    const poi = slot && slot.querySelector('.ta-poison-input');
    if (dmg) o.damage = num(dmg.value);
    if (bl) o.bleed = num(bl.value);
    if (poi) o.poison = num(poi.value);
    const pools = slot ? Array.from(slot.querySelectorAll('.ta-pool-input')) : [];
    if (pools.length) o.pool_spends = pools.map((p) => ({ id: num(p.dataset.id), amount: num(p.value) }));
    return o;
  }

  static _post(container, payload, onOk) {
    fetch('/encounter/resolve_attack', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    })
      .then((r) => r.json().catch(() => null))
      .then((res) => {
        const slot = container.querySelector('.ta-result');
        if (!res || res.ok === false) {
          if (slot) { slot.hidden = false; slot.innerHTML = `<p class="ta-warn">${(res && res.error) || 'Could not resolve the attack.'}</p>`; }
          return;
        }
        onOk(res);
      })
      .catch(() => {
        const slot = container.querySelector('.ta-result');
        if (slot) { slot.hidden = false; slot.innerHTML = '<p class="ta-warn">Could not resolve the attack.</p>'; }
      });
  }

  static _renderResult(container, res, committed) {
    const slot = container.querySelector('.ta-result');
    if (!slot) return;
    container._lastRes = res;
    const nameOf = TurnAttack._namer(container);
    const spends = (res.pool_spends || []).filter((s) => s.amount > 0);

    if (committed) {
      // Attack applied — the panel's work is done. Reload so the tracker
      // reflects the new HP / Combat Pool and the Attack pane resets; no
      // intermediate result screen.
      window.location.reload();
      return;
    }

    // Preview: editable Damage / Bleed / per-participant Combat Pool. The
    // Minor/Moderate/Major split is derived from Damage + Threshold (live).
    const rows = [];
    rows.push(`<div class="ta-field"><label>Damage` +
      ` <input type="number" class="ta-dmg-input" value="${res.damage}" min="0"></label>` +
      ` <span class="ta-dim">${res.damage_type || ''}</span> <span class="ta-split"></span></div>`);
    rows.push(`<div class="ta-field"><label>Bleed` +
      ` <input type="number" class="ta-bleed-input" value="${res.bleed}" min="0"></label></div>`);
    // Poison — only weapons that inject an Affliction (e.g. a spider's
    // venom) return a poison_name; its potency is editable like Bleed.
    if (res.poison_name) {
      rows.push(`<div class="ta-field"><label>Poison` +
        ` <input type="number" class="ta-poison-input" value="${res.poison || 0}" min="0"></label>` +
        ` <span class="ta-dim">${res.poison_name}</span></div>`);
    }
    spends.forEach((s) => {
      rows.push(`<div class="ta-field"><label>Combat Pool — ${nameOf(s.id)}` +
        ` <input type="number" class="ta-pool-input" data-id="${s.id}" value="${s.amount}" min="0"></label></div>`);
    });
    rows.push(`<div class="ta-actions"><button type="button" class="ce-btn ta-commit">Commit attack</button></div>`);
    slot.innerHTML = rows.join('');
    slot.hidden = false;
    // Mirror the Commit button up into the builder's title row (next to Roll
    // All / Confirm) so the DM can commit without moving the mouse far.
    const actions = container.querySelector('.rolls-actions');
    if (actions && !actions.querySelector('.ta-commit')) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'ce-btn ta-commit';
      btn.textContent = 'Commit attack';
      actions.appendChild(btn);
    }
    TurnAttack._renderSplit(container);
  }

  // Re-bucket the current Damage input into Minor/Moderate/Major using the
  // target's Threshold + Damage Resilience (mirrors the server's bucketing).
  static _renderSplit(container) {
    const res = container._lastRes || {};
    const slot = container.querySelector('.ta-result');
    const input = slot && slot.querySelector('.ta-dmg-input');
    const out = slot && slot.querySelector('.ta-split');
    if (!input || !out) return;
    const sev = bucketSeverity(num(input.value), res.threshold || 0, res.damage_resilience || 0);
    out.textContent = num(input.value) > 0 ? `(${TurnAttack._splitText(sev)})` : '';
  }

  static _splitText(sev) {
    sev = sev || {};
    const parts = ['minor', 'moderate', 'major'].filter((k) => sev[k]).map((k) => `${sev[k]} ${cap(k)}`);
    return parts.length ? parts.join(', ') : 'none';
  }

  // Resolve a Combatant id to a display name from the builder's roll groups,
  // reading ONLY the name text (excluding the TN tooltip span inside it).
  static _namer(container) {
    const map = {};
    container.querySelectorAll('.roll-group').forEach((g) => {
      const nm = g.querySelector('.creature-name');
      if (nm) map[g.dataset.rollId] = nameText(nm);
    });
    const choices = (container._lastDetail || {}).choices || {};
    const byCombatant = {};
    byCombatant[parseInt(container._attackerId, 10)] = map.attacker || ('#' + container._attackerId);
    if (choices.target != null) byCombatant[choices.target] = map.defender || ('#' + choices.target);
    return (id) => byCombatant[id] || ('#' + id);
  }
}

function cap(s) { return String(s).charAt(0).toUpperCase() + String(s).slice(1); }
function num(v) { const n = parseInt(v, 10); return Number.isNaN(n) ? 0 : n; }

// The Roll's creature name has a `.tn-tip` child span; read only its text
// nodes so the tooltip's computation text doesn't leak into the name.
function nameText(el) {
  let t = '';
  el.childNodes.forEach((n) => { if (n.nodeType === 3) t += n.textContent; });
  return t.trim() || el.textContent.trim();
}

// Mirror of Encounter::Severity.runtime_bucket: the bucket width is
// (threshold + damage_resilience), min 1. The first bucket-width of damage is
// Minor, the next bucket-width Moderate, the rest Major.
function bucketSeverity(damage, threshold, resilience) {
  const amount = Math.max(damage, 0);
  if (amount <= 0) return {};
  let bucket = (threshold || 0) + (resilience || 0);
  if (bucket <= 0) bucket = 1;
  const minor = Math.min(amount, bucket);
  const rest = amount - minor;
  const moderate = Math.min(rest, bucket);
  const major = rest - moderate;
  const out = {};
  if (minor > 0) out.minor = minor;
  if (moderate > 0) out.moderate = moderate;
  if (major > 0) out.major = major;
  return out;
}
