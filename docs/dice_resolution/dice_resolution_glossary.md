# Dice and Resolution Mechanics — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `dice_resolution_config.yaml`. Target Number Modifiers and Roll Modifiers are grouped into labeled subsections because they follow different stacking and application rules.

## Core Concepts

**Tier**: All creatures, items, spells, and abilities have a Tier, which represents the density of magical energy infusing them.

**Die Size**: The number of sides on each die. All dice rolled in the system use the same Die Size. *(configurable)*

## Checks and Rolls

**Check**: A resolution made whenever a creature takes an action with a chance of failure. A Check is composed of one or more Rolls, one from each creature involved.

**Roll**: A single creature's contribution to a Check, expressed as a roll of dice. Every participant in a Check makes exactly one Roll. A Roll is either a Supporting Roll or an Opposed Roll.

**Initial Roll**: The results of a Roll before any dice are rerolled or their values are adjusted. Each die in a Roll may be rerolled at most once; the value from the Initial Roll is replaced by the rerolled value.

**Final Roll**: The results of a Roll after any dice are rerolled or their values are adjusted.

**Supporting Roll**: A Roll made by a creature attempting the Check, or by a creature assisting another creature's attempt. Supporting Rolls contribute positively to the Degree of Success.

**Primary Roll**: A Roll made by a creature attempting the Check. Primary Rolls are Supporting Rolls and contribute positively to the Degree of Success.

**Opposed Roll**: A Roll made by a creature attempting to prevent the Check from succeeding. Opposed Rolls contribute negatively to the Degree of Success.

## Dice Counts

**Dice Count**: The number of dice rolled on a specific Roll.

**Minimum Dice Count**: The lowest permitted Dice Count. Every Roll must use at least this many dice. *(configurable)*

**Dice Count Range**: A value used to derive the maximum permitted Dice Count. The maximum equals the Minimum Dice Count plus the Dice Count Range, minus one. *(configurable)*

**Maximum Dice Count**: The maximum permitted Dice Count. Every Roll must have no more then this many dice. *(indirectly configurable)*

**Skill Prowess**: A signed integer summarizing a creature's effective competence at a particular Skill, computed by the skills domain. Prowess is the input to **Compute Check Details** and is the only value the skills domain hands to dice resolution.

**Compute Check Details**: A pure function that partitions a Skill Prowess into a `{Dice Count, Competency Bonus, Competency Penalty}` triple. Excess **positive** Prowess past the Maximum Dice Count becomes a Competency Bonus; excess **negative** Prowess past the Minimum Dice Count becomes a Competency Penalty. Both propagate to Opposed Rolls (with sign inversion on the opposed side); routing the remainder to Starting Value instead would silently strip that opposed-side effect, so the partition deliberately uses Competency modifiers. There is **no cap** on the Bonus or Penalty here — when a Bonus would push the Roll's TN past the Minimum Target Number, the existing overflow rule in **Compute Roll Parameters** converts the excess into Starting Successes downstream.

## Die Results

**Success**: A die result that meets or exceeds the Target Number. Each Success contributes one point to the Degree of Individual Success.

**Failure**: A die result equal to 1. Each Failure contributes a configurable number of points to the Degree of Individual Success, typically negative. A Check that ignores Failures sets this contribution to zero.

**Critical Success**: A die result equal to the Die Size. Each Critical Success contributes a configurable number of points to the Degree of Individual Success. This contribution replaces the single point a regular Success would otherwise contribute — a Critical does not count as a Success separately.

**Critical Count**: The total number of dice in a Roll whose result equals the Die Size. Some Checks have additional effects based on the Critical Count.

## Target Numbers

**Target Number**: A threshold compared against each die in a Roll. Any die whose result is greater than or equal to the Target Number counts as a Success. The Target Number for a given Roll is derived from the Base Target Number and any applicable Target Number Modifiers, and is clamped between the Minimum Target Number and Maximum Target Number. Abbreviated **TN**.

**Base Target Number**: The default Target Number before any Target Number Modifiers are applied. *(configurable)*

**Minimum Target Number**: The lowest value a Target Number may take after all Target Number Modifiers are applied. *(configurable)*

**Maximum Target Number**: The highest value a Target Number may take after all Target Number Modifiers are applied. *(configurable)*

## Resolution

**Degree of Individual Success**: The net result of a single Roll. Calculated by summing the contribution of every die in the Roll (Successes, Failures, Critical Successes) with any Starting contributions.

**Degree of Individual Failure**: Used when the Degree of Individual Success is negative. Equal to the absolute value of the Degree of Individual Success.

**Degree of Success**: The net result of an entire Check. Calculated as the sum of the Degrees of Individual Success from all Supporting Rolls, minus the sum of the Degrees of Individual Success from all Opposed Rolls.

**Degree of Failure**: Used when the Degree of Success is negative. Equal to the absolute value of the Degree of Success.

**Default Success Threshold**: The number of Successes required for a typical Check to succeed. Specific circumstances may require additional Successes, but absent any such rule, this is the number used. *(configurable)*

**Default Fumble Threshold**: The number by which Failures must exceed Successes for a Fumble to occur. Specific circumstances may require a greater excess, but absent any such rule, this is the number used. *(configurable)*

**Fumble**: An outcome that may occur when a Check produces more Failures than Successes by at least the Default Fumble Threshold. The consequences of a Fumble are at the discretion of the DM.

## Target Number Modifiers

Target Number Modifiers adjust the Target Number of a Roll before dice are rolled. They come in two forms: Target Number Bonuses, which reduce the Target Number for the creature's own Rolls and raise it for Opposed Rolls made against them; and Target Number Penalties, which do the reverse.

Modifiers of the same type do not stack — only the one with the largest magnitude of its sign applies. Bonuses and Penalties of the same type are tracked separately: the highest Bonus and the highest Penalty each apply, and their net effect is their arithmetic sum. For example, a +3 Bonus and a +5 Penalty of the same type produce a net +2 to the Target Number.

When Target Number Modifiers would push the Target Number outside the range defined by the Minimum Target Number and Maximum Target Number, the overflow is not wasted. Each point of Penalty beyond the Maximum Target Number becomes one additional Starting Failure, and each point of Bonus beyond the Minimum Target Number becomes one additional Starting Success. This conversion is 1:1.

The canonical list of valid bonus and penalty types does not currently belong to the dice resolution domain — see `docs/orphans.md`. Dice resolution treats type names as opaque. Every type in the list may produce a Bonus, a Penalty, and a Starting value (see below).

Bonuses and Penalties on a Roll propagate to every other Roll in the same Check by default: same-side Rolls receive them with the same sign, Opposed-side Rolls receive them with the sign inverted. A modifier may opt out of propagation with a "this-Roll-only" flag. Starting contributions do not propagate.

**Target Number Bonuses**: Modifiers that decrease the Target Number of a creature's own Rolls and increase the Target Number of all Opposed Rolls made against them.

**Target Number Penalties**: Modifiers that increase the Target Number of a creature's own Rolls and decrease the Target Number of all Opposed Rolls made against them.

**Starting Successes**: Successes added to a Roll before any dice are rolled. Starting Successes contribute to the Degree of Individual Success exactly as rolled Successes do. They come from two sources: direct Starting values provided by any modifier type (see Starting Value below) and overflow from Target Number Bonuses that would push the Target Number below the Minimum Target Number.

**Starting Failures**: Failures added to a Roll before any dice are rolled. Starting Failures contribute to the Degree of Individual Success exactly as rolled Failures do (and are ignored by Checks that ignore Failures). They come from two sources: direct Starting values provided by any modifier type and overflow from Target Number Penalties that would push the Target Number above the Maximum Target Number.

**Starting Value**: A signed integer Starting contribution associated with a specific modifier type. Positive values represent Starting Successes for that type; negative values represent Starting Failures. Any type in the Bonus Types List may have a Starting value — in practice, the Circumstance type is the primary source, but the mechanism is generic. The overall Starting Value for a Roll is the sum of every type's Starting value plus any Target Number overflow.

## Roll Modifiers

Roll Modifiers alter the dice of a Roll rather than its Target Number. The dice resolution module exposes three generic operations that external effects may invoke:

- **Value Adjustment**: a signed integer applied to a single die's value. Positive values raise a die and are targeted at the die most helpful to the Roll. Negative values lower a die and are targeted at the die most damaging to the Roll. Specific targeting rules depend on whether the Check counts Failures.
- **Reroll Operation**: a signed integer indicating the number of dice to reroll. Positive values reroll dice that are neither Successes nor Critical Successes (preferring the lowest values, which are typically Failures). Negative values reroll dice that are Successes or Critical Successes (preferring the highest values, which are typically Critical Successes).
- **Sweep Reroll**: a signed integer constrained to -1, 0, or +1. A value of +1 rerolls every die that is not a Success (every die with value < Target Number, including Failures). A value of -1 rerolls every Success (every die with value ≥ Target Number, including Critical Successes). A value of 0 has no effect. Sweep Reroll is mutually exclusive across directions on a single Roll — at most one direction applies.

No die may be rerolled more than once in a Roll. This rule spans the Reroll Operation and Sweep Reroll: a die rerolled by the Reroll Operation is skipped by Sweep Reroll, and vice versa.

When more than one of these operations applies to the same Roll, they execute in a fixed order: **Reroll Operation, then Sweep Reroll, then Value Adjustment.**

Specific named effects (those arising from divine intervention, fortune, magical guidance, and so on) are defined in the modules that introduce those concepts. Each such effect specifies which of the two generic operations it uses and with what magnitude.
