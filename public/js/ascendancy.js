// Ascendancy (check_resolution_design.md -> Ascendancy).
//
// A Roll's Inherent entries are its Tier-derived raw power: its own Inherent
// Bonus, plus the Inherent Penalties that crossed over from the other side
// during Propagation. When the two do not cancel out, the gap is amplified:
// the Roll gains an Ascendancy Bonus of 2 x the gap when its Inherent Bonus
// is the stronger, or an Ascendancy Penalty of 2 x the gap when the crossed
// Inherent Penalty is the stronger. Balanced Inherents — equal values, or no
// Inherent entries at all — add nothing.
//
// Only the strongest Inherent Bonus and the strongest Inherent Penalty are
// compared, mirroring the per-Type stacking that TN computation applies.
// apply() runs AFTER cross-side Propagation (the crossed entries are its
// input) and appends each Roll's Ascendancy entry directly, so the entry is
// not itself inverted onto the other side. No Roll field beyond
// `bonusPenaltyList` is read — in particular, Rolls do not carry a `tier`.
export class Ascendancy {
  static PER_POINT = 2;
  static TYPE = 'Ascendancy';
  static INHERENT = 'Inherent';

  // The Ascendancy [type, amount] pair for a propagated bonusPenaltyList,
  // or null when the strongest Inherent Bonus and strongest Inherent
  // Penalty balance (or no Inherent entry exists). The magnitude is
  // floor(PER_POINT x gap).
  static modifier(bonusPenaltyList) {
    let bonus = 0;
    let penalty = 0;
    for (const entry of bonusPenaltyList || []) {
      const [type, value] = entry;
      if (type !== Ascendancy.INHERENT) continue;
      const v = Number(value) || 0;
      if (v > bonus) bonus = v;
      if (v < penalty) penalty = v;
    }
    const gap = bonus + penalty; // penalty is <= 0, so this is bonus - |penalty|
    if (gap === 0) return null;
    const magnitude = Math.floor(Ascendancy.PER_POINT * Math.abs(gap));
    if (magnitude === 0) return null;
    return [Ascendancy.TYPE, gap < 0 ? -magnitude : magnitude];
  }

  // Append each Roll's Ascendancy entry. `check` must already be propagated
  // (the crossed Inherent Penalties are what the other side contributes).
  // Returns a copy; input is not mutated.
  static apply(check) {
    const extend = (roll) => {
      if (!roll) return roll;
      const mod = Ascendancy.modifier(roll.bonusPenaltyList);
      return mod ? { ...roll, bonusPenaltyList: (roll.bonusPenaltyList || []).concat([mod]) } : roll;
    };
    return {
      supporting: (check.supporting || []).map(extend),
      opposing: (check.opposing || []).map(extend),
    };
  }
}
