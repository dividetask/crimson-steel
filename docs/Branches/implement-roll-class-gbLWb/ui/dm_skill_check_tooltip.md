# DM Skill Check Tooltip

Hover popup on a `dm_skill_check_stub` cell. Shows the TN math and dice breakdown for that character/skill cell.

## Layout

Two short blocks stacked vertically:

1. **TN line** — `TN <n>` with the base TN, any situational modifier, and any flatfooted penalty as a parenthetical (e.g. `TN 7 (base 7, flat-footed −1)`).
2. **Dice line** — Number of dice and side count (e.g. `5d10`). Per-die `+/-` annotations are **not** shown — those were dropped in favour of just the count and TN math.

## Parameters

Required:
- Character id.
- Skill id.
- Active TN.

## Data sources

- TN base + bounds from `rules.json` (`dice.base_target_number`, `dice.tn_minimum`, `dice.tn_maximum`).
- Dice count from skill aptitude + proficiency formulas (see `dice_resolution_design.md`).
