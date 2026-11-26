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
| Weapons, armor | PHB 7 | 6 | ch. 7 | Partly — no weapon ranges, ammunition use, or proficiency rules |
| Goods and services, mounts, lodging | PHB 7 | 6 | — | Not designed |
| Carrying capacity | PHB 9 | 7 | — | Not designed |
| How combat works: round, initiative, surprise | PHB 8 | 8 | ch. 8 | Written |
| Attack, defence, damage, saves | PHB 8 | 8 | ch. 8 | Written |
| Actions in combat | PHB 8 | 8 | ch. 8 | Written |
| Injury and death, healing | PHB 8 | 8 | ch. 4, ch. 8 | Partly — Dying has no written rule, and no way to stabilise |
| Movement, position and distance | PHB 8 | 8 | Speed (ch. 5), Move (ch. 8), ch. 11 | Partly — see below |
| Cover, concealment, flanking | PHB 8 | 8 | — | Not designed |
| Special attacks: grapple, trip, disarm, charge, mounted | PHB 8 | 8 | — | Not designed |
| Delay and ready | PHB 8 | 8 | — | Not designed |
| Overland movement, travel | PHB 9 | 7 | "Traveling" phase named, ch. 8 | Not designed |
| Vision and light | PHB 9 | 7 | abilities named, no rules | Not designed |
| Casting spells, spell descriptions | PHB 10 | 9 | ch. 9 | Written — no counterspelling, dispelling, or line of sight |
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
| Magic items: use, slots, kinds, buying | DMG 7 | 15 | ch. 7 | Written — nothing on selling |
| Creating magic items | DMG 7 | 15 | Rituals (ch. 9) | Not designed |
| Condition summary | DMG 8 | appendix | ch. 4; catalog of named conditions | Partly — the named conditions are not printed |
| Monsters | Monster Manual | Bestiary | Templates in campaign data | No bestiary |
| Downtime | — | GMG 8 | "Downtime" phase named, ch. 8 | Not designed |

## Rules to settle

Places where the documents, the config and the engine say different things, and rules a chapter had to leave out because nothing defines them. The chapters state the designed rule; in each case the text or the engine has to move. File and line references are as of 2026-11-26.

### Settled

Rulings given on 2026-11-26. The book follows them; what is still to do is noted.

- **Every Check needs a Degree of Success of the Default Success Threshold** — attacks, spell attacks and saves included — counted after subtracting the opposing Rolls. *Still to do:* the engine applies damage, and fails a save, on any net Success (item 1).
- **One shared book.** There is no DM-only text; what the DM needs sits in sections headed "For the DM — …". A players-only manual may be cut from it later.
- **Every die is a d10**, and a percentage is rolled on two of them. *Still to do:* the loot and encounter tables still write their quantities in d2, d3, d4, d6, d8 and d16.
- **Catalog data is printed live**, with `{{table: …}}` — see [common/file_conventions.md](common/file_conventions.md) → *Paths and tables*.

### Resolution

1. **The engine hits on any net Success.** Settled above: a Check needs the Default Success Threshold. `Encounter::State#resolve_attack_payload` applies damage when `net.positive?`, `Encounter::Cast.resolve_save` fails the save the same way, a spell attack hits the same way (`cast_attack_target`), and [encounter_tests.md](common/encounter/encounter_tests.md) reads "applies damage when the net DoS is positive".
2. **Should more training ever make a Check worse?** Each new point of Competency resets the Dice Cap to its minimum. Rolling the full Dice Cap, average net Successes fall at every reset — at the shipped values, 3.0 at Prowess 4 and 2.4 at Prowess 5. In a fight the cheaper dice make up for it; outside a fight nothing does.
3. **Is Set-Value Spend in the game?** It is designed ([encounter_design.md](common/encounter/encounter_design.md) → *Set-Value Spend translation*) and coded (`Encounter::State#set_value_spend`), but `Set Value Spend Ratio` is marked `#DELETE ME` and the "Preroll" entry the design cites is not in the dice glossary. No chapter mentions it.

### Characters

4. **What Tier is a new character?** Tier 1, by `Tier Breakpoints` (`creatures_advancement.yaml:10`: level 1 reaches Tier 1). Tier 0, by the creation rules (`character_creation.yaml:5`, `CREATION_TIER` at `lib/character_creation.rb:28`). Chapter 5 gives no starting Tier.
5. **May one Attribute be picked twice as a chosen bonus at the same Tier?** No (`creatures_config.yaml:44`). Yes, and it doubles ([creatures_design.md](common/creatures/creatures_design.md) → *Tier Attribute Advancement Validation*).
6. **At what level is an Archetype taken?** The glossary names an "eligibility level" and no document gives it; a code comment says 3. `ranger` has no features of its own.
7. **Is the Skill Pick Budget per Class Level or fixed?** "Per-Class-Level" (`creatures_config.yaml:28`); "does not scale with Class Level" (`creatures_glossary.md:61`). The budget for a second Class is not stated.
8. **Ability bonuses to Speed, Hit Points and Mana are not applied.** `aggregated_modifiers` returns an empty list (`lib/creatures/accessor.rb:249`), so Fast Movement adds no Speed.
9. **Two config keys are out of step with the engine.** `Proficiency Advancement Rates` is in config, but the rates are hard-coded (`lib/proficiencies/ranks.rb:43`). `Default Base Speed` is cited by the design and missing from config; the code falls back to 30.
10. **Spells that are never granted.** A Druid's "every Nature spell" and a Bloodrager's chosen spells are not gathered into Granted Abilities (`lib/creatures/accessor.rb`).
11. **Which domains may a Cleric choose?** "3 domains granted from your god" (`talents.yaml:67`), or any domain that is not anathema, with Channel Divinity only for the deity's own (`deities.yaml` header). Anathema is not checked when a character is saved.
12. **Class abilities that are named but not defined:** the Monk's `stunning_strike` and `ki_pool`, the Cleric's `casting_feat`. An optional "background skill" exists only in `lib/class_list.rb:135`.
13. **Do item bonuses change the Effective Attribute?** No, says [creatures_design.md](common/creatures/creatures_design.md) → *Cross-domain interactions*; yes, does the engine (`lib/creature_modifiers.rb`), and [proficiencies_design.md](common/proficiencies/proficiencies_design.md) agrees with the engine. Chapters 5 and 6 follow the engine.
14. **Random encounter rows.** Four row kinds are designed; the engine rolls three (`lib/creatures/random_encounter.rb:14`). No shipped table uses the fourth.

### Combat

15. **Which Attribute drives Martial?** Dexterity (`skills.yaml:22`, [creatures_design.md](common/creatures/creatures_design.md) → *Ranks Computation*). The engine uses Strength for melee attacks and for Block and Parry, and Dexterity for ranged (`lib/routes/encounter_attack_ui.rb:54`, `:132`). Chapter 8 names no Attribute; chapters 1 and 6 say Dexterity.
16. **Fewest dice on an attack.** A Main Action has a minimum of `Main Action Minimum` (`encounter_glossary.md:53`); the attack builder offers 2 up to the Dice Cap (`encounter_attack_ui.rb:216`).
17. **Two Main Actions per turn** is tracked and not enforced (`lib/encounter/state.rb:1360`).
18. **Shock never shrinks the Combat Pool.** Designed in chapter 4; `consume_shock` (`lib/conditions/instance.rb:149`) has no caller.
19. **The Acid Counter never ticks.** `resolve_acid_turn_start` (`lib/conditions/instance.rb:475`) has no caller. Chapter 4 also says acid adds to the counter "rather than dealing damage immediately"; config and engine deal the damage *and* add to the counter (`lib/encounter/state.rb:655`).
20. **Electricity against metal armor does nothing.** The mechanic is not handled (`lib/encounter/severity.rb:49`) and the metal-armor test always answers no (`:104`).
21. **Concentration saves are never rolled.** No caller supplies a resolver, so every save passes (`lib/encounter/state.rb:644`); a channel with a duration in turns is skipped outright (`:1813`). How many dice the save rolls, and whether it costs Combat Pool, is not specified.
22. **Hidden** exists only in the design text ([encounter_glossary.md](common/encounter/encounter_glossary.md)); the engine has nothing for it.
23. **May an Unaware Creature defend?** The engine drops the Unaware Bonus whenever a defence is declared (`lib/encounter/attack.rb:84`); the design does not say, and two Talents imply Reactions are normally unavailable while Unaware (`talents.yaml:235`, `:244`).
24. **When do Luck Points clear?** At the start of the turn ([encounter_design.md](common/encounter/encounter_design.md) → *Combatant*), or at its end (the same document → *Per-turn cleanup*, and `lib/encounter/state.rb:1762`). Chapter 8 says the end.
25. **Initiative Insight above 1.** Repeat the shift once per point ([encounter_design.md](common/encounter/encounter_design.md) → *Initiative Insight*), or one shift of the whole amount (`lib/encounter/initiative.rb:82`, and the tests). Chapter 8 follows the code.
26. **Falling.** Bleed from a fall is designed and not applied (`lib/encounter/state.rb:696`). Whether Damage Reduction applies to a fall is not stated.
27. **Dying** is defined only in code, as a "first-pass interpretation" (`lib/conditions/instance.rb:741`). Nothing says how a Dying Creature stabilises or recovers, and because its turn is skipped (`lib/encounter/state.rb:486`) its Afflictions — Bleeding included — never resolve.
28. **How far does a Move take you?** Not stated anywhere; the engine only spends the dice (`lib/encounter/state.rb:320`). Chapter 8 says Speed limits it. Small Step is in the glossary only.
29. **Not designed at all:** delaying and readying; cover and concealment; flanking; reach, range limits and range penalties; charging, grappling, tripping and disarming; two-weapon fighting; attacks of opportunity; standing up from prone; mounted combat; size in combat; difficult terrain and diagonal movement; Travel and Downtime.

### Magic

30. **What does a cast cost?** "Speed + dice" ([turn_action_stub.md](common/ui/turn_action_stub.md), `lib/encounter/cast.rb:33`), but no Spell and no config gives a casting Speed, and the builder sets it to 0 (`lib/routes/encounter_cast_ui.rb:311`). Chapter 9 says the dice committed.
31. **"Rank" means two things.** Ranks in the casting Skill (`abilities_glossary.md:17`; used for range, targets and area), and total level (used for durations, `lib/encounter/state.rb:1000`). Chapter 9 uses Skill ranks.
32. **Halving.** A rounding remainder drops one Severity ([abilities_design.md](common/abilities/abilities_design.md) → *Halved Effect*); the engine halves each Severity and discards remainders (`lib/encounter/cast.rb:40`).
33. **Fumbled saves** are designed and have no branch in the engine (`lib/encounter/cast.rb:92`). It is also unclear whether the Degree of Failure is the save Roll's own or the net of the Check.
34. **Reaction Spells** are given the Main Action Minimum (`lib/encounter/special.rb:48`).
35. **Long Casts** — a Spell that takes several turns is never registered, because sustaining is built from a channel only (`lib/routes/encounter_cast_resolution.rb:169`). What each turn of a Long Cast costs is not stated.
36. **Spell attacks get no Flatfooted, Unaware or Helpless advantage** (`lib/routes/encounter_cast_ui.rb:429`); weapon attacks do.
37. **Who takes the magic toxicity of a Spell, and does a Spell add any?** Chapters 1 and 4 say magical healing does, to the one healed; Heal carries the values in `spells.yaml`. The engine adds magic toxicity only for a Potion or Oil, and to the caster (`lib/encounter/state.rb:1045`).
38. **Unsettling Words:** "a single die of your choice" (`talents.yaml:290`), or the highest Successes, as a negative Reroll does. Chapter 9 follows the Reroll rule.
39. **May the caster choose among a Spell's casting Skills?** Yes (`abilities_glossary.md:19`); the engine picks the Class's Skill or the first listed, and offers a choice only for items (`lib/routes/encounter_cast_ui.rb:514`).
40. **Not designed at all:** what a save for entering or ending a turn in a lingering Area is rolled against; who may perform a Ritual, with which Skill, and how one is learned; the highest Spell Tier a caster may learn or cast; counterspelling and dispelling; line of sight; verbal components (`silenced` and `deafened` refer to them, no Spell declares any).

### Conditions

41. **Bleeding's Potency decay.** Chapter 4's worked example assumes a decay of 0 and ends at Potency 1. `Default Potency Decay` is `tier`; the same Creature ends at Potency 0.

### Equipment

42. **What does a magical weapon's Tier add?** Guidance on the attack Roll and the damage ([equipment_design.md](common/equipment/equipment_design.md) → *Reconcile Loadout*). The engine carries no weapon Tier into an attack (`lib/routes/encounter.rb:570`, `lib/equipment/instance.rb:376`); the attack builder adds Guidance for spell strikes only (`lib/routes/encounter_attack_ui.rb:84`). A shield's Tier does nothing beyond Hardness and price.
43. **When is a helpful potion refused?** At or above the Toxicity Threshold ([equipment_design.md](common/equipment/equipment_design.md) → *Consume Item*, `lib/equipment/consumption.rb:98`); strictly above it (chapter 4). Equipment also lets a Ward's Temporary Hit Points through the block; chapter 4 blocks every beneficial effect. And in a fight the block is not honoured at all — the effects are applied even when the toxicity is refused (`lib/encounter/state.rb:1045`).
44. **Oils** impose no magic toxicity in a fight; only potions are wired (`lib/routes/encounter_cast_resolution.rb:61`).
45. **Elemental Resistance** is designed and nothing reads it.
46. **Scroll and Tier 0 prices.** The design says the price by form is "not yet defined". Chapter 7 gives the shop's rule: a Scroll is half the Potion price, and a Tier 0 spell item is half the Tier 1 price (`lib/store_spell_items.rb:15`). By the plain formula a Tier 0 Wand costs nothing.
47. **Random magical armor.** Body-armor Properties stay off shields by design; the code treats the two armor kinds alike (`lib/equipment/magical.rb:81`).
48. **Block needs a shield** in the glossary and the engine (`lib/routes/encounter_attack_ui.rb:249`), not in the design's Defensive Actions table. Paying from the Party's purse after your own exists only in the interface document and its route.
49. **Catalog duplicates.** "Short bow" and "Shortbow", "Great axe" and "Greataxe", at different prices; Arrow lists only Shortbow.
50. **Not designed at all:** one item per Slot is assigned to Creatures and enforced nowhere, and there is no rule for hands or for several rings; whether a shot uses up Ammunition; weapon ranges (only the Bola has one); what "simple" and "martial" weapons are, and what using a weapon or armor without proficiency costs; what Alchemist's fire and an Acid jar do; applying a poison dose; breaking gear (Hardness and Hit Points are stored and unused); carrying capacity; what a shop pays when you sell; starting gear and wealth.

### Smaller slips in the data and documents

- Fireball's save says "full" and "half" (`spells.yaml:71`) where the vocabulary is `halved`. Spiritual Hammer calls for a "Toughness save" (`spells.yaml:453`), which is not a save. Charm Person's modifier uses keys outside the Modifier Entry shape (`spells.yaml:869`).
- "Saturation" is still used for magic toxicity in `spells.yaml`, `talents.yaml:63` and `equipment_config.yaml` (`Consumable Saturation`).
- `abilities_glossary.md:61` sends "Channeled Ability" to the common glossary, which does not define it.
- [creatures_design.md](common/creatures/creatures_design.md) says the shipped Classes leave aligned saves empty (Sorcerer and Paragon set them), that a Class has two aligned saves, and that `HP Formula` lives in the config (it is in the advancement catalog). `creatures_tests.md:142` puts Arcane Trickster features at levels 1–2; the catalog has them at 3.
- Loot and encounter tables write quantities in d2, d3, d4, d6, d8 and d16 (`loot_tables.yaml`, `random_encounter_tables.yaml`), and the dice-expression reader has no way to write a small range in d10s. Settled above: every die is a d10.

## Data the book does not print

Chapters 5–9 print their tables straight from the config and the catalogs. What is still missing:

- **Chapter 4's tables** — the Afflictions (`conditions_afflictions.yaml`), the named conditions such as blind, prone and shaken (`conditions_effect_names.yaml`, where many have no description yet), and the Natural Recovery rates.
- **Talents** that are not reached through a Class (`talents.yaml`, `modifier_abilities.yaml`), and **Archetypes and NPC classes**, which the Class list leaves out.
- **Shops and loot tables** (`shops.yaml`, `loot_tables.yaml`) and the **random encounter tables** — chapters 5 and 7 explain how to roll them, and print none.
- **Anything that needs arithmetic.** `{{…}}` takes an integer offset and nothing else, so a product of two values — a Tier 2 potion's price, the ranks a Class Level is worth — is described, not shown.

## Review notes on chapters 1–4

Read against the config, the catalogs and the engine. **Wrong** contradicts them; **Missing** is something a table needs and the chapter does not say; **Wording** reads as a description of the software rather than a rule.

### 1 — Magical Tier

- **Missing.** Wisdom is credited with Initiative only. It also sets the Combat Pool (`Combat Pool Attribute`), the largest number a fighter has.
- **Missing.** Tier is "0 to 6"; Creatures stop at 5 (`Tiers`). Say that 6 is for gods and has no statistics.
- **Wrong.** Strength "defines … carrying capacity". No carrying rule exists.
- Dexterity "defines attack accuracy with physical weapons". The engine rolls melee attacks on Strength — *Rules to settle* 15.
- See *Rules to settle* 37 for what adds magic toxicity.

### 2 — Dice Resolution

- **Missing.** The chapter never says where a Roll's Dice Count comes from. It needs one line pointing at chapter 6.
- **Missing.** Two of the four Rerolls are implementer-only: rerolling Critical Successes (the `blurred` condition) and rerolling 1s (Halfling Luck).
- **Missing.** Which Rolls "ignore Failures"? The extra dice of a magical weapon do; the chapter names none.
- **Wrong.** The examples use "Skill" and "Equipment" Bonus Types. Neither is in the `Bonus Types List` (Competency, Circumstance, Morale, Guidance, Inherent, Ascendancy, Racial, Luck), and the list itself appears in no chapter before 9.
- **Wording.** A Reroll and a Nudge pick their dice by rule. At a table the roller applies that rule by hand; the text should say so. "The interface renders them like this" names an interface, which [file_conventions.md](common/file_conventions.md) rules out.
- **Wording.** The scoring example shows a 10 as the Critical Success; Die Size is config.

### 3 — Check Resolution

- **Wrong.** The same Bonus Type names: "Skill", "Equipment", "Armor".
- **Missing.** Area effects. One casting Roll is netted against each caught Creature's save separately (the Spread Check); only the implementer half says so. Chapter 9 now covers it from the caster's side.
- **Wording.** "Ordering-only Checks" describes an entry point and a "sorted permutation". The table rule is: sort each Roll high to low and compare die by die. Chapter 8 spells it out for Initiative.
- **Wording.** The Ascendancy passage carries builder language ("a combat builder injects a +0 Inherent Penalty").
- See *Rules to settle* 1.

### 4 — Conditions

- **Wrong.** The Bleeding worked example — *Rules to settle* 41.
- **Wrong.** Bardic Inspiration is given as a source of Temporary Hit Points and of a "+2 Skill Bonus"; it grants Luck. Prone is given as a "−1 Penalty"; the catalog makes it ±2 on attacks against the prone Creature.
- **Missing.** Dying. The engine treats a Creature whose damage has reached its Hit Points, but not yet the death threshold, as Dying: it cannot act and is Helpless (`Conditions::Instance#dying?`, which notes the rule is "pending a formal Dying spec"). The chapter goes straight to Dead. Chapter 8 describes it; chapter 4 should own it.
- **Missing.** Current Hit Points are never defined for the reader: maximum Hit Points less all damage, of every Severity.
- **Missing.** The named conditions and the fatigue track (winded, tired, exhausted, then unconscious).
- **Wording.** Several passages describe stored fields and calls rather than rules: `mana_spent`, "Apply Mana Cost", "Set Mana Spent", "every call to apply Toxicity comes tagged", "Source ID", "the Consume Shock call takes a cap", `recovery_ticks`.
- **Wording.** A heal "cascades down to the next-worse Severity". It flows from Major to Moderate to Minor — to the next *less* severe.
