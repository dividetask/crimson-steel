# Damage Types — Glossary

Reference module: exposes data about each damage type for combat, conditions, dice resolution, and equipment to consume. Does not apply damage, track HP, or evaluate roll results. *(configurable)* values come from `damage_types_config.yaml`.

## Severity

(Severity, Threshold, Damage Resilience: see common glossary.)

**Minor / Moderate / Major HP Pools**: The three severity-specific pools damage points fill. Pool sizes, recovery, and any pre-pool buffer (e.g. temporary HP) live in the character / conditions modules.

## Damage Types

(Damage Type: see common glossary.)

**Severity Resolution**: Every Damage Type either declares a Severity (Fire is moderate; Necrotic is major) or is marked for **Runtime Bucketing**. Today only **Physical** uses Runtime Bucketing.

**Runtime Bucketing**: The rule used by Physical Damage. Points fill Minor until `Threshold + Damage Resilience` is reached, then fill Moderate up to another `Threshold + Damage Resilience`, then Major. Bucketing happens in combat; this module only declares that Physical opts into the rule.

## Mechanics

**Mechanic**: One element of a Damage Type's `mechanics` list. Dictionary with a `kind` field plus kind-specific fields. The damage types module surfaces these verbatim; consumers interpret them.

Recognized kinds:

- **`damage_per_dice`** — bonus damage proportional to dice rolled. Fields: `bonus`, `per`. Fire's "+1 per 2 dice" is `{kind: damage_per_dice, bonus: 1, per: 2}`. Consumed by combat.
- **`apply_acid_counter`** — adds to the target's Acid Counter (a built-in field on conditions — see `conditions_glossary.md`). Fields: `per_damage` (default 1). Consumed by combat, which calls `APPLY_ACID_DAMAGE` on conditions.
- **`damage_multiplier`** — multiplies inflicted damage under a condition. Fields: `factor`, `condition` (free-form scope tag, e.g. `target_has_metal_armor`, `target_has_subtype:undead`). Consumed by combat.
- **`inflict`** — inflicts a named condition by N points per damage point. Fields: `condition_name`, `per_damage`. Cold's "two shock per damage" is `{kind: inflict, condition_name: shock, per_damage: 2}`. Consumed by conditions (or combat as router for built-in counters like Shock).
- **`critical_value`** — overrides per-die critical-success contribution for rolls of this damage type. Field: `value` (replaces `critical_modifier`). Consumed by dice resolution.

This module validates that `kind` is recognized and that required fields are present. It does not validate `condition` / `condition_name` strings — those are interpreted by consumers.

## Module Scope

Owns:
- Returning Severity (or Runtime Bucketing flag), description, and Mechanics list for a damage type.

Does not:
- Apply damage or compute the Runtime Bucketing split (combat).
- Track counters or conditions (conditions).
- Track which creatures have metal armor or subtypes (combat / equipment / character).
- Roll dice or modify roll results (dice resolution consumes `critical_value`).
