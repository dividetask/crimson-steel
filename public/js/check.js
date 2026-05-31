import { DiceConfig } from './config.js';
import { RandomRng } from './rng.js';
import { Propagation } from './propagation.js';
import { TnComputation } from './tnComputation.js';
import { Classifier } from './classifier.js';
import { Roll } from './roll.js';

// Multi-Roll composition. Applies cross-side propagation, defers all
// per-Roll math to Dice Resolution, then aggregates and classifies.
export class CheckResolution {
  // Pure preview: per-Roll { tn, startingValue } after propagation. No
  // dice rolled. Lists align with the input lists.
  static computeParameters(check, config = DiceConfig.default()) {
    const propagated = Propagation.apply(check);
    const compute = (roll) => (roll ? TnComputation.compute(roll, config) : null);
    return {
      supporting: propagated.supporting.map(compute),
      opposing: propagated.opposing.map(compute),
    };
  }

  // Like computeParameters, but each entry also carries the propagated
  // `bonusPenaltyList` (own entries plus the inverted cross-side entries) so a
  // UI can display the full TN computation without doing any of the math
  // itself. No dice rolled.
  static previewParameters(check, config = DiceConfig.default()) {
    const propagated = Propagation.apply(check);
    const compute = (roll) => {
      if (!roll) return null;
      const { tn, startingValue } = TnComputation.compute(roll, config);
      return { tn, startingValue, bonusPenaltyList: roll.bonusPenaltyList || [] };
    };
    return {
      supporting: propagated.supporting.map(compute),
      opposing: propagated.opposing.map(compute),
    };
  }

  // Full resolution. Returns { supportingResults, opposingResults,
  // degreeOfSuccess, outcome }. Degree of Success = sum of Supporting DoIS
  // minus sum of Opposing DoIS. A Check can always Fumble.
  static resolveCheck(check, rng = new RandomRng(), config = DiceConfig.default()) {
    const propagated = Propagation.apply(check);
    const resolve = (roll) => (roll ? Roll.resolveWithTn(roll, rng, config) : null);

    const supportingResults = propagated.supporting.map(resolve);
    const opposingResults = propagated.opposing.map(resolve);

    const sum = (results) => results.reduce((acc, r) => acc + (r ? r.dois : 0), 0);
    const degreeOfSuccess = sum(supportingResults) - sum(opposingResults);
    const outcome = Classifier.classify(degreeOfSuccess, true, config);

    return { supportingResults, opposingResults, degreeOfSuccess, outcome };
  }
}
