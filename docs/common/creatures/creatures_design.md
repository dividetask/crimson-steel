@chapter 5 Characters

# Creatures — Design

@player
The first four chapters were the engine: Tier, dice, Checks, and the state a Creature carries from moment to moment. This chapter is about the Creature itself — what it was born as, what it has trained to be, and how those choices become the numbers every other chapter reads. A **Creature** is anything the rules can act on: your character, the innkeeper, the ogre in the cave. All are built from the same parts and obey the same rules; a monster is simply a Creature the DM runs.

@implementation
Owns the Creature record: identity, Race + Aspect, Classes + Levels + Trained Skills + per-Class Choices, Tier Override, Tier Attribute Advancements, Group, Tags. Computes Tier, Effective Attributes, Speed, ranks for any proficiency key, Granted Abilities, and aggregated `modifiers:` from those Abilities. Produces a Creature Accessor that other domains read through.

Sibling domains:

- **Proficiencies** consumes the Creature Accessor (`ranks_for`, `attribute_value`, `has_ability`, `level_for_ability`) to compute Prowess. Creatures does not compute Prowess itself.
- **Combat** receives a Creature Lookup Callback wired to *Look up Creature* and reads per-Combatant data through it.
- **Conditions** holds per-Creature mutable state (HP damage, Ability Damage, Effects, etc.). The Creatures record is the *baseline*; Conditions' state layers on top at the consuming domain. Death checks read Creatures' attribute scores and max HP through the Accessor.
- **Abilities** is the source of truth for what each Granted Ability does. Creatures hands ability names back to callers; mechanical detail is looked up through Abilities.
- **Equipment** does not appear in this design — equipment is associated with a Creature through Creature ID at the Equipment level, not stored on the Creature record.

## What a Creature is

@player
Every Creature is described by five things:

- a **Name** and a **Player** — a Creature with no Player is run by the DM;
- a **Race** — what it was born as;
- six **Attributes** — the scores introduced in the Magical Tier chapter;
- its **Classes** — what it has trained as, with a level in each;
- its **Tags** — short labels for the kind of Creature it is (player character, hero, noble, commoner, animal), which decide how quickly its levels become Tier.

Everything else on a character sheet — Tier, Hit Points, Mana, Speed, ranks, abilities — is worked out from those five. This chapter gives the baseline; wounds, spent Mana and passing effects (the Conditions chapter) and gear (the Equipment chapter) are layered on top.

## Creating a character

@player
A new Player Character begins with one level in one Class. Take these steps in order — later steps read the results of earlier ones.

1. **Buy your Attributes.** All six start at {{character_creation.yaml > Attribute Allocation > starting_value}} and are raised or lowered from one shared pool of {{character_creation.yaml > Attribute Allocation > point_buy}} points. Each score has a total price — negative below the starting value, so lowering one can pay for raising another — and none may go below {{character_creation.yaml > Attribute Allocation > minimum}} or above {{character_creation.yaml > Attribute Allocation > maximum}}. The prices are in the table under this list.
2. **Choose a Race** from the **Playable Races**; its adjustments apply on top of the scores you bought.
3. **Choose a Class** from the Class list.
4. **Train your Skills.** Your **Skill Pick Budget** is `{{Skill Pick Formula}}`, where *int* is your Effective Intelligence and the bonus-skills term comes from your Class. Train that many Skills — any Skill, though your Class decides how fast each grows. A Skill that is really a family (a craft, a profession, a kind of performance) is trained one member at a time.
5. **Choose your spells**, if your Class casts them (see *Classes and levels*).
6. **Choose a deity and domains**, if you are a Cleric (see *Deities and domains*).
7. **Equip yourself** from the Equipment chapter.
8. **Work out the rest** — Tier, Effective Attributes, Hit Points, Mana, Speed, ranks and Granted Abilities — as the remainder of this chapter describes.

The total price of each score:

{{table: character_creation.yaml > Attribute Allocation > cost | label: Score | value: Total price}}

## Attributes, from base to Effective

@player
The scores you bought are your **Base Attributes**. The rules use the **Effective Attribute** — wherever this book names an Attribute, that is what it means. Build it in order:

1. Start from the Base Attribute.
2. Add your Race's adjustment, if any.
3. Add the **Inherent bonus** for your Tier, which every Attribute receives.
4. Add {{Per-Tier Inherent Chosen Bonus Amount}} for each time you have picked that Attribute as a **chosen bonus** (both bonuses are explained under *Tier*).
5. A total below 1 becomes 1.

A base Strength of 14, a Race that adds 2, and Strength picked once as a chosen bonus make an Effective Strength of 14 + 2 + the Tier's Inherent bonus + {{Per-Tier Inherent Chosen Bonus Amount}}.

Magic items and passing conditions that change an Attribute act on the Effective Attribute while they last (the Equipment and Conditions chapters).

## Races

@player
A **Race** is what a Creature was born as. It gives four things:

- **Size** — its size category.
- **Speed** — how far it moves, in feet.
- **Attribute adjustments** — bonuses and penalties to particular Attributes.
- **Abilities** — inborn traits, from resistance to poison to natural weapons. An ability may name a Tier; the Creature has it once its own Tier is that high.

Races come in families: a sub-race **inherits** from its parent, which may inherit in turn — a Hill Dwarf is a Dwarf, and a Dwarf is a Humanoid. Size and Speed come from the most specific Race in the line that states one. Attribute adjustments add up along the line. Abilities are gathered from the whole line, and where a sub-race and an ancestor name the same ability the sub-race's version counts.

A Player Character's Race must be one of the **Playable Races**, listed here with everything their line gives them. The broad parents only carry what their sub-races share: you play a Hill Dwarf or a Mountain Dwarf, never simply "a Dwarf". An adjustment to `all` applies to every Attribute.

{{table: creatures_race.yaml | rows: character_creation.yaml > Playable Races | inherit: parent | columns: size, speed, attribute_adjustments=Attribute adjustments, abilities.name=Abilities | label: Race}}

Every other Race — orcs, wolves, trolls — is for the DM's Creatures and is made of the same four parts.

## Classes and levels

@player
A **Class** is a path of training. A Creature holds a **Class Level** in each of its Classes; their sum is its **Total Class Level**. A Class sets:

| A Class sets | Meaning |
|---|---|
| **Martial advancement** | How quickly its levels build general combat training. |
| **Saves** | How quickly its levels build each of the six Saving Throws. |
| **Skills** | Which trained Skills it advances quickly or slowly, and how many bonus Skills it adds to the Skill Pick Budget. |
| **Mana per level** | Mana added for every level held in the Class. |
| **Abilities by level** | The class features gained at each Class Level. |
| **Spell selection** | For a casting Class, how its spells are chosen. |

The Class list gives all of this for every Class, level by level.

A casting Class chooses its spells in one of these ways: a **number of spells** that grows with Class Level; a **number of spells of each Spell Tier**, read from the Class's table; a pool of **points** that grows with Class Level, each spell costing points by its Tier; **domains**, chosen with a deity in place of individual spells; or **everything of a kind** — every spell cast with the Class's own casting Skill. A Class may also limit its choices to spells cast with a particular Skill. Spells and casting are the subject of the Magic and Abilities chapter.

### Gaining levels and multiclassing

@player
A new level goes into one of your Classes — one you hold, or a new one. Then update everything that reads Class Level: your ranks, your Mana, the class features listed at the new level, the spells your Class's selection rule now allows, and your Tier if your Total Class Level has reached a breakpoint. Two things do not move: the Skill Pick Budget does not grow with Class Level (trained Skills advance further instead), and Hit Points rise with Tier and Constitution, never with level.

A Creature with several Classes keeps a separate level, trained Skills and spell choices for each, and adds their contributions together: ranks and Mana sum across Classes, and it has every feature each Class grants at the level held in that Class. Tier reads the Total Class Level; a feature that grows with level reads the level of the Class that granted it.

### Taking an Archetype

@player
An **Archetype** is a specialised form of a Class, its **Parent Class**. A Creature takes an Archetype in place of its Parent Class once it reaches the Archetype's eligibility level: every level held in the Parent Class becomes a level in the Archetype, and new levels are taken there from then on. An Archetype is never chosen at character creation.

An Archetype keeps whatever its Parent Class sets unless it states its own value. Its class features are added to the parent's at each level, and any Skills it names adjust the parent's lists; neither replaces them.

- A Creature cannot hold levels in both a Class and one of its Archetypes, nor in two Archetypes of the same Parent Class.
- An Archetype may be combined freely with any Class that is not its parent.

## Tier

@player
Tier — the magical density of the Magical Tier chapter — is not chosen; it follows from Total Class Level. Each kind of Creature has a list of **Tier Breakpoints**: the Total Class Level at which it reaches each Tier. A Creature's Tier is the highest Tier whose breakpoint its Total Class Level has reached.

Its tags decide which list it reads; player characters, heroes, bosses, nobles, commoners and animals each have one. Tags that match several lists use whichever gives the highest Tier; tags that match none use whichever gives the lowest. The DM may instead simply set a Creature's Tier — a **Tier Override** — and the breakpoints are ignored.

The Total Class Level at which each kind of Creature reaches each Tier:

{{table: creatures_advancement.yaml > Tier Breakpoints | index: Tier | label: Tag}}

| | Tier by Tier |
|---|---|
| Tier | {{Tiers}} |
| Inherent bonus to every Attribute | {{Tier Minimum Inherent Bonus}} |
| Chosen bonuses picked on reaching the Tier | {{Tier Inherent Chosen Bonus Count}} |

A new Tier changes a great deal at once:

- **Inherent bonus.** Every Attribute carries the bonus for your current Tier, which replaces the previous Tier's rather than adding to it.
- **Chosen bonuses.** On reaching a Tier that grants them, pick that many Attributes; each rises by a further {{Per-Tier Inherent Chosen Bonus Amount}} for good. You may not pick the same Attribute twice at one Tier, but may pick it again at a later one. A pick not yet made simply does not apply.
- **Hit Points and Mana** follow formulas that change with Tier (below).
- **Turns.** At the higher Tiers a Creature acts more than once in a Round (the Combat chapter).
- **Everything else that reads Tier** — Toxicity Threshold, natural healing, the gap against an opponent of another Tier — moves with it.

## Ranks: Skills, Saves and Martial

@player
**Ranks** measure training. The Skills chapter turns them into dice; here is where they come from. Class Levels give ranks at one of three speeds, the **Proficiency Categories**: **Aligned** (fast — what the Class specialises in), **Unaligned** (ordinary) and **Opposed** (slow — what it neglects). The **Proficiency Advancement Rates** give the ranks each one is worth at a Class Level, and the Class list prints the result level by level:

{{table: Proficiency Advancement Rates | label: Category | value: Ranks at a Class Level}}

For each of your Classes, find the category it gives, read off the ranks for your level in that Class, and add the results across Classes.

- **Skills.** A Skill gains ranks from a Class only if you trained it in that Class, at the category that Class gives it. Some Classes name the few Skills they advance fast and treat the rest as ordinary; others name the few they treat as ordinary and advance all the rest fast.
- **Saves.** Every Class trains every Save: each of the six Saving Throws gains ranks from every Class you hold, at the category that Class gives that Save.
- **Martial.** General combat training gains ranks from every Class you hold, at that Class's Martial advancement.

## Hit Points, Mana and Speed

@player
**Maximum Hit Points** depend on Constitution and Tier alone. Each Tier has its own **HP Formula**, written in terms of your Effective Constitution (`con`); work it out for your Tier and round down.

{{table: creatures_advancement.yaml > HP Formula | index: Tier | value: Maximum Hit Points}}

**Maximum Mana** is two parts added together: the **Mana Base Formula** for your Tier, written in terms of your Effective Intelligence (`int`) and rounded down; and, for each of your Classes, its Mana per level multiplied by your level in it.

{{table: creatures_advancement.yaml > Mana Base Formula | index: Tier | value: Base Mana}}

**Speed** is your Race's Speed; a line that states none uses the default base Speed. Speed is never less than zero.

Abilities that add to one of these numbers say so, and follow the stacking rule of the Dice Resolution chapter: of several of the same Type, only the largest bonus and the largest penalty count. How much of your Hit Points and Mana is *left* is the Conditions chapter's subject.

## What your Race and Classes grant

@player
A Creature's **Granted Abilities** are everything it can do beyond the basic rules. Gather them from:

- **its Race** — every racial ability whose Tier it has reached;
- **its Class Levels** — every class feature listed at or below its level in each Class, an Archetype's included;
- **its Classes themselves** — the spells a Class teaches all its members;
- **its chosen spells** — once the Class has granted its spellcasting feature;
- **its deity and domains**, for a Cleric.

An ability gained twice is still one ability. One that grows with level reads the level of the Class that granted it; a racial ability reads Tier, and in any formula Tier 0 counts as 0.5. What each ability does is on the Class and Spell lists and in the Magic and Abilities chapter.

### Deities and domains

@player
A Cleric draws power from a deity. Every deity favours certain **domains**, and holds certain others **anathema**. A Cleric chooses one deity and three domains:

- Any domain may be chosen except one that is anathema to the deity.
- Every chosen domain grants its domain spells.
- A chosen domain that the deity favours also grants that domain's **Channel Divinity**.
- At Cleric level 4, the Cleric also gains the deity's own Channel Divinity.

The deities:

{{table: deities.yaml > Deities | columns: domains=Favoured domains, anathema, channel_divinity=Channel Divinity | label: Deity}}

The domains, and what each grants. A domain with nothing beside it has no spells or Channel Divinity yet:

{{table: deities.yaml > Domains | columns: spells=Domain spells, channel_divinity=Channel Divinity | label: Domain}}

## For the DM — NPCs and monsters

@player
Everything above applies unchanged to the Creatures you run. What differs is the setting up.

- **Tags set the pace.** Tag a Creature for what it is — hero, boss, noble, commoner, animal — and its levels become Tier on that list, so the same levels can mean a different Tier for a commoner than for a hero.
- **Or set the Tier outright** with a Tier Override, for a Creature whose power does not come from training.
- **NPC classes** exist only for your Creatures. They work like any other Class but are never offered to players.
- **Any Race** may be used, not only the playable ones. A beast is a Race whose natural weapons are among its racial abilities.
- **Hidden Tier.** You may keep a Creature's Tier secret; it still drives every number.
- **A quick monster** needs only a name, a Race and six Attributes — plus, if wanted, a Class and level, a Tier Override and a few trained Skills.

## For the DM — Templates and spawning

@player
Keep a Creature you expect to reuse as a **template**: a complete Creature that never enters play itself. When you need one, **spawn** a copy. Each copy is its own Creature with its own wounds and gear; copies are numbered so no two share a name, and are discarded once the fight and its looting are over.

A template may leave some facts open, to be rolled once for each copy:

- **Race** — a list of Races, each with a chance.
- **Class** — a list of Classes, each with a chance and a level; a cleric's entry may name pools from which its domains are drawn without repeats.
- **Trained Skills** — a list of candidates: shuffle it and train as many, from the top, as the copy's Skill Pick Budget allows.
- **Chosen bonuses** — picks drawn at random from a list of Attributes; here the same Attribute may come up twice.
- **Gear** — one table for the copy's weapons, armour and pocket change, another for what it drops when it falls (the Equipment chapter).

To roll on a list of chances, roll a percentage with two d{{Die Size}}s — tens and ones, reading a {{Die Size}} as zero and a double zero as one hundred — and read down the list, adding the chances as you go. The first entry whose running total reaches your roll is the result; the last entry takes whatever is left of the hundred.

## For the DM — Random encounter tables

@player
A **Random Encounter Table** builds a group of Creatures for you. Read its rows from top to bottom. Each row names templates and how many copies of each to spawn, and is one of these kinds:

- **Guaranteed** — it always happens.
- **Chance** — roll a percentage; it happens if the roll is no higher than its chance.
- **Weighted choice** — several results, each with a chance, rolled like the lists above; a roll past the last entry means nothing happens.

A row may be made conditional on an earlier row, and is skipped without rolling unless that row happened.

The number of copies is a plain number or a dice expression — so many dice of a stated size, plus or minus a fixed amount, such as two four-sided dice plus one — rolled when the row happens. A row may also give its copies a different name or a different table of drops. Nothing joins a fight until you put it there (the Combat chapter).

## What lives in the next chapter

@player
This chapter ends with a Creature and its ranks. The next chapter, **Skills**, turns ranks and Attributes into dice: what a Skill is, Prowess, the Dice Cap, and what it costs to attempt something you never trained.

## Common types

### Creature Record

The on-disk shape persisted in the `creatures_data_*.example.{json,yaml}` files (and the consuming project's runtime equivalent). See the note at the end of this common type for the multi-file pattern.

| Field | Type | Default on load | Description |
|---|---|---|---|
| `id` | integer | required | Creature ID. Unique across the dataset. |
| `name` | string | required | Display name. |
| `player` | string or null | null | Name of the player running this Creature. Empty for Creatures the DM runs. Stored as metadata; Creatures does not interpret. |
| `group` | string | `""` | Group classification (`pc`, `npc`, `enemy`, etc.). |
| `tags` | list of string | `[]` | Free-form tags. Tags drive Tier auto-computation via `Tier Breakpoints` and may be referenced by other domains. |
| `race` | string | required | Key into `creatures_race.yaml`. Names a single Race entry. Multi-level inheritance is expressed through that entry's `parent:` chain — there is no separate `race_aspect` field. |
| `attributes` | map of attribute key → integer | required | The six raw scores (`str`, `dex`, `con`, `int`, `wis`, `cha`). Every key is required; default zero is *not* assumed. |
| `tier` | integer or null | null | Tier Override. When non-null, *Get Tier* returns this verbatim and Tier Breakpoints are ignored. When null, Tier is auto-computed from Total Class Level against the breakpoint list selected by the Creature's `tags`. |
| `hide_tier` | boolean | false | Display-only flag. When true, the Creature's Tier is withheld from the rendered sheet (the real Tier is still stored and still drives HP/Mana/Toxicity and every other formula). For Creatures whose power level is meant to be hidden from players. |
| `advancement` | Advancement Block | `{}` | Holds the Creature's classes and tier attribute advancement picks. See *Advancement Block* below. |
| `loot_table` | string or null | null | Optional Loot Table ID (defined in Equipment). When set, Equipment's *Collect Combat Loot* rolls this table for the Creature on top of moving its Inventory. |
| `equipment_table` | string or null | null | Optional Equipment Loot Table ID rolled **once at spawn time** to generate the Creature's starting loadout — equipped gear, ammunition, and pocket change. Distinct from `loot_table` (death drops). The consuming project rolls it immediately after *Spawn Creature From Template* (see that entry point). |
| `race_table` | list of `{race, chance}` | `[]` | Optional weighted race list rolled **once at spawn time** to choose the spawn's `race` (e.g. a Slaver that is 50% orc, else human/elf/dwarf). `chance` values are absolute and conventionally sum to 1; leftover probability falls through to the last entry. Every `race` must resolve in `creatures_race.yaml`. The template's own `race` field is the default shown before any spawn. *Spawn Creature From Template* resolves the table to a concrete `race` and clears it on the spawn. |
| `class_table` | list of `{class, chance, level?, skills?, choices?, domain_picks?}` | `[]` | Optional weighted class list rolled **once at spawn time** to choose the spawn's class (e.g. a Slaver that is 50% warrior, else fighter/cleric/rogue). The chosen entry **replaces** `advancement.classes` with a single Class Entry (`level` defaults to 1; `skills`/`choices` optional). `chance` semantics match `race_table`. Every `class` must resolve in `creatures_advancement.yaml`. The template's own `advancement.classes` is the default shown before any spawn. An optional `domain_picks` (list of `{count, from}`) rolls that many **distinct** Cleric domains from each pool (never repeating across draws) and writes them to the spawn's `choices.domains` — used to give a cleric spawn a randomized domain spread. |
| `skill_table` | list of skill keys | `[]` | Optional candidate skill list. At spawn the list is shuffled and the first **N** are assigned to the spawn's (single) class, where N is the Skill Pick Budget — `Skill Pick Formula` (`floor(int/4) + bonus_skills`) evaluated against the spawn's resolved Effective Intelligence and the rolled class's `bonus_skills`. The count does **not** scale with Class Level (higher level advances the chosen skills, it does not grant more of them). Entries may be Set Instances (`perform_percussion`) but not bare Set Skill keys. |
| `tier_advancement_table` | `{count, from}` or null | null | Optional spec rolled **once at spawn time** to fill Tier Attribute Advancement: `count` picks, each chosen uniformly (repeats allowed) from the `from` attribute list, appended to `tier_attribute_advancement`. Used to randomize a tiered creature's chosen attribute bonuses (e.g. a Tier-2 Lieutenant's two picks across Str/Con/Cha/Dex). |
| `metadata` | dict | `{}` | Caller-supplied free-form data. Creatures does not interpret. Used by consuming projects for portrait paths, custom flags, etc. |

`mana_spent`, `hp_damage`, equipped items, active Conditions, and similar runtime state are **not** stored on the Creature record — they live in Conditions, Equipment, and elsewhere, keyed by Creature ID.

The persisted dataset is split across multiple files using the pattern `creatures_data_<suffix>.example.{json,yaml}` — by project convention, one each for PCs (ids 1..99), enemies and templates (100..1999), and NPCs (2000+). The loader concatenates every matching file into one dataset; the `id` field must be unique across every file. Creatures itself is indifferent to which file a record lives in.

### Advancement Block

The `advancement` field of a Creature Record.

| Field | Type | Default | Description |
|---|---|---|---|
| `classes` | map of class key → Class Entry-or-int | `{}` | One key per Class the Creature has levels in. The value is either an integer (shorthand for `{ level: N }` with no trained skills and no choices) or a full Class Entry (see below). |
| `tier_attribute_advancement` | list of attribute keys | `[]` | Flat list of focused-bonus picks made at each Tier-Up, in order. The list is chunked by `Tier Inherent Chosen Bonus Count[tier]`: the first `count[2]` entries are Tier 2's picks, the next `count[3]` entries are Tier 3's picks, etc. A list shorter than the cumulative count up to the Creature's current Tier means the trailing Tiers' chosen bonuses simply don't apply (the Creature has forgone those picks). |

### Class Entry

The value under a key in `advancement.classes`.

| Field | Type | Default | Description |
|---|---|---|---|
| `level` | integer | required | Class Level (≥ 0). |
| `skills` | list of string | `[]` | Skill keys the Creature has chosen to train in this Class. Set Instances are valid (e.g. `perform_dance`); bare Set Skill keys (ending in `_`) are not. |
| `choices` | dict | `{}` | Per-Class catalog choices. Free-form keys; the consuming Class entry interprets each one. Common keys include `spellcasting: [<spell_name>, ...]` (the spells chosen for the Class's Spellcasting-type ability — Bardic Spellcasting, Arcane Spellcasting, Druidic Spellcasting, or the Cleric's `domain` resolution), `deity: <name>` and `domains: [<name>, ...]` (Cleric — up to three domains; the legacy single `domain: <name>` is still accepted), Bard's Versatile Performance subject, etc. Creatures stores and round-trips the dict opaquely; spells listed under `choices.spellcasting` are surfaced as Granted Abilities by *Get Granted Abilities*. |

A bare integer in place of a Class Entry is shorthand: `fighter: 1` is equivalent to `fighter: { level: 1 }`.

### Race Entry (catalog)

The schema for entries in `creatures_race.yaml`. Looked up by the `race` key. Race entries form a chain via `parent:` — a child race inherits and extends its parent. A `race:` field on a Creature names a single (typically leaf) entry; *Look up Race* walks the chain to assemble the effective Race.

| Field | Type | Default | Description |
|---|---|---|---|
| `parent` | string or null | null | Key of the parent Race entry. The chain ends at an entry whose `parent` is null. |
| `size` | string | from parent (first-in-chain wins) | Creature size category (`small`, `medium`, etc.). |
| `speed` | integer | `Default Base Speed` config (first-in-chain wins) | Base speed in feet. |
| `attribute_adjustments` | map of attribute key → integer | `{}` | Adjustments to attributes contributed by this Race entry. `all: N` is shorthand for `+N` to every attribute and is mutually exclusive with per-attribute entries on the same entry. Adjustments accumulate down the chain (root + intermediate + leaf). |
| `abilities` | list of Race Ability Entry | `[]` | Race Granted Abilities. Concatenates down the chain with child-wins dedup on ability name. |

#### Race Ability Entry

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | required (unless context entry) | Ability name. |
| `min_level` | integer | rolling default | Minimum Tier at which the ability becomes active. |

A bare `{ min_level: N }` (no `name`) entry inside `abilities` is a **context entry** — it becomes the rolling default `min_level` for following ability entries until the next context entry. Context entries are flattened at config-load time; the runtime catalog contains only resolved ability entries with explicit `min_level`.

#### Race Chain Walk

When resolving a Race key:

1. Start at the named entry.
2. Walk `parent` chain to the root, collecting entries in leaf-first order.
3. **Size and Speed**: take the first non-null value encountered (leaf wins).
4. **Attribute Adjustments**: accumulate per-attribute amounts across the entire chain.
5. **Abilities**: concatenate from root to leaf; when a leaf ability shares a `name` with an ancestor's, the leaf entry overrides the ancestor's (child wins).

### Class Catalog Entry

The schema for entries in `creatures_advancement.yaml`'s `Classes:` map. Looked up by class key.

| Field | Type | Default | Description |
|---|---|---|---|
| `parent_class` | string or null | null | When non-null, this Class is an **Archetype** of the named parent Class. See *Archetype* below. |
| `npc_class` | boolean | false | When true, this is an NPC/enemy-only Class (e.g. `warrior`, `commoner`) excluded from the player-character class picker (*pc_class_keys*). Otherwise a normal Class in every mechanical respect. |
| `martial_advancement` | enum | required | One of `aligned`, `unaligned`, `opposed`. The rate at which each Class Level adds Martial ranks. (Martial is computed from this field, not from any proficiency list.) |
| `bonus_skills` | integer | 0 | Bonus Skill picks per Class Level used by the `Skill Pick Formula`. Advisory — Creatures does not enforce trained-skill counts. |
| `mana_per_level` | integer | 0 | Mana per Class Level contributed by this Class. Folds into Max Mana on top of the per-Tier `Mana Base Formula`. |
| `saves` | map | required | Save Attribute categorization. Has two sub-keys: `aligned` (the Save Attributes that advance at the fast `aligned` rate) and `opposed` (Save Attributes that advance at the slow `opposed` rate). A Save Attribute in **neither** list advances at the medium **`unaligned`** rate. The two lists must be disjoint. (The shipped Classes leave `saves.aligned` empty, so their listed-`opposed` Saves are Opposed and every other Save is Unaligned.) |
| `aligned_proficiencies` | list of string | none | Skills that advance at the `aligned` rate. Mutually exclusive with `unaligned_proficiencies` *at the top level of a non-Archetype Class*. Set Skill keys (ending `_`) are valid; any Set Instance whose prefix appears here is treated the same way. |
| `unaligned_proficiencies` | list of string | none | Inverse form. Skills that advance at the `unaligned` rate; every Skill *not* listed advances at the `aligned` rate. Use when most Skills are aligned (e.g. Bard). Mutually exclusive with `aligned_proficiencies` at the top level of a non-Archetype Class. |
| `opposed_proficiencies` | list of string | `[]` | Skills that advance at the `opposed` rate. Combines with either `aligned_proficiencies` or `unaligned_proficiencies`; takes precedence over the default for the Skills listed here. |
| `ability_progression` | map of integer (Class Level) → list of string | `{}` | Class Ability Progression. |
| `granted_spells` | list of Catalog Ability name | `[]` | Spells every Creature of this Class learns regardless of their `choices`. Domain-specific or otherwise choice-dependent spells live elsewhere (e.g. the Cleric Class resolves additional spells from `deities.yaml` via the Creature's `choices.deity` and `choices.domain`). |

A non-Archetype Class that declares neither `aligned_proficiencies` nor `unaligned_proficiencies` has no inclusion / exclusion declaration: every trained Skill advances at the `Default Skill Rate` (`unaligned`) unless it appears in `opposed_proficiencies`. Declaring both `aligned_proficiencies` and `unaligned_proficiencies` on a non-Archetype Class is a configuration error.

A Class entry that omits `mana_per_level` is treated as `mana_per_level: 0`.

### Archetype

A Class with a non-null `parent_class` is an **Archetype** of that parent. Archetypes do not extend their parent's skill / save / ability rules transparently the way Sub-Classes would — they form a separate progression that *replaces* the parent's at the Creature level.

Rules:

- A Creature cannot hold levels in both a Class and one of its Archetypes simultaneously. The validator rejects records that violate this rule.
- A Creature may multi-class across unrelated Classes (e.g. Rogue + Fighter), and may multi-class across an Archetype and any Class that is *not* its parent (e.g. Arcane Trickster + Fighter, Arcane Trickster + Cleric).
- An Archetype Class Entry inherits absent top-level fields from its parent: `martial_advancement`, `saves`, `bonus_skills`, `mana_per_level`, `granted_spells`, `spell_selection`, `aligned_proficiencies`, `unaligned_proficiencies`, `opposed_proficiencies`. When the Archetype declares one of those fields, it replaces the parent's.
- An Archetype's `ability_progression` extends the parent's: at each Class Level, the Archetype's list is appended to the parent's. The parent and Archetype must not name the same Ability at the same Level (validator rejects).
- For proficiency-list inheritance: the parent's lists are taken verbatim. The Archetype's lists, if present, are *additive adjustments* — `aligned_proficiencies` entries are added to the Aligned-rate set, `unaligned_proficiencies` entries are added to the Unaligned-rate set (and removed from Aligned if present there), `opposed_proficiencies` entries are added to the Opposed-rate set.

This means a Creature with `arcane_trickster: 4` (and no explicit rogue entry) gets the merged level-1 / level-2 progressions of both Rogue and Arcane Trickster at Class Level 1 and 2 respectively — the Archetype's level count is what drives the lookup, not the parent's.

### Effective Attribute Map

The output of *Get Effective Attributes*. A map from attribute key to integer. Always carries every Attribute key the project defines, even when the Creature has no specific bonus on that attribute (the value is just the Base Attribute plus Per-Tier Inherent Bonus in that case).

### Aggregated Modifier Entry

| Field | Type | Description |
|---|---|---|
| `target` | string | Verbatim from the Modifier Entry returned by Abilities. |
| `type` | string | Bonus Type Name. |
| `descriptors` | list of string | Verbatim. |
| `amount` | signed integer | The result of evaluating the Modifier Entry's `add`. Formulas are resolved against the Creature's `level` (Total Level) and `tier` (Tier 0 → 0.5). |
| `source` | string | The Ability name the entry came from. |

The output of *Get Aggregated Modifiers* is a list of these entries. Per-Bonus-Type stacking is the consumer's responsibility — Creatures does not collapse entries.

### Random Encounter Table Entry

The schema for entries in `random_encounter_tables.yaml`. Looked up by table key (the YAML map key — typically a snake_case identifier like `slave_lords_caravan`).

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | the table key | Display name. |
| `rolls` | list of Random Encounter Row | required | Rows evaluated in order at *Roll Random Encounter* time. |

### Random Encounter Row

Shares Equipment's Loot Roll Row shape — the same Guaranteed / Independent Chance / Weighted Choice / Gated Weighted Choice variants, the same `when` filter, the same `as` publishing of a Roll Variable. The only difference is the row payload: an Random Encounter Row produces a list of Spawn Refs instead of Item Stacks. A Roll Variable published by an Random Encounter Row may be referenced in later rows' `when` filters identically to Equipment's behavior.

### Spawn Ref

One instruction inside an Random Encounter Row payload. Each Spawn Ref expands into one or more new Creature records via *Spawn Creature From Template*.

| Field | Type | Default | Description |
|---|---|---|---|
| `template_id` | integer | required | Creature ID of an existing Creature record (typically tagged `enemy_template`) to clone. |
| `count` | string or integer | `1` | Number of spawns to produce. May be a dice expression (e.g. `2d4`) evaluated at roll time. |
| `name_override` | string | optional | Display name applied to every spawn produced by this Ref. When omitted, spawns inherit the template's `name`. |
| `loot_table` | string | optional | Loot Table ID stored on each spawn's Creature record, overriding the template's `loot_table`. |

## Public entry points

Function names are conceptual labels; implementations choose their own symbols. Where another domain's documentation cites a name (e.g. `creature_lookup` in Combat), the parenthetical here matches that name for traceability.

### Look up Creature (`creature_lookup`)

Inputs: Creature ID.

Behavior: Find the Creature record by ID. Construct a Creature Accessor wrapping it. Subsequent calls on the Accessor read fresh from the same record.

Returns: a Creature Accessor, or null when no Creature has that ID.

### List Creatures

Inputs: optional `group` filter (string), optional `tags` filter (list of string — entries must all be present).

Behavior: Walk every loaded Creature record and emit those that match.

Returns: a list of `(Creature ID, name)` pairs in load order. Used by stub UIs that present a roster.

### Find Creature by Name

Input: a display name (string).

Behavior: Linear scan for the first Creature whose `name` matches exactly. Case-sensitive.

Returns: a Creature Accessor, or null.

The exact-match contract keeps this entry point deterministic. Callers wanting fuzzy or prefix lookup do their own normalization on the result of *List Creatures*.

### Get Tier

Input: Creature ID (or Accessor).

Behavior:

1. If the Creature's `tier` field is non-null, return it (the Tier Override).
2. Otherwise resolve Tier from `tags`:
   - For each tag that matches a key in `Tier Breakpoints`, compute the largest index `i` such that `breakpoints[i] ≤ Total Class Level`. Index 0 of every list must be 0, so a Total Level of zero produces Tier 0 on that list.
   - If at least one tag matched, the Tier is the **maximum** across those per-list Tiers.
   - If no tag matched, the Tier is the **minimum** Tier across every list in `Tier Breakpoints` — the cautious fallback for an unclassified Creature.

Returns: integer ≥ 0.

### Get Effective Attributes

Input: Creature ID (or Accessor).

Behavior: Run the *Effective Attribute Computation* pipeline (see Operations). Returns the full attribute map.

Returns: Effective Attribute Map.

### Get Speed

Input: Creature ID (or Accessor).

Behavior:

1. Walk the Creature's Race chain. The Speed is the first non-null `speed` value encountered (leaf wins), or `Default Base Speed` if no entry in the chain declares one.
2. Add aggregated Speed-targeted Modifier amounts — see *Aggregated Modifier Application to Speed* in Operations.

Returns: integer Speed in feet.

Negative results are clamped at zero. The Speed value Creatures returns is the Creature's baseline; Combat / Conditions apply terrain and Condition modifiers on top.

Class-level Speed bonuses (Barbarian's Fast Movement, Monk's Unarmored Movement, etc.) are not stored on the Class entry — they live on the Granted Ability that confers them, as a `modifiers:` entry targeting `speed`. The Aggregated Modifier folds them in via step 3.

### Get Granted Abilities

Input: Creature ID (or Accessor), optional `source` filter (`race`, `class`, or absent for all).

Behavior: Concatenate:

- Race chain Abilities whose `min_level` is ≤ the Creature's current Tier. Chain order is root → leaf; child entries override ancestors on name (see *Race Chain Walk*).
- For each Class Entry the Creature holds: when the Class is an Archetype, the merged `ability_progression` is the parent's progression with the Archetype's appended at each Class Level. For non-Archetype Classes, the Class's own progression. Take entries whose Class Level ≤ the Creature's Class Level in that entry.
- For each Class Entry, the resolved Class's `granted_spells` (the parent's, when the Class is an Archetype that does not override; the Archetype's, when it declares its own).
- For each Class Entry, every entry in `choices.spellcasting` (the spells the player picked for the Class's Spellcasting-type ability). Only counted when the Class's progression actually granted a Spellcasting-type ability at or before the Creature's Class Level.
- For each Class Entry, choice-driven abilities looked up through external catalogs. A Cleric's `choices.deity` + `choices.domains` resolves, via `deities.yaml`: each chosen domain's bonus spells; the Channel Divinity Talent of each chosen domain that is one of the deity's own domains; and, at Cleric Level ≥ 4, the deity's own Channel Divinity Talent. (The legacy single `choices.domain` is treated as a one-element domain list.)

Deduplicate while preserving first-encounter order. Filter by `source` when supplied.

Returns: a list of `{ name, source }` records. `source` is one of `race` or `class:<class_key>`. The Class source carries the Class key so consumers (e.g. Floor Ability's `level_for_ability`) can recover the granting Class. Spells contributed via `choices.spellcasting` (and via deity/domain) report the granting Class as their source.

#### Kesser — Reversal Table (d10)

The deity Kesser's 4th-level Channel Divinity, **Kesser's Gambit** (`talents.yaml`, `roll_table: Kesser Reversal Table`), is a Reaction triggered on an attack or spell roll. The channeler rolls a d10 here; **Channel Successes** scale the entries. The table below is the canonical description; it is provided as data in `../abilities/roll_tables.yaml` and rolled in combat through the Roll Table Stub (`../ui/encounter_roll_table_stub.md`). Kesser's Ring (`../equipment/equipment_config.yaml` → *Unique Items*) grants the same Gambit, rolled with **Evocation** rather than a Cleric's **Invocation**.

| d10 | Effect |
|---|---|
| 1 | **Disaster.** Channel Successes are added or subtracted, whichever is worse for the cleric, to all checks. |
| 2 | **Backfire.** Attack causes a magical explosion. The damage dealt is dealt again to all creatures within 30'. A Charisma check against Channel Successes can reduce the damage taken by half. |
| 3 | **Sympathy.** Both attacker, channeler, and target take the attack's damage in full. Channeler can choose to increase or decrease damage by Channel Successes but must make the same choice for all affected creatures. |
| 4 | **Counter.** The target gets a free weapon attack after this attack resolves with starting successes equal to Channel Successes. |
| 5 | **Wild Deflection.** Attack changes target to a random creature in range instead — channeler picks if ties. |
| 6 | **Reversal.** Attacker and target swap tiers and dice for the attack. |
| 7 | **Surprise.** Target is flatfooted for this attack and all dice spent on defence are lost. Channeler can choose to increase or reduce damage dealt by Channel Successes. |
| 8 | **Naked.** Attacker's sword and target's armor teleport to a random square within 30'. Both gain a Charisma save against Channel Successes to resist. If a weapon teleports, the attack still resolves with a natural attack instead. |
| 9 | **Lucky Break.** All creatures gain a luck bonus or penalty on their roll equal to Channel Successes. |
| 10 | **Crit.** Channel Successes are added or subtracted, whichever is best for the channeler, to all checks. |

### Look up Class

Input: a Class key.

Behavior: Resolve through `creatures_advancement.yaml`'s `Classes:` map. When the entry has `parent_class`, apply the Archetype merge rules described above and return the resolved entry. The resolved entry retains the looked-up key (so `arcane_trickster` is reported as `arcane_trickster`, not `rogue`).

Returns: a Class Catalog Entry (post-merge for Archetypes), or null when the key matches nothing.

### Look up Race

Input: a Race key.

Behavior: Walk the `parent:` chain from the named entry. Apply the *Race Chain Walk* rules to produce a single resolved Race description.

Returns: a resolved Race Entry containing `size`, `speed`, `attribute_adjustments` (the per-attribute accumulated map), and `abilities` (the chain-resolved list, with context entries flattened), plus the original `race_key` that was queried. Returns null when the key matches nothing.

### Get Aggregated Modifiers

Input: Creature ID (or Accessor), optional `target` filter (string).

Behavior: Walk every Granted Ability via Abilities' *Get an Ability's Modifiers*. For each Modifier Entry, evaluate `add` against `{level: Total Level, tier: Tier (0 → 0.5)}`. Build an Aggregated Modifier Entry tagged with the source Ability name. Skip entries with `add = 0`. Filter by `target` when supplied.

Returns: a list of Aggregated Modifier Entries. Order: by Granted Ability order from *Get Granted Abilities*, then by Modifier Entry index within the Ability.

Per-Bonus-Type stacking is the consumer's concern (Combat folds these into Rolls; Conditions may bucket them with its own Active Effects). This entry point does not collapse.

### Get Max Hit Points

Input: Creature ID (or Accessor).

Behavior: Evaluate `HP Formula[tier]` from `creatures_config.yaml` against the Creature's Effective Constitution. Add `hp_bonus` Aggregated Modifier amounts (per-Bonus-Type stacking applied here — see Operations).

Returns: integer ≥ 0.

### Get Max Mana

Input: Creature ID (or Accessor).

Behavior: Evaluate `Mana Base Formula[tier]` from `creatures_advancement.yaml` against the Creature's Effective Intelligence. Add per-Class Mana contributions: each Class Entry contributes `class.mana_per_level × class.level`. Add `mana_bonus` Aggregated Modifier amounts.

Returns: integer ≥ 0.

### Serialization

- **Load Creatures** — accept a dict of `id → Creature Record`. Validate every entry (see *Validation* in Operations). Replace the loaded set.
- **Save Creatures** — produce the same shape.

Creatures does not own when to persist; the consuming project drives that.

## Creature Accessor

The interface returned by *Look up Creature*. Every method reads fresh from the underlying record.

| Method | Returns | Description |
|---|---|---|
| `id` | integer | Creature ID. |
| `name` | string | Display name. |
| `player` | string or null | The Player Name field from the record (null for DM-run Creatures). |
| `group` | string | Group classification. |
| `tags` | list of string | Tags. |
| `race` | string | The Race key stored on the record. The resolved Race chain is accessible via `record` or *Look up Race*. |
| `tier` | integer | Equivalent to *Get Tier*. |
| `total_level` | integer | Sum of Class Levels across the `advancement.classes` map. |
| `class_summary` | list of `(class_key, level)` | One per Class Entry, in stored order. Archetype keys are reported as themselves, not the parent's. |
| `level_for_class(class_key)` | integer | The Class Level the Creature has in the named Class. Zero when the Class is absent. |
| `attribute_value(attr)` | integer | Equivalent to *Get Effective Attributes*`[attr]`. The value Proficiencies and Combat read. |
| `base_attribute_value(attr)` | integer | The raw Base Attribute before Racial Adjustment and Inherent bonuses. UI surfaces consult this for display. |
| `ranks_for(key)` | integer | The Creature's ranks in the given concrete proficiency key. See *Ranks Computation* in Operations. The key must not end in `_`. |
| `rank_sources(key)` | list of `{class_key, level, category, rate, ranks}` | Each Class Entry's part in `ranks_for(key)`; the `ranks` sum to it. `category` is the Proficiency Category the Class gives the key (for a Skill, *Skill Rate Resolution* as if trained). `rate` is the category it advances at: null for a Skill the Class Entry has not trained, which gets no ranks. |
| `has_ability(name)` | boolean | True iff `name` appears in the Granted Abilities list. |
| `level_for_ability(name)` | integer | The level relevant to the granting source — Class Level when granted by a Class (including spells contributed via that Class's `choices.spellcasting` or `choices.deity`/`choices.domain`), the Creature's current Tier when granted by Race. Used by Proficiencies' Floor Ability and similar formulas. Zero when the Creature lacks the Ability. |
| `speed` | integer | Equivalent to *Get Speed*. |
| `max_hit_points` | integer | Equivalent to *Get Max Hit Points*. |
| `max_mana` | integer | Equivalent to *Get Max Mana*. |
| `hit_points_breakdown` | `{tier, formula, vars, base, modifiers, total}` | The parts behind *Get Max Hit Points*: the Tier's `HP Formula` entry, the values it read, its result, and the summed `hp_bonus` Aggregated Modifiers. `total` is `max_hit_points`. |
| `mana_breakdown` | `{tier, formula, vars, base, classes, modifiers, total}` | The parts behind *Get Max Mana*. `classes` lists `{class_key, level, per_level, amount}` for each Class Entry. `total` is `max_mana`. |
| `granted_abilities(source = null)` | list of `{name, source}` | Equivalent to *Get Granted Abilities*. |
| `aggregated_modifiers(target = null)` | list of Aggregated Modifier Entry | Equivalent to *Get Aggregated Modifiers*. |
| `tier_attribute_advancement` | list of attribute keys | The stored flat list of focused-bonus picks. The chunking by Tier is internal to *Effective Attribute Computation*. |
| `record` | Creature Record | Read-only view of the raw record. Stubs use this for display fields Creatures has no opinion on. |

The Accessor never mutates the record. Mutations go through the *Update* entry points below.

### Update entry points

These mutate the underlying Creature Record and persist on Save Creatures.

- **Set Tier Attribute Advancement** — `(creature_id, [attribute keys])`. Replaces the entire flat list wholesale. Validates that every entry is a recognized attribute key. The validator does *not* enforce that the list length matches the Creature's current Tier — a list shorter than that is treated as forgoing trailing picks.
- **Set Tier Override** — `(creature_id, integer or null)`. Writes the Creature's `tier` field.
- **Set Class Level** — `(creature_id, class_key, level)`. Adds the Class Entry to `advancement.classes` when absent. Removing a Class is `level = 0` with a follow-up *Prune Empty Classes*. Rejects when adding a Class would violate Archetype Exclusivity (the Creature already has the parent or one of the named Class's siblings).
- **Set Trained Skills** — `(creature_id, class_key, [skill_keys])`. Replaces the list under that Class Entry's `skills` field.
- **Set Class Choices** — `(creature_id, class_key, choices_dict)`. Replaces the named Class Entry's `choices` map wholesale. Cleric's `{deity: "...", domain: "..."}`, a spellcaster's `{spellcasting: [<spell_name>, ...]}`, Bard's Versatile Performance choice, etc., all route through this. The dict is stored opaquely; Creatures does not validate the keys or values beyond confirming they're a string-keyed dict.

Tier-up triggered by Class Level changes does not auto-fill `tier_attribute_advancement` — that's a UI flow. Until the Creature's user appends entries to the list, the newly-reached Tier's chosen bonuses simply don't apply.

### Spawn Creature From Template

Inputs: `template_id` (integer Creature ID of an existing record), optional `name_override`, optional `loot_table` override.

Behavior:
1. Read the template's Creature Record. Refuse if not found.
2. Allocate a fresh ID — one past the current maximum across every loaded Creature Record (all `creatures_data_*` files combined).
3. Deep-copy the template's fields into a new Creature Record at the new ID. Apply `name_override` and `loot_table` overrides when provided.
4. Add the new record to the dataset.

Returns: the new Creature ID.

The new record is persistent — it lives in the same dataset as PCs and templates and is round-tripped by Save Creatures. Lifecycle management (deletion after combat resolution) is the caller's responsibility. The post-combat loot stub in Equipment is the conventional caller for cleanup via *Delete Creature*.

When the template carries a `race_table`, the spawn rolls it (weighted by `chance`, using the caller-supplied `rng`) to pick a concrete `race`, writes that onto the spawn, and clears the spawn's `race_table`. The consuming project seeds this resolved `race` as a roll variable when rolling the `equipment_table`, so race-aware loadouts can branch with `when: { race: <race> }`. A `class_table` resolves the same way (same `rng`): the chosen entry replaces the spawn's `advancement.classes` with one Class Entry, and the table is cleared.

The spawn deep-copies the template's `equipment_table` (when present). Creatures itself does not roll it — generating the spawn's loadout is the consuming project's job, performed immediately after this call (and after *Roll Random Encounter*): roll the `equipment_table` via Equipment's *Roll Loot Table*, *Add Item* each produced Stack to the spawn, then *Reconcile Loadout*. Equipped rows in the table become the spawn's combat loadout; non-equipped rows (coins, trophies) are carried and collected by *Collect Combat Loot* on death.

### Delete Creature

Inputs: Creature ID.

Behavior: Remove the Creature Record from the dataset. Idempotent — no error if the ID is absent.

Returns: nothing.

Creatures does **not** cascade the delete into other domains. Callers are expected to clean up Conditions state, Equipment inventory owned by `creature:<id>`, and any Combat Combatant pointing at the deleted ID — typically via Equipment's post-combat loot stub, which composes *Collect Combat Loot* + Combat's *Remove Combatant* + *Delete Creature* in sequence.

### Roll Random Encounter

Inputs: Random Encounter Table ID, optional Random Seed (for deterministic testing).

Behavior:
1. Read the Random Encounter Table by ID.
2. Iterate the table's `rolls` in order. For each Random Encounter Row:
   - Evaluate `when` against the current Roll Variables; skip if any pair mismatches.
   - Resolve the Row by its shape (Guaranteed / Independent Chance / Weighted Choice / Gated Weighted Choice).
   - If the Row publishes via `as`, store the resulting `key` in Roll Variables. A skipped Row does not publish.
3. For each Spawn Ref in every resolved row, evaluate `count` (dice expressions roll now) and call *Spawn Creature From Template* that many times with the Ref's overrides. Collect the new Creature IDs in roll order.

Returns: the list of new Creature IDs.

*Roll Random Encounter* does not add the new Creatures to any Combat. The caller follows up with Combat's *Add Combatant* per ID.

### Load Random Encounter Tables / Save Random Encounter Tables

- **Load Random Encounter Tables** — accept a dict of `table_id → Random Encounter Table Entry`. Validate every entry (rows reference real template IDs; `count` parses; `loot_table` overrides reference real tables in Equipment). Replace the loaded set.
- **Save Random Encounter Tables** — produce the same shape.

### Add Random Encounter Table / Remove Random Encounter Table

- **Add Random Encounter Table** — `(table_id, Random Encounter Table Entry)`. Validates and inserts; refuses on duplicate ID.
- **Remove Random Encounter Table** — `(table_id)`. No-op when absent.

## Operations

### Effective Attribute Computation

Reads the Creature Record. For each attribute `a`:

1. `base = attributes[a]`.
2. `racial = racial_adjustment_for(race)[a]` — see *Racial Adjustment Resolution*.
3. `per_tier = Tier Minimum Inherent Bonus[tier]` — read directly from `creatures_config.yaml`'s per-Tier list.
4. `chosen = Per-Tier Inherent Chosen Bonus Amount × count of attribute key a in the slice of `tier_attribute_advancement` consumed by Tiers 2..tier`. The slice is built by walking the Tiers in order, taking `Tier Inherent Chosen Bonus Count[t]` entries from the head of the list for each Tier `t`. Tier 1 grants only the Per-Tier Inherent Bonus, not the Chosen Bonus — the Chosen Bonus begins at Tier 2.
5. `effective = max(1, base + racial + per_tier + chosen)` — every Effective Attribute floors at 1, so racial penalties (notably beasts' -8 Int) never drive a score below 1.

With the default `Tier Minimum Inherent Bonus: [0, 1, 2, 3, 4, 5]`, step 3 produces +0 at Tier 0, +1 at Tier 1, +2 at Tier 2, and so on. Tier 1 is the first Tier with a non-zero Per-Tier Inherent Bonus; Tier 2 is the first Tier with chosen bonus picks (per `Tier Inherent Chosen Bonus Count: [0, 0, 2, 2, 2, 2]`).

### Tier Attribute Advancement Chunking

The `tier_attribute_advancement` list is interpreted Tier-by-Tier. Walking Tiers `t = 2, 3, …, Creature's current Tier`, take `Tier Inherent Chosen Bonus Count[t]` entries from the head of the unconsumed portion of the list. The entries taken on Tier `t` are that Tier's picks.

A list shorter than the cumulative count is allowed and means the trailing Tiers' picks are forgone. A list longer than the cumulative count is also allowed (storing future picks ahead of time); only the chunks up to the Creature's current Tier apply.

### Racial Adjustment Resolution

Resolve the Race chain (root → leaf). Per attribute, sum the contributing entry's `attribute_adjustments[a]` (when present) across every entry in the chain. The `all: N` shorthand on any single entry expands to `+N` on every attribute key the project defines; mixing `all` with per-attribute entries on the same entry is rejected at load time.

### Ranks Computation

Given a proficiency key:

1. **Save key** (`<attr>_save` where `<attr>` is a recognized attribute key, by convention used by callers that build save Rolls): for each Class Entry, the rate is `aligned` if `<attr>` is in the resolved Class's `saves.aligned`, `opposed` if `<attr>` is in `saves.opposed`, otherwise `unaligned` (the medium rate — the rate for a Save Attribute the Class lists in neither set). `ranks = sum over Classes of floor(Class Level × Proficiency Advancement Rates[rate])`. Every Class contributes to every Save Attribute — "every Class trains every Save."
2. **Martial** (literal key `"martial"`): `ranks = sum over Classes of floor(Class Level × Proficiency Advancement Rates[resolved_class.martial_advancement])`. Martial is computed from the Class's `martial_advancement` field, never from `aligned_proficiencies`/`unaligned_proficiencies`/`opposed_proficiencies` — those lists never name `martial`. The `martial` entry in `skills.yaml` exists only to supply the driving attribute (`dex`) for Proficiency Prowess.
3. **Skill key** (any other key): for each Class Entry, run *Skill Rate Resolution* (see below) to obtain a rate of `aligned`, `unaligned`, `opposed`, or null. A null rate means the Creature gains no ranks for that Skill from that Class (untrained-and-not-opposed); the Skill is treated as zero contribution from that Class. `ranks = sum over Classes of floor(Class Level × Proficiency Advancement Rates[rate])` summing only Classes that produced a non-null rate.
4. **Granted-Ability ranks** are not produced here; Abilities don't add ranks, they add Modifiers via `modifiers:`.

The Floor Ability lift is *not* applied here — Proficiencies handles that on top of the ranks Creatures returns. Creatures returns ranks; Proficiencies layers the Floor Ability.

### Skill Rate Resolution

Given a queried Skill key `k` and a resolved Class entry (Archetype-merged when applicable), the rate is determined in this order. A null rate means the Creature gains no ranks from that Class for this Skill.

1. If `k` is not in the Creature's `skills` list for this Class Entry, the rate is null. Untrained Skills accrue no ranks regardless of how the Class categorizes them.
2. Otherwise, if `k` (or `k`'s longest matching Set Skill prefix) appears in the resolved Class's `opposed_proficiencies`, the rate is `opposed`.
3. Otherwise, if the resolved Class effectively declares `aligned_proficiencies` (inclusion form): if `k` (or its prefix) appears in the list, the rate is `aligned`; otherwise `unaligned` (the `Default Skill Rate`).
4. Otherwise, if the resolved Class effectively declares `unaligned_proficiencies` (inverse form): if `k` (or its prefix) appears in the list, the rate is `unaligned`; otherwise `aligned` (the inverse-form default).
5. Otherwise (the resolved Class declares neither inclusion nor inverse form): the rate is `unaligned`.

For an Archetype, the effective proficiency lists are computed per *Archetype* in Common Types: the parent's lists are taken as the baseline and the Archetype's additive adjustments are applied. A Skill the Archetype adds to `aligned_proficiencies` is treated as Aligned even if the parent did not categorize it.

The Set Skill prefix resolution reuses Proficiencies' *Prefix Match* rule: a bare Set Skill key (e.g. `perform_`) in any of the three lists matches every Set Instance (`perform_sing`) the Creature could train.

### Aggregated Modifier Application to Speed

After step 2 of *Get Speed*, the Creature's Aggregated Modifiers with `target = "speed"` apply with per-Bonus-Type stacking: within each Bonus Type, the largest positive amount and the most-negative amount (each appearing only if at least one entry of that sign exists) survive; sum the survivors.

This mirrors Conditions' *Get Modifiers* shape so the consuming project's Modifier handling is uniform across "always-on from Granted Abilities" (Creatures) and "active per-Creature Effects" (Conditions). Combat is the natural consumer when both are needed.

### Max Hit Points and Max Mana Formula Composition

`Max HP = floor(HP Formula[tier])` where `HP Formula` is a per-Tier list of expressions in `creatures_advancement.yaml`. The expressions reference `con` — substituted with the Creature's Effective Constitution at evaluation time. The resulting integer is added to the per-Bonus-Type aggregated `hp_bonus` amount.

`Max Mana = floor(Mana Base Formula[tier]) + sum over Classes of (resolved_class.mana_per_level × class.level) + aggregated mana_bonus`. `Mana Base Formula` is a per-Tier list of expressions in `creatures_advancement.yaml`.

Both formulas accept `+`, `-`, `*`, `/`, `()`, integer literals, and the attribute symbols `str` / `dex` / `con` / `int` / `wis` / `cha` (resolved to the Creature's Effective Attribute). Other symbols are a configuration error.

A Tier beyond the configured `HP Formula` or `Mana Base Formula` array is an error rather than a clamp.

### Tier Attribute Advancement Validation

When *Set Tier Attribute Advancement* is called with list `L`:

- Every entry of `L` must be a recognized attribute key.
- The list length is not strictly bounded — entries beyond the cumulative `Tier Inherent Chosen Bonus Count` summed up to the Creature's current Tier are allowed (they store future picks). Entries past the current Tier's reach simply don't apply yet.

Duplicates within `L` are allowed — picking the same attribute twice doubles the bonus on that Tier-Up.

### Archetype Resolution

Resolve a Class Entry's key against `creatures_advancement.yaml`'s `Classes:` map:

1. If the key matches an entry whose `parent_class` is null, return it verbatim.
2. If the key matches an entry whose `parent_class` is non-null, apply the Archetype merge rules (see *Archetype* in Common Types) against the parent and return the merged entry. The resolved entry retains the looked-up Archetype key.
3. If the key matches nothing, raise a configuration error at load time. Lookups at runtime treat the unknown key as zero contribution and emit a warning.

The Class Entry on the Creature always carries the resolved key — whether top-level Class or Archetype — so reverse lookups (Granted Ability source attribution) name the Archetype when the Creature took the Archetype.

### Archetype Exclusivity

A Creature's `advancement.classes` map must not contain both a Class and one of its Archetypes. The loader inspects every entry: for each key with `parent_class: X`, the map must not also contain key `X`; conversely, for each top-level Class `X` present in the map, the map must not contain any key whose `parent_class` is `X`. Violations are rejected with an Archetype Exclusivity error naming both keys.

Two Archetypes of the same parent may not coexist either — a Creature cannot be both an Arcane Trickster and any other Rogue Archetype simultaneously. The same rule covers that case (the second Archetype's `parent_class` is `rogue`, which collides with the first's parent chain).

### Validation

Every Creature Record is validated at load time:

- `id` is a positive integer, unique across every loaded `creatures_data_*` file.
- `race` resolves to a Race entry in `creatures_race.yaml`. The chain walk terminates (no cycles, root has null `parent`).
- Each `advancement.classes[key]` resolves through *Archetype Resolution*. `level ≥ 0`. `skills` entries do not end in `_`. Set Instances are accepted; the Set Skill prefix is resolved when computing ranks.
- The `advancement.classes` map satisfies *Archetype Exclusivity*.
- A non-Archetype Class Catalog Entry does not declare both `aligned_proficiencies` and `unaligned_proficiencies`. An Archetype Class Catalog Entry may declare any combination — each is an additive adjustment to the parent's effective categorization.
- Every Class Catalog Entry (or its parent, for an Archetype that omits the field) declares `saves.aligned` as a list of recognized attribute keys. Project convention has exactly two entries per Class; the loader does not enforce the count.
- `attributes` has every required attribute key (`str`, `dex`, `con`, `int`, `wis`, `cha`).
- `tier_attribute_advancement` entries are recognized attribute keys. Length is not bounded.
- `tier`, when non-null, is a non-negative integer.
- `choices` entries (notably `choices.spellcasting`) are stored opaquely. Validation that the spell names within resolve in Abilities is deferred to Abilities (warning at load, ignored at runtime).

Malformed records are rejected with a descriptive error naming the file and id; one malformed record does not silently drop other valid records — the loader rejects the whole file.

## Cross-domain interactions

- **Proficiencies.** Creatures provides the Creature Accessor. Proficiencies reads `ranks_for`, `attribute_value`, `has_ability`, `level_for_ability`. Creatures does not call Proficiencies.
- **Combat.** Combat receives a `creature_lookup` callback wired to *Look up Creature* and stores Creature IDs. Combat reads through the Accessor; per-Combatant *Combat Pool* and Initiative dice counts are computed by Combat using the Accessor's `attribute_value` and `ranks_for("martial")`.
- **Conditions.** Conditions stores per-Creature mutable state keyed by Creature ID; Creatures supplies the inputs Conditions' *Dead?* and *Magic Toxicity Update* need (max HP, attribute scores, Tier, Toxicity Threshold Attribute value). Conditions is invoked *by* the consuming project, not by Creatures.
- **Abilities.** Creatures looks up `modifiers:` lists via Abilities' *Get an Ability's Modifiers*. Creatures does not interpret the Modifier `target` keys — they pass through verbatim to consumers.
- **Equipment.** Equipment ties items to Creatures by ID outside the Creature Record. Item-driven attribute or skill bonuses come back as Active Effects through Conditions / Modifier aggregation at the consumer; they do not enter the Creature Record or the Effective Attribute calculation.

## Responsibilities

### Owned by the Creatures domain

- The Creature Record and its persistence shape.
- Tier computation: Total Class Level → tags → Tier Breakpoints → Tier (with the `tier` field as Tier Override).
- Effective Attribute computation: Base + Racial Adjustment chain + Per-Tier Inherent Bonus + Per-Tier Inherent Chosen Bonus (chunked from `tier_attribute_advancement`).
- Tier Attribute Advancement storage and validation.
- Race chain resolution and Granted Ability roll-up.
- Class / Archetype resolution and Granted Ability roll-up, including Archetype Exclusivity enforcement.
- Per-Class `choices` storage (Spellcasting picks, deity/domain, Versatile Performance subject, etc.).
- Ranks Computation for Skill, Save, and Martial keys.
- Speed computation: Race chain base + aggregated Speed Modifiers (Class-driven Speed bonuses come through Granted Ability `modifiers:` entries, not a Class table).
- Max HP and Max Mana formula composition.
- Modifier aggregation: walking Granted Abilities, evaluating `add` Formulas, returning Aggregated Modifier Entries.
- Producing the Creature Accessor consumed by other domains.
- `creatures_advancement.yaml`, `creatures_race.yaml`, `deities.yaml`, and `random_encounter_tables.yaml` catalogs.
- Load-time validation of Creature Records.

### Explicitly *not* owned here

- **Prowess and Dice Cap.** Proficiencies translates ranks to dice counts.
- **HP damage, Mana spent, Active Effects, Active Afflictions.** Conditions owns per-Creature mutable state. Creatures returns max HP and max Mana; current values are computed by Conditions against those maxes.
- **Combat Pool size.** Combat computes from `martial` ranks + Combat Pool Attribute + Turns Per Round[tier].
- **Initiative dice count.** Combat computes from Initiative Attribute + Initiative Divisor.
- **Per-Bonus-Type stacking.** Aggregated Modifiers are returned uncollapsed; consumers (Combat, Conditions) apply stacking.
- **Ability mechanics.** Spells, Talents, Stateful Abilities, Active Effects: Abilities and Conditions own those. Creatures hands names back.
- **Equipment and Currency.** Equipment owns its own state and aggregates by Creature ID.
- **Per-Creature combat state (initiative string, time tick schedule, etc.).** Combat owns those during an active fight.

### Unassigned (no current owner)

- **Languages.** A Creature's spoken / written language list. Useful for Chronicle and stubs but not currently modeled.
- **Encumbrance.** Carry capacity from Strength has no consumer yet; deferred until Equipment lands its weight rules.
- **Aging.** Tier and Level capture mechanical progression; biological aging (chronological age, lifespan) has no design.
- **Heritage events / story facts.** Background narrative belongs in Chronicle when it lands as a richer entity model; Creatures' `metadata` is the temporary home.
- **Companions and minions.** Creatures linked to one another (familiar, animal companion, summoned creature) currently use independent Creature records; a "controlling Creature" relationship is not modeled.
- **Attribute substitution.** Some Races (notably Undead) classically substitute one attribute for another in derived formulas (e.g. Charisma stands in for Constitution in HP calculations). The Race Entry schema does not yet carry a substitution map; until it does, such Creatures must either store the substituted value directly in `attributes` or be handled by a consumer-level shim. A future Race Entry field (e.g. `attribute_substitution: { con: cha }`) would route through *Effective Attribute Computation*.
