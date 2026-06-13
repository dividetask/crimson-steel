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

# Death Threshold

@function Death Threshold

A creature dies when any one of its three tracks — hit points, any single attribute, or magic toxicity — crosses its death threshold. Each threshold scales the track's maximum by the death multiplier ({{Death Multiplier}}):

> **Death Threshold** = {{Death Threshold Formula}}

# Additional Damage Checks

Some weapons and abilities — elemental weapons and the like — deal additional damage that is rolled separately from the main hit. That extra damage is resolved by its own check through a function in [Check Resolution](../check_resolution/check_resolution_overview.md).
