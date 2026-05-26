# Conditions — Glossary

Defines the vocabulary used by `conditions_design.md` and `conditions_tests.md`. Conditions tracks each Creature's mutable state — HP damage, Ability Damage, Temporary Hit Points, Mana Spent, Magic Toxicity, Shock, the Acid Counter, ongoing Afflictions, and Active Effects. *(configurable)* values come from `conditions_config.yaml`. The Affliction catalog lives in `afflictions.yaml`; the Effect Name catalog lives in `effect_names.yaml`.

## Hit Points and Damage

**Minor Damage**: Bruises and minor cuts. The lowest level of damage and the fastest to heal.

**Moderate Damage**: Lacerations and bone fractures. Damage that takes longer to heal but not the most severe.

**Major Damage**: Internal injuries and broken bones. The highest level of damage and the slowest to heal.

**Temporary Hit Points**: Magical reservoir of hit points that disappear when the effect ends. These hit points absorb damage preveting real damage from occurring.

**Heal Cascade**: A worst-first heal. A heal supplies one pool per Severity; each pool tries to heal its Severity, with any leftover draining into the next-worse pool. Excess past Minor is wasted.

## Ability Damage

**Ability Damage**: Damage dealt to ability scores. Tracked per attribute per Severity; insertion order across attributes is preserved so the Ability Heal Cascade can heal first-affected first.

**Ability Heal Cascade**: Heal Cascade applied to Ability Damage. Within a Severity, heal points pop damage from attributes in the order they were first affected.

## Mana

**Mana**: A Creature's expendable magical energy resource.

**Current Mana**: The Creature's currently available Mana.

## Natural Recovery

**Natural Recovery**: The process of recovering from negative effects through natural healing as opposed to magical effects.

**Recovery Tick**: The smallest amount of time that needs to pass to recover from injuries. *(configurable: rounds per Recovery Tick.)*

**Recovery Mode**: Slow or Fast. Slow represents recovery while travelling or otherwise active; Fast represents bed rest or active care from a healer.

**Heal Rate**: How quickly HP Damage heals at each Tier and Severity in each Recovery Mode. Higher Tiers heal faster; Minor heals fastest at every Tier; Major heals slowest. *(configurable)*

**Ability Heal Rate**: How quickly Ability Damage heals. Each heal point pops one queued Ability Damage point at that Severity in first-affected order. *(configurable)*

## Magic Toxicity

**Toxicity Source**: How a Magic-Toxicity-imposing effect is classified — positive (magical healing, voluntary attunement, buffs) or otherwise (harmful magic, environmental exposure). Toxicity Block applies only to positive sources; Toxicity Damage applies to any source.

## Death

**Death Threshold**: A Creature is Dead when any one of the three Death Tracks (HP, Attribute, Toxicity) has crossed its threshold. Each threshold is derived from a corresponding Creature maximum scaled by the Death Multiplier. *(configurable)*

**Death Multiplier**: The multiplier applied to each Death Track's maximum to produce the death threshold. *(configurable)*

## Shock

**Shock**: A counter of battlefield disorientation. Reduces dice from the Combat Pool.

## Afflictions

**Affliction**: An ongoing negative condition.

**Potency**: A number quantifying the severity of an Affliction.

**Active Affliction**: An Affliction the Creature currently carries. A Creature may carry several at once.

**Affliction Category**: A label classifying an Affliction — poison, disease, curse, bleed, other, etc.

**Inflicter Tier**: The highest Tier among the sources that inflicted an Affliction since it last cleared.

**Save Frequency**: How often an Affliction resolves on its own — every round, minute, hour, day, month, or year.

**Affliction Rule**: The Affliction's spec in the catalog — its save attribute, category, frequency, and per-resolution behavior.

**Affliction Effect**: What an Affliction resolution produces — HP damage at a Severity, Ability damage to an attribute at a Severity, or a named effect for a duration.

**Pending Afflictions**: Active Afflictions currently due to resolve.

**Active Effect**: A modifier currently applied to the Creature. Covers both buffs and debuffs.
