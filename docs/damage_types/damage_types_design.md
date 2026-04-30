# Damage Types — Design

Companion to `damage_types_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The damage types module is strict reference data. It tells callers what each type *means*; combat, conditions, dice resolution, and equipment implement the actual behaviors. The split mirrors the abilities module's relationship with its consumers.

## Key Operations

### Severity resolution

Every Damage Type has either:

- A declared Severity (one of `minor`, `moderate`, `major`) — applied to every damage point of that type; or
- A `runtime_bucketing: true` flag — Severity is determined at damage-application time by the combat module.

Today only **Physical** uses runtime bucketing. Its config entry has no `severity` field. Other types declare a Severity directly.

A damage type may **not** have both a declared Severity and `runtime_bucketing: true`. The validator rejects this configuration.

### Mechanic kinds and consumer routing

Each `kind` in a Mechanic dictates which consumer module interprets it:

| `kind` | Consumer | Effect |
|---|---|---|
| `damage_per_dice` | combat | Adds bonus damage scaling with dice count. |
| `counter` | conditions | Stateful per-target counter with turn-start behavior. |
| `damage_multiplier` | combat | Multiplies damage by `factor` under a `condition`. |
| `inflict` | conditions | Applies a named condition `per_damage` points per damage point. |
| `critical_value` | dice resolution | Overrides the Roll's `critical_modifier` when this type is at stake. |

The `on_turn_start` list inside a `counter` mechanic uses the same `kind` vocabulary, but the only kinds valid there today are `scale_self` and `deal_damage`. The damage types module enforces this nesting rule.

`condition` strings inside `damage_multiplier` (`target_has_metal_armor`, `target_has_subtype:undead`, etc.) are free-form scope tags. The damage types module does **not** validate them — it surfaces them and the consuming module decides whether it understands the tag.

### The Physical exception

Physical is the only type whose Severity isn't fixed at lookup time. Two consequences:

- The damage types module returns a "needs runtime bucketing" indicator rather than a Severity for Physical lookups.
- Abilities that deal Physical Damage must declare a `threshold` (or, for weapon attacks, the threshold comes from the weapon). The validation that `damage_type: physical` Entries declare a Threshold lives in the **abilities** module — the damage types module only declares that the rule exists.

The bucketing formula itself (Threshold + Damage Resilience filling Minor, then Moderate, then Major) lives in combat. The damage types module documents it for reference but does not implement it.

## Responsibilities

### Owned by the damage types domain

- Loading and validating `damage_types_config.yaml`.
- Exposing the Damage Type catalog: name, Severity (or runtime-bucketing flag), description, Mechanics list.
- Validating that each Mechanic's `kind` is recognized and that required fields are present.
- Validating that `runtime_bucketing` and `severity` are mutually exclusive on a Damage Type.
- Validating the nesting rule for `on_turn_start` (only `scale_self` and `deal_damage` allowed).

### Explicitly *not* owned here

- **Applying damage.** Combat module reads each damage point's Severity (looked up here) and routes it through Temporary HP and the Minor/Moderate/Major pools.
- **Runtime Bucketing for Physical.** Lives in combat. The Threshold input comes from the weapon (equipment) or the ability (abilities); Damage Resilience comes from the character module.
- **Counter state.** Tracking active acid counters per target, applying their turn-start behavior. Lives in the conditions module.
- **`condition` tag interpretation.** Whether a target "has metal armor" or a "subtype" is determined by the consuming module (combat with help from equipment / character).
- **Critical value override propagation.** The `critical_value` mechanic is consumed by dice resolution when a Roll resolves a damage check tagged with this Damage Type. The damage types module surfaces the value but never invokes it.
- **The list of Severity names.** While `temporary`/`minor`/`moderate`/`major` is configurable here, the **HP pool sizes and recovery rules** that give those names meaning live in the character module.

### Unassigned (no current owner)

- Cross-domain validation that every `condition` string used in a `damage_multiplier` (`target_has_metal_armor`, `target_has_subtype:undead`, etc.) is recognized by the consuming module. Today the tag is free-form and silent failure is possible.
- Cross-domain validation that every `condition_name` used in `inflict` (e.g. `shock`) corresponds to a real condition in the conditions module.
- A canonical home for the **threshold-bucketing formula** itself. Today it's only described prose in this glossary; once the combat domain is documented in this format, the formula migrates there.
