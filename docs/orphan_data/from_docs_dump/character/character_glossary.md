# Character — Glossary

Coordinator module: owns identity and base attributes; routes everything else to Race, Advancement, and (future) Skills, Combat, Conditions, Inventory, EffectsState. External callers go through Character rather than reaching into components directly.

## Identity

**Character**: A single playable or non-playable creature. Owns identity, base attributes, and references to its Race and Advancement.

**ID**: A unique non-reused integer identifier. Persists across renames; used by combat logs and external links.

**Name**: Displayed Character name. Free-form string.

**Player**: The player running the Character. Free-form; may be empty for NPCs and monsters.

**Tags**: Free-form labels classifying the Character. Defaults to `['player_character']`. Tags drive Tier auto-computation (see `advancement_glossary.md`'s **Tier Advancement Breakpoint List**); descriptive tags without a breakpoint list (`NPC`, `Ally`, `Enemy`) carry no mechanical effect.

**Ritual List**: A list of lists indexed by tier — `ritual_list[T]` is the tier-T ritual names the Character knows. Pure data.

## Attributes

**Base Attribute**: One of the six raw scores the Character owns directly: `str`, `dex`, `con`, `int`, `wis`, `cha`. Integers; missing keys default to 0.

**Effective Attribute**: `Character#attribute(key)` = `base + Advancement#attribute_bonus(key) + Race#adjustment_for(key)`.

## Tier

(Tier, Tier Override: see common glossary.)

## Derived Reads (delegated)

Every method routes to a component; Character never duplicates a component's logic.

- **`attribute(key)`** → base + advancement bonus + race adjustment.
- **`tier`** → override or `Advancement#tier`.
- **`classes`** → list of class keys with at least one level (Advancement).
- **`abilities`** → merged Race + Advancement abilities, deduped by name (first-seen wins).
- **`skill_ranks`**, **`save_ranks`** → Advancement.
- **`speed`** → Race.
- **`damage_resilience`** → `max(tier, 0) + Advancement#damage_resilience` (tier-derived base plus class contribution).
- **`damage_reduction`** → Advancement.
- **`max_hit_points`** → `Advancement#max_hit_points(self)`.
- **`max_mana`** → `Advancement#max_mana(self)`.
- **`ritual_list`** → returned verbatim.

## Roster Loading

**Roster YAML**: A file (see `docs/character/character_data.yaml.example`) with a `characters:` list. Each entry has `id`, `name`, `player`, `race`, `attributes`, optional `tags`, `tier`, `ritual_list`, and `advancement`. The `advancement.classes:` map can be shorthand (`{class_key: level}`) or expanded (`{class_key: {level: N, skills: [...]}}`).

**Class Levels Total**: Sum of all class levels in a character entry. Seeds `Race`'s `character_level` parameter for racial scaling.

## Module Scope

Owns:
- Identity (ID, name, player, tags), base attributes, Tier override, Ritual List.
- Construction of Race and Advancement instances.
- Delegated derived reads.
- Loading roster YAML into Character instances.

Does not:
- Compute Tier directly (Advancement).
- Compute attribute bonuses (Advancement and Race contribute).
- Track conditions, HP consumed, mana spent, equipment, or inventory (Conditions, Equipment, Inventory, EffectsState).
- Roll dice, resolve attacks, or apply damage.
- Persist character changes — roster YAML is read-only at startup; mutations live in state modules.
