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
| `apply_acid_counter` | combat → conditions | Combat calls `APPLY_ACID_DAMAGE` on conditions; the Acid Counter behavior is hardcoded there. |
| `damage_multiplier` | combat | Multiplies damage by `factor` under a `condition`. |
| `inflict` | combat → conditions | Combat invokes the right conditions API (`APPLY_SHOCK` for shock, etc.) per damage point. |
| `critical_value` | dice resolution | Overrides the Roll's `critical_modifier` when this type is at stake. |

Mechanic kinds that name a specific built-in counter (`apply_acid_counter`) exist because the conditions module exposes those counters as hardcoded top-level fields rather than as a generic catalog. Adding a new built-in counter requires both a code change in conditions *and* a corresponding mechanic kind here.

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
- Validating that mechanic kinds are recognized.

### Explicitly *not* owned here

- **Applying damage.** Combat module reads each damage point's Severity (looked up here) and routes it through whatever buffers and Severity pools the character module exposes.
- **Runtime Bucketing for Physical.** Lives in combat. The Threshold input comes from the weapon (equipment) or the ability (abilities); Damage Resilience comes from the character module.
- **Counter state.** Tracking the per-target Acid Counter and applying its turn-start halve-and-deal behavior. Lives in the conditions module as a hardcoded top-level field.
- **`condition` tag interpretation.** Whether a target "has metal armor" or a "subtype" is determined by the consuming module (combat with help from equipment / character).
- **Critical value override propagation.** The `critical_value` mechanic is consumed by dice resolution when a Roll resolves a damage check tagged with this Damage Type. The damage types module surfaces the value but never invokes it.
- **HP pool sizes and recovery rules.** The Severity names (`minor`/`moderate`/`major`) are configurable here, but what each pool's size is and how it refills lives in the character module. Any buffer that absorbs damage before it reaches a Severity pool (e.g. temporary hit points) is also a character/combat concern.

### Unassigned (no current owner)

- Cross-domain validation that every `condition` string used in a `damage_multiplier` (`target_has_metal_armor`, `target_has_subtype:undead`, etc.) is recognized by the consuming module. Today the tag is free-form and silent failure is possible.
- Cross-domain validation that every `condition_name` used in `inflict` (e.g. `shock`) corresponds to a real condition in the conditions module.
- A canonical home for the **threshold-bucketing formula** itself. Today it's only described prose in this glossary; once the combat domain is documented in this format, the formula migrates there.
