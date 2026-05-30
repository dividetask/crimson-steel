import { CheckResolution } from '../check.js';
import { DiceConfig } from '../config.js';
import { RandomRng } from '../rng.js';
import { DiceRenderer } from './diceRenderer.js';

// Turn Action panel — Attack flow (turn_action_stub.md → Attack).
//
// Drives the multi-step attack against the live Encounter pipeline:
//   GET  /encounter/attack_options  — attacker's weapons + targets
//   POST /encounter/build_attack    — Roll specs (Dice Caps, bonuses,
//                                     eligible defenses) for the chosen
//                                     target / weapon / defense
//   POST /encounter/resolve_attack  — spends Combat Pool, nets Successes,
//                                     applies damage
//
// The dice are resolved client-side by the shared Check engine
// (CheckResolution), the same math the Dice / Check Resolution stubs use.
// Stages: select (target/weapon/defense) → dice → roll → done.
export class TurnAttack {
  // Lazy-load the options the first time the Attack pane is opened.
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
        st.targetId = data.targets[0].combatant_id;
        st.weapon = data.weapons[0];
        st.defense = 'none';
        st.stage = 'select';
        TurnAttack._render(container);
      })
      .catch(() => fail(container, 'Could not load attack options.'));
  }

  static _bind(container) {
    container.addEventListener('click', (e) => {
      const btn = e.target.closest && e.target.closest('button');
      if (!btn || !container.contains(btn)) return;
      const st = container._ta;
      if (btn.classList.contains('ta-opt-target')) { st.targetId = num(btn.dataset.id); TurnAttack._render(container); }
      else if (btn.classList.contains('ta-opt-weapon')) { st.weapon = st.options.weapons.find((w) => w.item_type === btn.dataset.weapon); st.defense = 'none'; TurnAttack._render(container); }
      else if (btn.classList.contains('ta-opt-defense')) { st.defense = btn.dataset.defense; TurnAttack._render(container); }
      else if (btn.classList.contains('ta-build')) { TurnAttack._build(container); }
      else if (btn.classList.contains('ta-opt-atkdice')) { st.attackerDice = num(btn.dataset.dice); TurnAttack._render(container); }
      else if (btn.classList.contains('ta-opt-defdice')) { st.defenseDice = num(btn.dataset.dice); TurnAttack._render(container); }
      else if (btn.classList.contains('ta-roll')) { TurnAttack._roll(container); }
      else if (btn.classList.contains('ta-resolve')) { TurnAttack._resolve(container); }
      else if (btn.classList.contains('ta-back')) { st.stage = 'select'; TurnAttack._render(container); }
      else if (btn.classList.contains('ta-continue')) { window.location.reload(); }
    });
  }

  // ----- stage transitions -----

  static _build(container) {
    const st = container._ta;
    const kind = st.weapon.ranged ? 'ranged' : 'melee';
    postForm('/encounter/build_attack', {
      attacker_id: st.attackerId, target_id: st.targetId,
      weapon: st.weapon.item_type, defense: st.defense, hidden: 'false'
    }).then((spec) => {
      if (!spec || !spec.ok) return fail(container, (spec && spec.error) || 'Could not build the attack.');
      st.spec = spec;
      st.kind = spec.attack_kind || kind;
      st.declared = st.defense !== 'none';
      // Default the attacker to the largest affordable dice count.
      const atk = TurnAttack._attackerDiceBounds(st);
      st.attackerDice = atk.max >= atk.min ? atk.max : 0;
      if (st.declared && spec.defense) st.defenseDice = spec.defense.max_dice;
      st.stage = 'dice';
      TurnAttack._render(container);
    }).catch(() => fail(container, 'Could not build the attack.'));
  }

  static _roll(container) {
    const st = container._ta;
    const config = DiceConfig.default();
    const supporting = [{
      diceCount: st.attackerDice,
      bonusPenaltyList: (st.spec.attacker && st.spec.attacker.bonus_penalty_list) || [],
      criticalModifier: st.spec.attacker && st.spec.attacker.critical_modifier
    }];
    const opposing = st.declared ? [{
      diceCount: st.defenseDice,
      bonusPenaltyList: (st.spec.defense && st.spec.defense.bonus_penalty_list) || []
    }] : [];

    const res = CheckResolution.resolveCheck({ supporting, opposing }, new RandomRng(), config);
    st.roll = res;
    st.attackerSuccesses = res.supportingResults[0].dois;
    st.defenseSuccesses = st.declared ? res.opposingResults[0].dois : 0;
    st.stage = 'roll';
    TurnAttack._render(container);
  }

  static _resolve(container) {
    const st = container._ta;
    const atkSucc = num(valOf(container, '.ta-succ-atk', st.attackerSuccesses));
    const defSucc = st.declared ? num(valOf(container, '.ta-succ-def', st.defenseSuccesses)) : 0;
    const weapon = st.spec.weapon || st.spec.attacker.weapon || {};
    const payload = {
      target_id: st.targetId,
      attack_kind: st.kind,
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

  static _reset() { /* reserved */ }

  // Attacker dice are capped by the weapon's Dice Cap and by what the
  // Combat Pool can afford (dice × Speed ≤ remaining pool).
  static _attackerDiceBounds(st) {
    const speed = Math.max(1, (st.spec.attacker && st.spec.attacker.speed) || 1);
    const cap = (st.spec.attacker && st.spec.attacker.dice_cap) || 0;
    const max = Math.min(cap, Math.floor(st.poolRemaining / speed));
    return { min: 1, max, speed };
  }

  // ----- rendering -----

  static _render(container) {
    const st = container._ta;
    if (st.stage === 'select') container.innerHTML = TurnAttack._renderSelect(st);
    else if (st.stage === 'dice') container.innerHTML = TurnAttack._renderDice(st);
    else if (st.stage === 'roll') container.innerHTML = TurnAttack._renderRoll(st);
    else if (st.stage === 'done') container.innerHTML = TurnAttack._renderDone(st);
  }

  static _renderSelect(st) {
    const targets = st.options.targets.map((t) =>
      optBtn('ta-opt-target', { id: t.combatant_id }, t.name, t.combatant_id === st.targetId)).join('');
    const weapons = st.options.weapons.map((w) =>
      optBtn('ta-opt-weapon', { weapon: w.item_type }, `${w.display_name} <span class="ta-dim">(Spd ${w.speed}${w.ranged ? ', ranged' : ''})</span>`,
        w.item_type === st.weapon.item_type)).join('');
    const defenses = ['none', 'dodge', 'block'].concat(st.weapon.ranged ? [] : ['parry'])
      .map((d) => optBtn('ta-opt-defense', { defense: d }, cap(d), d === st.defense)).join('');
    return (
      group('Target', targets) +
      group('Weapon', weapons) +
      group('Target&rsquo;s defense', defenses) +
      `<div class="ta-actions"><button type="button" class="ce-btn ta-build">Build attack →</button></div>`
    );
  }

  static _renderDice(st) {
    const b = TurnAttack._attackerDiceBounds(st);
    if (b.max < b.min) {
      return summary(st) + `<p class="ta-warn">Not enough Combat Pool to attack with this weapon.</p>` +
        `<div class="ta-actions"><button type="button" class="ce-btn ta-back">← Back</button></div>`;
    }
    const atkStrip = strip('ta-opt-atkdice', b.min, b.max, st.attackerDice);
    let defBlock = '';
    if (st.declared && st.spec.defense) {
      const d = st.spec.defense;
      if (d.pool_cost) {
        defBlock = group(`${cap(st.defense)} dice`, strip('ta-opt-defdice', d.min_dice, d.max_dice, st.defenseDice));
      } else {
        defBlock = group(`${cap(st.defense)}`, `<span class="ta-dim">Saving throw — full Dice Cap (${d.dice_cap}d), no Combat Pool.</span>`);
      }
    }
    return (
      summary(st) +
      group(`Attacker dice <span class="ta-dim">(Cap ${st.spec.attacker.dice_cap}d, Speed ${b.speed})</span>`, atkStrip) +
      defBlock +
      `<div class="ta-actions"><button type="button" class="ce-btn ta-back">← Back</button> <button type="button" class="ce-btn ta-roll">Roll →</button></div>`
    );
  }

  static _renderRoll(st) {
    const config = DiceConfig.default();
    const ar = st.roll.supportingResults[0];
    let out = summary(st) +
      `<div class="ta-roll-row"><span class="ta-roll-label">Attacker</span> ` +
      DiceRenderer.renderDice(ar.finalDice, ar.tn, config.dieSize, ar.startingValue, 'shown') +
      ` <span class="ta-dim">DoIS ${ar.dois}</span></div>` +
      `<label class="ta-succ">Successes <input type="number" class="ta-succ-atk" value="${st.attackerSuccesses}"></label>`;
    if (st.declared) {
      const dr = st.roll.opposingResults[0];
      out += `<div class="ta-roll-row"><span class="ta-roll-label">${cap(st.defense)}</span> ` +
        DiceRenderer.renderDice(dr.finalDice, dr.tn, config.dieSize, dr.startingValue, 'shown') +
        ` <span class="ta-dim">DoIS ${dr.dois}</span></div>` +
        `<label class="ta-succ">Successes <input type="number" class="ta-succ-def" value="${st.defenseSuccesses}"></label>`;
    }
    out += `<div class="ta-actions"><button type="button" class="ce-btn ta-back">← Back</button> <button type="button" class="ce-btn ta-resolve">Resolve attack</button></div>`;
    return out;
  }

  static _renderDone(st) {
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
    return summary(st) + body +
      `<div class="ta-actions"><button type="button" class="ce-btn ta-continue">Continue</button></div>`;
  }
}

// ----- helpers -----

function summary(st) {
  const target = st.options.targets.find((t) => t.combatant_id === st.targetId);
  const def = st.defense === 'none' ? 'no defense' : cap(st.defense);
  return `<p class="ta-summary"><strong>${st.weapon.display_name}</strong> → <strong>${target ? target.name : 'target'}</strong> <span class="ta-dim">(${def})</span></p>`;
}

function group(label, inner) {
  return `<div class="ta-step"><div class="ta-step-label">${label}</div><div class="ta-step-opts">${inner}</div></div>`;
}

function optBtn(cls, data, label, selected) {
  const attrs = Object.keys(data).map((k) => `data-${k}="${data[k]}"`).join(' ');
  return `<button type="button" class="ta-opt ${cls}${selected ? ' ta-opt-on' : ''}" ${attrs}>${label}</button>`;
}

function strip(cls, min, max, current) {
  let out = '';
  for (let n = min; n <= max; n++) {
    out += `<button type="button" class="ta-opt ${cls}${n === current ? ' ta-opt-on' : ''}" data-dice="${n}">${n}d</button>`;
  }
  return out || '<span class="ta-dim">—</span>';
}

function cap(s) { return String(s).charAt(0).toUpperCase() + String(s).slice(1); }
function num(v) { const n = parseInt(v, 10); return Number.isNaN(n) ? 0 : n; }
function valOf(container, sel, fallback) { const el = container.querySelector(sel); return el ? el.value : fallback; }
function fail(container, msg) { container.innerHTML = `<p class="ta-warn">${msg}</p>`; }

function fetchJSON(url) {
  return fetch(url, { headers: { Accept: 'application/json' } }).then((r) => r.json().catch(() => null));
}
function postForm(url, params) {
  return fetch(url, { method: 'POST', body: new URLSearchParams(params) }).then((r) => r.json().catch(() => null));
}
function postJSON(url, payload) {
  return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })
    .then((r) => r.json().catch(() => null));
}
