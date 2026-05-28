import { DiceConfig } from '../config.js';
import { RandomRng } from '../rng.js';
import { Reroll } from '../reroll.js';
import { Nudge } from '../nudge.js';
import { Scoring } from '../scoring.js';
import { merge } from '../roll.js';
import { DiceRenderer } from './diceRenderer.js';

// Drives the "Roll" / "Roll All" buttons. Reads each per-Roll <tbody>'s
// data-config, runs the dice through the Dice Resolution primitives, and
// writes the dice rows + Result/Crits inputs back into the table.
//
// The stub's config carries a precomputed `tn` and `starting_value`
// (upstream Bonus/Penalty sources — proficiencies, abilities, conditions
// — aren't wired in yet), plus a single reroll slot, an optional
// mass_reroll, and a nudge. Those map onto the domain's positive/negative
// reroll slots and value adjustment here.
export class RollController {
  static rollAll(wrapper) {
    wrapper.querySelectorAll('tbody.roll-group').forEach((group) => {
      if (group.querySelector('.lock-btn.locked')) return;
      RollController.rollGroup(group);
    });
  }

  static rollGroup(group) {
    const cfg = JSON.parse(group.dataset.config);
    const config = new DiceConfig({ dieSize: cfg.die_size });
    const dieSize = config.dieSize;
    const tn = cfg.tn;
    const startingValue = parseInt(cfg.starting_value, 10) || 0;
    const rng = new RandomRng();

    const initial = rng.rollDice(cfg.dice_count, dieSize);
    let current = initial.slice();
    const skip = new Set();

    RollController._render(group, '.row-initial', DiceRenderer.renderDice(initial, tn, dieSize, startingValue));

    if (cfg.reroll) {
      const changes = Reroll.applyWithTn(current, RollController._slots(cfg.reroll), tn, rng, config, skip);
      RollController._markRerolled(skip, changes);
      current = merge(current, changes);
      RollController._render(group, '.row-reroll', DiceRenderer.renderDice(changes, tn, dieSize, startingValue, 'spacer'));
    }

    if (cfg.mass_reroll) {
      const slots = RollController._slots({ sign: cfg.mass_reroll.sign, max: true });
      const changes = Reroll.applyWithTn(current, slots, tn, rng, config, skip);
      RollController._markRerolled(skip, changes);
      current = merge(current, changes);
      RollController._render(group, '.row-mass-reroll', DiceRenderer.renderDice(changes, tn, dieSize, startingValue, 'spacer'));
    }

    if (cfg.nudge) {
      const valueAdjustment = {
        value: cfg.nudge.sign === 'neg' ? -cfg.nudge.count : cfg.nudge.count,
        max: cfg.nudge.max,
      };
      const changes = Nudge.applyWithTn(current, valueAdjustment, {
        tn,
        failureModifier: config.defaultFailureModifier,
        criticalModifier: config.defaultCriticalModifier,
      }, config);
      current = merge(current, changes);
      RollController._render(group, '.row-nudge', DiceRenderer.renderDice(changes, tn, dieSize, startingValue, 'spacer'));
    }

    const { dois, criticalCount } = Scoring.score(current, {
      tn,
      startingValue,
      failureModifier: config.defaultFailureModifier,
      criticalModifier: config.defaultCriticalModifier,
    }, config);

    const inputs = group.querySelectorAll('.result-input');
    if (inputs[0]) {
      inputs[0].value = dois;
      inputs[0].dispatchEvent(new Event('change', { bubbles: true }));
    }
    if (inputs[1]) inputs[1].value = criticalCount;
  }

  static _render(group, rowSelector, html) {
    const cell = group.querySelector(rowSelector + ' .dice-cell');
    if (cell) cell.innerHTML = html;
  }

  // UI single-slot reroll -> domain positive/negative slots.
  static _slots(mod) {
    const slot = { count: mod.count, max: !!mod.max };
    return {
      positiveReroll: mod.sign === 'pos' ? slot : null,
      negativeReroll: mod.sign === 'neg' ? slot : null,
    };
  }

  static _markRerolled(skip, changes) {
    changes.forEach((c, i) => {
      if (c !== null && c !== undefined) skip.add(i);
    });
  }
}
