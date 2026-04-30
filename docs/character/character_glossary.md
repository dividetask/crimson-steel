# Character — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. The Character module is a **coordinator**: it owns a small slice of state (identity and base attributes) and routes everything else to Race, Advancement, and — once they exist — Skills, Combat, Conditions, Inventory, and EffectsState. External callers go through Character rather than reaching into its components directly.

## Identity

**Character**: A single playable or non-playable creature. The Character class is the front door — every read about a creature flows through it so that a future effects layer can wrap reads uniformly. Each Character owns identity, base attributes, and a reference to its Race and Advancement; everything else is delegated.

**ID**: A unique non-reused integer identifier for the Character. Persists across renames; used by combat logs and external links.

**Name**: The displayed Character name. Free-form string.

**Player**: The player running the Character. Free-form string. Allowed to be empty for NPCs and monsters.

**Tags**: A list of free-form labels that classify the Character. Defaults to `['player_character']` when none are supplied. Tags drive Tier auto-computation (see `advancement_glossary.md`'s **Tier Advancement Breakpoint List**) — each tag that matches a key under `tier_advancement` contributes a breakpoint list, and the highest tier any matching list yields wins. Descriptive tags without a breakpoint list (`NPC`, `Ally`, `Enemy`) carry no mechanical effect; they're for filtering and presentation.

**Ritual List**: A list of lists indexed by tier. `ritual_list[T]` is the list of tier-T ritual names the Character knows. Pure data — Character does not interpret ritual content.

## Attributes

**Base Attribute**: One of the six raw scores the Character owns directly: `str`, `dex`, `con`, `int`, `wis`, `cha`. Stored as integers; missing keys default to 0.

**Effective Attribute**: The value returned by `Character#attribute(key)`. Computed as `base + Advancement#attribute_bonus(key) + Race#adjustment_for(key)`. The Character itself does no math beyond the sum — the components do their own.

## Tier

**Tier**: The Character's current Tier as a non-negative integer. Tier 0 is treated as 0.5 in formulas (project-wide convention). The Character may set an explicit `tier:` override, which always wins; otherwise the Tier is computed by `Advancement#tier` from total class levels and the matching breakpoint lists. See `advancement_glossary.md`.

**Tier Override**: An optional integer set on the Character entry that hardcodes the Tier and bypasses Advancement's auto-computation. Useful for NPCs whose effective power level isn't well captured by class levels.

## Derived Reads (delegated)

The Character exposes the following methods, each of which routes to a component:

- **`attribute(key)`** → base + advancement bonus + race adjustment.
- **`tier`** → override or `Advancement#tier`.
- **`classes`** → the list of class keys the Character has at least one level in (from Advancement).
- **`abilities`** → the merged list of Race abilities and Advancement abilities, deduped by name (first-seen wins).
- **`skill_ranks`** → from Advancement.
- **`save_ranks`** → from Advancement.
- **`speed`** → from Race.
- **`damage_resilience`** → `max(tier, 0) + Advancement#damage_resilience` (tier-derived base plus class contribution; the tier-0 → 0.5 floor lands at 0).
- **`damage_reduction`** → from Advancement.
- **`max_hit_points`** → `Advancement#max_hit_points(self)` — Advancement applies the formula, reading `tier` and the configured HP attribute back through the Character.
- **`max_mana`** → `Advancement#max_mana(self)`, same pattern.
- **`ritual_list`** → returned verbatim.

The Character class never duplicates a component's logic — if a value is computable from base attributes, it lives here only when it's a literal field. Anything formulaic delegates.

## Roster Loading

**Roster YAML**: A file in the format documented at `docs/character/character_data.yaml.example` containing a `characters:` list. Each entry has `id`, `name`, `player`, `race`, `attributes`, optional `tags`, `tier`, `ritual_list`, and `advancement` blocks. The `advancement` block's `classes:` map can be either shorthand (`{class_key: level}`) or expanded (`{class_key: {level: N, skills: [...]}}`).

**Class Levels Total**: The sum of all class levels in a character entry. Used to seed `Race`'s `character_level` parameter so racial scaling abilities know the Character's overall progression. Splitting across classes is summed — a 3-bard / 2-rogue counts as level 5 for racial scaling, not 3.

## Module Scope

The Character module:

- Owns identity (ID, name, player, tags), base attributes, the Tier override, and the Ritual List.
- Constructs and holds references to its Race and Advancement instances.
- Delegates derived reads to those components.
- Loads a roster YAML into a list of Character instances, wiring each one's Race and Advancement with the relevant config files.

It does **not**:

- Compute Tier directly (Advancement does, with character tags and class levels).
- Compute attribute bonuses (Advancement and Race each contribute their own additions).
- Track conditions, hit points consumed, mana spent, equipment, or inventory — those belong to Conditions, Equipment, Inventory, and the eventual EffectsState.
- Roll dice, resolve attacks, or apply damage.
- Persist character changes to disk — the YAML file is read-only at startup; mutations go through the conditions and other state modules and serialize separately.
