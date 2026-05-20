# Crimson Steel Online — Spells

This document defines spell mechanics, the spell-entry format used in
`data/compendium.json`, and the shared reference tables for range, casting
time, save, school, properties, and area.

Related documents:
- [DEFINITIONS.md](DEFINITIONS.md) — core game terms
- [SKILLS.md](SKILLS.md) — skill mechanics
- [DAMAGE_TYPES.md](DAMAGE_TYPES.md) — damage categories and types
- [CONDITIONS.md](CONDITIONS.md) — conditions referenced by spells

## Spells vs. Rituals

Spells and rituals share the same compendium entries. Whether a creature
casts an entry as a spell or a ritual depends on which list the entry
appears in on that character's sheet:

- **Spell** — cast as a main action (or whatever the entry's `casting_time`
  specifies).
- **Ritual** — the same entry cast over several minutes, typically out of
  combat. A creature that has an entry in their `rituals` list pays the
  longer casting time but does not need a main action.

## Tier

Each spell has one or more tiers. Tier 0 is treated as **0.5** in all
formulas (per the project-wide tier convention).

A spell entry's `tier` field is either a single integer or a list of
integers. When it is a list, the spell has multiple variants distinguished
by the `prefix` and/or `suffix` fields, which align by index with the tier
list.

## Range

The `range` field is an integer that maps to the table below.

| Value | Name     | Description                                   |
|-------|----------|-----------------------------------------------|
| 0     | Personal | The caster (or a point centered on them).     |
| 1     | Touch    | A target the caster can touch.                |
| 2     | Close    | A target within short distance.               |
| 3     | Medium   | A target within medium distance.              |
| 4     | Long     | A target within long distance.                |

Exact distances in feet are TBD and should be added to `data/rules.json`
when finalized.

## Casting Time

The `casting_time` field is a number representing how long the spell takes
to cast. Values smaller than 1 represent fractions of a turn; values of 1
or greater represent full rounds.

| Value | Meaning      |
|-------|--------------|
| 0     | Free action  |
| 0.25  | Bonus action |
| 0.5   | Main action  |
| 1     | 1 round      |
| 2     | 2 rounds     |
| 3     | 3 rounds     |
| N     | N rounds     |

For ritual casting, longer values such as `60` (1 hour) and `3600` (1 day)
may also appear.

## Save

The `save` field indicates the saving throw a target makes to resist or
reduce a spell's effect.

| Value   | Meaning                                       |
|---------|-----------------------------------------------|
| `0`     | No save.                                      |
| `"str"` | Strength save.                                |
| `"dex"` | Dexterity save.                               |
| `"con"` | Constitution save.                            |
| `"int"` | Intelligence save.                            |
| `"wis"` | Wisdom save.                                  |
| `"cha"` | Charisma save.                                |

Always use the attribute name. Never use legacy terms like "will save" or
"reflex save" — these have been replaced by "Wisdom save" and "Dexterity
save" respectively.

## Properties

The `properties` field is a list of property keywords that modify how the
spell behaves.

| Property        | Meaning                                                    |
|-----------------|------------------------------------------------------------|
| `concentration` | Effect persists only while the caster concentrates. The caster may spend additional dice on subsequent turns to extend or reapply the spell's effect. |

Additional property keywords may be added as new spells require them.

## Area

When a spell affects an area instead of (or in addition to) a single
target, its area is described by an `area` field on the spell entry. The
`area` field is an object with a shape and a size.

| Shape      | Size meaning                                             |
|------------|----------------------------------------------------------|
| `cone`     | Cone length in feet, originating from the caster or target square. |
| `radius`   | Radius in feet around the target square.                 |

Example:

```json
"area": { "shape": "cone", "size": 15 }
"area": { "shape": "radius", "size": 5 }
```

## Magic School

The `school` field categorizes spells by their magical discipline.

| School         | Notes                              |
|----------------|------------------------------------|
| `universal`    | Available to all casters.          |
| `resonance`    | TBD                                |
| `pneumancy`    | TBD                                |
| `convergence`  | TBD                                |
| `transmutation`| TBD                                |
| `enchantment`  | TBD                                |
| `augury`       | TBD                                |

School descriptions and their interactions are TBD and should be added
here as the system is finalized.

## Skill

The `skill` field is a list of skills that may be used to cast the spell.
The caster picks one of the listed skills when casting; that skill's
ranks and attribute modifier determine the spell's effectiveness. See
[SKILLS.md](SKILLS.md).

## Items

The `items` field lists which item forms a spell may be packaged into:

| Item     | Description                                                  |
|----------|--------------------------------------------------------------|
| `potion` | Drinkable; consumed on use.                                  |
| `oil`    | Applied to an object or surface; consumed on use.            |
| `scroll` | Read aloud; consumed on use.                                 |
| `wand`   | Reusable; carries a number of charges.                       |

An empty list means the spell cannot be packaged.

## Effect Hash

The `effect_hash` field is a map of named values used by the spell's
description. Values may be:

- A literal number or string.
- A list, indexed by tier (or by tier index when the spell has multiple
  tiers).
- A formula string (e.g. `"tier*2"`, `"-1*success"`). Formulas are
  evaluated with the casting context, where `tier` is the spell's tier
  (with tier 0 treated as 0.5) and `success` is the net successes rolled.

Names referenced in the description by `{name}` are substituted from the
effect hash at display time.

## Spell Entry Format

Each spell entry in `data/compendium.json` follows this structure:

```json
"Spell Name": {
  "tier": 0,                  // integer or [list of integers]
  "save": 0,                  // 0 or save attribute key
  "school": "resonance",
  "items": ["potion", "scroll", "wand"],
  "range": 2,                 // see Range table
  "duration": "instant",      // free-form; common values: "instant",
                              // "concentration", "rank", "rank*10",
                              // "1 round", "1 hour/level", "permanent"
  "casting_time": 0.5,        // see Casting Time table
  "skill": ["arcana"],
  "properties": [],
  "effect_hash": {},
  "area": { "shape": "cone", "size": 15 },  // optional
  "prefix": [null, "Greater"],              // optional, indexed by tier
  "suffix": ["Dart", "Breath", "Burst"],    // optional, indexed by tier
  "description": "..."
}
```

When `tier` is a list, `prefix` and/or `suffix` lists must align with it
by index. The displayed name is constructed as
`<prefix> <Spell Name> <suffix>` (omitting any null/empty parts).

## Saturation (Magic Toxicity)

Some spells impose **magic toxicity** on the target (also called
**magic saturation** — the two terms refer to the same mechanic). See
[CONDITIONS.md](CONDITIONS.md) for how saturation accumulates and is
recovered.

Spells that apply saturation use the following conventional fields in
their `effect_hash`:

- `minimum_saturation` — the minimum saturation applied per cast.
- `saturation` — the default saturation applied per cast.

Both are typically expressed as formulas of `tier`.
