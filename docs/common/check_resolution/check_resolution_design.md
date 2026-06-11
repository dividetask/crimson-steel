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

Pure calculation — no dice rolled. Applies cross-side modifier propagation and the Ascendancy modifier to each Roll's `bonus_penalty_list`, then asks dice resolution to compute each Roll's TN and Starting Value.

Input: a Check (two Roll lists).

Returns: parallel lists of `{tn, starting_value}` results. The list shapes match the input — `supporting_results[i]` corresponds to `supporting_roll_list[i]`, and similarly for opposing.

Used by interfaces that preview a Check before rolling — for example, a tooltip showing what TN each participant would face.

### Resolve a Check

The full pipeline. Applies cross-side propagation and the Ascendancy modifier, runs each Roll through dice resolution's full roll-with-TN entry point, aggregates per-Roll results into the Check-level Degree of Success, and classifies the Check Outcome.

Input: a Check.

Pipeline:
1. Apply cross-side propagation to produce a propagated copy of each Roll, then append each Roll's Ascendancy entry. See **Cross-side propagation** and **Ascendancy** below.
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

Every Bonus Type keeps its name when it crosses — an opponent's Inherent Bonus arrives as an Inherent Penalty. The **Ascendancy** operation (below) then amplifies any Inherent imbalance the crossing leaves behind.

When `opposing_roll_list` is empty, no Opposing Roll exists to propagate from, and the Initiating Roll receives no inverted entries. Other Supporting Rolls also receive no inverted entries (they would have received them from a non-existent Defending Roll). The Check resolves with Supporting-side DoIS only.

### Ascendancy

After cross-side propagation, each Roll derives its **Ascendancy** modifier from its own propagated `bonus_penalty_list`. Nothing else is read — in particular, Rolls do not carry a Tier and no Tier is passed to Check Resolution.

Compare the Roll's strongest **Inherent** Bonus `B` against its strongest **Inherent** Penalty `P` (both as magnitudes — the same per-Type stacking rule TN computation uses, so only the highest Bonus and the deepest Penalty of the Type count). When they differ, append one entry to the Roll's `bonus_penalty_list`:

- `B > P` — an **Ascendancy Bonus** of `floor(2 × (B − P))`.
- `P > B` — an **Ascendancy Penalty** of `floor(2 × (P − B))`.
- `B = P` — no entry. Balanced Inherents produce no Ascendancy.

The Inherent value stands in for the Tier (the Tier Minimum Inherent Bonus table is `[0, 1, 2, 3, 4, 5]`), so the project's **Tier 0 counts as 0.5** convention applies: when a Roll has at least one Inherent entry, a side of the comparison that is zero or absent reads as `0.5`. A Tier-1 Roll facing a Tier-0 opponent (whose Inherent of 0 never appears as an entry) therefore gains `floor(2 × (1 − 0.5)) = +1` Ascendancy, and the Tier-0 Roll takes `−1`. A Roll with **no Inherent entries at all** derives nothing — that absence is what scopes Ascendancy to combat.

A Creature's Inherent Bonus is its Tier-derived raw power, and propagation delivers the other side's Inherent as an inverted Inherent Penalty, so the gap measures how far the Roll out- or under-classes the strongest opponent it faces — `+1` Inherent against `+4` yields a `−6` Ascendancy. Ascendancy amplifies the gap: fighting up hurts twice over (the crossed Inherent Penalty *and* the derived Ascendancy Penalty), fighting down helps twice over.

Worked examples — Adam is the Initiating Roll, Ben a Supporting Roll, Dawn the Defending Roll, Carol another Opposing Roll:

1. **Everyone equal.** All four Rolls carry `Inherent +2`. After propagation each Roll holds `Inherent +2` and a crossed `Inherent −2` — balanced, so **no Ascendancy anywhere**.
2. **Adam +2 vs Dawn +1.** Adam ends with `Inherent +2`, `Inherent −1` (Dawn's, crossed), and — his Bonus exceeding his Penalty by 1 — an `Ascendancy +2` Bonus. Dawn mirrors him: `Inherent +1`, `Inherent −2`, `Ascendancy −2`.
3. **Adam +2 vs Dawn +1 (defending) and Carol +3 (opposing).** Adam receives every Opposer's Inherent (−1 and −3); per-Type stacking counts only the −3, so he ends `Inherent +2`, `Inherent −3`, `Ascendancy −2`. Carol receives the Initiating Roll's +2: `Inherent +3`, `Inherent −2`, `Ascendancy +2`. Dawn (the Defender) likewise receives the +2: `Inherent +1`, `Inherent −2`, `Ascendancy −2`.

This operation runs *after* propagation, and an Ascendancy entry itself never crosses sides — each Roll derives its own. Ascendancy stays scoped to **combat** because only the combat builders put `Inherent` entries on their Rolls — a Creature's Tier Inherent on attack, cast, and defense Rolls (a Spell's Tier rides the casting Roll as a **Guidance** Bonus, not an Inherent, so it stays out of the Ascendancy); opposed *skill* checks carry no Inherent entries and so derive nothing. When one side does not roll at all (a No-defense attack), the combat builder injects the un-rolled side's Inherent, negated, so the gap — and the derived Ascendancy — match the defended case. This is the Check-side half of the Tier Mismatch rule defined in `../encounter/encounter_design.md`; the Inherent damage-reduction half is applied server-side at damage time.

### Spread Check (area effects)

A Check flagged `spread: true` models an **area effect**: one Supporting side (the caster, plus any supports) opposed by *N independent* Opposing Rolls — every creature caught in the spell's footprint makes its own Save. **None of the Opposers is the singular Target / Defending Roll**; they are peers, each opposed only to the caster.

A Spread Check **prepares exactly like any other** (the standard bidirectional cross-side propagation, then Ascendancy) — it only **aggregates differently**:

- **Preparation is bidirectional**, so the caster and every Opposer exchange bonuses: the caster's casting bonuses (Competency, the Spell's Inherent, …) invert onto **each** caught creature's Save, and every Opposer's bonuses invert back onto the caster. Each Roll then derives its own Ascendancy from its Inherent imbalance: every caught creature measures against the caster's Inherent, while the caster — having received every Opposer's Inherent — measures against the strongest creature it caught (per-Type stacking counts only the deepest crossed Penalty).
- **Resolution is per-Opposer.** The Supporting side resolves once into a single Supporting DoIS total; each Opposing Roll then resolves and nets independently: `degree_of_success_i = Σ Supporting DoIS − Opposer_i DoIS`, classified into its own Outcome. There is **no single Check-level Degree of Success** — the result is one Outcome per caught creature.

A non-spread Check uses the same preparation but the pooled aggregation `Σ Supporting − Σ Opposing`.

### Check Outcome classification

Once `degree_of_success` is computed, the Check Outcome is derived by calling dice resolution's "classify a value against outcome thresholds" entry point with `can_fumble = true`. The Default Success and Default Fumble Thresholds applied are the dice resolution config values.

A Check can always Fumble — the Roll-level "failure_modifier == 0 suppresses Fumble" rule does not apply at the Check level.

## Cross-domain interactions

- Callers in higher-level domains construct a Check from per-creature Rolls and invoke either the parameters-only or full-resolution entry point.
- Cross-side propagation is a Check Resolution operation; the dice domain has no awareness of Check sides or propagation.
- Check Outcome classification is delegated to the dice resolution classifier so Default Success and Default Fumble Thresholds remain owned by dice resolution.
