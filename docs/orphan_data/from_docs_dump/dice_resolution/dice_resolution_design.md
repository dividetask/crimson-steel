# Dice and Resolution Mechanics — Design

Only operations whose behavior isn't obvious from the glossary are described here. Trivial wrappers (rolling N dice, summing dice, sorting) are omitted.

## Implementation language

This document describes the design of the dice domain without favoring one runtime over another. In practice the operations split between server-side Ruby (`lib/dice_system.rb`) and client-side JavaScript (`public/js/roll_stub.js`, `public/js/multi_roll_stub.js`). The split today:

- **Ruby (`DiceSystem`)** owns the canonical math: loading and validating `dice_resolution_config.yaml`, building the Initiative String Encoding table, rolling dice (`rand_roll_dice`), `compute_check_details`, `compute_roll_parameters`, `compute_results`, `apply_nudge`, `rand_reroll_some_dice`, `apply_sweep_reroll`, `roll_initiative_for_group`, `order_initiative`, and Check composition (`compose_check`). Modifier propagation across Rolls in a Check is also a Ruby operation.
- **JavaScript (`roll_stub.js`, `multi_roll_stub.js`, `attack_stub.js`)** owns presentation and the in-flow stub interactions: rendering dice with success/critical/failure styling, walking the DM through the per-step attack flow, computing per-step preview Target Numbers (`attackTn`, `defenseTn` in `attack_stub.js`), and chaining the configured Reroll Operation + Value Adjustment via `/roll_stub/reroll` and `/roll_stub/nudge` endpoints. The JavaScript layer never duplicates the dice math — it always calls back into Ruby for actual rolls and modifier application.

Specific named effects (e.g. Bardic Inspiration's Reroll Operation) live in the modules that introduce them. They typically end up server-side in Ruby with a JS-side trigger in the relevant stub.

## Key Operations

### Compute Check Details — Skill Prowess partition

Callers hand a Skill Prowess integer to `compute_check_details(prowess)` and receive `{dice_count, competency_bonus, competency_penalty, starting_value}`. The partition:

- **Competency tier from Prowess.** Each `Dice Count Range` worth of Prowess advances the Competency tier by one. `competency_bonus = floor(prowess / Range)` (positive Prowess only); `competency_penalty = ceil(-prowess / Range)` (negative only).
- **Leftover fills dice.** `Dice Count = clamp(Minimum Dice Count + (prowess mod Range), Minimum Dice Count, Maximum Dice Count)`. Negative Prowess subtracts dice from the minimum, clamped at the minimum.
- **No cap on Bonus or Penalty.** When a resulting Bonus would push the Roll's TN past the Minimum Target Number, the overflow rule in `compute_roll_parameters` converts the excess into Starting Successes downstream — that's where the floor is enforced.
- **Starting Value stays zero from this function.** Starting contributions arrive elsewhere (per-type Starting modifiers, the Bonus/Penalty TN overflow handled by `compute_roll_parameters`).

The partition deliberately uses Competency modifiers (which propagate to Opposed Rolls with sign inversion) rather than direct Starting Value emission. Routing excess Prowess into Starting Value would silently strip the opposed-side effect — a high-Prowess attacker should make their target's defense Roll harder, and Starting contributions don't propagate.

The function is pure: no dice rolled, no modifier dictionary built. Dice resolution never asks where the Prowess came from; that math belongs to the proficiency domain.

### Target Number computation with overflow conversion

When applying TN Modifiers, the resulting TN is clamped to `[Minimum Target Number, Maximum Target Number]`, but the clamped-off magnitude is **not discarded** — it converts 1:1 into Starting contributions:

- Bonus that would push TN below the minimum → each excess point becomes one Starting Success.
- Penalty that would push TN above the maximum → each excess point becomes one Starting Failure.

Per-type Bonuses and Penalties of the same type stack arithmetically. Only one Bonus and one Penalty per type apply; magnitude tie-breaking is by largest value. Modifier keys are treated as opaque — dice resolution does not validate type names.

### Modifier propagation across Rolls in a Check

Bonuses and Penalties attached to one Roll propagate **only to opposed-side Rolls**, with sign inverted (Bonus ↔ Penalty). Same-side Rolls are unaffected by each other's Bonuses and Penalties — every Roll only sees its own per-type Bonus/Penalty plus the inverted contributions from the opposing side.

A modifier may opt out of opposed-side propagation via a "this-Roll-only" flag. Starting contributions and Roll Modifiers (Reroll Operation, Sweep Reroll, Value Adjustment) do **not** propagate.

The earlier rule — same-sign propagation among Supporting Rolls — has been dropped. A Supporting ally's +N Bonus no longer raises an opposed defender's TN through any Supporting Roll except the one carrying the Bonus.

### Multi-Roll Check composition

The dice domain accepts a Check as an ordered list of Rolls, each tagged Supporting or Opposed. Convention: **the first Roll in the list is the Primary Roll** — informational, but downstream consumers may key off it.

The Degree of Success for the whole Check is the sum of Supporting Rolls' Degrees of Individual Success minus the sum of Opposed Rolls'. Fumble detection compares total Failures against total Successes across all Supporting Rolls.

### Nudge targeting (Value Adjustment)

A nudge changes one die's value, but the *interesting* question is *which* die. Target the die where the nudge would change its contribution to the Degree of Individual Success the most:

- Positive nudge → die with the largest positive delta.
- Negative nudge → die with the largest negative delta.
- Tie → lowest index wins.

The contribution function is piecewise: `critical_modifier` if value equals Die Size, `failure_modifier` if value equals 1, `1` if value ≥ TN, else `0`. The post-nudge value is clamped to `[1, Die Size]`. A nudge that produces no change is a no-op.

For Checks that ignore Failures, the caller passes `failure_modifier = 0`; the targeting logic falls out correctly without special-casing.

### Reroll Operation (selective reroll)

Selection is direction-dependent and prefers the highest-impact dice:

- **Positive `reroll_count`** rerolls dice that are *not* Successes (value < TN), preferring the lowest. Failures (value 1) are always rerolled first.
- **Negative `reroll_count`** rerolls dice that *are* Successes (value ≥ TN), preferring the highest. Critical Successes (value = Die Size) go first.

Implementation walks dice in ascending (positive) or descending (negative) order and stops as soon as a die crosses the Success threshold — no per-die membership check needed.

### Sweep Reroll

A categorical reroll. Encoded as `-1`, `0`, or `+1`:

- `+1` → reroll **every** die that is not a Success.
- `-1` → reroll **every** Success.
- `0` → no-op.

### Order of operations on a Roll

Modifiers apply in this fixed order:

1. **Reroll Operation** (Luck and similar).
2. **Sweep Reroll**.
3. **Value Adjustment** (Nudge).

The "no die rerolled more than once" rule spans steps 1 and 2: dice already rerolled by Reroll Operation are skipped by Sweep Reroll. Value Adjustment sees post-reroll values.

This order is observable — a Reroll Operation could turn a Failure into a near-Success that the Nudge then promotes; conversely, a Sweep Reroll on Failures will skip dice that the Reroll Operation already replaced.

### Initiative String Encoding and ordering

Initiative rolls are a degenerate case for the Check machinery — no Target Number, no Successes, no propagation — so they get their own pair of helpers (`Roll Initiative For Group`, `Order Initiative`) and a string representation that consumers can compare without decoding.

**Why a string?** A Combatant's initiative result is just an ordered multiset of die values, used only for relative ordering. A string encoding lets consumers store it as opaque data, sort it with the standard library's lex compare, and avoid re-implementing die-by-die tie-breaks. The encoding's monotonicity invariant — higher die value → higher ASCII character — is what makes lex compare equivalent to numeric comparison.

**Encoding construction.** At boot, build a `value → char` table covering 1 through Die Size:

1. Values 1–9 always use digit characters `'1'` through `'9'`.
2. For values 10+, consume characters from the configured `Initiative String Encoding` (default `"X"`).
3. If the configured string runs out, fall back to letters `A, B, C, …, Z`, **skipping any letter already used in the configured string** so the table has no duplicates.
4. Validate: all chars unique, all chars distinct from digits, the table monotonic in ASCII. Boot errors on any failure.

The auto-fill rule preserves monotonicity by construction only when the user string is itself monotonic; the validator catches misconfigurations (e.g., `"ZX"` fails because `'X' < 'Z'`).

**`Roll Initiative For Group`.** Takes dice counts aligned to the Combatant list. For each entry: roll N dice, sort descending, map through the encoding table, concatenate. Then run the strings through the same comparator as `Order Initiative`. Returns an aligned list — the caller never has to thread Combatant identities through the dice domain.

**`Order Initiative`.** Pure: sort by ASCII descending lex compare, breaking ties by original index, return the permutation.

The dice domain owns the encoding and ordering helpers but does **not** own initiative-specific roll modifications (Luck, Insight) — those are combat-specific variants in `combat_design.md`. The dice domain doesn't know what an Initiative is for; it just rolls dice and provides a string-based representation that's convenient for ordering.

## Responsibilities

### Owned by the dice resolution domain

- Loading and validating `dice_resolution_config.yaml`.
- Producing random die results.
- Computing final TN and Starting Value from a modifier dictionary.
- Skill Prowess partition via `compute_check_details`.
- Computing Degree of Individual Success and Critical Count for each Roll.
- Applying Roll Modifiers (Reroll Operation, Sweep Reroll, Value Adjustment) including target selection and rerolled-die bookkeeping.
- Composing a Check from tagged Rolls: aggregating Degrees of Individual Success, applying success thresholds, detecting Fumbles.
- Propagating same-Check Bonuses and Penalties (with sign inversion across sides) and honoring "this-Roll-only" opt-out.
- Building and validating the Initiative String Encoding at boot, `Roll Initiative For Group`, `Order Initiative`.

### Explicitly *not* owned here

- **Sourcing modifiers.** What grants a +2 Circumstance Bonus, a Reroll Operation, etc. lives in abilities/conditions/equipment.
- **The canonical list of modifier type names.** See `docs/orphans.md`. Dice resolution treats keys as opaque.
- **Tagging Rolls as Supporting vs. Opposed.** The caller assembles the Roll list.
- **Dice Count selection.** The caller passes whatever count is needed.
- **Presentation.** UI concern.

### Unassigned (no current owner)

- Validating that a passed Dice Count is within the configured Min/Max range.
- Validating that modifier keys belong to the canonical type list.
