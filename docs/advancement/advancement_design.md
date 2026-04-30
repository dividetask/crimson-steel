# Advancement — Design

Companion to `advancement_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The Advancement module is the home for everything that scales with a Character's tier or class levels. The Character class delegates here for every derived stat that isn't a literal field on the roster entry.

## Key Operations

### Tier auto-computation with tag dispatch

`tier` returns the override if one was set; otherwise:

1. Compute `total = sum(class_levels)`.
2. Look up each of the Character's tags in `tier_advancement`. Tags with no entry contribute nothing.
3. For each matching breakpoint list, count how many entries `total` meets or exceeds — that's the Tier that list yields.
4. Return the **maximum** Tier across matching lists.

When **no** tag matches, the fallback is intentionally cautious: take every breakpoint list defined in `tier_advancement` (regardless of whether the Character's tags reference it), compute the Tier each would yield, and return the **minimum**. This keeps an unrecognized character archetype from accidentally racing through tiers using whichever progression happens to be the fastest.

Tier 0 is a real outcome — it just means `total` doesn't meet the first breakpoint of any matching list.

### Attribute bonus composition

`attribute_bonus(attr)` is the sum of two terms:

- **Flat bonus** — `attribute_bonus_per_tier` summed across the first `tier` entries (one entry per tier earned). The same value applies to every attribute, so the result is independent of `attr`.
- **Focused bonus** — counts how many times `attr` appears in `tier_attribute_advancement`'s tier-T window for each T from 2 up to the current Tier, multiplied by `focused_attribute_bonus_per_tier[T-1]`.

Tier 1 contributes no focused bonus (the focused bonus list starts non-zero at index 1, i.e. tier 2). The `tier_attribute_advancement` list may be longer than the Character's current Tier — entries past the current Tier are ignored, so the player can pre-allocate future picks without affecting today's bonuses.

The window math: tier T's picks live at `tier_attribute_advancement[(T-2) * focused_attribute_count, focused_attribute_count]`. A short or missing list at a tier-up means that tier earns no focused bonus.

### Ability granting via class chain

`abilities` walks every Class the Character has levels in. For each Class, it walks the **Class Chain** (the Class itself, then `parent_class`, etc.) and inspects each ancestor's `abilities` list. An Ability is granted when the Character's level **in the originating Class** meets the Ability's `min_level`.

Two non-obvious rules:

- **Scaling levels accumulate across the chain.** When a Scaling Ability is granted by both a Class and its parent (or by two classes sharing a chain entry), the effective level is the **sum** of the Character's levels in every Class that contributed. So a 3-rogue / 3-arcane_trickster (where arcane_trickster has rogue as `parent_class`) gets a Scaling Ability shared with rogue at effective level 6.
- **Non-Scaling Abilities are present-or-absent.** A duplicate Non-Scaling grant is silently a no-op (the ability simply exists once).

The `Ability` struct stores `name` and `level` (nil for Non-Scaling). Consumers check `level.nil?` to distinguish the two.

### Sticky min_level pattern

Class abilities lists support **context entries** — entries without a `name` field. A context entry's `min_level` becomes the rolling default for every following Ability entry until the next context entry. The pattern lets a config file group abilities by required level without restating `min_level` on every entry:

```yaml
abilities:
  - name: rage
    scales_with_level: true
  - name: fast_movement
  - min_level: 2          # context entry — sets rolling min_level
  - name: uncanny_dodge   # min_level: 2 by inheritance
  - name: primal_tenacity # min_level: 2 by inheritance
  - min_level: 3
  - name: mindless_rage   # min_level: 3
```

Only `min_level` is sticky. **`scales_with_level` is not** — every Ability that needs it must declare it on its own entry. This keeps the config explicit about which abilities carry levels.

`Advancement.normalize_abilities_list` flattens sticky-context entries into per-Ability dictionaries at config-load time so downstream code never needs to reason about context state.

### Skill rank computation

`skill_ranks` returns a `{skill_name → rank}` dict. The walk is per-Class: for each Class the Character has levels in, the contributing skills are the Character's `chosen_skills_for(class)` plus all `mandatory_skills` from `skills.yaml`. Each contributing skill earns ranks at one of three rates:

| Category | Formula |
|---|---|
| `:class` | `floor(5 * level / 3)` |
| `:average` | `level` |
| `:opposed` | `floor(2 * level / 3)` |

Category resolution walks the Class Chain in order. The first ancestor whose `opposed_skills`, `class_skills`, or `non_class_skills` mentions the skill (by exact match or prefix match — entries ending in `_` match any string starting with that prefix and longer) wins. If no ancestor mentions the skill, the **default category** depends on whether the originating Class declares `class_skills`:

- Class declares `class_skills` (even an empty list) → `:average`.
- Class omits `class_skills` → `:class`.

The two defaults encode different design intents: declaring `class_skills` says "these are my fast skills, everything else is average"; omitting `class_skills` says "I train everything fast unless explicitly demoted".

### Save rank computation

Saves use a simpler rule: every save attribute is treated as **mandatory**. For each Class the Character has levels in, the save earns the **fast rate** (`floor(5 * level / 3)`) if the save attribute appears in the Class Chain's combined `saves` list, otherwise the **slow rate** (`floor(2 * level / 3)`). There is no average rate for saves.

This means a 3-fighter / 3-bard contributes to every save from both classes — the per-attribute total is the sum of both Classes' rates.

### HP and mana formulas

Both formulas are `floor(tier * attribute(name) / divisor)`. The Character is passed in so:

- `tier` reads through the Character (Override wins).
- `attribute(name)` reads through the Character's `attribute(name)` (so the result already includes Race adjustment and Advancement attribute bonus).

This double-routing keeps the formula consistent regardless of how the Character was constructed. Advancement could call `tier` and `attribute_bonus` on itself, but reading through the Character respects the Override and any future effects-layer wrapping.

### Class definition normalization

`Advancement.load_config(path)` normalizes every Class's `abilities` list at load time using `normalize_abilities_list`. The returned structure is:

```
{ 'rules' => <flat config>, 'classes' => <class_key → definition> }
```

The `classes` key is removed from the `rules` view so the rules dict is purely tier/attribute/HP/mana globals. Sticky context entries no longer appear in the normalized classes — every entry has a `name` and an explicit `min_level`.

## Responsibilities

### Owned by the advancement domain

- Loading `advancement_config.yaml` (tier rules, class definitions) and `skills.yaml` (skill metadata).
- Tier auto-computation from class levels with tag-keyed breakpoint lists, including the cautious "minimum across all lists" fallback when no tag matches.
- Flat and focused attribute bonus composition.
- Walking the Class Chain to enumerate granted Abilities, with cycle protection in case `parent_class` is misconfigured.
- Scaling Ability level accumulation across chained Classes.
- Sticky-`min_level` flattening at config-load time.
- Skill rank computation: per-Class category resolution (with prefix matches and chain walks) and rate selection.
- Save rank computation: chain-aware class/opposed dispatch.
- HP and mana formulas (read tier and attribute through the Character).
- Returning `damage_resilience` and `damage_reduction` class contributions (currently always 0 placeholders).

### Explicitly *not* owned here

- **Identity, base attributes, Tier Override, Ritual List** — Character.
- **Racial bonuses, racial abilities** — Race.
- **The Tier-derived base for damage resilience** (`max(tier, 0)`) — Character.
- **Per-Character mutable state** (current HP, conditions, equipped items) — conditions and equipment modules.
- **Choosing which class skills to advance** — that's a Character roster authoring decision; Advancement just reads the Character's `chosen_skills_for(class)` results.
- **Validating that a chosen skill exists in `skills.yaml`** — currently nothing validates this. Unknown skills earn ranks against an undefined category, which always falls back to a default.

### Unassigned (no current owner)

- **Filling out the procedural and stateful ability catalogs.** Class/racial abilities now have a defined home: stateless ones (Sneak Attack, Channel Divinity) live in the abilities module's Procedural Abilities catalog; stateful ones (Rage, Bardic Inspiration) live in the conditions module's Effect Names catalog or as Acid-Counter-style hardcoded fields. Always-on numeric bonuses live on the ability entry's `modifiers:` field. What's still unassigned is the actual content — most class abilities don't yet have entries in either catalog.
- **Class contributions to `damage_resilience` and `damage_reduction`.** The methods exist as 0-returning placeholders; the actual scaling rules per class haven't been designed.
- **Validation that `class_skills`, `non_class_skills`, and `opposed_skills` entries refer to real skills** in `skills.yaml`. Today a typo silently changes default-category behavior.
- **Validation that `parent_class` references a defined Class.** A typo produces a chain that walks a single step then terminates, with the missing parent contributing nothing.
- **Validation that `tier_attribute_advancement` picks reference real attribute keys.** A typo silently produces 0 focused bonus.
- **Bonus skills tracking and enforcement.** The `bonus_skills` field on each Class is documented but not currently consulted by Advancement — the Character can declare any number of chosen skills.
