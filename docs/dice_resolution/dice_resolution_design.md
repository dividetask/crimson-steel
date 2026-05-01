# Dice and Resolution Mechanics — Design

Companion to `dice_resolution_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

## Key Operations

Only operations whose behavior isn't obvious from the glossary are described here. Trivial wrappers (rolling N dice, summing dice, sorting) are omitted.

### Compute Check Details — Skill Prowess partition

Callers that have computed a Skill Prowess (skill ranks plus a half-attribute contribution, per the skills domain) hand the integer to `compute_check_details(prowess)` and receive a `{dice_count, competency_bonus, competency_penalty, starting_value}` hash. The cascade is:

1. **Dice first.** `Dice Count = clamp(Minimum Dice Count + prowess, Minimum Dice Count, Maximum Dice Count)`. A non-negative Prowess raises the dice pool toward the Maximum Dice Count; a negative Prowess clamps to the Minimum Dice Count.
2. **Competency modifier next.** Whatever (signed) Prowess remains after dice fill the pool becomes a Competency modifier:
   - **Positive remainder → Competency Bonus.**
   - **Negative remainder → Competency Penalty.**
   No cap is applied at this layer. When the resulting Bonus would push the Roll's TN past the Minimum Target Number, the existing overflow rule in `compute_roll_parameters` converts the excess into Starting Successes downstream — that's where the floor is enforced, not here.

   The partition deliberately uses Competency modifiers (which propagate to Opposed Rolls with sign inversion) rather than direct Starting Value emission. Routing excess Prowess into Starting Value would silently strip the opposed-side effect — a high-Prowess attacker should make their target's defense Roll harder, and Starting contributions don't propagate.

3. **Starting Value stays zero from this function.** It's still in the return shape for caller convenience but `compute_check_details` never emits a non-zero value. Starting contributions arrive elsewhere (per-type Starting modifiers, the Bonus/Penalty TN overflow handled by `compute_roll_parameters`).

The function is pure: no dice are rolled, no modifier dictionary is built. The caller folds the returned Competency Bonus or Penalty into the corresponding `"Competency Bonus"` / `"Competency Penalty"` modifier dictionary entry before invoking `compute_roll_parameters`. Dice resolution never asks where the Prowess number came from; ownership of that math belongs to the skills domain.

### Target Number computation with overflow conversion

When applying Target Number Modifiers, the resulting TN is clamped to `[Minimum Target Number, Maximum Target Number]`, but the clamped-off magnitude is **not discarded** — it converts 1:1 into Starting contributions:

- Bonus that would push TN below the minimum → each excess point becomes one Starting Success.
- Penalty that would push TN above the maximum → each excess point becomes one Starting Failure.

Per-type Bonuses and Penalties of the same type stack arithmetically (bonus and penalty cancel — see glossary). Only one Bonus and one Penalty per type apply; magnitude tie-breaking is by largest value. Per-type Starting contributions sum directly into the final Starting Value alongside any overflow.

Modifier keys are treated as opaque — dice resolution does not validate type names against any list. The canonical list of valid types is documented in `docs/orphans.md` until it finds a permanent home; validation, if needed, happens at the layer that assembles the modifier dictionary.

### Modifier propagation across Rolls in a Check

Bonuses and Penalties attached to one Roll propagate to every other Roll in the Check by default:

- Same-side Roll → applied with the same sign.
- Opposite-side Roll → applied with sign inverted (a Bonus on a Supporting Roll becomes a Penalty on every Opposed Roll, and vice versa).

A modifier may opt out of propagation with a "this-Roll-only" flag, in which case it stays on the Roll it was attached to. Starting contributions and Roll Modifiers (Reroll Operation, Sweep Reroll, Value Adjustment) do **not** propagate — they apply only to the Roll they target.

### Multi-Roll Check composition

The dice domain accepts a Check as an ordered list of Rolls, each tagged Supporting or Opposed. Convention: **the first Roll in the list is the Primary Roll.** This is informational — the Primary's contribution is computed identically to other Supporting Rolls — but downstream consumers may key off it (e.g., to identify which creature initiated the Check).

The Degree of Success for the whole Check is the sum of Supporting Rolls' Degrees of Individual Success minus the sum of Opposed Rolls'. Fumble detection compares total Failures against total Successes across all Supporting Rolls using the Default Fumble Threshold.

### Nudge targeting (Value Adjustment)

A nudge changes one die's value, but the *interesting* question is *which* die. The chosen target is the die where the nudge would change its contribution to the Degree of Individual Success the most:

- Positive nudge → die with the largest positive delta in contribution.
- Negative nudge → die with the largest negative delta.
- Tie → lowest index wins.

The contribution function is piecewise: `critical_modifier` if value equals Die Size, `failure_modifier` if value equals 1, `1` if value ≥ TN, else `0`. The post-nudge value is clamped to `[1, Die Size]`. A nudge that produces no change in the target die's value is a no-op.

For Checks that ignore Failures, the caller passes `failure_modifier = 0`; the targeting logic falls out correctly without special-casing.

### Reroll Operation (selective reroll)

Selection is direction-dependent and prefers the highest-impact dice:

- **Positive `reroll_count`** rerolls dice that are *not* Successes (value < TN), preferring the lowest values. Failures (value 1) are always rerolled first when present.
- **Negative `reroll_count`** rerolls dice that *are* Successes (value ≥ TN), preferring the highest values. Critical Successes (value = Die Size) go first.

Implementation walks dice in ascending (positive) or descending (negative) order and stops as soon as a die crosses the Success threshold — no per-die membership check needed.

### Sweep Reroll

A categorical reroll. Encoded as a signed integer constrained to `-1`, `0`, or `+1`:

- `+1` → reroll **every** die that is not a Success (every die with value < TN — Failures and middling non-result dice alike).
- `-1` → reroll **every** Success (every die with value ≥ TN, including Critical Successes).
- `0` → no-op.

Sweep Reroll cannot be both positive and negative on the same Roll — only one direction or neither applies.

### Order of operations on a Roll

For a single Roll, modifiers apply in this fixed order:

1. **Reroll Operation** (Luck and similar effects).
2. **Sweep Reroll**.
3. **Value Adjustment** (Nudge).

The "no die rerolled more than once" rule spans steps 1 and 2: dice already rerolled by the Reroll Operation are skipped by Sweep Reroll. The Value Adjustment in step 3 sees post-reroll values.

This order is observable — for example, a Reroll Operation could turn a Failure into a near-Success that the Nudge then promotes; conversely, a Sweep Reroll on Failures will skip dice that the Reroll Operation already replaced.

### Initiative String Encoding and ordering

Initiative rolls are a degenerate case for the Check machinery — no Target Number, no Successes, no propagation — so they get their own pair of helpers (`Roll Initiative For Group`, `Order Initiative`) and a string representation that consumers can compare without decoding.

**Why a string?** A Combatant's initiative result is just an ordered multiset of die values, used only for relative ordering. A string encoding lets consumers (combat) store it as opaque data, sort it with the same lex compare the standard library already provides, and avoid re-implementing die-by-die tie-breaks. The encoding's monotonicity invariant — higher die value → higher ASCII character — is what makes lex compare equivalent to the underlying numeric comparison.

**Encoding construction.** At boot, the dice resolution module builds a `value → char` table covering 1 through Die Size:

1. Values 1–9 always use digit characters `'1'` through `'9'`.
2. For values 10 and above, consume characters from the configured `Initiative String Encoding` (default `"X"`).
3. If the configured string runs out before reaching Die Size, fall back to letters `A, B, C, …, Z` in order, **skipping any letter already used in the configured string** so the table has no duplicates.
4. Validate: all chars unique, all chars distinct from the digit chars, and the table is monotonic in ASCII (each value's char has a strictly higher codepoint than the previous value's char). Boot errors on any failure.

The auto-fill rule preserves monotonicity by construction only when the user string is itself monotonic and slots into the alphabet without forcing a non-monotonic gap. The validator catches misconfigurations: e.g., `"ZX"` would fail because `'X' < 'Z'`, breaking monotonicity at value 11.

**`Roll Initiative For Group`.** Takes a list of dice counts aligned to the caller's Combatant list. For each entry: roll N dice, sort the values descending, map each value through the encoding table, and concatenate to produce that Combatant's Initiative String. Then run the strings through the same comparator as `Order Initiative` to compute each entry's `order_position`. Returns an aligned list — index `i` of the output corresponds to index `i` of the input — so the caller never has to thread Combatant identities through the dice domain.

**`Order Initiative`.** Pure: sort the inputs by ASCII descending lex compare, breaking ties by original index (lowest first), and return the permutation as a list of indices. Used by combat after applying Initiative Luck or Initiative Insight (which mutate the underlying string), or to re-derive turn order from persisted Initiative Strings on load.

The dice domain owns the encoding and the ordering helpers but does **not** own initiative-specific roll modifications (Luck, Insight) — those are combat-specific Reroll / Value Adjustment variants documented in `combat_design.md`. The dice domain does not know what an Initiative is for; it just rolls dice and provides a string-based representation that's convenient for consumers who only need ordering.

## Responsibilities

### Owned by the dice resolution domain

- Loading and validating `dice_resolution_config.yaml`.
- Producing random die results.
- Computing final TN and Starting Value from a modifier dictionary.
- Partitioning a Skill Prowess into `{Dice Count, Competency Bonus, Competency Penalty}` via **Compute Check Details**, using the Minimum Dice Count and Dice Count Range from config. No cap; downstream overflow handles TN-floor breaches.
- Computing Degree of Individual Success and Critical Count for each Roll.
- Applying Roll Modifiers (Reroll Operation, Sweep Reroll, Value Adjustment) including target selection and rerolled-die bookkeeping.
- Composing a Check from an ordered list of tagged Rolls: aggregating Degrees of Individual Success into a Degree of Success, applying success thresholds, detecting Fumbles.
- Propagating same-Check Bonuses and Penalties across Rolls (with sign inversion across sides) and honoring the per-modifier "this-Roll-only" opt-out.
- Building and validating the Initiative String Encoding at boot, rolling initiative for a group of Combatants (`Roll Initiative For Group`), and ordering Initiative Strings into a turn order (`Order Initiative`).

### Explicitly *not* owned here

- **Sourcing modifiers.** What grants a +2 Circumstance Bonus, a Reroll Operation, or a Sweep Reroll lives in the abilities/conditions/equipment domains. They hand the dice domain a fully-resolved set of Rolls with their modifiers attached.
- **The canonical list of modifier type names.** See `docs/orphans.md`. Dice resolution treats keys as opaque.
- **Tagging Rolls as Supporting vs. Opposed.** The caller assembles the Roll list and tags each entry; dice resolution does not infer sides from creature identity (it doesn't know about creatures at all).
- **Dice Count selection.** The Minimum/Maximum Dice Count are config values consulted by the caller; the dice domain accepts whatever count is passed.
- **Presentation.** Showing rolls to the player (animations, history, log entries) is a UI concern.

### Unassigned (no current owner)

- Validating that a passed Dice Count is within the configured Minimum/Maximum range — currently no class enforces this.
- Validating that modifier keys belong to the canonical type list (see `docs/orphans.md`).
