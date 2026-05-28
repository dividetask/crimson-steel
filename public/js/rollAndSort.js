import { DiceConfig } from './config.js';
import { RandomRng } from './rng.js';
import { Roll } from './roll.js';

// Order a list of Rolls relative to each other — no TN, no Successes, no
// propagation. Runs the no-TN Roll on each input, then sorts by Dice
// Result String descending. Ties break by original list index.
export class RollAndSort {
  // Returns { results, order }. `results` aligns with the input list;
  // `order` is a permutation of [0..n-1], highest-ordered Roll first.
  static run(rolls, rng = new RandomRng(), config = DiceConfig.default()) {
    const results = rolls.map((roll) => Roll.resolveWithoutTn(roll, rng, config));

    const order = results
      .map((r, i) => ({ s: r.diceResultString, i }))
      .sort((a, b) => (a.s < b.s ? 1 : a.s > b.s ? -1 : a.i - b.i))
      .map((entry) => entry.i);

    return { results, order };
  }
}
