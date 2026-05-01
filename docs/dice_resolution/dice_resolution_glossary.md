# Dice and Resolution Mechanics — Glossary

Owns dice rolling, success/failure counting, target numbers, and roll modifiers. Target Number Modifiers and Roll Modifiers follow different stacking and application rules. *(configurable)* values come from `dice_resolution_config.yaml`.

## Core Concepts

**Tier**: All creatures, items, spells, and abilities have a Tier representing the density of magical energy infusing them. (See common glossary.)

**Die Size**: Number of sides on each die. All dice in the system use the same Die Size. *(configurable)*

## Checks and Rolls

**Check**: A resolution made when a creature takes an action with a chance of failure. Composed of one or more Rolls, one per creature involved.

**Roll**: A single creature's contribution to a Check. Either a Supporting Roll or an Opposed Roll.

**Initial Roll**: Results of a Roll before any rerolls or value adjustments. Each die may be rerolled at most once.

**Final Roll**: Results after rerolls and value adjustments.

**Supporting Roll**: A Roll made by a creature attempting the Check or assisting another's attempt. Contributes positively to the Degree of Success.

**Primary Roll**: A Supporting Roll made by a creature attempting the Check (rather than assisting).

**Opposed Roll**: A Roll made by a creature attempting to prevent the Check from succeeding. Contributes negatively to the Degree of Success.

## Dice Counts

**Dice Count**: Number of dice rolled on a Roll.

**Minimum Dice Count**: Lowest permitted Dice Count. *(configurable)*

**Dice Count Range**: Used to derive the maximum: Maximum = Minimum + Range − 1. *(configurable)*

**Maximum Dice Count**: Highest permitted Dice Count. *(indirectly configurable)*

(Skill Prowess: see common glossary.)

**Compute Check Details**: A pure function that partitions Skill Prowess into `{Dice Count, Competency Bonus, Competency Penalty}`. Excess **positive** Prowess past Maximum Dice Count becomes a Competency Bonus; excess **negative** Prowess past Minimum Dice Count becomes a Competency Penalty. Both propagate to Opposed Rolls (with sign inversion). No cap — when a Bonus would push the Roll's TN past the Minimum Target Number, the overflow rule converts the excess into Starting Successes downstream. *(3 sentences — flagged: the partition algorithm, the propagation behavior, and the overflow handoff are each load-bearing)*

## Die Results

**Success**: A die result ≥ Target Number. Each contributes one point to Degree of Individual Success.

**Failure**: A die result equal to 1. Contributes a configurable number of points (typically negative). Checks that ignore Failures set this to zero.

**Critical Success**: A die result equal to Die Size. Contributes a configurable number of points; replaces the single point a regular Success would otherwise contribute.

**Critical Count**: Total number of dice in a Roll whose result equals Die Size. Some Checks have additional effects based on this.

## Target Numbers

**Target Number**: Threshold compared against each die. Any die ≥ TN counts as a Success. Derived from Base TN and any TN Modifiers; clamped between Minimum and Maximum TN. Abbreviated **TN**.

**Base Target Number**: Default TN before any TN Modifiers. *(configurable)*

**Minimum Target Number**: Lowest TN after modifiers. *(configurable)*

**Maximum Target Number**: Highest TN after modifiers. *(configurable)*

## Resolution

**Degree of Individual Success**: Net result of a single Roll. Sum of every die's contribution (Successes, Failures, Critical Successes) plus Starting contributions.

**Degree of Individual Failure**: Used when DoIS is negative; equals its absolute value.

**Degree of Success**: Net result of an entire Check — sum of Supporting Roll DoIS minus sum of Opposed Roll DoIS.

**Degree of Failure**: Used when Degree of Success is negative; equals its absolute value.

**Default Success Threshold**: Successes required for a typical Check to succeed. *(configurable)*

**Default Fumble Threshold**: Number by which Failures must exceed Successes for a Fumble. *(configurable)*

**Fumble**: An outcome that may occur when a Check produces enough excess Failures. Consequences are at DM discretion.

## Target Number Modifiers

TN Modifiers adjust the Target Number before dice are rolled. Two forms: **Bonuses** reduce the TN of the creature's own Rolls and raise it for Opposed Rolls against them; **Penalties** do the reverse.

Modifiers of the same type do not stack — only the largest magnitude of its sign applies. Bonuses and Penalties of the same type are tracked separately: highest Bonus and highest Penalty each apply, net is their arithmetic sum (e.g. +3 Bonus and +5 Penalty produce +2 to the TN).

When TN Modifiers would push the TN outside `[Minimum TN, Maximum TN]`, the overflow becomes Starting values 1:1: each point of Penalty beyond Maximum TN becomes a Starting Failure; each point of Bonus beyond Minimum TN becomes a Starting Success.

The canonical list of valid bonus/penalty types does not currently belong to dice resolution — see `docs/orphans.md`. Type names are treated as opaque. Every type may produce a Bonus, a Penalty, and a Starting value.

Bonuses and Penalties propagate to other Rolls in the same Check by default: same-side with same sign, Opposed-side with sign inverted. A modifier may opt out via a "this-Roll-only" flag. Starting contributions do **not** propagate.

**Target Number Bonuses**: Modifiers that decrease the TN of the creature's own Rolls and increase the TN of Opposed Rolls against them.

**Target Number Penalties**: Modifiers that increase the TN of the creature's own Rolls and decrease the TN of Opposed Rolls against them.

**Starting Successes**: Successes added before any dice are rolled. Contribute to DoIS exactly as rolled Successes do. Sources: direct Starting values from any modifier type, and overflow from Bonuses past Minimum TN.

**Starting Failures**: Failures added before any dice are rolled. Contribute to DoIS exactly as rolled Failures do (and ignored when the Check ignores Failures). Sources: direct Starting values from any modifier type, and overflow from Penalties past Maximum TN.

**Starting Value**: A signed integer Starting contribution associated with a specific modifier type. Positive = Starting Successes for that type; negative = Starting Failures. Any type in the Bonus Types List may have one (Circumstance is the primary source in practice). The overall Starting Value for a Roll is the sum across types plus TN overflow.

## Initiative

Initiative rolls are specialized: no Target Number, no Success/Failure counting, only relative ordering matters.

**Initiative String**: A string encoding one Combatant's initiative roll, sorted highest-to-lowest with one character per die. Encoding is fixed by **Initiative String Encoding** so ASCII-descending lex compare on two Initiative Strings reproduces the die-by-die comparison. Combat consumers store the string opaquely.

**Initiative String Encoding**: A configuration string giving labels for die values 10 and above. Values 1–9 are always digit characters. The user-supplied string supplies labels for 10, 11, 12, …; default `"X"` covers value 10 only. When Die Size exceeds the user string's coverage, the encoding extends with `A, B, C, …, Z`, **skipping any letter already present in the user string** to avoid duplicates. Validated at boot: every character unique across the full encoding (1–9 + user string + auto-fill); encoding **monotonic** (each successive value's character has a strictly greater ASCII codepoint); encoding covers the full range 1 through Die Size. *(4 sentences — flagged: each validation rule is a separate boot-time invariant)* *(configurable, default `"X"`)*

**Roll Initiative For Group**: Function that takes an ordered list of dice counts (one per Combatant) and returns an aligned list of `{initiative_string, order_position}`. `order_position` is a 0-indexed turn-order rank (0 = first). Rolls are independent — no propagation, modifiers, or rerolls at this layer.

**Order Initiative**: Pure function: given an ordered list of Initiative Strings, returns a list of indices giving turn order. Comparison is ASCII-descending lex compare; identical-string ties break by original index (lowest first).

## Roll Modifiers

Roll Modifiers alter the dice of a Roll rather than its TN. Three generic operations:

- **Value Adjustment**: signed integer applied to a single die's value. Positive raises, targeting the most helpful die; negative lowers, targeting the most damaging die. Targeting depends on whether the Check counts Failures.
- **Reroll Operation**: signed integer = number of dice to reroll. Positive rerolls non-Success / non-Critical dice (preferring lowest, typically Failures). Negative rerolls Successes or Critical Successes (preferring highest).
- **Sweep Reroll**: signed integer constrained to -1, 0, or +1. +1 rerolls every die that is not a Success; -1 rerolls every Success; 0 has no effect. Mutually exclusive across directions on a single Roll.

No die may be rerolled more than once in a Roll — this rule spans Reroll Operation and Sweep Reroll. When more than one operation applies, fixed order: **Reroll Operation, then Sweep Reroll, then Value Adjustment.**

Specific named effects (divine intervention, fortune, magical guidance, etc.) are defined in the modules that introduce them. Each specifies which generic operation it uses and with what magnitude.
