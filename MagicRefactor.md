# Magic Refactor — Conversation Summary

This document summarizes a design discussion about replacing the
Pathfinder-derived spells currently used by the Crimson Steel PCs with
original Crimson Steel spells. It captures the goals, the new spell
specifications agreed upon so far, the migration plan for PC character
sheets, the infrastructure documents that were created to support the
refactor, and the questions still outstanding.

Related files created or referenced during the discussion:
- [docs/SPELLS.md](docs/SPELLS.md)
- [docs/DAMAGE_TYPES.md](docs/DAMAGE_TYPES.md)
- [docs/CONDITIONS.md](docs/CONDITIONS.md)
- [docs/SPELL_REDESIGN.md](docs/SPELL_REDESIGN.md)

---

## Goals

1. Retire Pathfinder-derived spells currently referenced by the PCs
   and replace them with Crimson Steel originals.
2. Give each new spell multiple tiered versions wherever sensible.
3. Document the spell-system mechanics (range, casting time, schools,
   damage types, conditions, etc.) that were previously implicit in
   the data but not written down.
4. Migrate the four PC character sheets (`data/characters.json`) to
   reference the new spell names, and update the `firebolt` race feat
   on Lysander to `fire_dart`.

---

## PC Spell Inventory at the Start of the Refactor

Dumped from `data/characters.json` at the start of the thread:

- **Stumpy (Cleric)**
  - T0: Stabilize, Sacred Flame, Magic Vestments
  - T1: Cure Lesser Wounds, Healing Word, Command, Lesser Ward,
    Divine Favor, Shield of Faith
  - T2: Magic Weapon, Spiritual Weapon, Hold Person, Silence,
    Blindness/Deafness, Commune, Cure Simple Wounds, Simple Ward,
    Locate Object, Protection from Poison, Standard Surgery
- **Olga (Barbarian):** no spells
- **Lysander (Arcane Trickster)**
  - Spells — T0: Fire Bolt, Message, Silent Portal, Ghost Sound,
    Mage Hand
  - Spells — T1: Hideous Laughter, Illusion of Calm, Auditory
    Hallucination
  - Rituals — T0: Guidance, Resistance, Acid Splash, Drench, Light,
    Spark, Mending, Detect Magic
  - Rituals — T1: Alarm, Endure Elements, Mount, Charm Person, Ant
    Haul, Disguise Self, Obscuring Mist, Minor Recharge
  - Rituals — T2: Silent Image, Disguise Other, Invisibility, Basic
    Recharge
- **Cottonballs (Bard)**
  - T0: Detect Magic, Friends, Ghost Sound, Sift, Stabilize,
    Vacuous Vessel, Vicious Mockery
  - T1: Biting Words, Ears of the City, Silent Image, Timely
    Inspiration

---

## Infrastructure Docs Created

Before adding new spell entries, three supporting documents were
created so that the building-block concepts the spells depend on are
written down somewhere rather than living only in the data.

### `docs/SPELLS.md`

Defines the spell-entry format used by `data/compendium.json` and the
shared reference tables:

- **Tier convention:** Tier 0 is treated as 0.5 in all formulas.
- **Range table:** 0 = personal, 1 = touch, 2 = close, 3 = medium,
  4 = long. *(Exact distances in feet are TBD.)*
- **Casting time table:** 0 = free action, 0.25 = bonus action,
  0.5 = main action, 1+ = that many rounds.
- **Save values:** `0` (none) or one of `str` / `dex` / `con` / `int`
  / `wis` / `cha` (never "will save" or "reflex save").
- **Properties:** `concentration` and room for more as needed.
- **Area format:** an `area` field on the spell entry with
  `{ "shape": ..., "size": ... }`. Shapes currently defined: `cone`
  (length in feet from caster or target square) and `radius` (radius
  in feet around target square).
- **Magic schools** (bodies TBD): `universal`, `resonance`,
  `pneumancy`, `convergence`, `transmutation`, `enchantment`,
  `augury`.
- **Items:** `potion`, `oil`, `scroll`, `wand`.
- **Spells vs. rituals:** same compendium entry; a character casts
  it as a spell (main-action speed) or as a ritual (several minutes)
  depending on which list the entry is in on their sheet.
- **Saturation conventions:** `minimum_saturation` and `saturation`
  keys in `effect_hash`, used by spells that impose magic toxicity.

### `docs/DAMAGE_TYPES.md`

Defines damage categories and the five magical damage types.

- **Damage categories:** minor / moderate / major.
- **Physical types:** bludgeoning, slashing, piercing (cross-referenced
  to `data/rules.json`).
- **Magical types and their properties:**
  - **Radiant** — damage dealt to undead is upgraded to major damage.
  - **Fire** — each hit deals +1 damage (per hit, not per die or
    target).
  - **Acid** — damage carries over: at the start of the creature's
    turn it takes `floor(previous / 2)` acid damage; multiple acid
    sources in a turn are summed before computing next turn's
    residual.
  - **Electricity** — bonus successes equal to the target's damage
    reduction from metal armor.
  - **Cold** — inflicts shock equal to the damage dealt.
- **Metal armor:** placeholder rule that all medium and heavy armor
  counts as metal, pending a per-armor classification in
  `data/rules.json`.

### `docs/CONDITIONS.md`

Defines persistent conditions that spells reference.

- **Bleeding** — ongoing per-round damage reduced by Heal; stacks
  across sources.
- **Shock** — reduces available combat dice; excess lingers across
  turns until cleared.
- **Magic toxicity (= magic saturation; the two terms refer to the
  same mechanic)** — per-spell accumulation via
  `minimum_saturation` / `saturation`, with resistance and recovery
  defined in `data/rules.json` (`advancement.natural.sat_resist`,
  `sat_recovery`). Thresholds and penalty effects are TBD.
- Stubs for exhaustion, confusion, insanity, fatigue, sickened,
  paralysis, fear, blindness/deafness, charmed, stunned, helpless,
  and staggered — to be fleshed out later as needed.

---

## New Spell Specifications Agreed So Far

All specifications below are also captured in
[docs/SPELL_REDESIGN.md](docs/SPELL_REDESIGN.md).

### Heal — replaces Stabilize and the Cure family

- Single compendium entry named `Heal` with a `suffix` list indexed
  by tier.
- Tiers 0–5 with suffixes: Petty Wounds, Lesser Wounds, Simple Wounds,
  Moderate Wounds, Advanced Wounds, Extreme Wounds.
- School `pneumancy`, save `cha`, casting time 0.5, duration
  concentration.
- Effect hash:
  - `minor_damage: [1, 4, 8, 16, 32, 64]`
  - `moderate_damage: [0, 2, 4, 8, 16, 32]`
  - `major_damage: [0, 0, 0, 1, 2, 4]`
  - `bleeding: "-tier*2*success"` — tier 0 → 1 bleed/success via the
    0.5 rule (intentionally weaker than legacy Stabilize).
  - `minimum_saturation: "tier*2"`, `saturation: "tier*5"`
- Tier 0 (Heal Petty Wounds) is intentionally weaker than the old
  Cure tier 0 on both minor and moderate values.
- Initial cast heals damage and applies magic toxicity once. Each
  subsequent concentration round reduces bleeding only — no more
  healing, no more toxicity.
- Range, items, and skills are still TBD (presumed to match the
  legacy Cure values: range 1, items potion/scroll/wand, skills
  healing/nature/perform_).

### Elemental Damage Families — Radiant / Fire / Acid / Static / Frost

Five families share a common four-tier structure. Each family is a
single compendium entry with a `suffix` list.

| Tier | Suffix  | Targeting                                   | Range         | Save  | Damage rule |
|------|---------|---------------------------------------------|---------------|-------|-------------|
| 0    | Dart    | Ranged attack vs. single target.            | 2 (close)     | 0     | caster hits − defender dodges = damage |
| 1    | Breath  | 15 ft cone from caster.                     | 0 (personal)  | `dex` | caster successes − defender save successes = damage |
| 2    | Burst   | 5 ft radius around target square.           | 3 (medium)    | `dex` | caster successes − defender save successes = damage |
| 3    | Bomb    | 15 ft radius around target square.          | 3 (medium)    | `dex` | each caster success = 2 damage; each defender save success cancels 2 |

All tiers are concentration with a 4-dice minimum per turn (matching
legacy Fire Bolt).

Per-family values:

| Family  | Damage type | Skills              |
|---------|-------------|---------------------|
| Radiant | radiant     | `healing`, `nature` |
| Fire    | fire        | `arcana`            |
| Acid    | acid        | `arcana`            |
| Static  | electricity | `arcana`, `nature`  |
| Frost   | cold        | `arcana`            |

Schools and `items` lists for each family are still TBD.

Damage-type properties (radiant-vs-undead, fire +1, acid carryover,
electricity metal-DR successes, cold → shock) live in
`docs/DAMAGE_TYPES.md`.

### Magic Vestments — replaces the existing entry

- Single compendium entry with per-tier names:
  - T0: Fleeting Magic Vestments — duration 1 round
  - T1: Temporary Magic Vestments — 1 round per rank
  - T2: Magic Vestments — 1 minute per rank
  - T3: Extended Magic Vestments — 1 hour per rank
- School `resonance`, save 0, range 2, casting time 0.25 (bonus
  action), not concentration.
- Items: `oil`, `scroll`, `wand`.
- Effect: grants the target the benefits of medium armor (no
  penalties) for the duration. No effect if the target is already in
  medium or heavy armor; upgrades light or no armor to medium-armor
  defense.
- Skills list is still TBD (legacy entry used `healing` and
  `perform_`).

### Detect Magic — replaces the existing entry

- Single compendium entry with per-tier names:
  - T0: Detect Overt Magic — detects magical auras after 1 minute
    of sustained concentration.
  - T1: Detect Stationary Magic — reveals stationary auras with no
    focus requirement; moving auras remain hidden.
  - T2: Detect Magic Signatures — identifies the caster of a spell
    (within 1 day) or the maker of a magic item.
  - T3: See Magic — reveals all auras including moving; identifies
    signatures up to 1 week after casting/creation; not
    concentration; 1 minute per rank.
- School `augury`, save 0, range 0, casting time 2, duration
  concentration up to 1 minute per rank (tier 3 drops the
  concentration).
- Items: `scroll`, `wand`.
- Skills: `arcana`, `healing`, `nature`, `perform_`.
- The entry-format question — how to represent tier 0's "Detect
  Overt Magic" when `prefix` / `suffix` don't naturally compose with
  a base name — is an open item.

---

## Character-Sheet Migration Plan

The following renames are pending and should be applied together to
`data/characters.json` and `data/compendium.json`:

| Character   | Location               | From                 | To                     |
|-------------|------------------------|----------------------|------------------------|
| Stumpy      | spells (T0)            | Stabilize            | Heal Petty Wounds      |
| Stumpy      | spells (T0)            | Sacred Flame         | Radiant Dart           |
| Stumpy      | spells (T1)            | Cure Lesser Wounds   | Heal Lesser Wounds     |
| Stumpy      | spells (T2)            | Cure Simple Wounds   | Heal Simple Wounds     |
| Lysander    | spells (T0)            | Fire Bolt            | Fire Dart              |
| Lysander    | rituals (T0)           | Acid Splash          | Acid Dart              |
| Lysander    | rituals (T0)           | Detect Magic         | Detect Overt Magic     |
| Lysander    | feats.race             | `firebolt`           | `fire_dart`            |
| Cottonballs | spells (T0)            | Stabilize            | Heal Petty Wounds      |
| Cottonballs | spells (T0)            | Detect Magic         | Detect Overt Magic     |
| Cottonballs | classes[].spells (T0)  | `stabilize`          | `heal_petty_wounds`    |
| Cottonballs | classes[].spells (T0)  | `detect_magic`       | `detect_overt_magic`   |

---

## Remaining Spells Not Yet Redesigned

The following PC spells are still on legacy Pathfinder names and need
Crimson Steel replacements in future passes:

**Stumpy:** Healing Word, Command, Lesser Ward, Divine Favor, Shield
of Faith, Magic Weapon, Spiritual Weapon, Hold Person, Silence,
Blindness/Deafness, Commune, Simple Ward, Locate Object, Protection
from Poison, Standard Surgery.

**Lysander:** Message, Silent Portal, Ghost Sound, Mage Hand, Hideous
Laughter, Illusion of Calm, Auditory Hallucination, Guidance,
Resistance, Drench, Light, Spark, Mending, Alarm, Endure Elements,
Mount, Charm Person, Ant Haul, Disguise Self, Obscuring Mist, Minor
Recharge, Silent Image, Disguise Other, Invisibility, Basic Recharge.

**Cottonballs:** Friends, Ghost Sound, Sift, Vacuous Vessel, Vicious
Mockery, Biting Words, Ears of the City, Silent Image, Timely
Inspiration.

---

## Open Questions

1. Exact distances in feet for each `range` value.
2. Confirm the minimum-dice-per-turn rule (currently inherited as 4
   from legacy Fire Bolt) applies to every concentration damage
   spell.
3. Magic-toxicity thresholds, penalties, and consequences.
4. Formal definitions for each magic school.
5. Per-armor metal classification (to replace the placeholder "all
   medium and heavy armor is metal").
6. Per-spell TBDs:
   - Heal: range, items, skills.
   - Elemental damage families: school, items.
   - Magic Vestments: skills.
   - Detect Magic: compendium-entry format for per-tier names that do
     not compose as a clean prefix/suffix around a base name.
7. Whether Detect Magic T2 includes T1's ability (see stationary
   auras), and whether each tier is a strict superset of the lower
   tier.
8. Audit of every file that references the legacy spell keys —
   `data/classes.json`, `data/store.json`,
   `data/template-potions.json`, `data/rules.json`, `data/notes.json`,
   `data/compendium.json` — to ensure renames are complete.
