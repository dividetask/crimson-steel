import { DiceConfig } from './config.js';

// Reroll operation: two slots (positive and negative) applied in a single
// pass. The positive slot rerolls non-Successes lowest-first; the
// negative slot rerolls Successes highest-first. The two slots target
// structurally disjoint dice, so no die is rerolled twice. A slot with
// max = true expands its count to Maximum Dice Count.
//
// Each slot is { count, max } or null. Returns a changes array the same
// length as `dice`: the new value at each rerolled position, null
// elsewhere.
export class Reroll {
  // With a TN: positive targets value < TN, negative targets value >= TN.
  // `skip` is an optional Set of positions already rerolled this Roll
  // (e.g. by an earlier slot applied separately) which must not reroll
  // again — "no die is rerolled more than once".
  static applyWithTn(dice, { positiveReroll, negativeReroll } = {}, tn, rng, config = DiceConfig.default(), skip = null) {
    return Reroll._apply(dice, positiveReroll, negativeReroll, rng, config, skip, {
      positiveEligible: (v) => v < tn,
      negativeEligible: (v) => v >= tn,
    });
  }

  // Without a TN: eligibility uses fixed quartile thresholds.
  //   positive: value < floor(Die Size / 4) + 1
  //   negative: value >= Die Size - floor(Die Size / 4)
  static applyWithoutTn(dice, { positiveReroll, negativeReroll } = {}, rng, config = DiceConfig.default(), skip = null) {
    const q = Math.floor(config.dieSize / 4);
    const lowThreshold = q + 1;
    const highThreshold = config.dieSize - q;
    return Reroll._apply(dice, positiveReroll, negativeReroll, rng, config, skip, {
      positiveEligible: (v) => v < lowThreshold,
      negativeEligible: (v) => v >= highThreshold,
    });
  }

  static _apply(dice, positiveReroll, negativeReroll, rng, config, skip, { positiveEligible, negativeEligible }) {
    const changes = new Array(dice.length).fill(null);
    const blocked = (i) => skip && skip.has(i);

    if (positiveReroll) {
      const n = Reroll._count(positiveReroll, config);
      const candidates = dice
        .map((v, i) => ({ v, i }))
        .filter((d) => positiveEligible(d.v) && !blocked(d.i))
        .sort((a, b) => a.v - b.v || a.i - b.i); // lowest first
      for (const d of candidates.slice(0, n)) {
        changes[d.i] = rng.rollDie(config.dieSize);
      }
    }

    if (negativeReroll) {
      const n = Reroll._count(negativeReroll, config);
      const candidates = dice
        .map((v, i) => ({ v, i }))
        .filter((d) => negativeEligible(d.v) && !blocked(d.i))
        .sort((a, b) => b.v - a.v || a.i - b.i); // highest first
      for (const d of candidates.slice(0, n)) {
        changes[d.i] = rng.rollDie(config.dieSize);
      }
    }

    return changes;
  }

  static _count(slot, config) {
    return slot.max ? config.maximumDiceCount : slot.count;
  }
}
