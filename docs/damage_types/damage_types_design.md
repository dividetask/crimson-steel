# Damage Types — Design

Strict reference data. Combat, conditions, dice resolution, and equipment implement the actual behaviors; this domain just declares what each type *means*.

## Key Operations

### Severity resolution

A type either declares a Severity or sets `runtime_bucketing: true` — never both (validator rejects). Today only **Physical** uses runtime bucketing.

### Mechanic kinds and consumer routing

| `kind` | Consumer | Effect |
|---|---|---|
| `damage_per_dice` | combat | Bonus damage scaling with dice count. |
| `apply_acid_counter` | combat → conditions | Combat calls `APPLY_ACID_DAMAGE`; Acid Counter behavior is hardcoded in conditions. |
| `damage_multiplier` | combat | Multiplies damage by `factor` under a `condition`. |
| `inflict` | combat → conditions | Combat invokes the right conditions API per damage point. |
| `critical_value` | dice resolution | Overrides `critical_modifier` when this type is at stake. |

`apply_acid_counter` names a specific built-in counter because conditions exposes those counters as hardcoded fields rather than as a generic catalog. Adding a new built-in counter requires a code change in conditions *and* a corresponding mechanic kind here.

`condition` strings inside `damage_multiplier` (`target_has_metal_armor`, `target_has_subtype:undead`) are free-form; the consuming module decides whether it understands the tag. Damage types does not validate them.

### The Physical exception

Physical's Severity isn't fixed at lookup time. Two consequences:

- The damage types module returns a "needs runtime bucketing" indicator rather than a Severity for Physical lookups.
- Abilities that deal Physical Damage must declare a `threshold` (validation lives in **abilities**; for weapons it comes from the weapon).

The bucketing formula itself (Threshold + Damage Resilience filling Minor, then Moderate, then Major) lives in combat.

## Responsibilities

### Owned

- Loading and validating `damage_types_config.yaml`.
- The Damage Type catalog (name, Severity or runtime-bucketing flag, description, Mechanics).
- Validating each Mechanic's `kind` and required fields; validating that `runtime_bucketing` and `severity` are mutually exclusive.

### Not owned

- **Applying damage** — combat routes points through Severity pools.
- **Runtime Bucketing for Physical** — combat. Threshold input from weapon (equipment) or ability (abilities); Damage Resilience from character.
- **Counter state** — conditions (Acid Counter and similar).
- **`condition` tag interpretation** — consuming module.
- **Critical value override propagation** — dice resolution consumes `critical_value`.
- **HP pool sizes and recovery** — character/conditions.

### Unassigned

- Cross-domain validation that `condition` strings in `damage_multiplier` and `condition_name` strings in `inflict` are recognized by their consuming modules.
- A canonical home for the threshold-bucketing formula itself; it migrates to combat once that doc lands in this format.
