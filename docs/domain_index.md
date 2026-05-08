# Domain Index

The domains that will have file sets per `file_conventions.md`. This list will evolve as the project progresses.

| Domain | Status | Description |
|---|---|---|
| Roll Resolution | In progress | Single-Roll mechanics: dice rolling, rerolls, nudges, DoIS, outcome, Dice Result String. |
| Check Resolution | In progress | Multi-Roll composition: cross-side modifier propagation, aggregating DoIS across Rolls, Roll ordering. |
| Creatures | In progress | Identity, attributes, aspects (race etc.), and advancement (classes, tier breakpoints). Folds the previous Character, Race, and Advancement domains into one. |
| Proficiencies | Planned | Skills, saves, and proficiencies. |
| Equipment | Planned | Items a Creature carries or wears, and their effects. |
| Conditions | Planned | Temporary states affecting a Creature (poisoned, frightened, etc.). |
| Chronicle | In progress | Campaign-level state. Holds the current time, chapters, notes, and creature references. |
| Timekeeping | In progress | Calendar and clock calculations. Pure calculation; the current time is owned by Chronicle. |
| Combat | Planned | Turn order, actions, and combat-specific Roll modifications. |
| Abilities | Planned | Active and passive abilities a Creature can use. |
| Damage Types | Tentative | May be merged with another domain. |
| Atlas | Planned | World map / location data. |
| Modifiers | Tentative | The canonical list of Bonus/Penalty Type Names and the workflow for registering new ones. May end up part of another domain. |

## Cross-domain dependencies

A rough sketch of which domains depend on which. The arrow points from caller to callee:

- Check Resolution → Roll Resolution
- Combat → Check Resolution, Creatures, Conditions, Abilities
- Abilities → Roll Resolution, Conditions, Damage Types
- Equipment → Modifiers, Conditions, Damage Types
- Conditions → Modifiers, Abilities
- Creatures → Proficiencies, Equipment, Abilities, Conditions
- Chronicle → Timekeeping, Creatures

This is a starting picture and will be refined as each domain's design takes shape.

## Notes

- A "Tentative" domain may be merged into another or split into multiple as the design solidifies.
- Domains in "Planned" status have no design yet; the table is a placeholder so their existence and rough purpose is captured.
- A domain doesn't enter "In progress" until its design file is being actively written.
- Data that consumers need before its owning domain exists lives in `orphan_data/<future_domain>.yaml`. See `file_conventions.md`. Currently used for Equipment, Conditions, Abilities, and Modifiers.
