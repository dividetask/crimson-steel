# Dice and Resolution Mechanics — Glossary

Defines the vocabulary used by `dice_resolution_design.md` and `dice_resolution_tests.md`. Multi-Roll terms live in the check resolution glossary. *(configurable)* values come from `dice_resolution_config.yaml`.

## Rolls

**Die Size**: Number of sides on each die. All dice in the system use the same Die Size. *(configurable)*

**Roll**: A single resolution of dice against a Target Number, with optional Bonuses, Penalties, rerolls, and adjustments. The structure is fully defined in `dice_resolution_design.md`.

**Initial Roll**: Results of a Roll before any Dice Operations. Each die may be rerolled at most once.

**Final Roll**: Results after rerolls and value adjustments.

## Dice Counts

**Dice Count**: Number of dice rolled on a Roll.

**Minimum Dice Count**: Lowest permitted Dice Count. *(configurable)*

**Dice Count Range**: Used to derive the maximum: Maximum = Minimum + Range − 1. *(configurable)*

**Maximum Dice Count**: Highest permitted Dice Count. *(indirectly configurable)*

## Die Results

**Success**: A die result ≥ Target Number. Each contributes one point to Degree of Individual Success, or a higher amount if it is a Critical Success.

**Failure**: A die result equal to 1. Contributes a configurable number of points (typically negative). Rolls that ignore Failures set this to zero.

**Neutral Result**: A die result greater than 1 and less than the Target Number. Contributes no points to the Degree of Individual Success.

**Critical Success**: A die result equal to Die Size. Contributes a configurable number of points; replaces the single point a regular Success would otherwise contribute.

**Critical Count**: Total number of dice in a Roll whose result equals Die Size.

## Target Numbers

**Target Number**: Threshold compared against each die. Any die ≥ TN counts as a Success. Derived from Base TN and any TN Modifiers; clamped between Minimum and Maximum TN. Abbreviated **TN**.

**Base Target Number**: Default TN before any TN Modifiers. *(configurable)*

**Minimum Target Number**: Lowest TN after modifiers. *(configurable)*

**Maximum Target Number**: Highest TN after modifiers. *(configurable)*

## Resolution

**Degree of Individual Success**: Net result of a single Roll. Sum of every die's contribution plus the Roll's Starting Value. Abbreviated **DoIS**.

**Default Success Threshold**: Minimum value of DoIS required for a Roll to register as a Success outcome. *(configurable)*

**Default Fumble Threshold**: Maximum value of DoIS for a Roll to register as a fumble outcome. *(configurable)*

**Outcome**: One of `success`, `failure`, or `fumble`. Derived from DoIS using the configured thresholds.

## Modifiers

**Bonus**: A signed positive integer that decreases the Target Number of a Roll.

**Penalty**: A signed negative integer that increases the Target Number of a Roll.

**Net Modifier**: The signed sum of all Bonuses and Penalties on a Roll, after per-Type stacking. The Net Modifier decreases the Target Number when positive and increases it when negative. If applying the Net Modifier would push the Target Number past the Minimum or Maximum, the overflow becomes a Starting Value contribution to DoIS.

**Type Name**: An opaque string label attached to each Bonus or Penalty entry. Dice resolution does not validate or enumerate Type Names; the canonical list is owned by the Modifiers domain.

**Starting Value**: A signed integer added to the Degree of Individual Success before per-die contributions.

## Roll Modifiers

**Dice Operations**: Actions that alter the results of a Roll either positively or negatively. Includes rerolls and value adjustments.

**Reroll Operation**: A pair of slots — positive and negative — that re-roll subsets of dice. Positive rerolls non-Successes from the lowest first; negative rerolls Successes from the highest first. A `max` flag on either slot expands the slot's count to Maximum Dice Count.

**Value Adjustment** (also called **Nudge**): Adds a signed integer to one or more dice's values. In standard mode targets one die; in `max` mode shifts every die. Each adjusted value is clamped to `[1, Die Size]`.

## Encoding

**Dice Result String**: An ASCII encoding of a Roll's final dice, sorted descending. Designed so a list of these strings sorts correctly with any standard library sort — lex compare on the strings reproduces the die-by-die comparison of the underlying Rolls.

**Dice Result String Encoding**: A configuration string giving labels for die values 10 and above. Values 1–9 always use digit characters. *(configurable)*
