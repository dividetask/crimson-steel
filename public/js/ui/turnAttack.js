// Turn Action panel — Attack flow (turn_action_stub.md → Attack).
//
// A progressive-disclosure wizard: one decision is shown at a time, and
// each completed decision collapses to a thin "<Label>: <value> [change]"
// row. The actual dice are resolved by the shared Check Resolution stub —
// this controller fetches that stub as a server fragment (so combat reuses
// the exact same Roll UI and engine the Dice/Check stubs use), lets the
// DM roll it, then reads the resolved Successes back out to resolve the
// attack. No dice math lives here.
//
// Backing endpoints (all server-side):
//   GET  /encounter/attack_options  — weapons (with Dice Cap + base damage) + targets
//   POST /encounter/attack_check    — renders the Check stub for the Roll
//   POST /encounter/resolve_attack  — spends Combat Pool, applies damage
export class TurnAttack {
  static ensureLoaded(container) {
    if (!container || container.dataset.taLoaded) return;
    container.dataset.taLoaded = '1';

    const st = {
      attackerId: num(container.getAttribute('data-attacker-id')),
      poolRemaining: num(container.getAttribute('data-pool-remaining')) || 0,
      stage: 'loading'
    };
    container._ta = st;
    TurnAttack._bind(container);
    container.innerHTML = '<p class="ta-attack-loading">Loading attack options…</p>';

    fetchJSON('/encounter/attack_options?attacker_id=' + encodeURIComponent(st.attackerId))
      .then((data) => {
        if (!data || !data.ok) return fail(container, 'Could not load attack options.');
        if (!data.weapons.length) return fail(container, 'This Combatant has no equipped weapons.');
        if (!data.targets.length) return fail(container, 'No other Combatants to target.');
        st.options = data;
        st.stage = 'target';
        TurnAttack._render(container);
      })
      .catch(() => fail(container, 'Could not load attack options.'));
  }

  static _bind(container) {
    container.addEventListener('click', (e) => {
      const btn = e.target.closest && e.target.closest('button');
      if (!btn || !container.contains(btn) || btn.disabled) return;
      const st = container._ta;
      if (btn.dataset.taChange) return TurnAttack._change(container, btn.dataset.taChange);
      if (btn.classList.contains('ta-opt-target')) { st.targetId = num(btn.dataset.id); TurnAttack._advance(container, 'weapon'); }
      else if (btn.classList.contains('ta-opt-weapon')) {
        // The weapon name picks the largest roll the Combat Pool affords.
        const w = TurnAttack._weaponByType(st, btn.dataset.weapon);
        TurnAttack._pickWeapon(container, w, TurnAttack._affordableMax(st, w));
      } else if (btn.classList.contains('ta-opt-wdice')) {
        TurnAttack._pickWeapon(container, TurnAttack._weaponByType(st, btn.dataset.weapon), num(btn.dataset.dice));
      } else if (btn.classList.contains('ta-opt-defense')) {
        st.defense = btn.dataset.defense; st.declared = st.defense !== 'none'; TurnAttack._enterRoll(container);
      } else if (btn.classList.contains('ta-resolve')) { TurnAttack._resolve(container); }
      else if (btn.classList.contains('ta-continue')) { window.location.reload(); }
    });
  }

  // ----- step flow -----

  static _advance(container, stage) { container._ta.stage = stage; TurnAttack._render(container); }

  static _pickWeapon(container, weapon, dice) {
    const st = container._ta;
    st.weapon = weapon;
    st.attackerDice = dice;
    st.stage = 'defense';
    TurnAttack._render(container);
  }

  // "change" on a completed row: jump back to that step and invalidate
  // every later decision so the DM re-walks the wizard from there.
  static _change(container, step) {
    const st = container._ta;
    const i = ['target', 'weapon', 'defense'].indexOf(step);
    if (i <= 0) { st.weapon = null; st.attackerDice = null; }
    if (i <= 1) { st.defense = null; st.declared = false; }
    st.result = null;
    st.stage = step;
    TurnAttack._render(container);
  }

  // Defense chosen → fetch the Check Resolution stub fragment and inject
  // it. The server folds the Competency + Attacker Bonuses into each
  // Roll's TN / Starting Value and defaults the defender's dice.
  static _enterRoll(container) {
    const st = container._ta;
    st.stage = 'roll';
    container.innerHTML = TurnAttack._doneRows(st, 'roll') +
      `<div class="ta-step"><div class="ta-step-label">Roll</div><div class="ta-check-slot"><p class="ta-attack-loading">Building roll…</p></div></div>` +
      `<div class="ta-actions"><button type="button" class="ce-btn ta-resolve">Resolve attack</button></div>`;
    postText('/encounter/attack_check', {
      attacker_id: st.attackerId, target_id: st.targetId,
      weapon: st.weapon.item_type, defense: st.defense, dice: st.attackerDice
    }).then((html) => {
      const slot = container.querySelector('.ta-check-slot');
      if (slot) slot.innerHTML = html;
    }).catch(() => {
      const slot = container.querySelector('.ta-check-slot');
      if (slot) slot.innerHTML = '<p class="ta-warn">Could not build the roll.</p>';
    });
  }

  static _resolve(container) {
    const st = container._ta;
    const w = st.weapon;
    const payload = {
      target_id: st.targetId,
      attack_kind: w.ranged ? 'ranged' : 'melee',
      weapon: { damage_types: w.damage_types, threshold: w.threshold, base_damage: w.base_damage },
      attacker: { id: st.attackerId, dice: st.attackerDice, speed: w.speed, successes: TurnAttack._successesAt(container, 0) },
      defense: st.declared
        ? { choice: st.defense, id: st.targetId, dice: TurnAttack._diceAt(container, 1), speed: 1, successes: TurnAttack._successesAt(container, 1) }
        : { choice: 'none' }
    };
    postJSON('/encounter/resolve_attack', payload).then((res) => {
      if (!res || res.ok === false) return fail(container, (res && res.error) || 'Could not resolve the attack.');
      st.result = res;
      st.stage = 'done';
      TurnAttack._render(container);
    }).catch(() => fail(container, 'Could not resolve the attack.'));
  }

  // Read resolved Successes / dice out of the injected Check stub —
  // roll-group 0 is the attacker, 1 is the declared defender. The Success
  // value reflects any manual override the DM typed into the Result field.
  static _successesAt(container, idx) {
    const input = container.querySelector('.roll-group[data-roll-idx="' + idx + '"] .result-input');
    return input ? num(input.value) : 0;
  }

  static _diceAt(container, idx) {
    const g = container.querySelector('.roll-group[data-roll-idx="' + idx + '"]');
    if (!g) return 0;
    try { return num(JSON.parse(g.dataset.config).dice_count); } catch (e) { return 0; }
  }

  static _weaponByType(st, type) { return st.options.weapons.find((w) => w.item_type === type); }

  // Largest dice count this weapon's Speed lets the Combat Pool afford,
  // capped by the weapon's Dice Cap.
  static _affordableMax(st, w) {
    return Math.min(w.dice_cap, Math.floor(st.poolRemaining / Math.max(1, w.speed || 1)));
  }

  // ----- rendering -----

  static _render(container) {
    const st = container._ta;
    if (st.stage === 'done') { container.innerHTML = TurnAttack._doneRows(st, 'done') + TurnAttack._renderResult(st); return; }
    if (st.stage === 'roll') { TurnAttack._enterRoll(container); return; }
    container.innerHTML = TurnAttack._doneRows(st, st.stage) + TurnAttack._renderStep(st);
  }

  static _doneRows(st, current) {
    const order = ['target', 'weapon', 'defense'];
    const values = {
      target: () => TurnAttack._targetName(st),
      weapon: () => (st.weapon ? `${st.weapon.display_name} — ${st.attackerDice}d` : ''),
      defense: () => (st.defense === 'none' ? 'No defense' : cap(st.defense))
    };
    const labels = { target: 'Target', weapon: 'Weapon', defense: 'Defense' };
    const stop = (current === 'done' || current === 'roll') ? order.length : order.indexOf(current);
    let out = '';
    for (let i = 0; i < stop; i++) {
      const k = order[i];
      out += `<div class="ta-done-row"><span class="ta-done-label">${labels[k]}</span>` +
        `<span class="ta-done-val">${values[k]()}</span>` +
        `<button type="button" class="ta-change" data-ta-change="${k}">change</button></div>`;
    }
    return out;
  }

  static _renderStep(st) {
    if (st.stage === 'target') {
      return group('Target', st.options.targets.map((t) =>
        optBtn('ta-opt-target', { id: t.combatant_id }, t.name)).join(''));
    }
    if (st.stage === 'weapon') {
      const rows = st.options.weapons.map((w) => {
        const speed = Math.max(1, w.speed || 1);
        const affMax = TurnAttack._affordableMax(st, w);
        let strip = '';
        for (let n = 2; n <= w.dice_cap; n++) {
          const ok = n * speed <= st.poolRemaining;
          strip += `<button type="button" class="ta-opt ta-opt-wdice" ${ok ? '' : 'disabled'} ` +
            `data-weapon="${w.item_type}" data-dice="${n}" title="${n} dice = ${n * speed} Combat Pool">${n}d</button>`;
        }
        const name = `<button type="button" class="ta-opt ta-wname ta-opt-weapon" ${affMax >= 2 ? '' : 'disabled'} ` +
          `data-weapon="${w.item_type}">${w.display_name} <span class="ta-dim">(Spd ${speed}${w.ranged ? ', ranged' : ''}, Cap ${w.dice_cap}d)</span></button>`;
        return `<div class="ta-weapon-row">${name}<div class="ta-wdice-strip">${strip || '<span class="ta-dim">—</span>'}</div></div>`;
      }).join('');
      return group('Weapon &amp; dice <span class="ta-dim">(name = max affordable)</span>', rows);
    }
    if (st.stage === 'defense') {
      const choices = ['none', 'dodge', 'block'].concat(st.weapon && st.weapon.ranged ? [] : ['parry']);
      return group('Target&rsquo;s defense', choices.map((d) =>
        optBtn('ta-opt-defense', { defense: d }, d === 'none' ? 'No defense' : cap(d))).join(''));
    }
    return '';
  }

  static _renderResult(st) {
    const r = st.result;
    let body;
    if (r.damage > 0) {
      const sev = r.severity_map || {};
      const parts = ['minor', 'moderate', 'major'].filter((k) => sev[k]).map((k) => `${sev[k]} ${cap(k)}`);
      body = `<p class="ta-hit">Hit for <strong>${r.damage}</strong> ${r.damage_type || ''} damage` +
        (parts.length ? ` <span class="ta-dim">(${parts.join(', ')})</span>` : '') +
        `.</p><p class="ta-dim">Net Degree of Success ${r.net_dos}.</p>`;
    } else {
      body = `<p class="ta-miss">No damage — net Degree of Success ${r.net_dos}.</p>`;
    }
    return body + `<div class="ta-actions"><button type="button" class="ce-btn ta-continue">Continue</button></div>`;
  }

  static _targetName(st) {
    const t = st.options.targets.find((x) => x.combatant_id === st.targetId);
    return t ? t.name : '';
  }
}

// ----- helpers -----

function group(label, inner) {
  return `<div class="ta-step"><div class="ta-step-label">${label}</div><div class="ta-step-opts">${inner}</div></div>`;
}
function optBtn(cls, data, label) {
  const attrs = Object.keys(data).map((k) => `data-${k}="${data[k]}"`).join(' ');
  return `<button type="button" class="ta-opt ${cls}" ${attrs}>${label}</button>`;
}
function cap(s) { return String(s).charAt(0).toUpperCase() + String(s).slice(1); }
function num(v) { const n = parseInt(v, 10); return Number.isNaN(n) ? 0 : n; }
function fail(container, msg) { container.innerHTML = `<p class="ta-warn">${msg}</p>`; }

function fetchJSON(url) {
  return fetch(url, { headers: { Accept: 'application/json' } }).then((r) => r.json().catch(() => null));
}
function postText(url, params) {
  return fetch(url, { method: 'POST', body: new URLSearchParams(params) }).then((r) => r.text());
}
function postJSON(url, payload) {
  return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })
    .then((r) => r.json().catch(() => null));
}
