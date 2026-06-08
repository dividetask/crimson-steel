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
// up, labeled, on the opposing Roll's Target Number. Every other Bonus Type
// keeps its name when it crosses.
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
        const relabeled = Propagation.CROSS_SIDE_RELABEL[type] || type;
        base.push(src === undefined ? [relabeled, -value] : [relabeled, -value, src]);
      }
    }
    return { ...roll, bonusPenaltyList: base };
  }
}
