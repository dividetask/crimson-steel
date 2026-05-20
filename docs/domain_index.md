# Domain Index

The domains that will have file sets per `file_conventions.md`. This list will evolve as the project progresses.

| Domain | Status | Description |
|---|---|---|
| Roll Resolution | In progress | Single-Roll mechanics: dice rolling, rerolls, nudges, DoIS, outcome, Dice Result String. |
| Check Resolution | In progress | Multi-Roll composition: cross-side modifier propagation, aggregating DoIS across Rolls, Roll ordering. |
| Creatures | In progress | Identity, attributes, aspects (race etc.), and advancement (classes, tier breakpoints). Folds the previous Character, Race, and Advancement domains into one. |
| Proficiencies | In progress | Skill catalog and the Prowess formula. Owns Versatile Performance and Jack of All Trades substitutions. Saves are not part of the Proficiencies world; the public entry point accepts an attribute override for save and homebrew lookups. |
| Equipment | In progress | Items a Creature carries or wears, their effects, Currency and Gems, Loot Tables, Shops, end-of-Combat loot, and the Loot Archive. |
| Conditions | In progress | Per-Creature mutable state: HP damage, Ability Damage, Temporary HP, Mana, Magic Toxicity, Shock, Acid Counter, Active Afflictions, Active Effects. |
| Chronicle | In progress | Campaign-level state. Holds the current time, chapters, notes, and creature references. |
| Timekeeping | In progress | Calendar and clock calculations. Pure calculation; the current time is owned by Chronicle. |
| Combat | In progress | Combatants, initiative, Time Ticks within a Round, action economy (Main / Bonus / Free actions and Reactions), Combat Pool, defensive bonuses (Flatfooted, Unaware, Hidden), Set-Value Spend, Concentration maintenance, Damage Types and Severity Calculation. |
| Abilities | In progress | Reference catalog of Spells, Talents, and granted features (Stateful and Always-On Modifier). Owns Variant resolution, Effect Hash evaluation, Effect classification, Concentration Block resolution, Trigger Spec lookup, and the canonical Bonus Types List for Modifiers. Does not roll dice or track active state. |
| Atlas | In progress | Maps and the Tokens placed on them. Owns the Active Map pointer and Map archive state. |

## Cross-domain dependencies

A rough sketch of which domains depend on which. The arrow points from caller to callee:

- Check Resolution → Roll Resolution
- Proficiencies → Roll Resolution
- Combat → Check Resolution, Creatures, Conditions, Abilities, Chronicle
- Abilities → Roll Resolution, Conditions, Combat
- Equipment → Abilities (Bonus Types List), Conditions, Combat
- Conditions → Abilities, Creatures
- Creatures → Proficiencies, Equipment, Abilities, Conditions
- Chronicle → Timekeeping, Creatures
- Atlas → Creatures

This is a starting picture and will be refined as each domain's design takes shape.

## Notes

- A "Tentative" domain may be merged into another or split into multiple as the design solidifies.
- Domains in "Planned" status have no design yet; the table is a placeholder so their existence and rough purpose is captured.
- A domain doesn't enter "In progress" until its design file is being actively written.
- Data that consumers need before its owning domain exists lives in `orphan_data/<future_domain>.yaml`. See `file_conventions.md`. Equipment, Conditions, Abilities, and Modifiers have all migrated out of `orphan_data/` when their designs landed.
