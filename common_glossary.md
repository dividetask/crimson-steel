# Common Glossary

Terms defined in two or more module glossaries are consolidated here, organized by the module most responsible for the concept. Module glossaries reference these definitions rather than duplicating them.

## Advancement

**Tier**: Non-negative integer representing the Character's overall progression. Drives an Inherent bonus, Ascendancy bonus/penalty for Opposed Checks, and the HP/mana formulas. Tier 0 is treated as **0.5** in formulas and **0** for array indexes (project-wide convention). Computed by Advancement from total class levels and tag-keyed breakpoints unless a Tier Override is set.

**Tier Override**: Optional integer on the Character entry that bypasses Advancement's auto-computation. Forwarded to Advancement at construction; when present, every Tier query returns it directly.

**Save Attribute**: One of the six attribute keys (`str`, `dex`, `con`, `int`, `wis`, `cha`). Classes and Entries reference saves by attribute key.

## Damage Types

**Damage Type**: A category of damage with a name, an associated Severity (or runtime-bucketing rule), and a list of Mechanics. Defined in the damage_types catalog; consumed by abilities, combat, conditions, dice_resolution, and equipment.

**Severity**: A category that determines which Hit Point pool a damage point fills. Three values, least to most serious: **minor**, **moderate**, **major**. *(configurable)*

**Threshold**: Non-negative integer used by Runtime Bucketing for physical damage. For weapon attacks comes from the weapon; for ability-driven physical damage comes from the ability's `threshold` field. Combat picks the input.

**Damage Resilience**: A per-Character integer added to the Threshold during Runtime Bucketing. Sum of contributions from multiple sources: a tier-derived base (Character), a class contribution (Advancement), worn armor and magical-item bonuses (Equipment), and active abilities or conditions (Conditions).

## Proficiency

**Proficiency**: Umbrella term for the trainable tracks every Character has ranks in.

**Proficiency Prowess**: `Proficiency Ranks + floor(attribute / attribute_contribution_divisor)`. The single integer the proficiency domain hands to dice resolution

**Mandatory Proficiency**: A Proficiency every Class contributes ranks to regardless of the Character's chosen-skills list. The standard mandatory Skill is `martial` (flagged `mandatory: true` in `skills.yaml`); every Save Attribute is also mandatory (every Class trains every save).

**Prefix Match**: A list entry ending with `_` matches any skill that starts with that prefix and has more after the underscore. Example: `perform_` matches `perform_dance` but not `perform` itself. Used by Advancement when resolving a Skill against a Class's skill lists.

## Conditions

**Magic Toxicity**: A creature's accumulated exposure to magical effects. Non-negative integer counter on the conditions instance with no hard maximum.

**Toxicity Threshold**: Per-Character derived value gating non-harmful effects that would impose Magic Toxicity (see Acceptance Check). Default formula: `charisma × tier` (Tier 0 = 0.5 per project convention). Configurable.

**Acceptance Check**: Before any **non-harmful** effect that would impose Magic Toxicity on a creature lands, compare current Magic Toxicity to the Toxicity Threshold. If `current < threshold`, the effect applies (and may push toxicity above the threshold). If `current ≥ threshold`, the effect **fails** and inflicts the **Magic Poisoning** affliction instead.

**Magic Poisoning**: Affliction inflicted by a failed Acceptance Check. See Conditions

## Abilities

**Ability**: A named class- or race-granted feature the Character earns at a configured level threshold. Stored under a Class's or Race's `abilities:` list. An Ability has one or more **flavors**:
- **Procedural** — triggers during a specific action (attack, heal, save, etc.) and resolves immediately; may inflict effects on targets but leaves no per-creature state on the user.
- **Stateful** — maintains per-creature state on the user (Rage timer, Bardic Inspiration counter). Lives in conditions.
- **Always-On Modifier** — passive numeric bonus while the user has the ability. Lives in `modifiers:`.

Most abilities have a single flavor; some combine (e.g., a passive bonus plus a triggered effect on certain actions).

**Effect**: A single effect string in an Entry. One of: the literal `"none"` (no effect); a non-empty string interpreted as a named non-damage effect (passed through opaquely; conditions validates at apply time); or a damage expression of the form `"<formula> damage"` or `"<formula> <severity> damage"`. Damage Effects must have a determinable Severity (explicit in the string, or implicit from the Entry's Damage Type).

> Note: the conditions module previously used "Effect" for an active modifier instance; that concept is now called **Active Effect** in `conditions_glossary.md`.
