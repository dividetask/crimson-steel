# Dice and Resolution Mechanics — Design

Companion to `dice_resolution_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

## Key Operations

Only operations whose behavior isn't obvious from the glossary are described here. Trivial wrappers (rolling N dice, summing dice, sorting) are omitted.

### Target Number computation with overflow conversion

When applying Target Number Modifiers, the resulting TN is clamped to `[Minimum Target Number, Maximum Target Number]`, but the clamped-off magnitude is **not discarded** — it converts 1:1 into Starting contributions:

- Bonus that would push TN below the minimum → each excess point becomes one Starting Success.
- Penalty that would push TN above the maximum → each excess point becomes one Starting Failure.

Per-type Bonuses and Penalties of the same type stack arithmetically (bonus and penalty cancel — see glossary). Only one Bonus and one Penalty per type apply; magnitude tie-breaking is by largest value. Per-type Starting contributions sum directly into the final Starting Value alongside any overflow.

Implementations must reject unknown modifier keys rather than silently ignore them — modifier names are not free-form, they're enumerated in `dice_resolution_config.yaml` under `Bonus Types List`.

### Nudge targeting (Value Adjustment)

A nudge changes one die's value, but the *interesting* question is *which* die. The chosen target is the die where the nudge would change its contribution to the Degree of Individual Success the most:

- Positive nudge → die with the largest positive delta in contribution.
- Negative nudge → die with the largest negative delta.
- Tie → lowest index wins.

The contribution function is piecewise: `critical_modifier` if value equals Die Size, `failure_modifier` if value equals 1, `1` if value ≥ TN, else `0`. The post-nudge value is clamped to `[1, Die Size]`. A nudge that produces no change in the target die's value is a no-op (returns all-null change list).

For Checks that ignore Failures, the caller passes `failure_modifier = 0`; the targeting logic falls out correctly without special-casing.

### Selective reroll

Reroll selection is direction-dependent and prefers the highest-impact dice:

- **Positive `reroll_count`** rerolls dice that are *not* Successes (value < TN), preferring the lowest values. Failures (value 1) are always rerolled first when present.
- **Negative `reroll_count`** rerolls dice that *are* Successes (value ≥ TN), preferring the highest values. Critical Successes (value = Die Size) go first.

Implementation walks dice in ascending (positive) or descending (negative) order and stops as soon as a die crosses the Success threshold — no per-die membership check needed. Each die is rerolled at most once; visiting in sorted order satisfies this without bookkeeping.

### Order of operations

When both a Roll Modifier reroll and a Roll Modifier value adjustment apply to the same Roll, **reroll runs first, then value adjustment**. This is observable: a reroll could turn a Failure into a near-Success that the nudge then promotes.

## Responsibilities

### Owned by the dice resolution domain

- Loading and validating `dice_resolution_config.yaml`.
- Producing random die results.
- Computing final TN and Starting Value from a modifier dictionary.
- Computing Degree of Individual Success and Critical Count from a list of dice + TN + Starting Value.
- Applying value-adjustment and reroll Roll Modifiers, including target selection.
- Rejecting unknown modifier keys.

### Explicitly *not* owned here

- **Composing a Check from multiple Rolls.** Summing Supporting and Opposed Rolls into a Degree of Success, deciding success thresholds, and detecting Fumbles all happen in whatever module orchestrates Checks (combat, ability resolution, skill use). The dice domain only knows about a single Roll.
- **Sourcing modifiers.** What grants a +2 Circumstance Bonus, or a Reroll Operation, lives in the abilities/conditions/equipment domains. They hand the dice domain a fully-resolved modifier dictionary.
- **Dice Count selection.** The Minimum/Maximum Dice Count are config values consulted by the caller; the dice domain accepts whatever count is passed.
- **Presentation.** Showing rolls to the player (animations, history, log entries) is a UI concern.

### Unassigned (no current owner)

- Aggregating per-Roll results into a Check outcome (Degree of Success across Supporting/Opposed Rolls, Fumble detection). *Likely a `CheckResolver` class.*
- Deciding which creatures contribute Supporting vs. Opposed Rolls for a given action.
- Validating that a passed Dice Count is within the configured Minimum/Maximum range — currently no class enforces this.
