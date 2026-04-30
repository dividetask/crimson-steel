# Race — Design

Companion to `race_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The Race module is reference data with one twist: every read walks the Race Chain (a Race plus its ancestors via `parent_race`). The chain walk is what makes Sub-Races composable — Hill Dwarf inherits Dwarf's speed, abilities, and any partial adjustments, and stacks its own on top.

## Key Operations

### Race Chain walk

Every lookup builds the same chain: start at the Race, follow `parent_race` until either the field is absent or a cycle is detected (an already-seen race). The chain is built fresh on each call rather than cached — Race instances are short-lived and racial config rarely changes during a session.

Cycle protection is intentional: a misconfigured `parent_race` that points back to a descendant must not loop forever. A cycle terminates the walk at the first repeat without raising — the chain returned is the prefix up to but not including the second visit.

### First-in-chain vs accumulate-across-chain

Different fields use different chain semantics, and the rules don't generalize:

- **First-in-chain** (`name`, `size`, `speed`) — return the first non-nil value walking root-to-tail. The most-specific Race wins; ancestors fill in only when the descendant omits the field.
- **Accumulate-across-chain** (`ability_score_adjustments`) — sum every ancestor's contribution. A Hill Dwarf's `+2 con` from its own definition adds to any `+2 con` Dwarf might declare. Today only `ability_score_adjustments` accumulates this way.
- **Concatenate-across-chain** (`abilities`) — every ancestor's Abilities are gathered, then deduplicated by name with scaling-level accumulation (same rule Advancement uses for class abilities).

The split exists because the fields serve different design intents: identity values (name, size) are typically more specific the deeper you go, while bonuses are typically additive.

### Racial ability granting

`abilities` produces a list of `Ability` structs (the same struct Advancement uses) for every name granted by the Race Chain whose `min_level` ≤ the Character's level. Two non-obvious points:

- **The level compared against `min_level` is the Character's total class level**, passed in at construction time as `character_level`. It is not the tier and not a per-class level. This is what lets a tier-0 Satyr earn its Tier-3 racial ability at the same character milestone as a multiclassed PC.
- **Scaling abilities accumulate effective levels across the chain.** When both `dwarf` and `hill_dwarf` declare a scaling ability of the same name, the Character's total class level is added to the slot **for each chain ancestor that grants it**, mirroring how `Advancement#abilities` accumulates across `parent_class` entries. Today no built-in race exercises this case, but the rule is consistent with Advancement so future content can rely on it.

### Sticky min_level reuse

`Race.load_yaml` calls `Advancement.normalize_abilities_list` to flatten sticky context entries. The two domains share this helper rather than each implementing its own — racial ability lists support exactly the same `min_level`-only sticky context entries Advancement does. The shared `Ability` struct is also imported from Advancement.

### Empty-config tolerance

`Race.load_yaml(nil)` and a nonexistent path both return an empty hash. A Character constructed with a race key that doesn't appear in the config produces a Race instance whose every chain lookup falls through — empty adjustments, no abilities, nil speed/size. The Character itself does not raise; the missing race surfaces visually (no name, no speed, no bonuses) rather than as an error.

This keeps production startup permissive: the DM can drop in a partial config and the app still loads.

## Responsibilities

### Owned by the race domain

- Loading `race_config.yaml` and normalizing each Race's `abilities` list at load time.
- Walking the Race Chain on every lookup with cycle protection.
- Returning Name, Size, Speed using first-in-chain semantics.
- Returning `ability_score_adjustments` as the accumulated sum across the Race Chain.
- Returning `abilities` filtered by `min_level` against the Character's total class level, with scaling-level accumulation across chain ancestors.

### Explicitly *not* owned here

- **Tier, class levels, or class abilities** — Advancement.
- **Identity, base attributes, the Tier Override** — Character.
- **What a Racial Ability does mechanically.** The abilities module's Procedural Abilities catalog covers stateless racial abilities; the conditions module covers stateful ones; always-on numeric bonuses live on the ability entry's `modifiers:` field. Race itself returns names and levels only — mechanical effects are looked up by name in those catalogs.
- **Per-Character mutable state** (HP, conditions, currency).
- **Validation that `ability_score_adjustments` keys are real attributes** — typos silently produce a 0 contribution.

### Unassigned (no current owner)

- **Populating the procedural and stateful catalogs for racial abilities.** The catalogs exist (Abilities' Procedural Abilities, Conditions' Effect Names, the `modifiers:` field on each ability entry); most racial ability names don't yet have entries in any of them.
- **Cross-domain validation** that a Character's `race:` key exists in `race_config.yaml`. A typo silently produces an empty Race.
- **Preferred starting attribute distributions per Race.** The example config carries `ability_score_adjustments` but not the standard "+2 to one stat, +1 to another" point-buy steering that some games include — if Crimson Steel ever wants that, it needs a home.
