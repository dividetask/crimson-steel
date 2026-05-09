# DM Skill Check Stub

DM-only `/dm_social` page showing a matrix of characters × selected skills. Each cell shows the dice count and proficiency bonus and surfaces a tooltip on hover.

## Layout

1. **Skill picker** — Multi-select of skills to show as columns.
2. **Character rows** — One row per visible character.
3. **Cells** — Each cell shows `<dice_count>d / +<prof_bonus>`. Hover surfaces `dm_skill_check_tooltip`.

## Parameters

Required:
- List of character ids to display as rows.
- List of skill ids to display as columns.
- Current TN (defaults from `rules.json` `dice.base_target_number`).

## Visibility

DM only.

## Data sources

- Skill aptitude / proficiency / dice count via the same accessors used by the character sheet.
- TN configuration from `rules.json`.
