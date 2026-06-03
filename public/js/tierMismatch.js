// Tier Mismatch (encounter_design.md -> Tier Mismatch).
//
// When two Creatures of different Tiers oppose each other on a Check, the
// higher-Tier side gains an Ascendancy Bonus and the lower-Tier side takes
// an Ascendancy Penalty, scaled by the Tier difference (+/- 2 per Tier).
// Tier 0 counts as 0.5; magnitudes are floored.
//
// This is the Check-side half of the rule. The Inherent damage reduction
// half is not a Roll modifier — it reduces dealt damage — and is applied
// server-side when damage is resolved.
//
// Each Roll may carry a numeric `tier`. apply() runs AFTER cross-side
// Propagation and appends the Ascendancy entry directly from the two
// sides' tiers, so it is not itself inverted/propagated. A Roll without a
// tier (or with no opposing tier) gets nothing.
export class TierMismatch {
  static ASCENDANCY_PER_TIER = 2;
  static TYPE = 'Ascendancy';

  // Tier 0 -> 0.5 per project convention. An absent tier (null/undefined)
  // returns null — distinct from Tier 0 — so a Roll with no Tier opts out.
  static effectiveTier(tier) {
    if (tier === null || tier === undefined) return null;
    const t = Number(tier);
    if (!Number.isFinite(t)) return null;
    return t === 0 ? 0.5 : t;
  }

  // The Ascendancy [type, amount] pair for an actor of `actorTier` opposing
  // `opponentTier`, or null when either tier is absent, the tiers are equal,
  // or the floored magnitude is 0.
  static ascendancyModifier(actorTier, opponentTier) {
    const a = TierMismatch.effectiveTier(actorTier);
    const o = TierMismatch.effectiveTier(opponentTier);
    if (a === null || o === null) return null;
    const delta = a - o;
    if (delta === 0) return null;
    const magnitude = Math.floor(TierMismatch.ASCENDANCY_PER_TIER * Math.abs(delta));
    if (magnitude === 0) return null;
    return [TierMismatch.TYPE, delta < 0 ? -magnitude : magnitude];
  }

  // Append each Roll's Ascendancy entry, measured against the opposing
  // side's primary (initiating / defending) Roll's tier — mirroring the
  // pairing used by Propagation. Returns a copy; input is not mutated.
  static apply(check) {
    const supporting = check.supporting || [];
    const opposing = check.opposing || [];
    const initiating = supporting[0] || null;
    const defending = opposing[0] || null;

    const extend = (roll, opponent) => {
      if (!roll) return roll;
      const mod = opponent ? TierMismatch.ascendancyModifier(roll.tier, opponent.tier) : null;
      if (!mod) return roll;
      return { ...roll, bonusPenaltyList: (roll.bonusPenaltyList || []).concat([mod]) };
    };

    return {
      supporting: supporting.map((roll) => extend(roll, defending)),
      opposing: opposing.map((roll) => extend(roll, initiating)),
    };
  }
}
