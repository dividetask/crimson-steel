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
      for (const [type, value, src] of source.bonusPenaltyList || []) {
        base.push(src === undefined ? [type, -value] : [type, -value, src]);
      }
    }
    return { ...roll, bonusPenaltyList: base };
  }
}
