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

## Aspects

**Aspect**: A category of inherited or chosen attributes that contributes adjustments and Granted Abilities. Race is the prototypical Aspect category; the consuming project may add more.

**Aspect Entry**: A single named entry within an Aspect category. A Creature references one Aspect Entry per category.

**Aspect Chain**: The ordered sequence of Aspect Entries reached by following an entry's parent reference back to the root. A child Aspect Entry inherits and extends its parent's contributions.

**Race**: A Creature's biological or metaphysical heritage. The default Aspect category shipped with Creatures.

## Advancement and Tier

(See `common_glossary.md` Advancement section, which points here.)

**Tier Breakpoints**: The Total Class Levels at which a Creature reaches each Tier.

**Inherent Bonus**: A bonus that stacks into the Effective Attribute.

**Tier-Up Choice**: The per-Creature record of which Attributes received the Tier Inherent Chosen Bonus at each Tier.

## Classes

**Class**: A definition in the Advancement configuration. A Creature can hold levels in one or more Classes.

**Class Level**: A Creature's level in a specific Class.

**Total Class Level**: The sum of a Creature's levels across every Class.

**Class Chain**: The ordered sequence of Class definitions reached by following a Class's Parent Class reference back to the root. A child Class inherits absent fields from its ancestors and may override or extend proficiency categorizations.

**Archetype**: A Class that is can be taken after reaching a certain level in it's Parent Class. All levels from the Parent Class are converted to The Archtype Class when the Archtype is taken. 

**Parent Classs**: A Class that offers one or more Archtype Classes upon reaching a specific level.

**Class Ability Progression**: A per-Class map from Class Level to the Abilities granted at that Level.

**Trained Skill**: A Skill the Creature has chosen to invest in under a given Class.

**Skill Pick Budget**: The number of Skill choices a Creature is *expected* to have per Class Level of the choosen Class.

## Random Encounter Tables and Spawns

**Random Encounter Table**: A named table the DM rolls to populate an upcoming Combat. Reuses Equipment's Loot Roll Row shape — Guaranteed / Independent Chance / Weighted Choice / Gated Weighted Choice rows with `when` and `as` semantics — but resolves each row to Spawn Refs rather than Item Stacks.

**Spawn Ref**: One instruction inside a Random Encounter Row payload. Names a template Creature and a count; each evaluation produces that many fresh Creature records via Spawn Creature From Template.

**Spawned Creature**: A Creature record created by Spawn Creature From Template or Roll Random Encounter. Persistent — round-tripped by Save Creatures — but typically deleted after combat resolves, via Equipment's post-combat loot stub.

**Enemy Template**: A long-lived Creature record tagged `enemy_template`, kept as a source-of-truth for cloning. Templates are never themselves added to a Combat; Spawned Creatures (instances cloned from a template) are.
