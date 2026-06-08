import { ActionBuilder } from './actionBuilder.js';
import { placeCommitProxy } from './turnCommit.js';

// Turn Action panel — Attack (turn_action_stub.md → Attack).
//
// Thin host for the Action Builder. Confirm is multi-stage so the DM
// can review before anything is saved:
//   1st Confirm  -> non-mutating PREVIEW (commit:false). When the weapon
//       carries magical Damage Riders, a second Roll Resolution Stub (the 4
//       extra dice per rider, at the attack's Target Number) renders first;
//       the DM rolls + Confirms it and it collapses to its own row (with a
//       Change button). Then the editable Damage / Bleed / Combat-Pool screen
//       appears. With no riders the damage screen shows immediately.
//   Final Confirm -> the "Commit attack" button: applies the (possibly edited)
//       result for real (spends Combat Pool, applies damage + bleed + rider
//       damage), locks.
export class TurnAttack {
  static ensureLoaded(container) {
    if (!container || container.dataset.taLoaded) return;
    container.dataset.taLoaded = '1';
    const attackerId = container.getAttribute('data-attacker-id');
    container._attackerId = attackerId;

    container.addEventListener('action:confirmed', (e) => TurnAttack._preview(container, e.detail));
    container.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.ta-commit')) { e.preventDefault(); TurnAttack._commit(container); }
      // The rider Roll Resolution Stub's Roll / Confirm / Change are driven by
      // the shared handlers in app.js (any .rolls-wrapper). We only hook the
      // Confirm (reveal the damage screen) and Change (hide it again), without
      // preventing app.js from collapsing / expanding the stub.
      if (e.target.closest && e.target.closest('.ta-rider-stub .btn-confirm')) TurnAttack._onRiderConfirm(container);
      if (e.target.closest && e.target.closest('.ta-rider-stub .btn-rolls-change')) TurnAttack._onRiderChange(container);
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
        const builder = container.querySelector('.action-builder');
        if (builder) ActionBuilder.ensureLoaded(builder);
        else container.innerHTML = '<p class="ta-warn">Could not load the attack.</p>';
      })
      .catch(() => { container.innerHTML = '<p class="ta-warn">Could not load the attack.</p>'; });
  }

  // Translate the builder's confirmed choices into a resolve payload.
  static _payload(container, detail, commit) {
    const choices = detail.choices || {};
    const rolls = detail.rolls || [];
    const weaponType = String(choices.action || '').split('|')[0];
    // Defence values are "<type>|<dice>" where <type> may be "parry:<weapon>"
    // or "shield:<casterId>"; the server's defence kind is the base before ':'.
    const defFull = String(choices.defense || 'none');
    const defType = defFull.split('|')[0];
    const defenseName = defType.split(':')[0];
    const atk = rolls.find((r) => r.id === 'attacker') || {};
    const base = {
      target_id: choices.target,
      weapon_type: weaponType,
      commit: commit,
      // Luck spent on this attack (one entry per source; source_id null = DM).
      // The rerolls are already on the chosen Rolls; the server only debits
      // each source's Reservoir / DM pool on commit.
      luck: ActionBuilder.luckSpends(choices),
      attacker: { id: parseInt(container._attackerId, 10), dice: atk.dice_count, speed: atk.speed, successes: atk.successes }
    };

    // Shield of Faith: the shielding caster blocks as a separate Opposing Roll,
    // spending Reservoir dice (the target's own Defense stays out).
    if (defenseName === 'shield') {
      const sh = rolls.find((r) => r.id === 'shield') || {};
      return Object.assign(base, {
        defense: { choice: 'none' },
        shield: { id: parseInt(defType.split(':')[1], 10), dice: parseInt(defFull.split('|')[1], 10) || 0,
                  successes: sh.successes || 0, spell_name: 'Shield of Faith' }
      });
    }

    const def = rolls.find((r) => r.id === 'defender');
    const declared = def && defenseName !== 'none';
    return Object.assign(base, {
      defense: declared
        ? { choice: defenseName, id: choices.target, dice: def.dice_count, speed: def.speed || 0, successes: def.successes }
        : { choice: 'none' }
    });
  }

  // First Confirm: non-mutating preview. Keep the builder; show the editable
  // result underneath so the DM can still go back.
  static _preview(container, detail) {
    container._lastDetail = detail;
    const payload = TurnAttack._payload(container, detail, false);
    TurnAttack._post(container, payload, (res) => TurnAttack._renderResult(container, res, false));
  }

  // Second Confirm: apply the attack for real, carrying any DM edits and the
  // rolled magical Damage Riders.
  static _commit(container) {
    if (!container._lastDetail) return;
    const payload = TurnAttack._payload(container, container._lastDetail, true);
    payload.override = TurnAttack._gatherOverride(container);
    payload.rider_results = TurnAttack._gatherRiders(container);
    TurnAttack._post(container, payload, (res) => TurnAttack._renderResult(container, res, true));
  }

  // The rider amounts for the commit payload, read from the (DM-editable)
  // damage screen boxes: one { id, damage, self_damage } per rider.
  static _gatherRiders(container) {
    const screen = container.querySelector('.ta-damage-screen');
    return (container._riders || []).map((rider) => {
      const dmgEl = screen && screen.querySelector(`.ta-rider-dmg-input[data-id="${rider.id}"]`);
      const selfEl = screen && screen.querySelector(`.ta-rider-self-input[data-id="${rider.id}"]`);
      return { id: rider.id, damage: dmgEl ? num(dmgEl.value) : 0, self_damage: selfEl ? num(selfEl.value) : 0 };
    });
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

    if (committed) {
      // Attack applied — the panel's work is done. Reload so the tracker
      // reflects the new HP / Combat Pool and the Attack pane resets; no
      // intermediate result screen.
      window.location.reload();
      return;
    }

    container._riders = res.riders || [];
    container._riderRolls = {};

    // When the weapon has Damage Riders, the rider Roll Resolution Stub is
    // injected into the attack builder's own results block — directly under the
    // Net Degree of Success line and above its Change button — so it reads as a
    // continuation of the same attack table, with its Roll / Confirm in the same
    // place the attack roll's were. The DM rolls + Confirms it, it collapses to
    // a row beneath Net Degree of Success, and only then is the editable damage
    // screen (in .ta-result below) revealed. With no riders the damage screen
    // shows straight away.
    if (container._riders.length) {
      const { tn, dieSize } = TurnAttack._attackerTn(container);
      const results = container.querySelector('.action-builder .rolls-results');
      const prior = results && results.querySelector('.ta-rider-stub');
      if (prior) prior.remove();
      const stubHtml = `<div class="ta-rider-stub">${TurnAttack._riderStubHtml(container._riders, tn, dieSize)}</div>`;
      const changeBtn = results && results.querySelector('.btn-rolls-change');
      if (changeBtn) changeBtn.insertAdjacentHTML('beforebegin', stubHtml);
      else if (results) results.insertAdjacentHTML('beforeend', stubHtml);
      slot.hidden = false;
      slot.innerHTML = '<div class="ta-damage-screen" hidden></div>';
    } else {
      slot.hidden = false;
      slot.innerHTML = '<div class="ta-damage-screen"></div>';
      TurnAttack._renderDamageScreen(container, res);
    }
  }

  // Build the editable damage screen + Commit button. The weapon's base
  // Damage, each magical rider's bonus Damage (its own box), any Vicious-style
  // self-inflicted Damage (its own box), Bleed, and per-participant Combat
  // Pool are all editable; the rider boxes are prefilled from the rider roll.
  static _renderDamageScreen(container, res) {
    const screen = container.querySelector('.ta-damage-screen');
    if (!screen) return;
    const nameOf = TurnAttack._namer(container);
    const spends = (res.pool_spends || []).filter((s) => s.amount > 0);
    const rolls = container._riderRolls || {};
    const rows = [];
    const gap = num(res.inherent_dr) > 0 ? ` <span class="ta-dim">(−${num(res.inherent_dr)} tier mismatch)</span>` : '';
    rows.push(`<div class="ta-field"><label>Damage` +
      ` <input type="number" class="ta-dmg-input" value="${res.damage}" min="0"></label>` +
      ` <span class="ta-dim">${res.damage_type || ''}</span>${gap} <span class="ta-split"></span></div>`);
    // One bonus-damage box per rider (separate from the base damage and from
    // each other), plus a self-damage box for a rider that bites the wielder.
    (container._riders || []).forEach((rider) => {
      const roll = rolls[rider.id] || { damage: 0, self_damage: 0 };
      const note = rider.kind === 'named_effect' ? cap(String(rider.effect || '')) : (rider.damage_type || '');
      const sev = rider.severity ? rider.severity + ' ' : '';
      rows.push(`<div class="ta-field"><label>${esc(rider.label)} damage` +
        ` <input type="number" class="ta-rider-dmg-input" data-id="${rider.id}" value="${roll.damage}" min="0"></label>` +
        ` <span class="ta-dim">${sev}${esc(note)}</span></div>`);
      if (rider.self_damage) {
        rows.push(`<div class="ta-field"><label>Self damage (wielder)` +
          ` <input type="number" class="ta-rider-self-input" data-id="${rider.id}" value="${roll.self_damage}" min="0"></label>` +
          ` <span class="ta-dim">${esc(rider.self_damage.severity)}</span></div>`);
      }
    });
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
    screen.innerHTML = rows.join('');
    // Surface a Commit button at the top of the Turn Action stub (the action
    // menu's confirm slot) so the DM commits without reaching down to the
    // result. It proxies to the real Commit button rendered above.
    placeCommitProxy(container, 'Commit attack');
    TurnAttack._renderSplit(container);
  }

  // Markup for the rider Roll Resolution Stub — the standard `.rolls-wrapper`
  // the dice engine + app.js delegation already drive (Roll All / Confirm /
  // Change). One Roll per rider: `rider.dice` dice at the attack's TN.
  static _riderStubHtml(riders, tn, dieSize) {
    // failure_modifier 0: rider (bonus) damage counts Successes and Crits but
    // never lets a rolled 1 subtract from the total. Crits still count double
    // (the Dice Resolution default critical_modifier), so the Result column is
    // the bonus damage the rider deals.
    const cfgFor = (r) => esc(JSON.stringify({ dice_count: r.dice, tn: tn, die_size: dieSize, starting_value: 0, failure_modifier: 0 }));
    const bodies = riders.map((r, i) => (
      `<tbody class="roll-group" data-roll-idx="${i}" data-rider-id="${r.id}" data-roll-id="rider-${r.id}" data-config='${cfgFor(r)}'>` +
        '<tr class="roll-row row-initial">' +
          `<td rowspan="1" class="character-cell">` +
            `<span class="stub-line creature-name">${esc(r.label)}</span>` +
            `<span class="stub-line params">${r.dice} dice @ TN ${tn}</span>` +
            `<span class="stub-line roll-name"><em>(${esc(TurnAttack._riderTypeNote(r))})</em></span>` +
          '</td>' +
          '<td class="mod-cell"></td><td class="mod-cell"></td>' +
          '<td class="dice-cell"><span class="dice-placeholder">[ &mdash; ]</span></td>' +
          '<td rowspan="1" class="result-cell"><input class="result-input" type="text" value=""></td>' +
          '<td rowspan="1" class="result-cell"><input class="result-input" type="text" value=""></td>' +
          '<td rowspan="1" class="lock-cell"><button type="button" class="lock-btn" aria-label="Toggle lock"></button></td>' +
        '</tr>' +
      '</tbody>'
    )).join('');
    const resultRows = riders.map((r, i) => (
      `<div class="rolls-result-row" data-roll-idx="${i}">` +
        `<span class="rolls-result-name">${esc(r.label)}:</span>` +
        '<span class="rolls-result-value"></span>' +
      '</div>'
    )).join('');
    const rollLabel = riders.length > 1 ? 'Roll All' : 'Roll';
    return '<div class="rolls-wrapper" data-stub="roll" data-state="active">' +
      '<div class="rolls-header">' +
        '<span class="rolls-title">Damage Riders</span>' +
        '<div class="rolls-actions">' +
          `<button type="button" class="btn-roll-all">${rollLabel}</button>` +
          '<button type="button" class="btn-confirm">Confirm</button>' +
        '</div>' +
      '</div>' +
      '<table class="stub-table roll-table">' +
        '<colgroup><col class="col-character"><col class="col-mod"><col class="col-mod"><col class="col-dice"><col class="col-result"><col class="col-result"><col class="col-lock"></colgroup>' +
        '<thead><tr><th>Rider</th><th>Reroll</th><th>Nudge</th><th>Dice</th><th>Result</th><th>Crits</th><th></th></tr></thead>' +
        bodies +
      '</table>' +
      '<div class="rolls-results" hidden>' + resultRows +
        '<button type="button" class="btn-rolls-change"><span class="cr-change-icon">↶</span> Change</button>' +
      '</div>' +
    '</div>';
  }

  static _riderTypeNote(r) {
    return r.kind === 'named_effect' ? cap(String(r.effect || '')) : (r.damage_type || '');
  }

  // The rider stub's Confirm: read each rider's rolled dice, record the
  // Successes / 1s for the commit payload, relabel its collapsed row with the
  // damage it deals, and reveal the damage screen. Deferred so app.js's
  // collapse (the shared .btn-confirm handler) runs first.
  static _onRiderConfirm(container) {
    TurnAttack._computeRiderResults(container);
    setTimeout(() => {
      const stub = container.querySelector('.ta-rider-stub');
      (container._riders || []).forEach((rider) => {
        const r = container._riderRolls[rider.id] || { damage: 0, self_damage: 0 };
        const cell = stub && stub.querySelector(`.rolls-result-row[data-roll-idx="${rider.id}"] .rolls-result-value`);
        if (cell) cell.textContent = TurnAttack._riderOutcomeText(rider, r);
      });
      TurnAttack._renderDamageScreen(container, container._lastRes || {});
      const screen = container.querySelector('.ta-damage-screen');
      if (screen) screen.hidden = false;
    }, 0);
  }

  // The rider stub's Change re-opens the dice: hide the damage screen until the
  // DM re-Confirms the riders.
  static _onRiderChange(container) {
    container._riderRolls = {};
    const screen = container.querySelector('.ta-damage-screen');
    if (screen) { screen.hidden = true; screen.innerHTML = ''; }
  }

  // Read each rider roll's outcome. The bonus damage is the roll's Result
  // (Degrees of Success with failure_modifier 0 — Crits count double, 1s never
  // subtract) times the rider's per-Success amount. A rolled 1 only feeds
  // Vicious-style self-damage (minimum + amount per 1), never the bonus damage.
  static _computeRiderResults(container) {
    const stub = container.querySelector('.ta-rider-stub');
    const rolls = {};
    (container._riders || []).forEach((rider) => {
      const g = stub && stub.querySelector(`tbody.roll-group[data-rider-id="${rider.id}"]`);
      let result = 0; let ones = 0;
      if (g) {
        const input = g.querySelector('.result-input');
        result = input ? num(input.value) : 0;
        ones = g.querySelectorAll('.dice-cell .die.fail').length;
      }
      const damage = Math.max(0, result) * (rider.amount || 1);
      const self = rider.self_damage
        ? (rider.self_damage.minimum || 0) + ones * (rider.self_damage.amount || 0)
        : 0;
      rolls[rider.id] = { result: result, ones: ones, damage: damage, self_damage: self };
    });
    container._riderRolls = rolls;
  }

  // Human-readable summary of a rolled rider, mirroring the server's math.
  static _riderOutcomeText(rider, roll) {
    const parts = [];
    if (rider.kind === 'named_effect') {
      parts.push(`${roll.damage} ${rider.effect}`);
    } else {
      const sev = rider.severity ? ' ' + rider.severity : '';
      parts.push(`${roll.damage}${sev} ${rider.damage_type}`);
    }
    if (rider.self_damage) {
      parts.push(`wielder takes ${roll.self_damage} ${rider.self_damage.severity}`);
    }
    return parts.join('; ');
  }

  // The attacker Roll's Target Number and die size, read from the builder's
  // attacker roll-group config (where the rider dice are rolled).
  static _attackerTn(container) {
    const g = container.querySelector('.roll-group[data-roll-id="attacker"]');
    let tn = 0; let dieSize = 6;
    if (g) { try { const c = JSON.parse(g.dataset.config); tn = c.tn; dieSize = c.die_size; } catch (e) { /* defaults */ } }
    return { tn: tn, dieSize: dieSize };
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
function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/'/g, '&#39;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

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
