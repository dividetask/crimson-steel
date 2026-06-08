import { DiceConfig } from './config.js';

// TN computation: turn a Roll's bonus_penalty_list and
// starting_contribution into a final TN and Starting Value.
//
// Per-Type stacking: for each Bonus/Penalty Type only the highest
// positive and the lowest negative entry contribute; the rest are
// ignored. Contributing entries sum into the TN Net Modifier. The TN
// clamps to [Minimum, Maximum]; whatever overflow the clamp discarded
// becomes Starting Value (Bonuses below Minimum → Starting Successes,
// Penalties above Maximum → Starting Failures).
export class TnComputation {
  // roll: { bonusPenaltyList?: [[typeName, value], ...], startingContribution?: number }
  static compute(roll, config = DiceConfig.default()) {
    const list = roll.bonusPenaltyList || [];
    const startingContribution = roll.startingContribution || 0;

    const netModifier = TnComputation.netModifier(list);
    const candidate = config.baseTargetNumber - netModifier;

    const min = config.minimumTargetNumber;
    const max = config.maximumTargetNumber;

    if (candidate < min) {
      return { tn: min, startingValue: startingContribution + (min - candidate) };
    }
    if (candidate > max) {
      return { tn: max, startingValue: startingContribution - (candidate - max) };
    }
    return { tn: candidate, startingValue: startingContribution };
  }

  // The entries that actually contribute to the TN: per Type, the highest
  // positive and the lowest negative entry (the rest are ignored). Each carries
  // its signed influence on the TN — a Bonus (positive value) LOWERS the TN
  // (TN = Base − Net Modifier), so its influence is negative. Callers that want
  // to display the breakdown read this rather than re-deriving the sign.
  static contributions(list) {
    const highestPositive = new Map();
    const lowestNegative = new Map();

    for (const [type, value, source] of list) {
      if (value > 0) {
        if (!highestPositive.has(type) || value > highestPositive.get(type).value) {
          highestPositive.set(type, { value, source });
        }
      } else if (value < 0) {
        if (!lowestNegative.has(type) || value < lowestNegative.get(type).value) {
          lowestNegative.set(type, { value, source });
        }
      }
    }

    // `source` (optional 3rd element of each entry) is a display label the
    // TN-breakdown tooltip shows in parentheses; it does not affect stacking.
    const out = [];
    for (const [type, e] of highestPositive) out.push({ type, value: e.value, influence: -e.value, source: e.source });
    for (const [type, e] of lowestNegative) out.push({ type, value: e.value, influence: -e.value, source: e.source });
    return out;
  }

  // Sum, per Type, the highest positive and lowest negative entries.
  static netModifier(list) {
    return TnComputation.contributions(list).reduce((net, c) => net + c.value, 0);
  }
}
