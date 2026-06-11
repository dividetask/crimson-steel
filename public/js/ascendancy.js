// Ascendancy (dice_resolution_design.md -> Ascendancy).
//
// A Roll's Inherent entries are its Tier-derived raw power: its own Inherent
// Bonus, plus the Inherent Penalties that represent the creature(s) it is
// measured against — the opponent's Inherent, delivered by cross-side
// Propagation on a combat Check, or composed directly onto a one-sided Roll
// (an Affliction save carries the saver's Inherent Bonus and the inflicter's
// Inherent Penalty). When the two do not cancel out, the gap is amplified:
// the Roll gains an Ascendancy Bonus of floor(2 x gap) when its Inherent
// Bonus is the stronger, or an Ascendancy Penalty of floor(2 x gap) when the
// Inherent Penalty is the stronger.
//
// GATE: Ascendancy is derived only when the Roll carries an Inherent
// *Penalty* — an Inherent entry with value <= 0. A Roll with an Inherent
// Bonus but no Inherent Penalty involves no other creature, so it derives
// nothing. A Penalty of exactly 0 still counts: a combat builder injects a
// `+0` Inherent Penalty against a Tier-0 opponent precisely so the gate fires
// and the Tier-0-as-0.5 convention can still amplify the gap.
//
// The Inherent value stands in for the Tier (the Tier Minimum Inherent Bonus
// table is [0, 1, 2, 3, 4, 5]), so the project's "Tier 0 counts as 0.5"
// convention applies here: a side of the comparison that is zero reads as
// 0.5 — the Tier-0 value.
//
// Only the strongest Inherent Bonus and the strongest Inherent Penalty are
// compared, mirroring the per-Type stacking that TN computation applies. This
// derivation runs as a step of TN computation (Roll Resolution), so it
// applies to every Roll — combat or not — wherever an Inherent imbalance is
// present. It runs AFTER any cross-side Propagation, and the derived entry is
// not itself propagated. No Roll field beyond `bonusPenaltyList` is read — in
// particular, Rolls do not carry a `tier`.
export class Ascendancy {
  static PER_POINT = 2;
  static TYPE = 'Ascendancy';
  static INHERENT = 'Inherent';

  // Tier 0 -> 0.5: a zero side of the comparison reads as the Tier-0 value.
  static effective(value) {
    return value === 0 ? 0.5 : value;
  }

  // The Ascendancy [type, amount] pair for a bonusPenaltyList, or null when
  // the Roll carries no Inherent Penalty (no opposing creature), or its
  // strongest Inherent Bonus and strongest Inherent Penalty balance. The
  // magnitude is floor(PER_POINT x gap), the gap measured on effective
  // (0 -> 0.5) values.
  static modifier(bonusPenaltyList) {
    let bonus = 0;
    let penalty = 0;
    let penaltyPresent = false;
    for (const entry of bonusPenaltyList || []) {
      const [type, value] = entry;
      if (type !== Ascendancy.INHERENT) continue;
      const v = Number(value) || 0;
      if (v > bonus) bonus = v;
      // An Inherent entry of value <= 0 is a Penalty (the opposing creature's
      // Tier). 0 counts — that is the injected Tier-0 opponent. A creature's
      // own Inherent Bonus is only ever stamped when positive, so a <= 0
      // entry never misreads an own Bonus as an opponent.
      if (v <= 0) {
        penaltyPresent = true;
        if (v < penalty) penalty = v;
      }
    }
    if (!penaltyPresent) return null;
    const gap = Ascendancy.effective(bonus) - Ascendancy.effective(-penalty);
    if (gap === 0) return null;
    const magnitude = Math.floor(Ascendancy.PER_POINT * Math.abs(gap));
    if (magnitude === 0) return null;
    return [Ascendancy.TYPE, gap < 0 ? -magnitude : magnitude];
  }
}
