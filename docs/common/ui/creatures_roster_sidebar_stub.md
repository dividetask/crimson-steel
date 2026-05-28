# Creatures Roster Sidebar Stub

A DM-only sidebar listing the campaign roster — Players, NPCs, and one section per themed Creature Template file under `docs/common/creatures/`. Each themed section mixes that file's creature templates with the random encounter tables filed under the same `category` key (`random_encounter_tables.yaml`'s `category:` field), so the DM sees both together. Embedded by the Character Sheets page on the left of the main panel; each row's name is a link to the matching sheet, which replaces the navigation arrows the page used to carry.

See `ui_conventions.md` for shared rules.

## Layout

A vertical sidebar, top to bottom:

1. **Players** — `<details>`-style collapsible group titled `Players`. One row per Creature whose `tags` include `player_character`. Player rows render a **single Active / Absent toggle** in place of the `+ / −` buttons — a Player can't appear in Combat more than once, so the binary state (in the party, or sitting out) is what the DM tracks. Default is **Active**.

2. **NPCs** — `<details>`-style group titled `NPCs`. One row per Creature whose `group` is `npc`. NPC rows render the same Active / Absent toggle as Player rows, but default to **Inactive** — an NPC is in the world but not in the active scene until the DM flips them.

3. **Themed categories** — one `<details>`-style group per entry in the project's themed Creature Template files (`docs/common/creatures/creatures_data_<theme>.example.yaml`). The display order is the order the categories appear in the page configuration. Each section's body mixes:
   - **Creature template rows** — every template whose `tags` include `category:<theme_key>` (and `enemy_template`).
   - **Encounter table rows** — every entry in `random_encounter_tables.yaml` whose `category:` field equals the same `<theme_key>`.

   The two row kinds are intermixed; the project's display ordering puts templates first, then random encounter tables. Random Encounter Tables therefore **do not have a dedicated group** — they live with the templates from their theme.

All groups start **collapsed**. The open/closed state of each group persists in `localStorage` keyed by the group's `data-group-key` (e.g. `cs-roster-group:players`, `cs-roster-group:general_red_tier`). A page refresh restores whatever the DM had open last.

## Per-row controls

### Players + NPCs

- **Creature name link** — clicking navigates to `/character-sheets?i=<sheet_index>` for that Creature.
- **Active / Absent toggle** (right side of the row) — single button that flips between `Active` and `Absent`. Visually distinct in the two states (e.g., outlined when Active, muted with strikethrough on the row text when Absent). Players default to Active; NPCs default to Absent. The button is rendered but the state is purely client-side in this stub; persistence wiring lands later. The toggle is sized identically to the Encounter row's `Roll` button so the two line up vertically across the sidebar.

### Creature Template rows (within themed categories)

Each template row has, in left-to-right order:

- **`−` button** — emits a `remove_combatant` event for the most recently added Combatant with this Creature ID. Inert in this stub.
- **Creature name link** — clicking navigates to `/character-sheets?i=<sheet_index>` for the template.
- **Copy count badge** — when at least one Combatant in the active Combat references this Creature ID. Suppressed when zero. Renders to the left of the `+` button.
- **`+` button** — emits an `add_combatant` event carrying the Creature ID. For a Creature Template the parent first calls Creatures' *Spawn Creature From Template* to produce a fresh Creature record, then *Add Combatant* on the new ID. Followed by Combat's *Reroll Initiative* with `missing_only = true`. **Rendered but inert** until the Combat UI lands.

### Random Encounter Table rows (within themed categories)

Each encounter row has:

- **Table name link** — clicking navigates to `/character-sheets?random_encounter_template=<table_id>`, which renders the Encounter Template Stub (`creatures_random_encounter_template_stub.md`) in the main panel.
- **`Roll` button** — emits a `roll_random_encounter` event. The parent resolves it by fetching a fresh roll and rendering an Encounter Roll Result panel (`creatures_random_encounter_roll_result_stub.md`) above the main panel. The roll-result panel commits the result to Combat on render; further clicks on its own internal `Roll` button replace the result (each click = a re-roll that supersedes the previous). Same size as the Active / Absent toggle on Player rows so the controls all line up at the right edge.

## DM-only

The entire sidebar is DM-only. Player viewers do not see the sidebar at all; the character-sheets page renders the main panel without one.

## Parameters

Required:
- A `roster` structure:
  - `players` — list of `{ id, name, sheet_index, active }` (`active` defaults to true).
  - `npcs` — list of `{ id, name, sheet_index, active }` (`active` defaults to false).
  - `categories` — list of `{ key, name, templates, random_encounter_tables }`. Each `templates` entry is `{ id, name, sheet_index, copy_count }`; each `random_encounter_tables` entry is `{ table_id, name }`.
- The viewer role — must be `dm`. The stub renders nothing for player viewers.

Optional:
- Current `sheet_index` — when the sidebar is rendered next to a specific Creature's sheet, the matching row is highlighted.

## Composition

Embedded by the Character Sheets page (`/character-sheets`) to the left of the main sheet panel. The host page renders the sidebar plus the chosen creature's `creatures_minimal_stub` or `creatures_full_stub`. The sidebar's name links point at `/character-sheets?i=<sheet_index>&detail=<minimal|full>`; the parent preserves the current `detail` mode across navigations.

## LocalStorage persistence

The sidebar stores one boolean per group under a key of the form `cs-roster-group:<data-group-key>`. The handler is `toggle` on each `<details>` element: when an open event fires, the value `"open"` is stored; when a close event fires, the key is removed. On page load the sidebar's bootstrap script reads each known group key and sets the matching `<details>` `open` attribute accordingly. Missing keys leave the default (collapsed) intact.

## What this stub does not do

- The `+` and `−` buttons do not yet mutate Combat State.
- The Active / Absent toggle does not persist beyond the current page load — every refresh resets the toggle to its default for that row kind.
- Random Encounter Table rows render with a `Roll` button and a name link; both render correctly but the roll result panel's "add to Combat" / "append to enemy data file" side effects are not yet wired.
- The sidebar does not delete Creature records. The post-combat cleanup flow in `equipment_post_combat_creatures_stub.md` is the conventional caller for that.
- The sidebar does not edit Creature records.
