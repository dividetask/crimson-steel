# Advancement — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `advancement_config.yaml`. The Advancement module computes every level- or tier-derived value the Character delegates: Tier itself, attribute bonuses, abilities granted, skill and save ranks, HP and mana caps, and class contributions to damage resilience and damage reduction.

## Tier

**Tier**: A non-negative integer representing the Character's overall progression. Drives attribute bonuses, scaling-ability levels, and the HP / mana formulas. Tier 0 is treated as **0.5** in formulas, per the project-wide convention. Computed by Advancement from total class levels unless the Character supplies an explicit Tier Override.

**Tier Override**: An optional integer set on the Character's entry. Forwarded to Advancement at construction; when present, every Tier query returns it directly without consulting class levels.

**Tier Advancement Breakpoint List**: A list of class-level thresholds for tiers 1 through 5, keyed by Character tag in the `tier_advancement` config. A Character is at tier T if their total class levels meet or exceed `breakpoints[T-1]`. *(configurable)*

**Tag-Driven Tier Selection**: When more than one of the Character's tags has a breakpoint list under `tier_advancement`, Advancement evaluates each list and takes the **highest** Tier any of them yields. If none of the Character's tags has an entry, the fallback is the **slowest** progression among all defined breakpoint lists (the smallest Tier any of them grants for the Character's total levels).

## Attribute Advancement

**Flat Attribute Bonus**: A bonus applied to **every** attribute, accumulated tier-by-tier from `attribute_bonus_per_tier`. The Character's flat bonus at tier T is the sum of the first T entries in that list. *(configurable)*

**Focused Attribute Bonus**: A bonus applied to a specific attribute the player picked at a given tier-up. Each tier from 2 onward grants `focused_attribute_count` picks; the magnitude per pick at tier T is `focused_attribute_bonus_per_tier[T-1]`. The same attribute may be picked multiple times across tiers — each pick adds another bonus of the per-tier magnitude. *(configurable — list, count, and the attribute slate are all driven by config plus the Character's `tier_attribute_advancement` list)*

**Tier Attribute Advancement**: A flat list on the Character's `advancement` block enumerating every focused-attribute pick made (or pre-allocated) across tier-ups. Indexing convention: the first `focused_attribute_count` entries are tier 2's picks, the next chunk is tier 3's, and so on. May be longer than the Character's current Tier so future picks can be slotted in advance.

## Class Levels

**Class**: A discipline the Character has invested levels in. Each Class is keyed by a string in `advancement_config.yaml`'s `classes:` map. *(configurable)*

**Class Level**: The Character's level in a specific Class. Stored under `advancement.classes` in the roster entry; may be expressed as a shorthand integer or a `{level: N, skills: [...]}` map.

**Total Class Level**: The sum of every Class Level. Drives Tier auto-computation and racial scaling-ability levels.

**Class Definition**: An entry under `classes` in the config defining a Class's `name`, `saves`, `bonus_skills`, `class_skills`, `non_class_skills`, `opposed_skills`, `parent_class`, and `abilities` list. *(configurable)*

**Archetype**: A Class with a `parent_class` field. The Character's levels in an Archetype also count toward the parent Class's abilities and inherit the parent's class-skill list and save list. The optional `min_parent_level` field documents the prerequisite level in the parent Class needed to take the Archetype.

**Class Chain**: The list of a Class's ancestors via `parent_class`, starting with the Class itself. Lookups (skill category resolution, save attribute set, ability list) walk the chain in order; cycles are guarded against.

## Skill Categories

**Class Skill**: A skill listed under a Class's `class_skills`. Advances at the **fast rate** — `floor(5 * level / 3)`.

**Non-Class Skill**: A skill listed under `non_class_skills`. Advances at the **average rate** — `level`.

**Opposed Skill**: A skill listed under `opposed_skills`. Advances at the **slow rate** — `floor(2 * level / 3)`.

**Default Skill Category**: The category used when none of a Class's explicit lists mention the skill. If the Class declares `class_skills` (even an empty list), unmentioned skills default to **average**. If the Class omits `class_skills` entirely, unmentioned skills default to **class** — i.e. the Class trains "everything not listed elsewhere" at the fast rate.

**Prefix Match**: A list entry ending with `_` matches any skill that starts with that prefix and has more after the underscore. Example: `perform_` matches `perform_dance` and `perform_song` but not `perform` itself.

**Mandatory Skill**: A skill flagged `mandatory: true` in `skills.yaml`. Every Class contributes ranks to a Mandatory Skill regardless of the Character's chosen-skills list, so a Mandatory Skill (typically `martial`) accumulates from every Class the Character has levels in.

**Chosen Skills**: The list under a Class entry's `skills:` key in the Character's roster entry. Each Class only contributes to Chosen Skills (plus Mandatory Skills) — a skill the Character isn't training under any Class earns no ranks even if every Class would treat it as a Class Skill.

## Saves

**Save Attribute**: One of the six attribute keys (`str`, `dex`, `con`, `int`, `wis`, `cha`).

**Class Save**: A Save Attribute listed under a Class's `saves` field, including any inherited from the Class Chain. The Class advances Class Saves at the **fast rate** (`floor(5 * level / 3)`).

**Opposed Save**: Any Save Attribute the Class does **not** include in its `saves` list. The Class advances Opposed Saves at the **slow rate** (`floor(2 * level / 3)`). There is no average rate for saves — every save attribute is either class or opposed for a given Class.

## Abilities

**Ability**: A named class- or race-granted feature the Character earns at a configured level threshold. Stored in `advancement_config.yaml` under a Class's `abilities:` list.

**Scaling Ability**: An Ability with `scales_with_level: true`. Its effective level is the **sum** of the Character's levels across every Class in the Class Chain that grants the Ability. Non-Scaling Abilities have no level — they're either present or absent.

**Min Level**: The Class Level required for the Character to gain an Ability. Defaults to 1.

**Sticky Min Level**: A `min_level` carried by a context entry in the abilities list — an entry without a `name` field. Every following Ability entry inherits the rolling `min_level` until the next context entry. Other fields are **not** sticky; in particular `scales_with_level` must be set on each Ability entry that needs it.

## HP and Mana

**Max Hit Points**: `floor(tier * attribute(hp_attribute) / hp_divisor)`. Tier comes from the Character (so the Override is authoritative); the attribute is read back through the Character's `attribute(...)` call. Tier 0 yields 0. *(configurable: `hp_attribute`, `hp_divisor`)*

**Max Mana**: `floor(tier * attribute(mana_attribute) / mana_divisor) + sum(class_levels[c] * mana_per_level[c])`. The first term is the tier × attribute scaling shared with HP (defaults: `int / 2`). The second term is a **per-class-level grant**: each level in a class adds the class's `mana_per_level` to the total. Standard `mana_per_level` values: `1` for fighter / barbarian / rogue / ranger, `2` for bard / arcane_trickster, `4` for cleric / druid / wizard. *(configurable: `mana_attribute`, `mana_divisor`, and per-class `mana_per_level`)*

**Mana Per Level**: Per-class integer field. Archetypes carry their own value rather than inheriting from `parent_class` — this is what makes the **retroactive mana grant** work when a character takes an archetype.

## Archetype Exclusivity

**Archetype Exclusivity**: A character cannot hold levels in both a parent class and one of its archetypes simultaneously. Once an archetype is taken, all of the character's previous parent-class levels are reclassified as the archetype. The archetype's `mana_per_level` applies to every reclassified level (the *retroactive mana grant* rule). Validation runs in the Advancement constructor and raises when a character entry has both a parent class and an archetype with positive levels.

## Damage Mitigation

**Damage Resilience**: Class-driven contribution from `Advancement#damage_resilience`. Returns 0 today — placeholder until Class definitions describe how class abilities raise it. The Character adds its own tier-derived base on top.

**Damage Reduction**: Class-driven contribution from `Advancement#damage_reduction`. Returns 0 today, same placeholder rationale.

## Module Scope

The Advancement module computes everything that's a **function of the Character's tier and class levels**. It does not own:

- **Identity, base attributes, the Tier Override, the Ritual List** — Character.
- **Racial adjustments, racial abilities, racial speed/size** — Race.
- **Per-Character mutable state** (current HP, conditions, equipped items, magic toxicity) — conditions and equipment modules.
- **Resolving an attack or applying damage** — combat and dice resolution.

It does **own**:

- Loading `advancement_config.yaml` (rules and class definitions) and `skills.yaml` (skill metadata, including `mandatory` flags).
- Computing Tier from class levels and tag-keyed breakpoint lists.
- Computing attribute bonuses (flat plus focused) for any attribute key.
- Walking the Class Chain to enumerate granted abilities, deduplicating by name and accumulating scaling levels.
- Computing skill ranks and save ranks per Class plus the Character's Chosen Skills.
- Returning Max Hit Points and Max Mana given a Character.
