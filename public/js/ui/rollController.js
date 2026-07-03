import { DiceConfig } from '../config.js';
import { RandomRng } from '../randomRng.js';
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
    // A Roll may override the scoring modifiers (e.g. magical Damage Riders
    // score bonus damage without letting 1s count against it: failure_modifier
    // 0). Absent, the Dice Resolution defaults apply.
    const failureModifier = cfg.failure_modifier != null ? cfg.failure_modifier : config.defaultFailureModifier;
    const criticalModifier = cfg.critical_modifier != null ? cfg.critical_modifier : config.defaultCriticalModifier;
    const rng = new RandomRng();

    const initial = rng.rollDice(cfg.dice_count, dieSize);
    let current = initial.slice();
    const skip = new Set();

    RollController._render(group, '.row-initial', DiceRenderer.renderDice(initial, tn, dieSize, startingValue));

    // Reroll: the Roll's positive (low-die) and negative (high-die) slots,
    // applied in a single domain pass (no die rerolled twice). The legacy
    // single-slot `reroll` (StepMachine / manual) and the two-slot
    // `positive_reroll` / `negative_reroll` (composed upstream, e.g. Luck) both
    // feed the same Reroll primitive — Roll Resolution owns the application.
    const rerollSlots = RollController._rerollSlots(cfg);
    if (rerollSlots.positiveReroll || rerollSlots.negativeReroll) {
      const changes = Reroll.applyWithTn(current, rerollSlots, tn, rng, config, skip);
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
        failureModifier,
        criticalModifier,
      }, config);
      current = merge(current, changes);
      RollController._render(group, '.row-nudge', DiceRenderer.renderDice(changes, tn, dieSize, startingValue, 'spacer'));
    }

    const { dois, criticalCount } = Scoring.score(current, {
      tn,
      startingValue,
      failureModifier,
      criticalModifier,
    }, config);

    // Stash the final (post-reroll/nudge) dice so a host that logs the Roll —
    // e.g. the DM Page Skill action — can record the actual dice it showed.
    group.dataset.rolledDice = JSON.stringify(current);

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

  // The Roll's reroll slots for the domain Reroll primitive, reading the
  // two-slot `positive_reroll` / `negative_reroll` config (composed upstream)
  // and the legacy single-slot `reroll` (StepMachine / manual).
  static _rerollSlots(cfg) {
    let pos = cfg.positive_reroll ? { count: cfg.positive_reroll.count, max: !!cfg.positive_reroll.max } : null;
    let neg = cfg.negative_reroll ? { count: cfg.negative_reroll.count, max: !!cfg.negative_reroll.max } : null;
    if (cfg.reroll) {
      const s = RollController._slots(cfg.reroll);
      if (s.positiveReroll) pos = s.positiveReroll;
      if (s.negativeReroll) neg = s.negativeReroll;
    }
    return { positiveReroll: pos, negativeReroll: neg };
  }

  static _markRerolled(skip, changes) {
    changes.forEach((c, i) => {
      if (c !== null && c !== undefined) skip.add(i);
    });
  }
}
