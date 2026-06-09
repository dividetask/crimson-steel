# Creatures — Glossary

Defines the vocabulary used by the Creatures design and tests. Creatures owns identity, base attributes, the Aspect mechanism, the Advancement schema, and composition of derived values across Aspects, Classes, and other domains.

## Identity

**Creature**: A single playable or non-playable being the rules apply to.

**Player**: The person controlling a Creature. Empty for Creatures the Game Master runs.

**Tag**: A free-form label classifying a Creature. Tags drive Tier auto-computation and may be referenced by other domains.

## Attributes

**Attribute**: A category of physical or mental characteristics that is quantified by a single number. *(configurable)*

**Base Attribute**: A number representing a Creature's raw physical or mental ability in a specific Attribute before accounting for magical effects, racial bonuses, or benefits from their Tier.

**Effective Attribute**: A number representing a Creature's raw physical or mental ability in a specific Attribute after accounting for magical effects, racial bonuses, or benefits from their Tier.

**Save Attribute**: One of the six Attributes, used when a Creature rolls to resist an effect targeting that Attribute. Every Attribute has a corresponding Saving Throw.

## Race

**Race**: A Creature's biological or metaphysical heritage. Stored as a single key on the Creature; the catalog resolves the key through a `parent:` chain to assemble the effective Race.

**Race Entry**: A single named entry in `creatures_race.yaml`. May have a `parent:` reference to another Race Entry. The chain ends at an entry whose `parent` is null.

**Race Chain**: The ordered sequence of Race Entries reached by following an entry's `parent:` reference back to the root. A child Race inherits and extends its parent's contributions.

**Race Chain Walk**: The resolution that consumes a Race Chain to produce the effective Race — first-in-chain wins for `size` and `speed`, accumulated for `attribute_adjustments`, concatenated with child-wins dedup for `abilities`.

## Advancement and Tier

(See `common_glossary.md` Advancement section, which points here.)

**Tier Breakpoints**: The Total Class Levels at which a Creature reaches each Tier.

**Inherent Bonus**: A bonus that stacks into the Effective Attribute.

**Tier Attribute Advancement**: The per-Creature flat list of which Attributes received the Tier Inherent Chosen Bonus, in pick order across Tiers. Chunked by `Tier Inherent Chosen Bonus Count` to recover each Tier's picks.

## Classes

**Class**: A definition in the Advancement configuration. A Creature can hold levels in one or more Classes.

**Class Level**: A Creature's level in a specific Class.

**Total Class Level**: The sum of a Creature's levels across every Class.

**Archetype**: A Class that is taken in place of its Parent Class once the Creature has reached the eligibility level. When a Creature adopts an Archetype, all of their levels in the Parent Class convert to levels in the Archetype, and they cannot subsequently hold levels in the Parent Class. Archetypes inherit absent fields from their Parent Class and additively adjust proficiency categorizations.

**Parent Class**: A Class that offers one or more Archetypes. The Archetype's `parent_class:` field names this Class.

**Archetype Exclusivity**: The rule that a Creature's `advancement.classes` map must not contain both a Parent Class and one of its Archetypes, nor two Archetypes of the same Parent Class.

**Class Ability Progression**: A per-Class map from Class Level to the Abilities granted at that Level.

**Trained Skill**: A Skill the Creature has chosen to invest in under a given Class. Stored in that Class Entry's `skills:` list.

**Skill Pick Budget**: The number of Skill choices a Creature is *expected* to have, computed from `Skill Pick Formula` (`floor(int/4) + bonus_skills`) against the Creature's Effective Intelligence and the chosen Class's `bonus_skills` field. The count is fixed for the Class — it does *not* scale with Class Level (a higher-level Creature advances the same Skills further rather than training more of them). Advisory — Creatures does not enforce the count.

## Random Encounter Tables and Spawns

**Random Encounter Table**: A named table the DM rolls to populate an upcoming Combat. Reuses Equipment's Loot Roll Row shape — Guaranteed / Independent Chance / Weighted Choice / Gated Weighted Choice rows with `when` and `as` semantics — but resolves each row to Spawn Refs rather than Item Stacks.

**Spawn Ref**: One instruction inside a Random Encounter Row payload. Names a template Creature and a count; each evaluation produces that many fresh Creature records via Spawn Creature From Template.

**Spawned Creature**: A Creature record created by Spawn Creature From Template or Roll Random Encounter. Persistent — round-tripped by Save Creatures — but typically deleted after combat resolves, via Equipment's post-combat loot stub.

**Enemy Template**: A long-lived Creature record tagged `enemy_template`, kept as a source-of-truth for cloning. Templates are never themselves added to a Combat; Spawned Creatures (instances cloned from a template) are.
