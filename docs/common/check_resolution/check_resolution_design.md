# Check Resolution — Design

Owns multi-Roll composition: cross-side modifier propagation, aggregating Degrees of Individual Success across Rolls, and ordering Rolls relative to each other. Single-Roll mechanics live in `dice_resolution_design.md` and are not duplicated here — Check Resolution defers all per-Roll math to the dice resolution domain.

## Common types

### Roll Lists

A Check is two ordered lists of Rolls:

- `supporting_roll_list` — required, non-empty. The first entry is the Initiating Roll.
- `opposing_roll_list` — may be empty. The first entry is either the Defending Roll or null. A null first entry indicates the Check has Opposing Rolls but no Defender.

Each Roll uses the structure defined by the dice resolution domain. Check Resolution does not extend or modify it.

### Per-Roll Result

A single Roll's resolved result, as returned by dice resolution's roll-with-TN entry point: `tn`, `starting_value`, `initial_dice`, `reroll_changes`, `nudge_changes`, `final_dice`, `degree_of_individual_success`, `critical_count`, `outcome`. Check Resolution does not interpret these fields; it just collects and forwards them.

## Public entry points

### Compute Check parameters

Pure calculation — no dice rolled. Applies cross-side modifier propagation to each Roll's `bonus_penalty_list`, then asks dice resolution to compute each Roll's TN and Starting Value (dice resolution derives the Tier-mismatch Ascendancy entry itself, during TN computation — see **Ascendancy** below).

Input: a Check (two Roll lists).

Returns: parallel lists of `{tn, starting_value}` results. The list shapes match the input — `supporting_results[i]` corresponds to `supporting_roll_list[i]`, and similarly for opposing.

Used by interfaces that preview a Check before rolling — for example, a tooltip showing what TN each participant would face.

### Resolve a Check

The full pipeline. Applies cross-side propagation, runs each Roll through dice resolution's full roll-with-TN entry point (which derives the Ascendancy entry from the propagated Inherent imbalance), aggregates per-Roll results into the Check-level Degree of Success, and classifies the Check Outcome.

Input: a Check.

Pipeline:
1. Apply cross-side propagation to produce a propagated copy of each Roll. Ascendancy is no longer a Check step — TN computation derives it per Roll. See **Cross-side propagation** and **Ascendancy** below.
2. For each prepared Roll, invoke the roll-with-TN entry point in dice resolution.
3. Sum DoIS from Supporting results minus DoIS from Opposing results to produce `degree_of_success`.
4. Classify `degree_of_success` against the outcome thresholds via the dice resolution classifier. See **Check Outcome classification** below.

Returns:

| Field | Type | Description |
|---|---|---|
| `supporting_results` | list of Per-Roll Result | Aligned with `supporting_roll_list`. |
| `opposing_results` | list of Per-Roll Result | Aligned with `opposing_roll_list`. May be empty. |
| `degree_of_success` | signed integer | Sum of Supporting DoIS minus sum of Opposing DoIS. |
| `outcome` | Check Outcome (success, failure, or fumble) | Derived from `degree_of_success`. |

Callers that walk the resolution step-by-step (e.g., a UI that lets the GM fudge dice between Rolls) can call dice resolution's per-Roll entry point directly and aggregate themselves; this entry point is the convenience bundle for "resolve everything at once."

### Roll and Sort

For Rolls used purely for relative ordering — no TN, no Successes, no propagation. Calls dice resolution's no-TN roll entry point on each Roll, then sorts the resulting Dice Result Strings descending (lex compare).

Input: a list of Rolls.

Returns:

| Field | Type | Description |
|---|---|---|
| `results` | list of dice resolution no-TN results | Aligned with the input list. |
| `order` | list of integers | A permutation of `[0..n-1]`. The first entry is the index of the Roll that ordered highest. |

Tie-breaking is by original list index — the Roll appearing earlier in the input list wins ties. Callers needing a different tie-breaker reorder `results` themselves after this returns.

This entry point does not apply cross-side propagation, does not aggregate, and does not classify a Check Outcome. It is a self-contained helper for ordering use cases.

## Operations

### Cross-side propagation

Bonuses and Penalties on Rolls on one side are inverted (Bonus ↔ Penalty) and added to the `bonus_penalty_list` of specific Roll(s) on the other side. The propagation rules:

- The Initiating Roll receives inverted entries from **every** Opposing Roll.
- The Defending Roll receives inverted entries from **every** Supporting Roll.
- Other Supporting Rolls receive inverted entries from the Defending Roll only.
- Other Opposing Rolls receive inverted entries from the Initiating Roll only.

Only `bonus_penalty_list` propagates. `starting_contribution` and Roll Modifiers (reroll, nudge, failure modifier, critical modifier) do not. A Defender's reroll doesn't affect the Initiator's dice; a Supporting ally's `starting_contribution` doesn't affect anyone else's Starting Value.

The propagation is structural — every entry in a Roll's `bonus_penalty_list` propagates per the rules above, **except** Bonus Types named in the Roll's optional **`no_propagate`** field (a list of Bonus Type names). Those entries stay on the Roll's own side: the Roll's own Target Number still includes them, but they are **not** inverted onto the opponent. (A Dodge uses this so its Competency helps the dodger's own Roll without penalizing the attacker.)

Every Bonus Type keeps its name when it crosses — an opponent's Inherent Bonus arrives as an Inherent Penalty. The Tier-mismatch **Ascendancy** amplification then reads that imbalance, but it is no longer a Check operation: it is derived per Roll during TN computation (see **Ascendancy** below).

When `opposing_roll_list` is empty, no Opposing Roll exists to propagate from, and the Initiating Roll receives no inverted entries. Other Supporting Rolls also receive no inverted entries (they would have received them from a non-existent Defending Roll). The Check resolves with Supporting-side DoIS only.

### Ascendancy

The Tier-mismatch Ascendancy amplification is **not** a Check Resolution step. It is derived per Roll, from the Roll's own Inherent imbalance, as a step of **TN computation** (Roll Resolution) — see `../dice_resolution/dice_resolution_design.md` → *Ascendancy*. Moving it there lets *any* Roll with an Inherent Penalty derive it, not only combat Checks (an Affliction save, composed one-sidedly, gets it too).

Check Resolution's only role is to deliver the Inherent entries the derivation reads: cross-side propagation inverts each side's Inherent onto the other as an Inherent Penalty (keeping its name), so after propagation a Roll holds its own Inherent Bonus plus the strongest opponent's Inherent as a Penalty. The amplification then doubles that gap at TN time.

Worked examples — Adam is the Initiating Roll, Dawn the Defending Roll, Carol another Opposing Roll. The lists shown are **after propagation**, before TN computation derives each Roll's Ascendancy:

1. **Everyone equal.** All Rolls carry `Inherent +2`; each ends with `Inherent +2` and a crossed `Inherent −2` — balanced, so TN computation derives **no Ascendancy anywhere**.
2. **Adam +2 vs Dawn +1.** Adam ends `Inherent +2`, `Inherent −1` (Dawn's, crossed) → TN computation derives `Ascendancy +2`. Dawn ends `Inherent +1`, `Inherent −2` → `Ascendancy −2`.
3. **Adam +2 vs Dawn +1 (defending) and Carol +3 (opposing).** Adam receives every Opposer's Inherent (−1 and −3); per-Type stacking counts only the −3 → `Ascendancy −2`. Carol receives Adam's +2 (`Inherent +3`, `Inherent −2`) → `Ascendancy +2`. Dawn receives the +2 (`Inherent +1`, `Inherent −2`) → `Ascendancy −2`.

Combat is what places Inherent entries on Rolls — a Creature's own Tier Inherent on its attack, cast, and defense Rolls (emitted even at Tier 0, as a `0`, so it crosses and the opponent's Ascendancy gate fires; a Spell's Tier rides the casting Roll as a **Guidance** Bonus, not an Inherent, so it stays out of the Ascendancy). When one side does not roll at all (a No-defense attack), the combat builder injects the un-rolled side's Inherent, negated — `0` included — so the gap, and the derived Ascendancy, match the defended case. Opposed *skill* checks carry no Inherent entries and so derive nothing.

### Spread Check (area effects)

A Check flagged `spread: true` models an **area effect**: one Supporting side (the caster, plus any supports) opposed by *N independent* Opposing Rolls — every creature caught in the spell's footprint makes its own Save. **None of the Opposers is the singular Target / Defending Roll**; they are peers, each opposed only to the caster.

A Spread Check **prepares exactly like any other** (the standard bidirectional cross-side propagation; TN computation then derives each Roll's Ascendancy from its propagated Inherent imbalance) — it only **aggregates differently**:

- **Preparation is bidirectional**, so the caster and every Opposer exchange bonuses: the caster's casting bonuses (Competency, the caster's own Tier Inherent, the Spell's Tier as a Guidance Bonus, …) invert onto **each** caught creature's Save, and every Opposer's bonuses invert back onto the caster. TN computation then derives each Roll's Ascendancy from its Inherent imbalance: every caught creature measures against the caster's Inherent, while the caster — having received every Opposer's Inherent — measures against the strongest creature it caught (per-Type stacking counts only the deepest crossed Penalty).
- **Resolution is per-Opposer.** The Supporting side resolves once into a single Supporting DoIS total; each Opposing Roll then resolves and nets independently: `degree_of_success_i = Σ Supporting DoIS − Opposer_i DoIS`, classified into its own Outcome. There is **no single Check-level Degree of Success** — the result is one Outcome per caught creature.

A non-spread Check uses the same preparation but the pooled aggregation `Σ Supporting − Σ Opposing`.

### Check Outcome classification

Once `degree_of_success` is computed, the Check Outcome is derived by calling dice resolution's "classify a value against outcome thresholds" entry point with `can_fumble = true`. The Default Success and Default Fumble Thresholds applied are the dice resolution config values.

A Check can always Fumble — the Roll-level "failure_modifier == 0 suppresses Fumble" rule does not apply at the Check level.

## Cross-domain interactions

- Callers in higher-level domains construct a Check from per-creature Rolls and invoke either the parameters-only or full-resolution entry point.
- Cross-side propagation is a Check Resolution operation; the dice domain has no awareness of Check sides or propagation.
- Check Outcome classification is delegated to the dice resolution classifier so Default Success and Default Fumble Thresholds remain owned by dice resolution.
