# Crimson Steel Online — Spell Redesign (Work In Progress)

This document tracks the ongoing replacement of legacy Pathfinder-derived
spells with Crimson Steel spells. Each spell below has been discussed
with the DM and recorded here in enough detail to be translated into
`data/compendium.json` entries once the design is complete.

Open questions are called out explicitly at the end of each spell and in
a consolidated list at the bottom of this document.

Related documents:
- [SPELLS.md](SPELLS.md) — spell-entry format, range, casting time,
  saves, schools, properties, area, effect_hash, items
- [DAMAGE_TYPES.md](DAMAGE_TYPES.md) — damage categories and magical
  damage-type properties
- [CONDITIONS.md](CONDITIONS.md) — bleeding, shock, magic toxicity

---

## Scope

1. Replace the `Stabilize` and `Cure` spell family with a new unified
   `Heal` spell family.
2. Replace `Sacred Flame`, `Fire Bolt`, and `Acid Splash` (and add
   `Static` and `Frost` equivalents) with five elemental damage spell
   families that share a common structure.
3. Replace `Magic Vestments` with a four-tier version.
4. Replace `Detect Magic` with a four-tier version.
5. Update PC character sheets to reference the new spell names, and
   rename the `firebolt` race feat on Lysander to `fire_dart`.

Additional spells will be defined in later passes; their entries will
be appended to this document as they are specified.

---

## Heal (replaces Stabilize and the Cure family)

- **Compendium structure:** single entry named `Heal` with a `suffix`
  list indexed by tier.
- **Tiers:** 0–5
- **Suffixes (indexed by tier):**
  - 0: Petty Wounds
  - 1: Lesser Wounds
  - 2: Simple Wounds
  - 3: Moderate Wounds
  - 4: Advanced Wounds
  - 5: Extreme Wounds
- **School:** pneumancy
- **Save:** `cha`
- **Range:** 1 (touch) — **TBD: confirm; current Cure uses 1.**
- **Casting time:** 0.5 (main action)
- **Duration:** concentration
- **Properties:** `concentration`
- **Items:** `potion`, `scroll`, `wand` — **TBD: confirm; current Cure
  uses these.**
- **Skills:** `healing`, `nature`, `perform_` — **TBD: confirm; current
  Cure uses these.**
- **Effect hash:**
  - `minor_damage: [1, 4, 8, 16, 32, 64]` *(tier 0 is 1, not 2 — this is
    an intentional nerf relative to the old Cure tier 0 which healed 2
    minor)*
  - `moderate_damage: [0, 2, 4, 8, 16, 32]` *(tier 0 is 0, not 1 —
    intentional nerf)*
  - `major_damage: [0, 0, 0, 1, 2, 4]`
  - `bleeding: "-tier*2*success"` *(tier 0 is treated as 0.5, so tier 0
    reduces bleeding by 1 per success — less effective than the old
    Stabilize, which reduced bleeding by 3 per success)*
  - `minimum_saturation: "tier*2"`
  - `saturation: "tier*5"`
- **Rules:**
  - On the initial cast, the target is healed according to the damage
    amounts above and magic toxicity is applied.
  - While concentrating on later turns, the spell continues to reduce
    bleeding (using the same `-tier*2*success` formula each round) but
    does **not** apply additional healing and does **not** apply
    additional magic toxicity.

### Heal — Open Questions

- Confirm `range`, `items`, `skills` match legacy Cure.

---

## Elemental Damage Spell Families

Five spell families share a common structure. Each family is a single
compendium entry with a `suffix` list of four entries:

| Tier | Suffix  | Targeting                                         | Range | Save         | Damage rule |
|------|---------|---------------------------------------------------|-------|--------------|-------------|
| 0    | Dart    | Ranged attack vs. a single target.                | 2 (close)  | 0 (none) | Caster's attack successes − defender's attack successes = damage. |
| 1    | Breath  | Area, 15 ft cone originating from the caster.     | 0 (personal) | `dex`   | Caster's successes − defender's Dexterity save successes = damage (per target). |
| 2    | Burst   | Area, 5 ft radius around target square.           | 3 (medium) | `dex`   | Caster's successes − defender's Dexterity save successes = damage (per target). |
| 3    | Bomb    | Area, 15 ft radius around target square.          | 3 (medium) | `dex`   | Each caster success counts as **2 damage**; each defender save success cancels **2 damage**. |

Each damage entry is cast as a main action (`casting_time: 0.5`) and has
the `concentration` property. On the casting turn and each subsequent
concentration turn, the caster must spend at least **4 dice**. Spending
more dice produces more potential successes and therefore more damage
(the ranged attack in the Dart case, or the damage roll in the area
cases).

Five families, identical structure except for the damage type and
skill list:

| Family  | Damage type | Skills                | School        |
|---------|-------------|-----------------------|---------------|
| Radiant | radiant     | `healing`, `nature`   | **TBD**       |
| Fire    | fire        | `arcana`              | **TBD**       |
| Acid    | acid        | `arcana`              | **TBD**       |
| Static  | electricity | `arcana`, `nature`    | **TBD**       |
| Frost   | cold        | `arcana`              | **TBD**       |

- **Area entries:**
  - Breath: `{ "shape": "cone", "size": 15 }`
  - Burst: `{ "shape": "radius", "size": 5 }`
  - Bomb: `{ "shape": "radius", "size": 15 }`
- **Duration:** `concentration`
- **Items:** **TBD**

Damage-type properties (radiant upgrades vs. undead, fire +1/hit, acid
half-carryover, electricity bonus successes from metal-armor DR, cold
inflicts shock equal to damage) are documented in
[DAMAGE_TYPES.md](DAMAGE_TYPES.md).

### Elemental Damage — Open Questions

- Confirm `school` for each family (the legacy cantrips used `resonance`).
- Confirm `items` list.
- Confirm minimum-dice-per-turn is 4 across all five families and all
  four tiers.
- Does the concentration continuation spend dice again (as with the
  legacy Fire Bolt) for every family and tier?

---

## Magic Vestments (replaces the existing Magic Vestments)

- **Compendium structure:** single entry with a `prefix` list indexed
  by tier.
- **Tiers:** 0–3
- **Names (indexed by tier):**
  - 0: Fleeting Magic Vestments
  - 1: Temporary Magic Vestments
  - 2: Magic Vestments
  - 3: Extended Magic Vestments
- **School:** resonance
- **Save:** 0 (none)
- **Range:** 2 (close)
- **Casting time:** 0.25 (bonus action)
- **Duration (by tier):**
  - 0: 1 round
  - 1: 1 round per rank
  - 2: 1 minute per rank
  - 3: 1 hour per rank
- **Items:** `oil`, `scroll`, `wand`
- **Skills:** **TBD** (current entry uses `healing`, `perform_`)
- **Properties:** none (not concentration)
- **Effect:**
  - Takes ordinary clothing and grants the target the defensive
    benefits of **medium armor** for the duration.
  - No effect on a target already wearing medium or heavy armor.
  - On a target wearing light armor or no armor, grants the benefits of
    medium armor without medium-armor penalties (speed, stealth, etc.).

### Magic Vestments — Open Questions

- Confirm `skills` list.

---

## Detect Magic (replaces the existing Detect Magic)

- **Compendium structure:** single entry with per-tier names (the
  format for this is TBD — see Open Questions).
- **Tiers:** 0–3
- **Names (indexed by tier):**
  - 0: Detect Overt Magic
  - 1: Detect Stationary Magic
  - 2: Detect Magic Signatures
  - 3: See Magic
- **School:** augury
- **Save:** 0 (none)
- **Range:** 0 (personal)
- **Casting time:** 2 (2 rounds)
- **Duration:** concentration, up to 1 minute per rank
  *(tier 3 is not concentration and lasts 1 minute per rank outright —
  see per-tier effects below)*
- **Items:** `scroll`, `wand`
- **Skills:** `arcana`, `healing`, `nature`, `perform_`
- **Properties:** `concentration` (for tiers 0–2)
- **Per-tier effect:**
  - **T0 — Detect Overt Magic:** Detects magical auras. Requires 1
    minute of sustained concentration to yield any information.
  - **T1 — Detect Stationary Magic:** Reveals stationary magical auras
    without the 1-minute focus requirement. Moving auras cannot be
    seen.
  - **T2 — Detect Magic Signatures:** Identifies the caster of a spell
    cast up to 1 day prior; identifies the maker of a magic item.
  - **T3 — See Magic:** Reveals all magical auras, including moving
    auras. Identifies magical signatures up to 1 week after the spell
    was cast or the item was made. Not a concentration spell; duration
    1 minute per rank.

### Detect Magic — Open Questions

- Tier 0's name "Detect Overt Magic" does not fit a clean
  prefix/suffix pattern around a base "Detect Magic" string. Decide
  whether to:
  1. Store each tier's name as a literal in a new `name` list field;
  2. Extend the entry schema with an `infix` field; or
  3. Store each tier as a separate compendium entry.
- Does T2 include T1's ability (see stationary auras), or only
  signatures?
- Is each tier strictly a superset of the lower tier? The T3 spec
  mentions seeing all auras and reading signatures up to a week, but
  does not explicitly restate the T0 1-minute-of-focus detection or
  the T1 stationary-auras reveal.

---

## Character-Sheet Migration

Rename the following entries in `data/characters.json`:

| Character   | Location        | From                 | To                     |
|-------------|-----------------|----------------------|------------------------|
| Stumpy      | spells (T0)     | Stabilize            | Heal Petty Wounds      |
| Stumpy      | spells (T0)     | Sacred Flame         | Radiant Dart           |
| Stumpy      | spells (T1)     | Cure Lesser Wounds   | Heal Lesser Wounds     |
| Stumpy      | spells (T2)     | Cure Simple Wounds   | Heal Simple Wounds     |
| Lysander    | spells (T0)     | Fire Bolt            | Fire Dart              |
| Lysander    | rituals (T0)    | Acid Splash          | Acid Dart              |
| Lysander    | rituals (T0)    | Detect Magic         | Detect Overt Magic     |
| Lysander    | feats.race      | `firebolt`           | `fire_dart`            |
| Cottonballs | spells (T0)     | Stabilize            | Heal Petty Wounds      |
| Cottonballs | spells (T0)     | Detect Magic         | Detect Overt Magic     |
| Cottonballs | classes[].spells (T0) | `stabilize`    | `heal_petty_wounds`    |
| Cottonballs | classes[].spells (T0) | `detect_magic` | `detect_overt_magic`   |

Additionally, every spell/ritual migration must be mirrored in
`data/compendium.json` by replacing the old spell entries with the new
ones, and any other file that references the old spell keys (see
"Open Questions" below for the audit list).

---

## Remaining Spells Not Yet Redesigned

The following spells across the PCs' sheets still need Crimson Steel
replacements:

**Stumpy:**
- T0: Magic Vestments *(now specified above)*
- T1: Healing Word, Command, Lesser Ward, Divine Favor, Shield of Faith
- T2: Magic Weapon, Spiritual Weapon, Hold Person, Silence,
  Blindness/Deafness, Commune, Simple Ward, Locate Object, Protection
  from Poison, Standard Surgery

**Lysander:**
- Spells T0: Message, Silent Portal, Ghost Sound, Mage Hand
- Spells T1: Hideous Laughter, Illusion of Calm, Auditory Hallucination
- Rituals T0: Guidance, Resistance, Drench, Light, Spark, Mending
  *(Detect Magic now specified above)*
- Rituals T1: Alarm, Endure Elements, Mount, Charm Person, Ant Haul,
  Disguise Self, Obscuring Mist, Minor Recharge
- Rituals T2: Silent Image, Disguise Other, Invisibility, Basic Recharge

**Cottonballs:**
- T0: Friends, Ghost Sound, Sift, Vacuous Vessel, Vicious Mockery
  *(Detect Magic now specified above)*
- T1: Biting Words, Ears of the City, Silent Image, Timely Inspiration

---

## Global Open Questions

1. Exact distances in feet for each `range` value (personal / touch /
   close / medium / long). Proposed location: `data/rules.json`.
2. Minimum-dice-per-turn rule for concentration damage spells — is the
   legacy "4 dice minimum" (from Fire Bolt) universal across all
   concentration spells, or per-spell?
3. Magic toxicity thresholds, penalties, and consequences — currently
   only the accumulation formulas are defined per spell.
4. Formal definitions for each magic school (`universal`, `resonance`,
   `pneumancy`, `convergence`, `transmutation`, `enchantment`,
   `augury`).
5. Per-armor metal/non-metal classification (currently a blanket rule
   of "all medium and heavy armor is metal"); target location in
   `data/rules.json`.
6. Audit of every file that references the legacy spell keys — at
   minimum `data/classes.json`, `data/store.json`,
   `data/template-potions.json`, `data/rules.json`, `data/notes.json`,
   `data/compendium.json` — to ensure renames are complete.
7. Compendium-entry format extension to support tier-indexed full
   names that are not clean prefix/suffix variants (needed for Detect
   Magic).
