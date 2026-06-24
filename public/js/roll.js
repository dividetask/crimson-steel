import { DiceConfig } from './config.js';
import { RandomRng } from './randomRng.js';
import { TnComputation } from './tnComputation.js';
import { Reroll } from './reroll.js';
import { Nudge } from './nudge.js';
import { Scoring } from './scoring.js';
import { DiceResultString } from './diceResultString.js';

// Merge a changes array onto a dice array: a non-null change replaces the
// value at that position; null leaves the value untouched.
function merge(dice, changes) {
  return dice.map((v, i) => (changes[i] === null || changes[i] === undefined ? v : changes[i]));
}

// Full single-Roll pipeline. resolveWithTn computes a Roll Outcome;
// resolveWithoutTn produces only an ordering string. Both apply Reroll
// then Nudge (the fixed order of operations).
export class Roll {
  // Returns { tn, startingValue, initialDice, rerollChanges, nudgeChanges,
  //           finalDice, dois, criticalCount, outcome }.
  static resolveWithTn(roll, rng = new RandomRng(), config = DiceConfig.default()) {
    const failureModifier = roll.failureModifier != null ? roll.failureModifier : config.defaultFailureModifier;
    const criticalModifier = roll.criticalModifier != null ? roll.criticalModifier : config.defaultCriticalModifier;

    const { tn, startingValue } = TnComputation.compute(roll, config);
    const initialDice = rng.rollDice(roll.diceCount, config.dieSize);

    const rerollChanges = Reroll.applyWithTn(initialDice, roll, tn, rng, config);
    const afterReroll = merge(initialDice, rerollChanges);

    const nudgeChanges = Nudge.applyWithTn(afterReroll, roll.valueAdjustment, { tn, failureModifier, criticalModifier }, config);
    const finalDice = merge(afterReroll, nudgeChanges);

    const { dois, criticalCount, outcome } = Scoring.score(
      finalDice,
      { tn, startingValue, failureModifier, criticalModifier },
      config
    );

    return { tn, startingValue, initialDice, rerollChanges, nudgeChanges, finalDice, dois, criticalCount, outcome };
  }

  // Returns { initialDice, rerollChanges, nudgeChanges, finalDice,
  //           diceResultString }. Reads only diceCount, valueAdjustment,
  //           positiveReroll, negativeReroll.
  static resolveWithoutTn(roll, rng = new RandomRng(), config = DiceConfig.default()) {
    const initialDice = rng.rollDice(roll.diceCount, config.dieSize);

    const rerollChanges = Reroll.applyWithoutTn(initialDice, roll, rng, config);
    const afterReroll = merge(initialDice, rerollChanges);

    const nudgeChanges = Nudge.applyWithoutTn(afterReroll, roll.valueAdjustment, config);
    const finalDice = merge(afterReroll, nudgeChanges);

    const diceResultString = DiceResultString.encode(finalDice, config);

    return { initialDice, rerollChanges, nudgeChanges, finalDice, diceResultString };
  }
}

export { merge };
