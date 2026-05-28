# Combat DM Social Matrix Stub

A DM-only matrix that lets the Game Master roll opposed and unopposed social Checks for the entire party against a single Game-Master-controlled Creature in one batched action.

See `ui_conventions.md` for shared rules.

## Layout

Three regions:

1. **Player-Character sidebar** — radio buttons, one per player-character Creature (every Creature whose `tags` include `player_character` per `creatures_design.md`). The selected Creature is the **Lead PC** — used as the comparison reference in the matrix's row headers. Selection persists in `localStorage`.
2. **Game-Master Creature sidebar** — radio buttons grouped by Creature `group` field (`npc`, `enemy`, etc., per Creatures). The selected Creature is the **Opponent**. Selection persists in `localStorage`.
3. **Skill matrix** — a table with one row per social Skill and one column per PC plus the Opponent plus the row's bonus/penalty inputs.

Above the matrix: `Lead PC: <name>` and `Opponent: <name>` labels, plus a `Roll All` button that rolls every cell in one click (mirroring the convention in `check_resolution_stub.md`).

## Parameters

Required:
- Player-character Creature list — Creatures whose `tags` include `player_character`, surfaced via Creatures' *List Creatures*.
- Game-Master Creature list — every other Creature, grouped by `group`.
- Viewer role — must be `dm`. The stub renders nothing for player viewers.

Optional:
- Pre-computed per-Creature dice counts and modifiers for each social Skill — typically built by the parent page by calling Proficiencies' *Compute Roll inputs for a Proficiency* for each (Creature, Skill) pair. When omitted, the stub renders an empty matrix and emits a `compute_request` event so the parent page can fill it.

## Skill matrix

Rows — the social Skills, in this order:

- Perception (unopposed).
- Sense Motive (unopposed).
- Deception (opposed vs. Sense Motive).
- Persuasion (opposed vs. *Persuasion Counter* — see below).
- Wisdom Saving Throw (unopposed).
- Intelligence Saving Throw (unopposed).

The Skill keys match the proficiency keys in `proficiencies/skills.yaml`; Saves use the `<attr>_save` proficiency keys per `combat_design.md`'s *Saving Throws* construction.

Columns:

- One per PC. The Lead PC is highlighted.
- The Opponent.
- A **row bonus** integer input. The value is added to every cell's modifier list as a `Circumstance` Bonus (per `ui_conventions.md`'s modifier presentation).
- A **row penalty** integer input. Same handling, signed negative.

Each cell shows the Roll's dice count and the resolved modifier (using `ui_conventions.md`'s modifier presentation). After a roll, the cell switches to a net-successes display — green for positive, red for negative. Opposed cells show `(self_net − opponent_net)` once both sides have rolled.

Persuasion's **Persuasion Counter** is the higher-DoIS Skill between Persuasion and Sense Motive on each PC, chosen per cell. The opposing Skill name renders inside the cell header so the GM sees which Skill the matrix picked. Selection is done by the parent page when it computes per-Creature inputs.

## Behavior

- Selecting a PC or Opponent saves the choice to `localStorage` keyed per the conventions in `ui_conventions.md`. Row bonus / penalty inputs also persist.
- `Roll All` walks every cell, building each Roll through Combat's Saving Throw construction (Saves) or Proficiencies' *Compute Roll inputs for a Proficiency* (Skills), then resolving via Dice Resolution. The cell's display switches to the net-successes view.
- Hovering any cell surfaces a tooltip; see `combat_dm_social_cell_tooltip.md`.
- Each cell carries a manual override input (per the *Manual override fields* convention in `ui_conventions.md`) so the DM can type the final net successes regardless of the rolled dice. The override is authoritative for any downstream resolution.

## DM-only

The entire stub is DM-only. The parent page does not invoke this stub for player viewers.

## Composition

Self-contained scene-level stub. Not embedded inside other stubs. The tooltip child (`combat_dm_social_cell_tooltip.md`) appears on hover.

## What this stub does not do

- It does not compute per-Creature dice counts or modifiers. Those come from Proficiencies (Skills) and Combat's Saving Throw construction (Saves) via the parent page.
- It does not resolve Checks into Outcomes. The net-successes display is the cell-level result; aggregating an opposed Check's net into a Degree of Success is the parent page's responsibility (typically by feeding the values to Check Resolution).
- It does not persist Roll history. The stub renders the current matrix only; per-roll dice survive only within the live page session.
