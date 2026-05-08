# Encounter Banner

Shared message surface that the DM uses to broadcast the most recent encounter roll. Renders as a structured payload with a bullet list — one bullet per loot item per creature.

## Glossary

- **Banner** — A dismissible block that appears on DM pages above the main content.
- **Structured Payload** — JSON the banner renders into a heading + bullet list rather than a free-text string.
- **Player Visibility** — Whether the banner is shown on the player-facing `/character` page.

## Design

The banner reads from a single field on combat state. Setting it (e.g. via random-encounter roll) replaces the previous content. Clearing happens via `POST /combat/encounter_message/clear`.

Final visibility rule: the banner is **hidden from players on `/character`**. It is visible on DM pages and on `/scene/<viewer_id>` only for DM viewers. Earlier iterations showed it everywhere; the final state restricts it to the DM.

Each loot entry is its own bullet — including gold, which is one bullet per creature, and items, which are one bullet per item. This was iterated from a single comma-joined string (early), to one bullet per creature with comma-joined loot, to the final per-item granularity.

## Data shape

```
combat.encounter_message = {
  table: <str>,
  entries: [
    {creature: <str>, gold: <int>, items: [<str>, ...]},
    ...
  ]
}
```
