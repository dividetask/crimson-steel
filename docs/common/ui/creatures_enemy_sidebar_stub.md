# Creatures Enemy Sidebar Stub

A DM-only collapsible sidebar listing every non-PC Creature record in the dataset, grouped, with per-row affordances for adding the Creature to the active Combat or removing it.

See `ui_conventions.md` for shared rules.

## Layout

A vertical sidebar. The top has a `Clear all enemies` button that emits a `clear_enemies` event the parent page resolves by calling Combat's *Remove Combatant* for every non-PC Combatant in the active Combat.

Below the button, two stacked sections:

### Random Encounter Tables

A collapsible group titled `Random Encounter Tables`, listing every entry from `random_encounter_tables.yaml`. One row per Random Encounter Table. Each row shows the table's display name and a single `Roll` button. Clicking `Roll` emits a `roll_random_encounter` event carrying the table ID; the parent resolves it through Creatures' *Roll Random Encounter*, then iterates the returned new Creature IDs and calls Combat's *Add Combatant* for each, followed by Combat's *Reroll Initiative* with `missing_only = true`. The newly-spawned Creatures appear in the Creatures section below on the next render (under whichever `group` their template carried).

### Creatures

One collapsible group per Creature `group` value (e.g. `enemy`, `npc`) plus any other grouping the parent page declares. Each group is a `<details>`-style element; its open / closed state persists in `localStorage` keyed by group label (per `ui_conventions.md`).

Inside a group:

1. **Creature rows** — one per Creature record in the group. Each row shows:
   - The Creature name (clickable; opens the Creature in detail via `creatures_minimal_stub`). Spawned instances render their `name` (which mirrors the template's `name` by default) — when the parent groups spawns under their template, the row indents under the template.
   - **Copy count** — the number of Combatants in the active Combat whose `creature_id` matches this Creature record. A small badge beside the row; suppressed when zero.
   - `+` button — emits an `add_combatant` event carrying the Creature ID. For an enemy template (tag `enemy_template`) the parent first calls Creatures' *Spawn Creature From Template* to produce a fresh Creature record, then *Add Combatant* on the new ID. For a non-template Creature (a PC, NPC, or already-spawned enemy) the parent calls *Add Combatant* directly. Either path is followed by *Reroll Initiative* with `missing_only = true`.
   - `−` button — emits a `remove_combatant` event for the most recently added Combatant with this Creature ID. The parent page resolves through Combat's *Remove Combatant*. Hidden when the copy count is zero. *Remove Combatant* alone does **not** delete the Creature record — that happens through the post-combat cleanup flow in `equipment_post_combat_creatures_stub.md`.

## Parameters

Required:
- The Creature roster — Creatures' *List Creatures* result, filtered to exclude any Creature whose `tags` include `player_character`. The parent page may pre-group the roster.
- The active Combat's Combatant list — to compute per-Creature copy counts. Sourced from the Combat State.
- Viewer role — must be `dm`. The stub renders nothing for player viewers.

## Copy count

For each Creature record, the count is the number of entries in the Combat State's `combatants` list whose `creature_id` matches the Creature's ID. The number renders as a small badge beside the row.

## DM-only

The entire sidebar is DM-only. Player viewers do not see the sidebar.

## Composition

Embedded by pages that surface non-PC Creatures alongside the active Combat — typically the Combat page's enemy detail surface and any dedicated bestiary page. The host page renders the sidebar alongside the main panel (which shows one Creature at a time via `creatures_minimal_stub`).

When the host page is showing a specific Creature, the sidebar highlights that Creature's row.

## What this stub does not do

- It does not roll Initiative directly. The parent page calls *Reroll Initiative* with `missing_only = true` after each *Add Combatant* (the standard pattern from `encounter_design.md`).
- It does not delete Creature records. The post-combat cleanup flow in `equipment_post_combat_creatures_stub.md` handles that — typically with both `Loot` and `Delete` toggled on for spawned enemies.
- It does not edit Creature records. Editing is the responsibility of dedicated Creatures-domain UIs.
