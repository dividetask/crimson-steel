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

  // Sum, per Type, the highest positive and lowest negative entries.
  static netModifier(list) {
    const highestPositive = new Map();
    const lowestNegative = new Map();

    for (const [type, value] of list) {
      if (value > 0) {
        if (!highestPositive.has(type) || value > highestPositive.get(type)) {
          highestPositive.set(type, value);
        }
      } else if (value < 0) {
        if (!lowestNegative.has(type) || value < lowestNegative.get(type)) {
          lowestNegative.set(type, value);
        }
      }
    }

    let net = 0;
    for (const v of highestPositive.values()) net += v;
    for (const v of lowestNegative.values()) net += v;
    return net;
  }
}
