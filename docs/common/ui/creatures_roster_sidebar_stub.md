# Creatures Roster Sidebar Stub

A DM-only sidebar listing every Creature record in the dataset plus every Encounter Table, grouped, with per-row affordances for adding the Creature to the active Combat or removing it. Embedded by the Character Sheets page on the left of the main panel; the row name is a link to that Creature's character sheet, which replaces the navigation arrows the page used to carry.

This stub is similar in shape to `creatures_enemy_sidebar_stub.md` but has a wider scope: it also lists Players, NPCs, and Encounter Tables, and its primary role is navigation between character sheets rather than combat operations.

See `ui_conventions.md` for shared rules.

## Layout

A vertical sidebar, top to bottom:

1. **Players** — `<details>`-style collapsible group titled `Players`. One row per Creature whose `tags` include `player_character`. Starting state is **collapsed**; open/closed state persists in `localStorage` keyed by group label (per `ui_conventions.md`).

2. **NPCs** — `<details>`-style group titled `NPCs`. One row per Creature whose `group` is `npc` and whose `tags` do not include `enemy_template`. Starting state is **collapsed**.

3. **Enemies** — `<details>`-style group titled `Enemies`. One row per Creature whose `group` is `enemy` and whose `tags` do not include `enemy_template` (i.e. spawned enemies, not templates). Starting state is **open**.

4. **Creature Templates** — `<details>`-style group titled `Creature Templates`. One row per Creature whose `tags` include `enemy_template`. Starting state is **open**. The `+` button on a template row first spawns a fresh Creature from the template (via Creatures' *Spawn Creature From Template*) and then adds the result to Combat.

5. **Encounter Tables** — `<details>`-style group titled `Encounter Tables`. One row per entry in `encounter_tables.yaml`. Each row shows the table's display name and a single `Roll` button. Clicking the name navigates to the encounter table's detail view (not yet implemented — placeholder destination); clicking `Roll` emits a `roll_encounter` event the parent resolves by calling Creatures' *Roll Encounter*, then *Add Combatant* for each returned id. Starting state is **open**.

## Per-row controls (sections 1-4)

Each Creature row has, in order:

- **`+` button** — emits an `add_combatant` event carrying the Creature ID. For a Creature Template the parent first calls Creatures' *Spawn Creature From Template* to produce a fresh Creature record, then *Add Combatant* on the new ID. For a non-template Creature (Player, NPC, or already-spawned Enemy) the parent calls *Add Combatant* directly. Either path is followed by Combat's *Reroll Initiative* with `missing_only = true`. **The button is rendered but does not yet mutate state in this stub — Combat UI wiring is future work.**
- **Creature name link** — clicking navigates to `/character-sheets?i=<index>` for that Creature. The link is the row's primary affordance.
- **`−` button** — emits a `remove_combatant` event for the most recently added Combatant with this Creature ID. Hidden when the copy count is zero. Same "rendered but inert" note applies.
- **Copy count badge** — when the Creature has at least one Combatant in the active Combat referencing it, a small numeric badge renders beside the row. Suppressed when zero. Sourced from Combat State's `combatants` list (filtered by `creature_id`).

## DM-only

The entire sidebar is DM-only. Player viewers do not see the sidebar at all; the character-sheets page renders the main panel without one.

## Parameters

Required:

- A `roster` structure with keyed groups: `players`, `npcs`, `enemies`, `templates`, `encounter_tables`. Each value is a list of rows. Creature rows carry `{ id, name, copy_count, sheet_index }`; encounter rows carry `{ table_id, name }`. The parent supplies this — Creatures' *List Creatures* with the appropriate filters produces the four creature lists; Encounter Tables come from `Creatures::Encounter.tables`.
- The viewer role — must be `dm`. The stub renders nothing for player viewers.

Optional:

- Current `sheet_index` — when the sidebar is rendered next to a specific Creature's sheet, the matching row is highlighted.

## Composition

Embedded by the Character Sheets page (`/character-sheets`) to the left of the main sheet panel. The host page renders the sidebar plus the chosen creature's `creatures_minimal_stub` or `creatures_full_stub`. The sidebar's name links point at `/character-sheets?i=<index>&detail=<minimal|full>`; the parent preserves the current `detail` mode across navigations.

## What this stub does not do

- The `+` and `−` buttons do not yet mutate Combat State. They render as visible affordances but are inert. The full wiring will land alongside the Combat domain UI; per `creatures_enemy_sidebar_stub.md` the parent resolves these events by calling Combat's *Add Combatant* / *Remove Combatant* and Combat's *Reroll Initiative*.
- Encounter Table rows render with a `Roll` button and a name link, but neither is functional yet. The Encounter Table detail view is a separate page that has not been designed.
- The sidebar does not delete Creature records. The post-combat cleanup flow in `equipment_post_combat_creatures_stub.md` is the conventional caller for that.
- The sidebar does not edit Creature records. Editing is the responsibility of dedicated Creatures-domain UIs.
