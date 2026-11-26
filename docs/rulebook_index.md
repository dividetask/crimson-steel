# Rulebook Index

The chapters of the Crimson Steel rulebook — the book a table needs to play the game with real dice — and what that book still lacks. [domain_index.md](domain_index.md) lists the *concepts*; this lists the *book* assembled from them. How a chapter is written and marked up is in [common/file_conventions.md](common/file_conventions.md); how the site shows it is in [project/compendium.md](project/compendium.md).

## Chapters

Each chapter is the `@player` half of one concept's design document.

| # | Chapter | Concept folder | Covers |
|---|---|---|---|
| 1 | Magical Tier | `magical_tier` | The world's magic, Tier, magic toxicity, what each Attribute does. |
| 2 | Dice Resolution | `dice_resolution` | One Roll: dice, Target Number, Bonuses and Penalties, Rerolls, Nudges, the outcome. |
| 3 | Check Resolution | `check_resolution` | Several Rolls at once: opposed Checks, Ascendancy, Degree of Success. |
| 4 | Conditions | `conditions` | What persists: damage by Severity, healing, Mana, magic toxicity, Afflictions, effects, recovery, death. |
| 5 | Characters | `creatures` | Making a character, Races, Classes and levels, Tier, ranks, Hit Points and Mana; NPCs and monsters for the DM. |
| 6 | Skills | `proficiencies` | Ranks to Prowess to dice, untrained use, saves and Martial, making and opposing a Skill Check. |
| 7 | Equipment | `equipment` | Money, weapons, armor, magical items, consumables, prices; shops and loot for the DM. |
| 8 | Combat | `encounter` | Rounds and turns, Initiative, the Combat Pool, actions, attacking and defending, damage, being taken out. |
| 9 | Magic and Abilities | `abilities` | Reading and casting a Spell, areas, channeling, Rituals, Talents, Bonus Types. |
| 10 | Time and the Calendar | `timekeeping` | The Round, the calendar, keeping the clock. |
| 11 | The Map | `atlas` | Maps and grids, Tokens, Zones, fog of war. |
| 12 | The Chronicle | `chronicle` | The campaign record: Chapters, notes, who sees what, the Scene. |
| — | Spells, Classes, Glossary | catalogs | Reference lists the site builds from the catalogs. |

Chapters 5–12 were written in one pass on 2026-11-26 from the implementer rules. They have not been play-tested as prose.

## Reference books

The chapter list was checked against the tables of contents of four books.

- **D&D 3.5 Player's Handbook** — 1 Abilities · 2 Races · 3 Classes · 4 Skills · 5 Feats · 6 Description · 7 Equipment · 8 Combat · 9 Adventuring · 10 Magic · 11 Spells.
- **D&D 3.5 Dungeon Master's Guide** — 1 Running the Game · 2 Using the Rules · 3 Adventures · 4 Nonplayer Characters · 5 Campaigns · 6 Characters · 7 Magic Items · 8 Glossary.
- **Pathfinder Core Rulebook** — 1 Getting Started · 2 Races · 3 Classes · 4 Skills · 5 Feats · 6 Equipment · 7 Additional Rules · 8 Combat · 9 Magic · 10 Spells · 11 Prestige Classes · 12 Gamemastering · 13 Environment · 14 Creating NPCs · 15 Magic Items · appendices (Special Abilities, Conditions).
- **Pathfinder GameMastery Guide** — 1 Getting Started · 2 Running the Game · 3 Player Characters · 4 Nonplayer Characters · 5 Rewards · 6 Creating a World · 7 Adventures · 8 Advanced Topics · 9 NPC Gallery.

Source of each list: the Pathfinder Core Rulebook's section headings were read from Paizo's reference document; the 3.5 topic list from the System Reference Document index. The printed chapter numbers of the two 3.5 books, and the GameMastery Guide's chapter list, are quoted from memory — those parts are not in the open reference documents.

## Coverage

What the reference books cover, and where it lives here. **Written** means the book has the text. **Partly** means some of the topic has rules and text. **Not designed** means no rule exists in the documents, the config, or the engine.

### The players' side

| Topic | 3.5 | Pathfinder | Here | Status |
|---|---|---|---|---|
| The core mechanic, common terms | PHB intro | 1 | ch. 2, 3, Glossary | Written |
| Ability scores | PHB 1 | 1 | ch. 1 (what each does), ch. 5 (Point Buy, Effective Attributes) | Written |
| Races | PHB 2 | 2 | ch. 5 | Written |
| Classes | PHB 3 | 3 | ch. 5, Class list | Written |
| Prestige classes | DMG 6 | 11 | Archetypes, ch. 5 | Written |
| Skills | PHB 4 | 4 | ch. 6 | Partly — no per-Skill uses, no retry or time-taken rules |
| Feats | PHB 5 | 5 | Talents, ch. 9; Class list | Written — abilities come from Class and Race only |
| Alignment | PHB 6 | 7 | — | Not designed |
| Religion | PHB 6 | 3 | Deities and domains, ch. 5 | Written |
| Age, height, weight, languages | PHB 6 | 7 | — | Not designed |
| Wealth and money | PHB 7 | 6 | ch. 7 | Partly — no starting wealth |
| Weapons, armor | PHB 7 | 6 | ch. 7 | Written |
| Goods and services, mounts, lodging | PHB 7 | 6 | — | Not designed |
| Carrying capacity | PHB 9 | 7 | — | Not designed |
| How combat works: round, initiative, surprise | PHB 8 | 8 | ch. 8 | Written |
| Attack, defence, damage, saves | PHB 8 | 8 | ch. 8 | Written |
| Actions in combat | PHB 8 | 8 | ch. 8 | Written |
| Injury and death, healing | PHB 8 | 8 | ch. 4, ch. 8 | Written |
| Movement, position and distance | PHB 8 | 8 | Speed (ch. 5), Move (ch. 8), ch. 11 | Partly — see below |
| Cover, concealment, flanking | PHB 8 | 8 | — | Not designed |
| Special attacks: grapple, trip, disarm, charge, mounted | PHB 8 | 8 | — | Not designed |
| Delay and ready | PHB 8 | 8 | — | Not designed |
| Overland movement, travel | PHB 9 | 7 | "Traveling" phase named, ch. 8 | Not designed |
| Vision and light | PHB 9 | 7 | abilities named, no rules | Not designed |
| Casting spells, spell descriptions | PHB 10 | 9 | ch. 9 | Written |
| Spell lists | PHB 11 | 10 | Spell list | Written |

### The DM's side

| Topic | 3.5 | Pathfinder | Here | Status |
|---|---|---|---|---|
| Running the game, table rules | DMG 1 | 12, GMG 2 | — | Not written |
| Adjudicating checks and difficulty | DMG 2 | 4 | ch. 6 | Partly — no table of typical modifiers |
| Experience and levelling | DMG 2 | 12, GMG 5 | Tier breakpoints, ch. 5 | Not designed — nothing says how a level is earned |
| Designing encounters, difficulty | DMG 3 | 12 | Tier guidance (ch. 1), random encounter tables (ch. 5) | Partly — no way to size a fight |
| Placing treasure, wealth by level | DMG 3 | 12 | Loot tables, shops (ch. 7) | Partly — no guidance on how much |
| Dungeons, doors, traps | DMG 3 | 13 | — | Not designed |
| Wilderness, weather, getting lost | DMG 3 | 13 | — | Not designed |
| Environmental dangers | DMG 8 | 13 | Falling (ch. 8), acid (ch. 4) | Partly — no cold, heat, starvation, suffocation, drowning, darkness |
| NPC classes, creating NPCs | DMG 4 | 14 | ch. 5 | Written |
| NPC attitudes, social encounters | DMG 4 | 4 | Opposed Skills (ch. 6) | Partly |
| Campaigns and world-building | DMG 5 | GMG 6 | Calendar (ch. 10), record (ch. 12) | Campaign content, not common rules |
| Cohorts, familiars, mounts, animal companions | DMG 6 | 3 | — | Not designed |
| Magic items: use, slots, kinds, buying | DMG 7 | 15 | ch. 7 | Written |
| Creating magic items | DMG 7 | 15 | Rituals (ch. 9) | Not designed |
| Condition summary | DMG 8 | appendix | ch. 4; catalog of named conditions | Partly — the named conditions are not printed |
| Monsters | Monster Manual | Bestiary | Templates in campaign data | No bestiary |
| Downtime | — | GMG 8 | "Downtime" phase named, ch. 8 | Not designed |
