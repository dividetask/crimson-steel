# Encounter Banner Stub

Dismissible block surfacing the most recent encounter roll. Renders a structured payload as a heading + per-entry bullets.

## Layout

1. **Heading** — Encounter table name plus a Dismiss button.
2. **Per-creature block** — One block per spawned creature:
   - Creature name as a sub-heading.
   - One bullet for gold rolled.
   - One bullet per loot item rolled.

## Parameters

Required:
- Encounter message payload (table name + list of `{creature, gold, items}` entries).
- Viewer role — `dm` or `player`.

## Visibility

Hidden from players on `/character`. Visible to DM viewers everywhere.

## Data sources

- Encounter message from combat state (`combat.encounter_message`).
