import { DiceConfig } from '../config.js';
import { RandomRng } from '../randomRng.js';
import { Scoring } from '../scoring.js';
import { DiceRenderer } from './diceRenderer.js';

// Drives the compact Skill-Roll stub (_compact_roll_stub.erb). It is rolled
// once, the moment the stub is injected (the Skill list's Roll button is the
// only trigger): it rolls the dice through the Dice Resolution primitives,
// shows every die, reveals the result, then POSTs the roll to the Log — so a
// player rolls in the open and cannot silently fish for a better outcome.
export class CompactRoll {
  static roll(el) {
    if (el.dataset.rolled === '1') return;
    el.dataset.rolled = '1';

    const cfg = JSON.parse(el.dataset.config);
    const meta = JSON.parse(el.dataset.meta || '{}');
    const config = new DiceConfig({ dieSize: cfg.die_size });
    const dieSize = config.dieSize;
    const tn = cfg.tn;
    const startingValue = parseInt(cfg.starting_value, 10) || 0;

    const dice = new RandomRng().rollDice(cfg.dice_count, dieSize);

    const diceEl = el.querySelector('.compact-roll-dice');
    if (diceEl) diceEl.innerHTML = DiceRenderer.renderDice(dice, tn, dieSize, startingValue);

    const { dois, criticalCount } = Scoring.score(dice, {
      tn,
      startingValue,
      failureModifier: config.defaultFailureModifier,
      criticalModifier: config.defaultCriticalModifier,
    }, config);

    const resEl = el.querySelector('.compact-roll-result');
    if (resEl) {
      resEl.textContent = CompactRoll._resultText(dois, criticalCount);
      resEl.hidden = false;
    }

    // Best-effort delivery to the DM Page Roll Log; the roll is already shown locally.
    fetch('/dm/roll', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        creature_id: meta.creature_id,
        creature_name: meta.creature_name,
        roll_name: meta.roll_name,
        ranks: meta.ranks,
        tn,
        base_tn: meta.base_tn,
        bonus_penalty_list: meta.bonus_penalty_list,
        dice_count: cfg.dice_count,
        starting_value: startingValue,
        dice,
        dois,
        critical_count: criticalCount,
      }),
    }).catch(function () { /* log delivery is best-effort */ });
  }

  static _resultText(dois, crits) {
    const s = dois + (Math.abs(dois) === 1 ? ' success' : ' successes');
    const c = crits > 0 ? ' · ' + crits + (crits === 1 ? ' crit' : ' crits') : '';
    return s + c;
  }
}
