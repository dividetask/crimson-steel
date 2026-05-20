# Advancement — Glossary

Computes every level- or tier-derived value the Character delegates: Tier, attribute bonuses, granted abilities, skill / save ranks, HP and mana caps, and class contributions to damage resilience and damage reduction. *(configurable)* values come from `advancement_config.yaml`.

## Tier

(Tier, Tier Override: see common glossary.)

**Tier Advancement Breakpoint List**: A list of class-level thresholds for tiers 1–5, keyed by Character tag in the `tier_advancement` config. A Character is at tier T if their total class levels meet or exceed `breakpoints[T-1]`. *(configurable)*

**Tag-Driven Tier Selection**: When more than one of the Character's tags has a breakpoint list, Advancement takes the **highest** Tier any of them yields. If none match, the fallback is the **slowest** progression among all defined breakpoint lists.

## Attribute Advancement

**Flat Attribute Bonus**: A bonus applied to **every** attribute, accumulated tier-by-tier from `attribute_bonus_per_tier`. Character's flat bonus at tier T is the sum of the first T entries. *(configurable)*

**Focused Attribute Bonus**: A bonus applied to a specific attribute the player picked at tier-up. Each tier from 2 onward grants `focused_attribute_count` picks; magnitude per pick at tier T is `focused_attribute_bonus_per_tier[T-1]`. The same attribute may be picked multiple times across tiers.

**Tier Attribute Advancement**: Flat list on the Character's `advancement` block enumerating every focused-attribute pick. The first `focused_attribute_count` entries are tier 2's picks, the next chunk is tier 3's, etc. May be longer than current Tier so future picks can be slotted in advance.

## Class Levels

**Class**: A discipline the Character has invested levels in. Keyed by string in `advancement_config.yaml`'s `classes:` map.

**Class Level**: The Character's level in a specific Class. Stored under `advancement.classes` in the roster entry; may be a shorthand integer or `{level: N, skills: [...]}` map.

**Total Class Level**: Sum of every Class Level. Drives Tier auto-computation and racial scaling-ability levels.

**Class Definition**: An entry under `classes` defining `name`, `saves`, `bonus_skills`, `class_skills`, `non_class_skills`, `opposed_skills`, `parent_class`, and `abilities`.

**Archetype**: A Class with a `parent_class` field. Levels in an Archetype also count toward the parent Class's abilities and inherit the parent's class-skill list and save list. Optional `min_parent_level` documents the prerequisite.

**Class Chain**: List of a Class's ancestors via `parent_class`, starting with the Class itself. Lookups walk the chain in order; cycles are guarded.

## Skill Categories

**Class Skill**: A skill listed under `class_skills`. Advances at the **fast rate** — `floor(5 * level / 3)`.

**Non-Class Skill**: A skill listed under `non_class_skills`. Advances at the **average rate** — `level`.

**Opposed Skill**: A skill listed under `opposed_skills`. Advances at the **slow rate** — `floor(2 * level / 3)`.

**Default Skill Category**: The category used when none of a Class's explicit lists mention the skill. If the Class declares `class_skills` (even an empty list), unmentioned skills default to **average**; if the Class omits `class_skills` entirely, unmentioned skills default to **class**.

**Chosen Skills**: The list under a Class entry's `skills:` key in the Character's roster entry. Each Class only contributes to Chosen Skills (plus Mandatory Proficiencies).

(Proficiency, Mandatory Proficiency, Prefix Match: see common glossary.)

## Saves

(Save Attribute: see common glossary.)

**Class Save**: A Save Attribute listed under a Class's `saves` field, including any inherited from the Class Chain. Advances at the **fast rate** (`floor(5 * level / 3)`).

**Opposed Save**: Any Save Attribute the Class does **not** include. Advances at the **slow rate** (`floor(2 * level / 3)`). There is no average rate for saves.

## Abilities

(Ability: see common glossary.)

**Scaling Ability**: An Ability with `scales_with_level: true`. Effective level is the **sum** of Character's levels across every Class in the Class Chain that grants the Ability. Non-Scaling Abilities have no level — present or absent.

**Min Level**: Class Level required for the Character to gain an Ability. Defaults to 1.

## HP and Mana

**Max Hit Points**: `floor(tier * attribute(hp_attribute) / hp_divisor)`. Tier comes from the Character (Override authoritative); the attribute is read via `attribute(...)`. Tier 0 yields 0. *(configurable: `hp_attribute`, `hp_divisor`)*

**Max Mana**: `floor(tier * attribute(mana_attribute) / mana_divisor) + sum(class_levels[c] * mana_per_level[c])`. First term is tier × attribute scaling (defaults `int / 2`); second term is a per-class-level grant. *(configurable: `mana_attribute`, `mana_divisor`, per-class `mana_per_level`)*

**Mana Per Level**: Per-class integer field. Archetypes carry their own value rather than inheriting from `parent_class` — what makes the **retroactive mana grant** work when a character takes an archetype.

## Archetype Exclusivity

**Archetype Exclusivity**: A character cannot hold levels in both a parent class and one of its archetypes simultaneously. Once an archetype is taken, all previous parent-class levels are reclassified as the archetype, and the archetype's `mana_per_level` applies to every reclassified level. Validation runs in the Advancement constructor. *(3 sentences — flagged: encodes both the rule, the reclassification semantics, and the retroactive mana grant)*

## Damage Mitigation

**Damage Resilience**: Class-driven contribution from `Advancement#damage_resilience`. Returns 0 today — placeholder. The Character adds its own tier-derived base on top. (See common glossary.)

**Damage Reduction**: Class-driven contribution from `Advancement#damage_reduction`. Returns 0 today — placeholder.

## Module Scope

Owns:
- Loading `advancement_config.yaml` and `skills.yaml`.
- Computing Tier from class levels and tag-keyed breakpoint lists.
- Computing attribute bonuses (flat plus focused).
- Walking the Class Chain to enumerate granted abilities, deduplicating by name and accumulating scaling levels.
- Skill ranks and save ranks per Class plus Chosen Skills.
- Max Hit Points and Max Mana for a Character.

Does not own:
- Identity, base attributes, Tier Override, Ritual List (Character).
- Racial adjustments, racial abilities (Race).
- Per-Character mutable state (conditions, equipment).
- Resolving attacks or applying damage (combat, dice resolution).
