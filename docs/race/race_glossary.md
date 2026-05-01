# Race — Glossary

Reference module: given a race key and Character level, returns size, speed, ability score adjustments, and granted abilities. Owns no per-Character mutable state. *(configurable)* values come from `race_config.yaml`.

## Core

**Race**: The creature type a Character belongs to. Keyed by a string in `race_config.yaml`'s `races:` map.

**Race Definition**: An entry under `races` defining optional `name`, `parent_race`, `size`, `speed`, `ability_score_adjustments`, and `abilities`. Omitted fields are inherited from the Race Chain.

**Sub-Race**: A Race with a `parent_race`. Inherits everything its parent declares; `ability_score_adjustments` and abilities accumulate up the chain, scalar fields (`size`, `speed`) fall through to the first ancestor that declares them.

**Race Chain**: A Race's ancestors via `parent_race`, starting with the Race itself. Walked by every lookup; cycles are guarded.

## Adjustments and Speed

**Ability Score Adjustment**: A racial modifier added to a Character's base attribute. Map of attribute key to integer; `Race#ability_score_adjustments` returns the sum across the Race Chain.

**Speed**: The Character's base walking speed in feet. Returned from the first ancestor in the Race Chain that declares a `speed`.

**Size**: The Character's size category (`Small`, `Medium`, etc.). Same first-in-chain rule as Speed.

## Racial Abilities

**Racial Ability**: A named feature granted by the Race. Stored on `abilities` with the same shape as a Class's abilities list (see `advancement_glossary.md`): `name`, `min_level` (default 1), optional `scales_with_level`.

**Scaling Racial Ability**: An Ability with `scales_with_level: true`. Effective level is the Character's **total class level**, not tier; when granted by multiple ancestors the levels accumulate.

**Character Level Threshold**: A Racial Ability's `min_level`, compared against the Character's total class level — racial abilities gate on overall progression, not per-class level.

(Sticky Min Level: see common glossary.)

## Module Scope

Owns:
- Loading `race_config.yaml` and exposing Race Definitions by key.
- Walking the Race Chain (with cycle protection) to gather inherited values.
- Returning name, size, speed, accumulated adjustments, and granted Abilities for a given Race + level.
- Reusing `Advancement.normalize_abilities_list` to flatten sticky-context entries at load.

Does not:
- Track which Characters belong to which Race (Character).
- Compute Tier or class-derived bonuses (Advancement).
- Define what a Racial Ability does mechanically.
- Validate attribute keys in `ability_score_adjustments`.
