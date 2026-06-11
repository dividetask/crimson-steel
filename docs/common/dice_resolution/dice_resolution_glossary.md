# Dice and Resolution Mechanics — Glossary

Defines the vocabulary used by `dice_resolution_design.md` and `dice_resolution_tests.md`. Multi-Roll terms live in the check resolution glossary. *(configurable)* values come from `dice_resolution_config.yaml`.

## Rolls

**Die Size**: The number of sides on each die. All dice in the system use the same Die Size.

**Initial Roll**: Results of a Roll before any rerolls or value adjustments. Each die may be rerolled at most once.

**Final Roll**: Results after rerolls and value adjustments.

**Base Target Number**: Default TN before any TN Modifiers.

**Dice Count**: The number of dice rolled on a Roll.

**Dice Count Range**: The span between Minimum Dice Count and Maximum Dice Count, used to derive the Maximum.

**Critical Count**: The number of dice in a Roll that came up as a Critical Success.

## Resolution

**Default Success Threshold**: Minimum value of DoIS required for a Roll to register as a Success outcome.

**Default Fumble Threshold**: Maximum value of DoIS for a Roll to register as a fumble outcome.

**Roll Outcome**: A Roll's resolved result — Success, Failure, or Fumble. Derived from DoIS using the configured thresholds.

## Roll Modifiers

**Dice Operations**: Actions that alter the results of a Roll either positively or negatively. Includes rerolls and value adjustments.

**Reroll Operation**: A pair of slots — positive and negative — that re-roll subsets of dice. The positive slot rerolls non-Successes from the lowest first; the negative slot rerolls Successes from the highest first. A maximum-mode flag on either slot expands the slot's count to Maximum Dice Count.

**Value Adjustment** (also called **Nudge**): An adjustment that shifts one or more dice values. In standard mode it targets one die; in maximum mode it shifts every die. Adjusted values are clamped to the legal die range.

**Ascendancy**: The Tier-mismatch amplification derived during TN computation from a Roll's Inherent imbalance — `floor(2 × gap)` between its strongest Inherent Bonus and strongest Inherent Penalty, a Bonus when the former leads and a Penalty when the latter does. Gated on a present Inherent Penalty (value ≤ 0, a 0 counts); a zero side reads as 0.5 (Tier 0). See `dice_resolution_design.md` → *Ascendancy*.

## Encoding

**Dice Result String**: A sortable text encoding of a Roll's final dice, ordered from highest to lowest. Designed so a list of these strings, sorted alphabetically, reproduces the die-by-die comparison of the underlying Rolls.

**Dice Result String Encoding**: The set of labels used to encode die values in a Dice Result String. *(configurable)*
