# Templates and Enemies

Adds commoner and aberration class templates, gives the wardog a declared natural bite weapon, hardens the GearTable resolver, and persists the enemies-sidebar collapsed state.

## Glossary

- **Class Template** — A pre-built character archetype (commoner, aberration, wardog, etc.) used to spawn enemies or NPCs.
- **Natural Weapon** — A weapon entry declared as part of a creature's body (bite, claws, slam) rather than wielded.
- **GearTable** — The resolver that turns a creature's gear reference into actual item entries.
- **Enemies Sidebar** — The collapsible list on the DM's `/enemies` page; each category collapses independently and remembers state across reloads.

## Design

### Templates

- **Commoner** — Generic NPC class with str/con saves emphasised. Drops monster-only placeholder fields.
- **Aberration** — Creature class with wis/cha saves. Drops monster-placeholder fields.
- **Wardog** — Animal template with a declared natural bite weapon (so it has a weapon to attack with by default).

Both class templates were added; placeholder monster fields they had inherited were removed.

### GearTable hardening

`GearTable.resolve` previously assumed every reference resolved to a Hash. Some references (e.g. malformed escaped_slave gear) returned scalars, which crashed the resolver. The fix: skip non-Hash refs and emit a warning. Escaped_slave gear was also fixed in data.

### Enemies sidebar

- Each category collapses by default (cleaner first paint).
- Collapse state is persisted in `localStorage` keyed by category name, so reloads keep the user's choice.

### Bleed on ranged

Combat's bleed application previously only applied for melee attacks. The branch broadens it so ranged attacks also apply `weapon_bleed` — see [combat-tracker.md](combat-tracker.md).

## Cross-domain interactions

- Class templates live in `../common/data/classes.yaml.example`.
- Natural weapons are defined in `rules.json` `reference.natural_weapons`.
- Enemies sidebar UI is in `views/enemies.erb`.
