import { DiceConfig } from './config.js';
import { RandomRng } from './rng.js';
import { Propagation } from './propagation.js';
import { TierMismatch } from './tierMismatch.js';
import { TnComputation } from './tnComputation.js';
import { Classifier } from './classifier.js';
import { Roll } from './roll.js';

// Multi-Roll composition. Applies cross-side propagation and the Tier
// Mismatch Ascendancy modifier, defers all per-Roll math to Dice
// Resolution, then aggregates and classifies.
export class CheckResolution {
  // Cross-side Propagation followed by the Tier Mismatch Ascendancy
  // modifier. Tier Mismatch runs AFTER Propagation so its Ascendancy entry
  // is not itself inverted onto the other side.
  static prepare(check) {
    return TierMismatch.apply(Propagation.apply(check));
  }
  // Pure preview: per-Roll { tn, startingValue } after propagation. No
  // dice rolled. Lists align with the input lists.
  static computeParameters(check, config = DiceConfig.default()) {
    const propagated = CheckResolution.prepare(check);
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
    const propagated = CheckResolution.prepare(check);
    const compute = (roll) => {
      if (!roll) return null;
      const list = roll.bonusPenaltyList || [];
      const { tn, startingValue } = TnComputation.compute(roll, config);
      // `contributions` carries each contributing entry's signed TN influence,
      // so a UI can render the breakdown without doing any TN math itself.
      return { tn, startingValue, bonusPenaltyList: list, contributions: TnComputation.contributions(list) };
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
    const propagated = CheckResolution.prepare(check);
    const resolve = (roll) => (roll ? Roll.resolveWithTn(roll, rng, config) : null);

    const supportingResults = propagated.supporting.map(resolve);
    const opposingResults = propagated.opposing.map(resolve);

    const degreeOfSuccess = CheckResolution.degreeOfSuccess({
      supporting: supportingResults.map((r) => (r ? r.dois : 0)),
      opposing: opposingResults.map((r) => (r ? r.dois : 0)),
    });
    const outcome = Classifier.classify(degreeOfSuccess, true, config);

    return { supportingResults, opposingResults, degreeOfSuccess, outcome };
  }

  // Net Degree of Success for a Check from already-known per-Roll DoIS:
  // sum of Supporting minus sum of Opposing. Used when the DoIS were rolled or
  // entered outside resolveCheck (e.g. the Check Builder reads them from the
  // dice table); resolveCheck uses it too.
  static degreeOfSuccess({ supporting = [], opposing = [] } = {}) {
    const sum = (xs) => xs.reduce((acc, n) => acc + (Number(n) || 0), 0);
    return sum(supporting) - sum(opposing);
  }
}
