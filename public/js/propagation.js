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
// Every Bonus Type keeps its name when it crosses — an opponent's Inherent
// arrives as an Inherent Penalty. The crossed Inherent entries are what the
// Ascendancy step (ascendancy.js, run after propagation) compares against
// the Roll's own Inherent Bonus.
export class Propagation {
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
        // An Ascendancy entry never crosses: it is a derived entry each Roll
        // computes from its own Inherent imbalance after propagation (see
        // ascendancy.js), so a pre-existing one must not leak to the other
        // side as a phantom bonus.
        if (type === 'Ascendancy') continue;
        base.push(src === undefined ? [type, -value] : [type, -value, src]);
      }
    }
    return { ...roll, bonusPenaltyList: base };
  }
}
