# Race — Design

Reference data with one twist: every read walks the Race Chain (a Race plus its ancestors via `parent_race`). The chain walk is what makes Sub-Races composable — Hill Dwarf inherits Dwarf and stacks its own on top.

## Key Operations

### Race Chain walk

Built fresh on each call rather than cached — Race instances are short-lived and racial config rarely changes mid-session. A misconfigured `parent_race` cycle terminates at the first repeat without raising; the chain returned is the prefix up to but not including the second visit.

### First-in-chain vs accumulate-across-chain

Different fields use different chain semantics; the rules don't generalize because the fields serve different design intents (identity values get more specific deeper; bonuses are additive):

- **First-in-chain** (`name`, `size`, `speed`) — first non-nil walking root-to-tail.
- **Accumulate** (`ability_score_adjustments`) — sum every ancestor's contribution.
- **Concatenate-with-dedup** (`abilities`) — gather all, dedupe by name with scaling-level accumulation (same rule as Advancement).

### Racial ability granting

`abilities` filters by `min_level` against the Character's **total class level** (passed in at construction), not the tier or any per-class level. This lets a tier-0 Satyr earn its Tier-3 racial ability at the same milestone as a multiclassed PC.

Scaling abilities accumulate effective levels across the chain (mirroring Advancement's parent_class accumulation). No built-in race exercises this today, but the rule is consistent so future content can rely on it.

### Sticky min_level reuse

`Race.load_yaml` calls `Advancement.normalize_abilities_list` to flatten Sticky Min Level context entries — racial ability lists support exactly the same context entries Advancement does. The shared `Ability` struct is also imported from Advancement.

### Empty-config tolerance

A nonexistent path or a Character with an unknown race produces a Race instance whose every chain lookup falls through (empty adjustments, no abilities, nil speed/size). Character does not raise — the missing race surfaces visually rather than as an error, so the DM can drop in a partial config and the app still loads.

## Responsibilities

### Owned

- Loading `race_config.yaml`; normalizing abilities lists at load time.
- Race Chain walking with cycle protection.
- Name/Size/Speed (first-in-chain), `ability_score_adjustments` (accumulate), `abilities` (concatenate-with-dedup, filtered by Character's total class level, with scaling-level accumulation).

### Not owned

- **Tier, class levels, class abilities** — Advancement.
- **Identity, base attributes, Tier Override** — Character.
- **What a Racial Ability does mechanically** — abilities (procedural), conditions (stateful), or `modifiers:` (always-on).
- **Per-Character mutable state** — conditions/equipment.
- **Validation of `ability_score_adjustments` keys** — typos silently produce 0.

### Unassigned

- Populating procedural/stateful catalogs and `modifiers:` for racial abilities.
- Cross-domain validation that a Character's `race:` key exists.
- Preferred starting attribute distributions per Race (point-buy steering).
