# Combat DM Social Cell Tooltip

A read-only popup that shows one cell's full Roll inputs and dice values for `encounter_dm_social_stub.md`. Surfaces on hover.

See `ui_conventions.md` for shared rules.

## Content

A small panel with the following rows, top to bottom. Rows with no data are omitted.

1. **Title** — `<Creature Name> · <Skill Name>` (e.g. `Stumpy · Perception`).
2. **Modifier breakdown** — one line per modifier in the constructed Roll's `bonus_penalty_list`, each line using the modifier presentation from `ui_conventions.md` (`+<n> <label>` / `-<n> <label>`). The Competency Modifier returned by Proficiencies appears as its own line; row-level bonus and penalty inputs from the matrix appear as additional lines.
3. **TN line** — the Target Number the Roll resolves against, followed by the Base Target Number and any per-modifier adjustments that contributed. The final TN matches what Dice Resolution received.
4. **Dice line** — the rolled dice values, with per-die highlighting per `ui_conventions.md`'s Dice Highlighting table.
5. **Net successes line** — `Net: +<successes>` or `-<failures>` (the Degree of Success from Dice Resolution). Color-matched to the cell's display.
6. **Opposing line** — for opposed cells only: `vs. <Opponent Name> <opposing Skill>: <opponent_net>` and `Difference: <self_net - opponent_net>`. The opposing Skill is the one selected by the parent's Persuasion-Counter logic when applicable.

When the cell has not been rolled yet, the tooltip shows only the title, modifier breakdown, and TN line.

## Parameters

Required:
- A cell record carrying Creature Name, Skill Name, the constructed Roll (dice count, modifiers, TN), and — when rolled — the dice values and resulting Degree of Success.
- For opposed cells: the opponent's matching cell record.

## Data sources

The tooltip composes pre-computed values from:

- **Proficiencies** — `compute_roll_inputs_for_a_proficiency` supplies the dice count, Competency Modifier, and the per-Skill attribute. The parent matrix calls this and passes the result in.
- **Combat** — the Saving Throw construction (per `encounter_design.md`) for Wisdom Save and Intelligence Save rows.
- **Dice Resolution** — the rolled dice values and Degree of Success. Computed when the user presses Roll on the matrix; never persisted.
- **Row bonus / penalty inputs** — read from the parent matrix's controls.

The tooltip does no computation itself; the parent matrix gathers the inputs and passes them in.

## Composition

Self-contained. Not designed to embed inside another tooltip. The parent matrix triggers one tooltip per hovered cell.
