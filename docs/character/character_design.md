# Character — Design

Companion to `character_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The Character module is a **coordinator**, not a calculator. Its job is to hold the small set of values that don't belong to a more specialized module (identity, base attributes, Tier override, Ritual List) and to route every other read to whichever component knows the answer. Keeping the surface narrow lets a future effects layer wrap reads uniformly: monkey-patch `Character#attribute` and every consumer in the app sees the modified value.

## Key Operations

### Effective attribute composition

`attribute(key)` returns `base + Advancement#attribute_bonus(key) + Race#adjustment_for(key)`. The three contributions are non-overlapping by design:

- **Base** — the raw score the player picked at creation. Stored on the Character.
- **Advancement bonus** — the cumulative tier flat bonus plus any focused-attribute picks the player has spent at this attribute. Lives in Advancement because it's tier-derived.
- **Race adjustment** — racial modifiers, summed up the parent_race chain. Lives in Race.

The Character does no clamping, no max enforcement, and no formula — just a sum. Components that need a special rule (e.g. caps at high tier) implement it themselves and return their adjusted contribution.

### Tier resolution

`tier` returns the override if one was set on the Character entry; otherwise it delegates to `Advancement#tier`. The override **always wins**, even if Advancement was constructed without the same value, so an NPC with `tier: 3` in YAML stays tier 3 regardless of how many class levels they happen to have.

When derived values (`damage_resilience`, `max_hit_points`, etc.) need the Tier, they read it back through the Character, not through Advancement directly. That keeps the override authoritative through every consumer without each component needing its own copy.

### Ability deduplication across Race and Advancement

`abilities` merges the Race's abilities list and the Advancement's abilities list, keyed by name. **First seen wins** — Race is iterated first, then Advancement, so a duplicate name from a class is suppressed in favor of the racial version.

This rule matters because both Race and Advancement may grant abilities that scale with the Character's level. The "first seen wins" rule prevents a doubled-scaling bug where the same ability name appears twice and each iteration adds the level a second time. If a future design wants combined scaling, the merge rule will need a redesign — today the assumption is that the same ability name from two sources is a config mistake, not a feature.

### Roster loading

`Character.load_yaml(path, advancement_path:, skills_path:, races_path:)` reads a roster YAML and constructs a list of Character instances. Side-effects worth knowing:

- The advancement and skills config files are loaded **once** and shared across every Character — class definitions and tier rules are global, not per-character.
- The race definitions are similarly loaded once and shared.
- Each Character's `total_class_levels` is computed up front and passed to `Race` so racial scaling abilities have the right total.
- A character's `tier:` override is forwarded to both the Character and the Advancement constructors so either path returns the same answer.

Missing roster files return `[]` rather than raising — production starts empty until the DM drops a roster in. Missing advancement / skills / races files default to empty hashes, which means every derived bonus collapses to 0 but the Character still loads.

### Tag normalization

The `tags` field accepts either a missing key, an empty list, or a populated list of strings. Empty/missing → `['player_character']`. This default is the gateway to Tier auto-computation — without any matching tag in `tier_advancement`, Advancement falls back to the slowest progression in the system (see `advancement_glossary.md`).

## Responsibilities

### Owned by the character domain

- Identity fields: `id`, `name`, `player`, `tags`, `ritual_list`.
- Base attribute storage and the `attribute_keys` constant (`%i[str dex con int wis cha]`).
- Holding a single `Race` instance and a single `Advancement` instance per Character.
- The Tier Override: storing it on construction and returning it ahead of Advancement's computed Tier.
- Composing Effective Attributes from base + Advancement bonus + Race adjustment.
- Merging `Race#abilities` and `Advancement#abilities` with first-seen-wins deduplication.
- Loading a roster YAML and wiring each entry's Race and Advancement.

### Explicitly *not* owned here

- **Tier auto-computation** — Advancement reads class levels and breakpoint lists.
- **Attribute bonuses from levels** — Advancement.
- **Racial bonuses, racial abilities, speed, size** — Race.
- **Skill ranks and save ranks** — Advancement.
- **HP and mana formulas** — Advancement (`max_hit_points` / `max_mana`).
- **Damage resilience and damage reduction class contributions** — Advancement (Character only adds the tier-derived base for resilience).
- **Conditions, current HP, temp HP, magic toxicity, shock** — the conditions module, indexed per-Character externally.
- **Equipment, inventory, currency** — equipment / inventory modules.
- **Active effects, buff stacking** — conditions module.
- **Combat actions, attacks, dice rolls** — combat / dice resolution.

### Unassigned (no current owner)

- **Per-Character mutable state that doesn't fit any specific module yet** — e.g. notes the DM keeps about a character, custom flags. Currently nothing centralizes this; the conditions module owns mechanical state but not narrative state.
- **Validation of roster entries against the configs they reference.** Today a `race:` key that doesn't appear in `races.yaml` silently produces a Race instance whose every chain lookup falls through. Same for unknown class keys. There's no author-time check that the roster aligns with the configs.
- **Persistence of mutations.** The Character is loaded once at startup and never written back; any per-session mutations live in the conditions module or in-memory only. A save/load loop for changes to identity (renames, etc.) is unspecified.
