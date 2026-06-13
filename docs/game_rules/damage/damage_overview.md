# Damage Overview

# Damage

When an attack or effect lands it deals damage. Every point of damage has a [[damage type]] and a [[damage severity]], and damage accumulates on a creature until it crosses a [[death threshold]].

# Damage Types

Every source of damage has a [[damage type]]:

- **Physical** — bludgeoning, slashing, and piercing.
- **Elemental** — fire, cold, acid, and electricity.
- **Radiant**, **emotional**, and **force**.

A damage type sets the [[damage severity]] of the damage it deals, and may carry a mechanic — for example acid builds an Acid Counter, and cold inflicts Shock.

# Damage Severity

Damage is tracked at one of three severities, healed worst-first:

- [[minor damage]] — bruises and shallow cuts; heals fastest.
- [[moderate damage]] — deep wounds and fractures.
- [[major damage]] — grievous injuries; heals slowest.

# Damage Reduction

@function Damage Reduction

A creature's [[damage reduction]] is subtracted from each incoming hit before it is dealt. Armor and tough hide raise it, and bonuses and penalties adjust it, with same-type entries stacking as on any other roll.

# Ascendancy Damage Reduction

@function Ascendancy Damage Reduction

[[ascendancy]] also shows up as damage: a higher-[[tier]] defender shrugs off part of a lower-Tier attacker's damage.

> **Ascendancy Damage Reduction** = {{Ascendancy Damage Reduction Formula}}

The Tier gap is the defender's Tier minus the attacker's effective Tier (Tier 0 counts as one-half); an attacker of equal or higher Tier is reduced by nothing.

# Glory

A weapon with the [[glory]] enchantment treats its wielder as one or more Tiers higher when attacking a higher-Tier foe, shrinking the Tier gap before ascendancy damage reduction applies — so the wielder loses less damage fighting up. Glory affects only weapon attacks, never spells or abilities.

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
