import { DiceConfig } from './config.js';
import { Classifier } from './classifier.js';

// Scoring: turn final dice + TN + Starting Value into a Degree of
// Individual Success, a Critical Count, and a Roll Outcome.
//
// Per-die contribution:
//   Die Size            -> critical_modifier
//   1                   -> failure_modifier
//   >= TN (not Die Size)-> +1
//   otherwise           -> 0
//
// DoIS = Starting Value + sum of contributions. The outcome is classified
// with can_fumble = (failure_modifier !== 0): a Roll that ignores
// Failures cannot Fumble.
export class Scoring {
  static score(finalDice, { tn, startingValue = 0, failureModifier = -1, criticalModifier = 2 } = {}, config = DiceConfig.default()) {
    let dois = startingValue;
    let criticalCount = 0;

    for (const v of finalDice) {
      if (v === null || v === undefined) continue;
      if (v === config.dieSize) {
        dois += criticalModifier;
        criticalCount += 1;
      } else if (v === 1) {
        dois += failureModifier;
      } else if (v >= tn) {
        dois += 1;
      }
    }

    const outcome = Classifier.classify(dois, failureModifier !== 0, config);
    return { dois, criticalCount, outcome };
  }
}
