// Cross-side propagation. Bonuses and Penalties on one side are inverted
// (Bonus <-> Penalty) and appended to specific Rolls on the other side:
//
//   Initiating Roll      <- every Opposing Roll
//   Defending Roll       <- every Supporting Roll
//   Other Supporting     <- the Defending Roll only
//   Other Opposing       <- the Initiating Roll only
//
// Only bonus_penalty_list propagates; Starting Value and Roll Modifiers do
// not. Returns a propagated copy of the Check — each Roll cloned with its
// bonus_penalty_list extended. A null Roll (a Defender slot left blank)
// contributes nothing and receives nothing.
//
// Ascendancy: a creature's Inherent Bonus is the advantage of its own Tier;
// to its opponent that same edge is the Tier-gap disadvantage we call
// Ascendancy. So when an `Inherent` entry crosses sides it is relabeled
// `Ascendancy` (still inverted) — this is how a different-Tier matchup shows
// up, labeled, on the opposing Roll's Target Number. Ascendancy only exists
// where there IS a Tier gap: when both Rolls carry a `tier` and the Tiers
// are EQUAL, the Inherent does not cross at all — same-Tier opponents see
// no Ascendancy entry (their equal Inherents would only net to zero).
// Every other Bonus Type keeps its name when it crosses.
export class Propagation {
  // Bonus Types that change name when they propagate to the other side.
  static CROSS_SIDE_RELABEL = { Inherent: 'Ascendancy' };

  static apply(check) {
    const supporting = check.supporting || [];
    const opposing = check.opposing || [];

    const initiating = supporting[0] || null;
    const defending = opposing[0] || null;

    const supportingResults = supporting.map((roll, i) => {
      if (!roll) return roll;
      const sources = i === 0 ? opposing : [defending];
      return Propagation._extend(roll, sources);
    });

    const opposingResults = opposing.map((roll, j) => {
      if (!roll) return roll;
      const sources = j === 0 ? supporting : [initiating];
      return Propagation._extend(roll, sources);
    });

    return { supporting: supportingResults, opposing: opposingResults };
  }

  // True when both Rolls carry a numeric tier and the tiers are equal —
  // the no-Tier-gap case in which an Inherent entry does not cross.
  static _equalTiers(a, b) {
    if (a == null || b == null) return false;
    const an = Number(a);
    const bn = Number(b);
    return Number.isFinite(an) && Number.isFinite(bn) && an === bn;
  }

  static _extend(roll, sourceRolls) {
    const base = (roll.bonusPenaltyList || []).slice();
    for (const source of sourceRolls) {
      if (!source || source === roll) continue;
      // A Roll may declare Bonus Types that stay on its own side and do not
      // cross to the opponent (e.g. a Dodge's Competency helps the dodger but
      // never penalizes the attacker). Those entries are skipped here.
      const noCross = source.noPropagate || [];
      for (const [type, value, src] of source.bonusPenaltyList || []) {
        if (noCross.includes(type)) continue;
        // An Ascendancy entry never crosses: each side derives its own from
        // the Tier gap (the same reason Tier Mismatch runs after propagation
        // — see check_resolution_design.md). Without this, a no-defense
        // attack's explicit Ascendancy would inert onto a shielding ally's
        // Roll as a phantom bonus.
        if (type === 'Ascendancy') continue;
        // Equal-Tier opponents exchange no Ascendancy: the Inherent crosses
        // only across a Tier gap.
        if (type === 'Inherent' && Propagation._equalTiers(roll.tier, source.tier)) continue;
        const relabeled = Propagation.CROSS_SIDE_RELABEL[type] || type;
        base.push(src === undefined ? [relabeled, -value] : [relabeled, -value, src]);
      }
    }
    return { ...roll, bonusPenaltyList: base };
  }
}
