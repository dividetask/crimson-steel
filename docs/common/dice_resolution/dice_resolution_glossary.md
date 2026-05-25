# Dice and Resolution Mechanics — Glossary

Defines the vocabulary used by `dice_resolution_design.md` and `dice_resolution_tests.md`. Multi-Roll terms live in the check resolution glossary. *(configurable)* values come from `dice_resolution_config.yaml`.

## Rolls

**Die Size**: The number of sides on each die. All dice in the system use the same Die Size. *(configurable)*

**Roll**: A single resolution of dice against a Target Number, with optional Bonuses, Penalties, rerolls, and adjustments. The structure is fully defined in `dice_resolution_design.md`.

**Initial Roll**: Results of a Roll before any Dice Operations. Each die may be rerolled at most once.

**Final Roll**: Results after rerolls and value adjustments.

## Dice Counts

**Dice Count**: The number of dice rolled on a Roll.

**Minimum Dice Count**: The lowest permitted Dice Count. *(configurable)*

**Dice Count Range**: The span between Minimum Dice Count and Maximum Dice Count, used to derive the Maximum. *(configurable)*

**Maximum Dice Count**: The highest permitted Dice Count. *(indirectly configurable)*

## Die Results

**Success**: A die result that meets or exceeds the Target Number. Each Success contributes one point to Degree of Individual Success, or more if it is a Critical Success.

**Failure**: The lowest possible die result. Contributes a configurable amount to Degree of Individual Success (typically negative). Rolls that ignore Failures set this contribution to zero.

**Neutral Result**: A die result between Failure and the Target Number. Contributes nothing to Degree of Individual Success.

**Critical Success**: A die result equal to the Die Size. Contributes a configurable amount; replaces the regular Success contribution rather than stacking with it.

**Critical Count**: The number of dice in a Roll that came up as a Critical Success.

## Target Numbers

**Target Number**: Threshold compared against each die. Any die ≥ TN counts as a Success. Derived from Base TN and any TN Modifiers; clamped between Minimum and Maximum TN. Abbreviated **TN**.

**Base Target Number**: Default TN before any TN Modifiers. *(configurable)*

**Minimum Target Number**: Lowest TN after modifiers. *(configurable)*

**Maximum Target Number**: Highest TN after modifiers. *(configurable)*

## Resolution

**Degree of Individual Success**: Net result of a single Roll. Sum of every die's contribution plus the Roll's Starting Value. Abbreviated **DoIS**.

**Default Success Threshold**: Minimum value of DoIS required for a Roll to register as a Success outcome. *(configurable)*

**Default Fumble Threshold**: Maximum value of DoIS for a Roll to register as a fumble outcome. *(configurable)*

**Outcome**: A Roll's resolved result — Success, Failure, or Fumble. Derived from DoIS using the configured thresholds.

## Modifiers

**Bonus**: A positive modifier that decreases the Target Number of a Roll.

**Penalty**: A negative modifier that increases the Target Number of a Roll.

**Net Modifier**: The combined effect of all Bonuses and Penalties on a Roll, after per-Type stacking. The Net Modifier decreases the Target Number when net-positive and increases it when net-negative. When applying the Net Modifier would push the Target Number past the Minimum or Maximum, the overflow becomes a Starting Value contribution to DoIS.

**Type Name**: The label attached to each Bonus or Penalty identifying its stacking category. Dice resolution does not validate or enumerate Type Names; the canonical list is owned by the Abilities domain (Bonus Types List).

**Starting Value**: An amount added to the Degree of Individual Success before per-die contributions.

## Roll Modifiers

**Dice Operations**: Actions that alter the results of a Roll either positively or negatively. Includes rerolls and value adjustments.

**Reroll Operation**: A pair of slots — positive and negative — that re-roll subsets of dice. The positive slot rerolls non-Successes from the lowest first; the negative slot rerolls Successes from the highest first. A maximum-mode flag on either slot expands the slot's count to Maximum Dice Count.

**Value Adjustment** (also called **Nudge**): An adjustment that shifts one or more dice values. In standard mode it targets one die; in maximum mode it shifts every die. Adjusted values are clamped to the legal die range.

**Preroll**: A Roll modifier that adds dice with caller-chosen extreme values to the Roll's scoring without actually rolling them. Positive Preroll adds Critical Successes (each scored at the Roll's critical contribution); negative Preroll adds Failures (each scored at the Roll's failure contribution). Prerolled dice are not eligible for rerolls or nudges — the caller has already chosen them. Used by callers (e.g. Combat's Set-Value Spend) that let an actor pay a cost to lock in extreme dice rather than risk a random Roll.

## Encoding

**Dice Result String**: A sortable text encoding of a Roll's final dice, ordered from highest to lowest. Designed so a list of these strings, sorted alphabetically, reproduces the die-by-die comparison of the underlying Rolls.

**Dice Result String Encoding**: The set of labels used to encode die values in a Dice Result String. *(configurable)*
