# Race — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `race_config.yaml`. The Race module is a **reference**: it answers "what does this race grant?" given a race key and the Character's level, and it does not own per-Character mutable state.

## Core

**Race**: The creature type a Character belongs to. Each Race is keyed by a string in `race_config.yaml`'s `races:` map. *(configurable)*

**Race Definition**: An entry under `races` defining the Race's optional `name`, `parent_race`, `size`, `speed`, `ability_score_adjustments`, and `abilities`. Any field omitted is inherited from the Race Chain.

**Sub-Race**: A Race whose `parent_race` field references another Race. The Sub-Race inherits everything its parent declares, with the Sub-Race's own values stacking on top — `ability_score_adjustments` accumulate up the chain (Hill Dwarf's `+2 con +2 wis` plus inherited values from `dwarf`), abilities accumulate, and scalar fields (`size`, `speed`) fall through to the first ancestor that declares them.

**Race Chain**: The list of a Race's ancestors via `parent_race`, starting with the Race itself. Walked by every lookup; cycles are guarded against.

## Adjustments and Speed

**Ability Score Adjustment**: A racial modifier added to a Character's base attribute. Stored on the Race Definition as a map of attribute key (`str`/`dex`/`con`/`int`/`wis`/`cha`) to integer. Returned by `Race#ability_score_adjustments` as the sum across the Race Chain — every chain entry's adjustments add together.

**Speed**: The Character's base walking speed in feet. Returned from the **first** ancestor in the Race Chain that declares a `speed`. Sub-Races may omit `speed` and inherit; they may also override by declaring their own value.

**Size**: The Character's size category (`Small`, `Medium`, etc.). Same first-in-chain rule as Speed.

## Racial Abilities

**Racial Ability**: A named feature granted by the Race. Stored on a Race Definition's `abilities` list with the same shape as a Class's abilities list (see `advancement_glossary.md`). An Ability has a `name`, a `min_level` (default 1), and an optional `scales_with_level` flag.

**Sticky Min Level**: A `min_level` carried by a context entry — an entry without a `name`. Every following Ability entry inherits the rolling `min_level` until the next context entry. The same flattening pass `Advancement` uses runs at config-load time so downstream code never sees context entries.

**Scaling Racial Ability**: An Ability with `scales_with_level: true`. Its effective level is the Character's **total class level**, not their tier. When the same scaling Ability is granted by multiple ancestors in the Race Chain, the effective levels accumulate just like in Advancement.

**Character Level Threshold**: The Character's total class level required to gain a Racial Ability (`min_level`). Compared against the Character's overall progression rather than against any single class. This is the gate that lets racial abilities show up at character milestones rather than at race-specific levels.

## Module Scope

The Race module:

- Loads `race_config.yaml` and exposes Race Definitions by key.
- For a given Race key and Character level, returns the Race's name, size, speed, accumulated ability score adjustments, and granted Abilities.
- Walks the Race Chain to gather inherited values, with cycle protection.
- Reuses `Advancement.normalize_abilities_list` to flatten sticky-context entries at load time.

It does **not**:

- Track which Characters belong to which Race — that's the Character class.
- Compute Tier or class-derived bonuses — Advancement.
- Define what a Racial Ability *does* mechanically. Today the Ability is just a name with a level; lookups for actual mechanical effects go through whichever future class-abilities catalog handles them.
- Validate that an attribute key in `ability_score_adjustments` is one of the six recognized attributes.
