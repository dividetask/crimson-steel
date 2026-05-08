# DM Skill Check Screen

DM-only `/dm_social` page for adjudicating social and skill checks. Displays a per-character row with the relevant skill total, and on hover shows a tooltip that breaks down the TN math and the dice that would be rolled.

## Glossary

- **TN (Target Number)** — The dice face value at or above which a die counts as a success. Defaults from `rules.json`, modified by situational adjustments.
- **Dice Breakdown** — The list of dice the character would roll, derived from skill aptitude, attribute, and proficiency.
- **Tooltip** — The hover popup that shows the TN math and dice breakdown for one character/skill cell.

## Design

The page renders a matrix of characters × selected skills. Each cell shows the static dice count and proficiency bonus, and on hover surfaces a tooltip with:

- The TN being used and how it was derived (base TN, situational modifiers, flatfooted penalty).
- The dice that would be rolled (count, side count, any bonus dice).

The tooltip iteration: an early version annotated each individual die with `+/-` modifiers; the final version drops per-die annotations and shows only the TN math + the resulting dice count.

The screen is read-only — clicking a cell does not commit a roll. The DM uses this to set TNs and decide who rolls before a roll is actually taken on the social page or in combat.

## Cross-domain interactions

- Reads skill aptitude/proficiency via the same path as character sheets.
- Reads TN configuration from `rules.json` (`dice.base_target_number`, `dice.tn_minimum`, `dice.tn_maximum`).
- See `ui/dm_skill_check_stub.md` and `ui/dm_skill_check_tooltip.md` for layout.
