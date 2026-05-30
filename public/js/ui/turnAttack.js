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
//   GET  /encounter/attack_options  — weapons + targets
//   POST /encounter/build_attack    — Dice Caps / Speed / eligible defenses
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
      if (!btn || !container.contains(btn)) return;
      const st = container._ta;
      if (btn.dataset.taChange) return TurnAttack._change(container, btn.dataset.taChange);
      if (btn.classList.contains('ta-opt-target')) { st.targetId = num(btn.dataset.id); TurnAttack._advance(container, 'weapon'); }
      else if (btn.classList.contains('ta-opt-weapon')) { st.weaponType = btn.dataset.weapon; TurnAttack._advance(container, 'defense'); }
      else if (btn.classList.contains('ta-opt-defense')) { st.defense = btn.dataset.defense; TurnAttack._afterDefense(container); }
      else if (btn.classList.contains('ta-opt-atkdice')) { st.attackerDice = num(btn.dataset.dice); TurnAttack._enterRoll(container); }
      else if (btn.classList.contains('ta-resolve')) { TurnAttack._resolve(container); }
      else if (btn.classList.contains('ta-continue')) { window.location.reload(); }
    });
  }

  // ----- step flow -----

  static _advance(container, stage) { container._ta.stage = stage; TurnAttack._render(container); }

  // "change" on a completed row: jump back to that step and invalidate
  // every later decision so the DM re-walks the wizard from there.
  static _change(container, step) {
    const st = container._ta;
    const order = ['target', 'weapon', 'defense', 'dice'];
    const i = order.indexOf(step);
    if (i <= 0) { st.weaponType = null; }
    if (i <= 1) { st.defense = null; st.spec = null; }
    if (i <= 2) { st.attackerDice = null; st.spec = null; }
    st.result = null;
    st.stage = step;
    TurnAttack._render(container);
  }

  // Defense chosen → fetch the Roll spec (Dice Caps, Speed, eligible
  // defenses) so the Dice step knows the attacker's bounds.
  static _afterDefense(container) {
    const st = container._ta;
    const weapon = TurnAttack._weapon(st);
    postForm('/encounter/build_attack', {
      attacker_id: st.attackerId, target_id: st.targetId,
      weapon: st.weaponType, defense: st.defense, hidden: 'false'
    }).then((spec) => {
      if (!spec || !spec.ok) return fail(container, (spec && spec.error) || 'Could not build the attack.');
      st.spec = spec;
      st.declared = st.defense !== 'none';
      // Default the defender to its largest roll (the DM can still adjust
      // the resulting Successes in the Check stub).
      if (st.declared && spec.defense) st.defenseDice = spec.defense.pool_cost ? spec.defense.max_dice : spec.defense.dice_cap;
      const b = TurnAttack._attackerDiceBounds(st);
      st.attackerDice = b.max >= b.min ? b.max : 0;
      st.stage = 'dice';
      TurnAttack._render(container);
    }).catch(() => fail(container, 'Could not build the attack.'));
  }

  // Dice chosen → fetch the Check Resolution stub fragment and inject it.
  static _enterRoll(container) {
    const st = container._ta;
    st.stage = 'roll';
    container.innerHTML = TurnAttack._doneRows(st, 'roll') +
      `<div class="ta-step"><div class="ta-step-label">Roll</div><div class="ta-check-slot"><p class="ta-attack-loading">Building roll…</p></div></div>` +
      `<div class="ta-actions"><button type="button" class="ce-btn ta-resolve">Resolve attack</button></div>`;
    postText('/encounter/attack_check', {
      attacker_id: st.attackerId, target_id: st.targetId, weapon: st.weaponType,
      defense: st.defense, dice: st.attackerDice, def_dice: st.declared ? st.defenseDice : ''
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
    const atkSucc = TurnAttack._successesAt(container, 0);
    const defSucc = st.declared ? TurnAttack._successesAt(container, 1) : 0;
    const weapon = st.spec.weapon || (st.spec.attacker && st.spec.attacker.weapon) || {};
    const payload = {
      target_id: st.targetId,
      attack_kind: st.spec.attack_kind,
      weapon: { damage_types: weapon.damage_types, threshold: weapon.threshold, base_damage: weapon.base_damage },
      attacker: { id: st.attackerId, dice: st.attackerDice, speed: st.spec.attacker.speed, successes: atkSucc },
      defense: st.declared
        ? { choice: st.defense, id: st.targetId, dice: st.defenseDice, speed: 1, successes: defSucc }
        : { choice: 'none' }
    };
    postJSON('/encounter/resolve_attack', payload).then((res) => {
      if (!res || res.ok === false) return fail(container, (res && res.error) || 'Could not resolve the attack.');
      st.result = res;
      st.stage = 'done';
      TurnAttack._render(container);
    }).catch(() => fail(container, 'Could not resolve the attack.'));
  }

  // Read the resolved Successes (DoIS) out of the injected Check stub —
  // roll-group 0 is the attacker, 1 is the declared defender. The value
  // reflects any manual override the DM typed into the result field.
  static _successesAt(container, idx) {
    const input = container.querySelector('.roll-group[data-roll-idx="' + idx + '"] .result-input');
    return input ? num(input.value) : 0;
  }

  static _attackerDiceBounds(st) {
    const speed = Math.max(1, (st.spec.attacker && st.spec.attacker.speed) || 1);
    const cap = (st.spec.attacker && st.spec.attacker.dice_cap) || 0;
    return { min: 1, max: Math.min(cap, Math.floor(st.poolRemaining / speed)), speed };
  }

  static _weapon(st) { return st.options.weapons.find((w) => w.item_type === st.weaponType); }

  // ----- rendering -----

  static _render(container) {
    const st = container._ta;
    if (st.stage === 'done') { container.innerHTML = TurnAttack._doneRows(st, 'done') + TurnAttack._renderResult(st); return; }
    if (st.stage === 'roll') { TurnAttack._enterRoll(container); return; }
    container.innerHTML = TurnAttack._doneRows(st, st.stage) + TurnAttack._renderStep(container, st);
  }

  // Thin summary rows for every step completed before `current`, each
  // with a Change affordance.
  static _doneRows(st, current) {
    const order = ['target', 'weapon', 'defense', 'dice'];
    const values = {
      target: () => TurnAttack._targetName(st),
      weapon: () => { const w = TurnAttack._weapon(st); return w ? w.display_name : ''; },
      defense: () => st.defense === 'none' ? 'No defense' : cap(st.defense),
      dice: () => st.attackerDice + 'd'
    };
    const labels = { target: 'Target', weapon: 'Weapon', defense: 'Defense', dice: 'Dice' };
    const stop = current === 'done' || current === 'roll' ? order.length : order.indexOf(current);
    let out = '';
    for (let i = 0; i < stop; i++) {
      const k = order[i];
      out += `<div class="ta-done-row"><span class="ta-done-label">${labels[k]}</span>` +
        `<span class="ta-done-val">${values[k]()}</span>` +
        `<button type="button" class="ta-change" data-ta-change="${k}">change</button></div>`;
    }
    return out;
  }

  static _renderStep(container, st) {
    if (st.stage === 'target') {
      return group('Target', st.options.targets.map((t) =>
        optBtn('ta-opt-target', { id: t.combatant_id }, t.name)).join(''));
    }
    if (st.stage === 'weapon') {
      return group('Weapon', st.options.weapons.map((w) =>
        optBtn('ta-opt-weapon', { weapon: w.item_type }, `${w.display_name} <span class="ta-dim">(Spd ${w.speed}${w.ranged ? ', ranged' : ''})</span>`)).join(''));
    }
    if (st.stage === 'defense') {
      const w = TurnAttack._weapon(st);
      const choices = ['none', 'dodge', 'block'].concat(w && w.ranged ? [] : ['parry']);
      return group('Target&rsquo;s defense', choices.map((d) =>
        optBtn('ta-opt-defense', { defense: d }, d === 'none' ? 'No defense' : cap(d))).join(''));
    }
    if (st.stage === 'dice') {
      const b = TurnAttack._attackerDiceBounds(st);
      if (b.max < b.min) {
        return `<p class="ta-warn">Not enough Combat Pool to attack with this weapon.</p>`;
      }
      return group(`Attacker dice <span class="ta-dim">(Cap ${st.spec.attacker.dice_cap}d, Speed ${b.speed})</span>`,
        strip('ta-opt-atkdice', b.min, b.max));
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
function strip(cls, min, max) {
  let out = '';
  for (let n = min; n <= max; n++) out += `<button type="button" class="ta-opt ${cls}" data-dice="${n}">${n}d</button>`;
  return out || '<span class="ta-dim">—</span>';
}
function cap(s) { return String(s).charAt(0).toUpperCase() + String(s).slice(1); }
function num(v) { const n = parseInt(v, 10); return Number.isNaN(n) ? 0 : n; }
function fail(container, msg) { container.innerHTML = `<p class="ta-warn">${msg}</p>`; }

function fetchJSON(url) {
  return fetch(url, { headers: { Accept: 'application/json' } }).then((r) => r.json().catch(() => null));
}
function postForm(url, params) {
  return fetch(url, { method: 'POST', body: new URLSearchParams(params) }).then((r) => r.json().catch(() => null));
}
function postText(url, params) {
  return fetch(url, { method: 'POST', body: new URLSearchParams(params) }).then((r) => r.text());
}
function postJSON(url, payload) {
  return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })
    .then((r) => r.json().catch(() => null));
}
