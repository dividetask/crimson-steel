import { DiceConfig } from './config.js';
import { RandomRng } from './randomRng.js';
import { Propagation } from './propagation.js';
import { TnComputation } from './tnComputation.js';
import { Classifier } from './classifier.js';
import { Roll } from './roll.js';

// Multi-Roll composition. Applies cross-side propagation, defers all per-Roll
// math to Dice Resolution, then aggregates and classifies.
export class CheckResolution {
  // Cross-side Propagation only. The Tier-mismatch Ascendancy modifier is no
  // longer a Check step — it is derived per Roll during TN computation (Roll
  // Resolution, see tnComputation.js / ascendancy.js), reading the Inherent
  // Penalties Propagation has by then crossed over. A Spread (area) Check
  // uses the same bidirectional preparation (the caster and every Opposer
  // exchange bonuses) and differs only in how `resolveCheck` aggregates
  // (per-Opposer, below).
  static prepare(check) {
    return Propagation.apply(check);
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
      // The displayed list includes the derived Ascendancy entry (if any) so
      // the breakdown matches the TN, which TN computation derives the same way.
      const list = TnComputation.withAscendancy(roll.bonusPenaltyList || []);
      const { tn, startingValue } = TnComputation.compute(roll, config);
      // `contributions` carries each contributing entry's signed TN influence,
      // so a UI can render the breakdown without doing any TN math itself.
      return { tn, startingValue, bonusPenaltyList: list, contributions: TnComputation.contributions(roll.bonusPenaltyList || []) };
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

    // Spread Check: resolve the Supporting side once, then net it against EACH
    // Opposer independently — a separate Degree of Success and Outcome per
    // caught creature. There is no single Check-level Degree of Success.
    if (check.spread) {
      const supportTotal = supportingResults.reduce((a, r) => a + (r ? r.dois : 0), 0);
      const perOpposer = opposingResults.map((r) => {
        if (!r) return null;
        const dos = supportTotal - r.dois;
        return { ...r, degreeOfSuccess: dos, outcome: Classifier.classify(dos, true, config) };
      });
      return { supportingResults, opposingResults: perOpposer, spread: true };
    }

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
