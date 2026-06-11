import { DiceConfig } from './config.js';
import { Ascendancy } from './ascendancy.js';

// TN computation: turn a Roll's bonus_penalty_list and
// starting_contribution into a final TN and Starting Value.
//
// Ascendancy (Tier-mismatch amplification) is derived here, as a step of
// Roll Resolution: before stacking, any Inherent imbalance in the list
// yields a derived Ascendancy entry (see ascendancy.js). Because it lives in
// TN computation rather than Check Resolution, every Roll that carries an
// Inherent Penalty — a combat Roll after Propagation, or a one-sided Roll
// such as an Affliction save — picks it up.
//
// Per-Type stacking: for each Bonus/Penalty Type only the highest
// positive and the lowest negative entry contribute; the rest are
// ignored. Contributing entries sum into the TN Net Modifier. The TN
// clamps to [Minimum, Maximum]; whatever overflow the clamp discarded
// becomes Starting Value (Bonuses below Minimum → Starting Successes,
// Penalties above Maximum → Starting Failures).
export class TnComputation {
  // The list with its derived Ascendancy entry appended (or unchanged when
  // no Inherent imbalance is present). Per-Type stacking makes a duplicate
  // append idempotent, so this is safe to apply more than once.
  static withAscendancy(list) {
    const mod = Ascendancy.modifier(list || []);
    return mod ? (list || []).concat([mod]) : (list || []);
  }

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

    for (const [type, value, source] of TnComputation.withAscendancy(list)) {
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
