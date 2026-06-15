# Damage Overview

# Damage

When an attack or effect lands it deals damage. Every point of damage has a [[damage type]] and a [[damage severity]]. A creature dies when damage equals or exceeds a [[death threshold]].

# Damage Severity

Damage is tracked at one of three severities, healed worst-first:

- [[minor damage]] — bruises and shallow cuts; heals fastest.
- [[moderate damage]] — deep wounds and fractures.
- [[major damage]] — grievous crippling injuries; heals slowest. Each point of [[major damage]] imparts two points of [[pain]] reducing combat effectiveness.

# Damage Types

Every source of damage has a [[damage type]]:

- **Physical** — Tangible kinetic harm inflicted by physical forces such as weapons, gravity, or falling objects. All physical damage comes from one of the following categories: bludgeoning, slashing, and piercing. All physical damage is treated the same unless a creature has a resistance or vulnerability to a specific damage subtype. Physical damage always has a [[threshold]] value. The first points of physical damage are minor damage up to the [[threshold]], with damage beyond that [[threshold]] upgrading to moderate damage, and major damage if the damage exceeds twice the [[threshold]].
- **Fire** — A subtype of Elemental damage originating from heat, or open flames. When rolling for fire damage the total damage is increased by 1. Fire damage is always moderate damage.
- **Cold** — A subtype of Elemental damage originating from freezing temperatures. Cold damage is always minor damage but each point of damage inflicts an equal amount of [[shock]].
- **Acid** — A subtype of Elemental damage originating from caustic substances. Acid damage is always moderate damage and deals persistent damage each turn until it becomes exhausted.
- **Electricity** — A subtype of Elemental damage originating from electricity. Damage from Electricity is doubled against creatures wearing metal armor.
- **Radiant** — Harm caused by intense light and radiant energy — sunlight, searing brightness, heat radiation, and the burns they inflict. Radiant is typically minor damage. Against vulnerable creatures, such as undead and shadow based creatures, it deals double damage upgraded to major damage.
- **Force** — Pure magical kinetic energy that is not reduced against incorporeal enemies. Force damage is always minor damage.
- **Emotional** — A damage type representing acute psychological trauma, stress, or ego depletion that reduces a character's resolve and will to fight without leaving physical marks. Emotional damage is always minor damage. [[Criticals]] rolled for emotional damage do triple damage.
- **Necrotic** — A damage type representing accelerated biological decay and cell death that rapidly rots living tissue, muscles, and organic matter on contact. Necrotic damage is always major damage, but has no effect on the undead or creatures without biological bodies.

# Damage Reduction

@function Damage Reduction

A creature's [[damage reduction]] is subtracted from each incoming hit before it is dealt. Bonuses and penalties from armor, magic, or circumstances adjust it.

# Ascendancy Damage Reduction

@function Ascendancy Damage Reduction

[[ascendancy]] also shows up as damage: a higher-[[tier]] defender shrugs off part of a lower-Tier attacker's damage.

> **Ascendancy Damage Reduction** = {{Ascendancy Damage Reduction Formula}}

The Tier gap is the defender's Tier minus the attacker's effective Tier (Tier 0 counts as one-half); an attacker of equal or higher Tier is reduced by nothing.

# Glory

A weapon with the [[glory]] enchantment treats its wielder as one or more [[Tiers]] higher when attacking a higher-Tier foe, shrinking the [[Tier]] gap before ascendancy damage reduction applies — so the wielder loses less damage fighting up. Glory affects only weapon attacks.

# Damage Resilience

@function Damage Resilience

[[damage resilience]] is added to a weapon's [[weapon threshold]] when its damage is sorted into severities, so more resilience keeps more of a hit at the lighter severities. Bonuses and penalties adjust it the same way.

# Weapon Thresholds

Physical damage is sorted into severities by the weapon's [[weapon threshold]]: the first threshold + [[damage resilience]] points land as [[minor damage]], the next that many as [[moderate damage]], and the rest as [[major damage]]. Damage of other types uses its own fixed severity instead.

# Acid Damage

@function Acid Damage

Acid lingers on a creature as an [[acid counter]]. Each turn it deals that much [[minor damage]] and then halves, shrinking away over several turns:

> **Acid Damage** = {{Acid Damage Formula}}

Other recurring damage is handled the same way.

# Death Threshold

@function Death Threshold

A creature dies when any one of its three tracks — hit points, any single attribute, or magic toxicity — crosses its death threshold. Each threshold scales the track's maximum by the death multiplier ({{Death Multiplier}}):

> **Death Threshold** = {{Death Threshold Formula}}

# Additional Damage Checks

On a hit, an elemental weapon adds {{Elemental Weapon Dice}} dice to the attack. Each success deals 1 point of the weapon's element and a [[critical success|crit]] deals 2, while 1s do nothing; some elements also boost what a crit does. Other damage sources — emotional and the like — work the same way. The roll is resolved by the Additional Damage function in [Check Resolution](../check_resolution/check_resolution_overview.md).
