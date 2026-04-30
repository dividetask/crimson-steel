# Damage Types — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `damage_types_config.yaml`. The damage types module is a **reference** module: it exposes data about each damage type for other modules (combat, conditions, dice resolution, equipment) to consume. It does not apply damage, track HP, or evaluate roll results.

## Severity

**Severity**: A category that determines which Hit Point pool a damage point is applied to. The three severities, from least to most serious, are **minor**, **moderate**, and **major**. *(configurable)*

**Minor / Moderate / Major HP Pools**: The three severity-specific pools. Damage points fill the pool corresponding to the damage's Severity. The pools' sizes and recovery rules — and any buffer (such as temporary hit points) that absorbs damage before it reaches a Severity pool — live in the character module and are not a concern of this domain.

## Damage Types

**Damage Type**: A category of damage with a name, an associated Severity (or a runtime bucketing rule), a description, and a list of Mechanics. The damage type catalog is configurable; consuming modules look up a damage type by name to resolve its behavior.

**Severity Resolution**: Every Damage Type either declares a Severity (Fire is moderate; Necrotic is major) or is marked for **runtime bucketing**. Today only **Physical** uses runtime bucketing.

**Runtime Bucketing**: The rule used by Physical Damage. Points of damage fill the Minor pool until a count equal to **Threshold + Damage Resilience** is reached; the next points fill Moderate up to another Threshold + Damage Resilience; everything beyond goes to Major. The bucketing happens in the combat module; the damage types module only declares that Physical opts into the rule.

**Threshold**: A non-negative integer used by Runtime Bucketing. For weapon attacks, comes from the weapon. For abilities that deal Physical Damage directly (without a weapon), the Entry must declare its own Threshold — see `abilities_glossary.md`.

**Damage Resilience**: A per-character integer added to the Threshold during Runtime Bucketing. Owned by the character module.

## Mechanics

**Mechanic**: One element of a Damage Type's `mechanics` list. A dictionary with a `kind` field and additional fields specific to that kind. The damage types module surfaces these verbatim; consuming modules interpret them.

The recognized kinds today (more may be added as new damage types are introduced):

- **`damage_per_dice`** — adds bonus damage proportional to the number of dice rolled. Fields: `bonus` (integer added per group), `per` (group size). Fire's "+1 damage per 2 dice rolled" is `{kind: damage_per_dice, bonus: 1, per: 2}`. Consumed by the combat module.
- **`apply_acid_counter`** — adds to the target's Acid Counter (a built-in field on the conditions module — see `conditions_glossary.md`). Fields: `per_damage` (integer, default 1). Acid uses `{kind: apply_acid_counter, per_damage: 1}`. Consumed by combat, which calls `APPLY_ACID_DAMAGE` on conditions. The halve-and-deal behavior at turn start is hardcoded in the conditions module rather than declared here.
- **`damage_multiplier`** — multiplies inflicted damage under a condition. Fields: `factor` (number), `condition` (a free-form scope tag the consumer recognizes, e.g. `target_has_metal_armor`, `target_has_subtype:undead`). Electricity's "doubled vs metal armor" and Radiant's "double vs undead/shadow" both use this. Consumed by combat.
- **`inflict`** — inflicts a named condition by N points per damage point applied. Fields: `condition_name` (string), `per_damage` (integer). Cold's "two points of shock per point of damage" is `{kind: inflict, condition_name: shock, per_damage: 2}`. Consumed by the conditions module (or by combat as a router for built-in counters like Shock).
- **`critical_value`** — overrides the per-die critical-success contribution for rolls that resolve this damage type. Fields: `value` (integer, replaces `critical_modifier`). Emotional's "each critical rolled deals 3 instead of 2" is `{kind: critical_value, value: 3}`. Consumed by dice resolution.

The damage types module validates that every `kind` is one it recognizes, and that the kind's required fields are present. It does not validate `condition` or `condition_name` strings; those are interpreted by the consuming modules.

## Module Scope

The damage types module is strictly a **reference**. Given a damage type name, it returns:

- The type's Severity (or a flag indicating Runtime Bucketing).
- The type's display description.
- The type's Mechanics list.

It does **not**:

- Apply damage to creatures.
- Compute the bucketed split of Physical Damage (combat owns Runtime Bucketing).
- Track counters or apply conditions (conditions module).
- Track which creatures have metal armor or which subtypes apply (combat / equipment / character).
- Roll dice or modify roll results (dice resolution module consumes `critical_value` mechanics during a Roll).
