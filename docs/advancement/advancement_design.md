# Advancement — Design

The Advancement module is the home for everything that scales with a Character's tier or class levels. The Character class delegates here for every derived stat that isn't a literal field on the roster entry.

## Key Operations

### Tier auto-computation with tag dispatch

`tier` returns the override if one was set; otherwise:

1. Compute `total = sum(class_levels)`.
2. Look up each Character tag in `tier_advancement`. Tags with no entry contribute nothing.
3. For each matching breakpoint list, count how many entries `total` meets or exceeds.
4. Return the **maximum** Tier across matching lists.

When **no** tag matches, the fallback is intentionally cautious: take every breakpoint list defined in `tier_advancement`, compute the Tier each would yield, and return the **minimum**. This keeps an unrecognized character archetype from accidentally racing through tiers using whichever progression happens to be the fastest.

Tier 0 is a real outcome — `total` doesn't meet the first breakpoint of any matching list.

### Attribute bonus composition

`attribute_bonus(attr)` is the sum of two terms:

- **Flat bonus** — `attribute_bonus_per_tier` summed across the first `tier` entries. The same value applies to every attribute, so the result is independent of `attr`.
- **Focused bonus** — counts how many times `attr` appears in `tier_attribute_advancement`'s tier-T window for each T from 2 up to current Tier, multiplied by `focused_attribute_bonus_per_tier[T-1]`.

Tier 1 contributes no focused bonus. The `tier_attribute_advancement` list may be longer than the Character's current Tier — entries past current Tier are ignored, so the player can pre-allocate future picks without affecting today's bonuses.

The window math: tier T's picks live at `tier_attribute_advancement[(T-2) * focused_attribute_count, focused_attribute_count]`.

### Ability granting via class chain

`abilities` walks every Class the Character has levels in. For each Class, it walks the **Class Chain** (the Class itself, then `parent_class`, etc.) and inspects each ancestor's `abilities` list. An Ability is granted when the Character's level **in the originating Class** meets the Ability's `min_level`.

Two non-obvious rules:

- **Scaling levels accumulate across the chain.** When a Scaling Ability is granted by both a Class and its parent (or by two classes sharing a chain entry), the effective level is the **sum** of the Character's levels in every Class that contributed. So a 3-rogue / 3-arcane_trickster (where arcane_trickster has rogue as `parent_class`) gets a Scaling Ability shared with rogue at effective level 6.
- **Non-Scaling Abilities are present-or-absent.** A duplicate Non-Scaling grant is silently a no-op.

The `Ability` struct stores `name` and `level` (nil for Non-Scaling). Consumers check `level.nil?` to distinguish.

### Sticky Min Level pattern

Class abilities lists support **context entries** — entries without a `name` field. A context entry's `min_level` becomes the rolling default for every following Ability entry until the next context entry. Example:

```yaml
abilities:
  - name: rage
    scales_with_level: true
  - name: fast_movement
  - min_level: 2          # context entry
  - name: uncanny_dodge   # min_level: 2 by inheritance
  - name: primal_tenacity # min_level: 2 by inheritance
  - min_level: 3
  - name: mindless_rage   # min_level: 3
```

Only `min_level` is sticky. **`scales_with_level` is not** — every Ability that needs it must declare it on its own entry. This keeps the config explicit about which abilities carry levels.

`Advancement.normalize_abilities_list` flattens these at config-load time so downstream code never reasons about context state.

### Skill rank computation

`skill_ranks` returns `{skill_name → rank}`. Per-Class: contributing skills are the Character's `chosen_skills_for(class)` plus all `mandatory_skills` from `skills.yaml`. Each contributing skill earns ranks at one of three rates:

| Category | Formula |
|---|---|
| `:class` | `floor(5 * level / 3)` |
| `:average` | `level` |
| `:opposed` | `floor(2 * level / 3)` |

Category resolution walks the Class Chain in order. The first ancestor whose `opposed_skills`, `class_skills`, or `non_class_skills` mentions the skill (by exact match or Prefix Match) wins. If no ancestor mentions the skill, the **default category** depends on whether the originating Class declares `class_skills`:

- Class declares `class_skills` (even empty) → `:average`.
- Class omits `class_skills` → `:class`.

The two defaults encode different design intents: declaring `class_skills` says "these are my fast skills, everything else is average"; omitting `class_skills` says "I train everything fast unless explicitly demoted".

### Save rank computation

Saves are simpler: every save attribute is treated as **mandatory**. Per Class, the save earns the **fast rate** (`floor(5 * level / 3)`) if the save attribute appears in the Class Chain's combined `saves` list, otherwise the **slow rate** (`floor(2 * level / 3)`). No average rate.

A 3-fighter / 3-bard contributes to every save from both classes — per-attribute total is the sum of both Classes' rates.

### HP and mana formulas

**Max Hit Points**: `floor(tier * attribute(hp_attribute) / hp_divisor)`. The Character is passed in so `tier` and `attribute(name)` route through Character (Override wins; result already includes Race adjustment and Advancement attribute bonus). Reading through Character respects the Override and any future effects-layer wrapping.

**Max Mana**:
```
max_mana = floor(tier * attribute(mana_attribute) / mana_divisor) +
           sum over class_levels of (level * class.mana_per_level)
```

The second term is a **per-class-level grant**. Standard `mana_per_level` values: 1 (fighter, barbarian, rogue, ranger), 2 (bard, arcane_trickster), 4 (cleric, druid, wizard).

The per-class grant is what makes the **retroactive mana** rule work — see Archetype Exclusivity below.

### Archetype Exclusivity

A character cannot hold levels in both a parent class (e.g. `rogue`) and one of its archetypes (e.g. `arcane_trickster`) simultaneously. The constructor raises on violation.

Why: once an archetype is taken, the lore is "all your previous parent-class levels are now archetype levels." The character is `arcane_trickster: 5`, not `rogue: 3 / arcane_trickster: 2`. This matters because the archetype's `mana_per_level` (e.g. 2 for arcane_trickster) applies to every reclassified level — `rogue: 3 / arcane_trickster: 2` would otherwise grant `3*1 + 2*2 = 7` mana; the reclassified `arcane_trickster: 5` grants `5*2 = 10`. Skill, save, and ability resolution don't change because `Advancement#abilities` already walks the parent_class chain. Mana is the field that depends on the per-level integer rather than the chain walk.

### Class definition normalization

`Advancement.load_config(path)` normalizes every Class's `abilities` list at load time. The returned structure is:

```
{ 'rules' => <flat config>, 'classes' => <class_key → definition> }
```

The `classes` key is removed from the `rules` view so the rules dict is purely tier/attribute/HP/mana globals.

## Responsibilities

### Owned by the advancement domain

- Loading `advancement_config.yaml` and `skills.yaml`.
- Tier auto-computation with the cautious "minimum across all lists" fallback.
- Flat and focused attribute bonus composition.
- Walking the Class Chain to enumerate granted Abilities, with cycle protection.
- Scaling Ability level accumulation across chained Classes.
- Sticky Min Level flattening at config-load time.
- Skill rank computation: per-Class category resolution (with Prefix Matches and chain walks) and rate selection.
- Save rank computation: chain-aware class/opposed dispatch.
- HP and mana formulas (read tier and attribute through the Character).
- Returning `damage_resilience` and `damage_reduction` class contributions (currently 0 placeholders).

### Explicitly *not* owned here

- **Identity, base attributes, Tier Override, Ritual List** — Character.
- **Racial bonuses, racial abilities** — Race.
- **The Tier-derived base for damage resilience** (`max(tier, 0)`) — Character.
- **Per-Character mutable state** — conditions and equipment modules.
- **Choosing which class skills to advance** — that's a roster authoring decision.
- **Validating that a chosen skill exists in `skills.yaml`** — currently nothing validates this.

### Unassigned (no current owner)

- **Filling out the procedural and stateful ability catalogs.** Class/racial abilities now have a defined home; what's unassigned is the actual content.
- **Class contributions to `damage_resilience` and `damage_reduction`.** The methods exist as 0-returning placeholders; the actual scaling rules per class haven't been designed.
- **Validation that `class_skills`, `non_class_skills`, `opposed_skills` entries refer to real skills** in `skills.yaml`. A typo silently changes default-category behavior.
- **Validation that `parent_class` references a defined Class.**
- **Validation that `tier_attribute_advancement` picks reference real attribute keys.**
- **Bonus skills tracking and enforcement.** The `bonus_skills` field on each Class is documented but not currently consulted.
