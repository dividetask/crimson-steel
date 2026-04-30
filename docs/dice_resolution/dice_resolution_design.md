# Dice and Resolution Mechanics — Design

Companion to `dice_resolution_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

## Key Operations

Only operations whose behavior isn't obvious from the glossary are described here. Trivial wrappers (rolling N dice, summing dice, sorting) are omitted.

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

## Responsibilities

### Owned by the dice resolution domain

- Loading and validating `dice_resolution_config.yaml`.
- Producing random die results.
- Computing final TN and Starting Value from a modifier dictionary.
- Computing Degree of Individual Success and Critical Count for each Roll.
- Applying Roll Modifiers (Reroll Operation, Sweep Reroll, Value Adjustment) including target selection and rerolled-die bookkeeping.
- Composing a Check from an ordered list of tagged Rolls: aggregating Degrees of Individual Success into a Degree of Success, applying success thresholds, detecting Fumbles.
- Propagating same-Check Bonuses and Penalties across Rolls (with sign inversion across sides) and honoring the per-modifier "this-Roll-only" opt-out.

### Explicitly *not* owned here

- **Sourcing modifiers.** What grants a +2 Circumstance Bonus, a Reroll Operation, or a Sweep Reroll lives in the abilities/conditions/equipment domains. They hand the dice domain a fully-resolved set of Rolls with their modifiers attached.
- **The canonical list of modifier type names.** See `docs/orphans.md`. Dice resolution treats keys as opaque.
- **Tagging Rolls as Supporting vs. Opposed.** The caller assembles the Roll list and tags each entry; dice resolution does not infer sides from creature identity (it doesn't know about creatures at all).
- **Dice Count selection.** The Minimum/Maximum Dice Count are config values consulted by the caller; the dice domain accepts whatever count is passed.
- **Presentation.** Showing rolls to the player (animations, history, log entries) is a UI concern.

### Unassigned (no current owner)

- Validating that a passed Dice Count is within the configured Minimum/Maximum range — currently no class enforces this.
- Validating that modifier keys belong to the canonical type list (see `docs/orphans.md`).
