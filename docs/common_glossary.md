# Common Glossary

Terms defined in two or more module glossaries are consolidated here, organized by the module most responsible for the concept. Module glossaries reference these definitions rather than duplicating them.

## Advancement

**Tier**: Non-negative integer representing the Character's overall progression. Drives attribute bonuses, scaling-ability levels, and the HP/mana formulas. Tier 0 is treated as **0.5** in formulas (project-wide convention). Computed by Advancement from total class levels and tag-keyed breakpoints unless a Tier Override is set.

**Tier Override**: Optional integer on the Character entry that bypasses Advancement's auto-computation. Forwarded to Advancement at construction; when present, every Tier query returns it directly.

**Save Attribute**: One of the six attribute keys (`str`, `dex`, `con`, `int`, `wis`, `cha`). Classes and Entries reference saves by attribute key.

**Sticky Min Level**: A `min_level` carried by a context entry (an entry without a `name`) in an abilities list. Every following Ability inherits the rolling `min_level` until the next context entry. Used by both Advancement (class abilities) and Race (racial abilities).

## Damage Types

**Damage Type**: A category of damage with a name, an associated Severity (or runtime-bucketing rule), and a list of Mechanics. Defined in the damage_types catalog; consumed by abilities, combat, conditions, dice_resolution, and equipment.

**Severity**: A category that determines which Hit Point pool a damage point fills. Three values, least to most serious: **minor**, **moderate**, **major**. *(configurable)*

**Threshold**: Non-negative integer used by Runtime Bucketing for physical damage. For weapon attacks comes from the weapon; for ability-driven physical damage comes from the ability's `threshold` field. Combat picks the input.

**Damage Resilience**: A per-Character integer added to the Threshold during Runtime Bucketing. Sum of a tier-derived base (owned by Character) and a class contribution (owned by Advancement).

## Skills

**Skill Prowess**: `Skill Ranks + floor(attribute / attribute_contribution_divisor)`. The single integer the skills domain hands to dice resolution; partitioned there into Dice Count + Competency Bonus + Starting Value.

**Mandatory Skill**: A skill flagged `mandatory: true` in `skills.yaml`. Every Class contributes ranks regardless of the Character's chosen-skills list. The standard Mandatory Skill is `martial`.

**Prefix Match**: A list entry ending with `_` matches any skill that starts with that prefix and has more after the underscore. Example: `perform_` matches `perform_dance` but not `perform` itself. Used by Advancement when resolving a Skill against a Class's skill lists.

## Combat

**Round**: The in-game time unit. Signed integer counter incremented when the turn pointer wraps past the last Combatant. Combat owns the timeline; conditions reads `current_round` from callers.

## Conditions

**Magic Toxicity**: A creature's accumulated burden from repeated magical exposure. Single non-negative signed integer counter on the conditions instance; never negative. Maximum (typically derived from a configurable attribute) lives on Character; the caller enforces the cap. Per project convention, "magic toxicity" is preferred over "mana saturation".

## Abilities

**Ability**: A named class- or race-granted feature the Character earns at a configured level threshold. Stored under a Class's or Race's `abilities:` list. May be a Procedural Ability (one-shot, no per-creature state), a Stateful Counterpart (lives in conditions), or an Always-On Modifier.

**Effect**: A single effect string in an Entry. One of: the literal `"0"` or `"none"` (no effect); a non-empty string interpreted as a named non-damage effect (passed through opaquely; conditions validates at apply time); or a damage expression of the form `"<formula> damage"` or `"<formula> <severity> damage"`. Damage Effects must have a determinable Severity (explicit in the string, or implicit from the Entry's Damage Type).

> Note: the conditions module previously used "Effect" for an active modifier instance; that concept is now called **Active Effect** in `conditions_glossary.md`.
