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

Pure calculation — no dice rolled. Applies cross-side modifier propagation to each Roll's `bonus_penalty_list`, then asks dice resolution to compute each Roll's TN and Starting Value.

Input: a Check (two Roll lists).

Returns: parallel lists of `{tn, starting_value}` results. The list shapes match the input — `supporting_results[i]` corresponds to `supporting_roll_list[i]`, and similarly for opposing.

Used by interfaces that preview a Check before rolling — for example, a tooltip showing what TN each participant would face.

### Resolve a Check

The full pipeline. Applies cross-side propagation, runs each Roll through dice resolution's full roll-with-TN entry point, aggregates per-Roll results into the Check-level Degree of Success, and classifies the Check Outcome.

Input: a Check.

Pipeline:
1. Apply cross-side propagation to produce a propagated copy of each Roll. See **Cross-side propagation** below.
2. For each propagated Roll, invoke the roll-with-TN entry point in dice resolution.
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

The propagation is structural — every entry in a Roll's `bonus_penalty_list` propagates per the rules above. No per-entry opt-out exists.

When `opposing_roll_list` is empty, no Opposing Roll exists to propagate from, and the Initiating Roll receives no inverted entries. Other Supporting Rolls also receive no inverted entries (they would have received them from a non-existent Defending Roll). The Check resolves with Supporting-side DoIS only.

### Tier Mismatch (Ascendancy)

After cross-side propagation, each Roll that carries a `tier` gains its **Ascendancy** modifier — `±2 × Δ` against the opposing primary Roll's `tier` (Bonus when higher-Tier, Penalty when lower; Tier 0 counts as 0.5, floored) — appended to its `bonus_penalty_list`. This runs *after* propagation precisely so the Ascendancy entry is not inverted back onto the other side: each side derives its own modifier directly from the two Tiers. A Roll without a `tier`, or with no opposing Tier, gets nothing — this is the opt-in seam that scopes Ascendancy to **combat**: only the attack and cast builders stamp `tier` on their Rolls, so opposed *skill* checks (whose builders leave `tier` unset) get no Ascendancy. This is the Check-side half of the Tier Mismatch rule defined in `../encounter/encounter_design.md`; the Inherent damage-reduction half is applied server-side at damage time.

### Check Outcome classification

Once `degree_of_success` is computed, the Check Outcome is derived by calling dice resolution's "classify a value against outcome thresholds" entry point with `can_fumble = true`. The Default Success and Default Fumble Thresholds applied are the dice resolution config values.

A Check can always Fumble — the Roll-level "failure_modifier == 0 suppresses Fumble" rule does not apply at the Check level.

## Cross-domain interactions

- Callers in higher-level domains construct a Check from per-creature Rolls and invoke either the parameters-only or full-resolution entry point.
- Cross-side propagation is a Check Resolution operation; the dice domain has no awareness of Check sides or propagation.
- Check Outcome classification is delegated to the dice resolution classifier so Default Success and Default Fumble Thresholds remain owned by dice resolution.
