# Races

Race drives starting attribute adjustments, base speed, and tier-progression abilities. Race entries live on each character as a list (`race: [variant, family]` so e.g. `["hill", "dwarf"]`) and resolve through `rules.json`.

## Glossary

- **Race Family** — The base race (`human`, `dwarf`, `orc`, `elf`, `gnome`, `satyr`, etc.).
- **Race Variant** — A sub-type (e.g. `hill` / `mountain` for dwarf, `high` / `wood` for elf).
- **Racial Adjustment** — Starting-attribute modifiers granted by race+variant (`rules.json` `character_creation_rules.racial_adjustments`).
- **Race Speed** — Per-race base speed (`rules.json` `reference.race.speed`); modified by `speed_modifiers.race`.
- **Tier Progression** — Per-race ability list keyed by tier (`rules.json` `reference.race.tier_progression`). A race ability is granted when the character's tier reaches the listed tier.
- **Race Ability** — An ability (passive or active) inherited from race rather than class. Examples: orc `ferocity`, ghoul `ghoul_paralysis`, troll `regeneration`.

## Design

A character's `race` field is a list — first element is the variant, last element is the family — so `["hill", "dwarf"]` resolves variant `hill` of family `dwarf`. `race_sym` returns the variant; `race[0]` is also used as the lookup key into `tier_progression`.

`undead?` is true when any element of `race` equals `"undead"` (e.g. wights, ghouls, skeletons, zombies).

Speed: `30 + speed_modifiers.race[variant] + speed_modifiers from abilities`. Dwarf is `-10`, satyr is `+5`. The base 30 is overridden by `reference.race.speed` if a per-race default is listed (dwarf 20, satyr 35).

Race abilities (`race_abilities` method on CharacterSheet) merge:

- Character's class abilities, plus
- Race tier_progression entries whose tier ≤ current tier.

Race abilities flow through the same machinery as class abilities — `damage_reduction`, `damage_resilience`, `hp_bonus`, `initiative_bonus`, etc., are all summed via `race_ability_bonus`.

Natural weapons: a race that lists weapon ability names (`bite`, `claws`, `slam`) generates corresponding natural weapon entries via `weapon_props`. `rules.json` `reference.natural_weapons` defines damage type and weight for each.

## Cross-domain interactions

- Race data definitions live in `../common/data/races.yaml.example` (human / dwarf / orc and others).
- Race ability definitions are in `rules.json` `reference.abilities`.
- `staggered` (zombie) halves the combat pool — see [combat-tracker.md](combat-tracker.md).
