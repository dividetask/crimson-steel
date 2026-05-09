# Random Encounters

DM-triggered roll that pulls a wandering encounter from the active table, drops the resulting creatures into the combat tracker, and posts a banner summarising what was rolled.

## Glossary

- **Encounter Table** — A weighted list of encounter entries grouped by source category. An entry names a creature, a quantity expression, and a loot table reference.
- **Encounter Roll** — The roll that selects one encounter table entry and resolves its quantity dice.
- **Encounter Banner** — A persistent message surface that displays the result of the most recent roll. See [encounter-banner.md](encounter-banner.md).
- **Loot Per Creature** — Each creature in the encounter rolls its own loot independently (gold and items), and each item appears as its own bullet in the banner.

## Design

Endpoint: `POST /combat/roll_encounter`. The DM invokes it without a confirm prompt — the prior confirm dialog was removed to keep the loop fast. The roll picks an entry from the active table, resolves quantity, then for each spawned creature rolls a fresh loot result.

Encounter entries are nested under their source category in the table editor (rather than rendered flat) so the DM can see which region a result came from at a glance.

Result payload structure (passed to the banner renderer):

```
{
  table: <name>,
  entries: [
    {
      creature: <template_id>,
      gold: <int>,
      items: [<item_name>, ...]
    },
    ...
  ]
}
```

Each spawned creature is added to the combat tracker as if the DM had used `add_enemy` for it. The banner is set via `POST /combat/encounter_message/clear` to dismiss.

## Cross-domain interactions

- Reads loot tables from `../../common/data/loot_tables.yaml.example`.
- Writes to combat state via the same code path as manual `add_enemy`.
- Banner display is shared with non-roll DM messages — see [encounter-banner.md](encounter-banner.md).
