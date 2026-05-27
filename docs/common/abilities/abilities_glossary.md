# Abilities — Glossary

Defines the vocabulary used by `abilities_design.md` and `abilities_tests.md`. The Abilities domain is a strict **reference**: it exposes data about Spells, Talents, and granted features for other modules to consume. It does not track active effects on Creatures — that lives in Conditions. *(configurable)* values come from `abilities_config.yaml`. Schemas, field names, and operation details are defined in `abilities_design.md`; this file restricts itself to vocabulary.

## Abilities

**Ability Type**: A Ability's broad category — Spell or Talent.

**Passive Ability**: An Ability that does not require activation.

**Active Ability**: An Ability that does requires a creature to take an action to activate.

**Stateful Ability**: An Ability whose behavior includes per-Creature mutable state — a counter, timer, or pool.

## Variants

**Ability Rank**: The Proficiency Ranks investing in the Skill used by the specified Ability. (See Proficiencies)

**Ability Skill**: The skill used with and associated with an Ability. Some Abilities may allow a Creature to choose from multiple Skills when using the Ability.

**Spell School**: The magical discipline a Spell belongs to.

**Variant Axis**: The dimension along which a Ability has multiple Variants.

**Variant**: One form of a Ability along its Variant Axis.

**Aspect**: A label on the Aspect axis (for example Fire or Acid).

## Activation Time

**Activation Time**: How long it takes to use an Ability.

**Action Alias**: A categorical activation time tied to the Combat action economy — Free, Bonus, Reaction, Main, or Full Turn.

**Real-Time Alias**: An activation time measured in wall-clock minutes — 1 minute, 10 minutes, 1 hour, 1 day. *(configurable)*

**Turn-Count Activation**: A multi-turn activation expressed directly as a turn count (e.g., a two-turn cast).

## Target

**Ability Target**: Who or what the Ability affects.

**Willing Target**: An Ability that only affects targets that consent.

## Range

**Ability Range**: The distance over which the Ability reaches its target.

**Ability Range Category**: A short description of an Abilities range that can be used to calculate the maximum distance a Creature can target with the specified Ability. *(configurable)*

**Reach**: Distance in feet a Creature can touch without moving.

## Area

**Area**: The area-of-effect of an Ability. Carries shape, size , and an Area Anchor.

**Area Anchor**: Where an Area is centered.

## Channeling

(Channeled Ability and Channeling: see common glossary.)

## Saves

**Save Attribute**: One of the six attributes, or "no save" when an Ability does not allow one.

**Save Effect**: An Effect associated with a Save outcome.

## Spellcasting without an Ability

**Ritual**: The act of drawing out a ritual circle that will allow a creature to cast a single Spell. The Ritual is consumed and destroyed after the Spell is cast.

**Item Form**: A physical form a Spell may be packaged in. *(configurable)*

## Effects

**Effect**: A single effect produced by an Ability.

**Effect Duration**: How long an Ability's effect persists.

**Unconditional Effect**: An Effect that applies regardless of the results of a save or attack roll.

(Damage Type: see combat glossary.)

## Triggers

**Trigger**: A circumstance that allows an Ability to take Effect.

**Trigger Condition**: The action or occurrence that the Trigger fires during.

## Modifiers

**Modifier**: A named numeric adjustment to some target value on a Creature — attack, save, speed, damage reduction, a skill, etc.

**Bonus Type Name**: The category a Modifier belongs to.

**Bonus Types List**: The canonical set of valid Bonus Type Names.

**Modifier Direction**: The sign-flavor a Modifier appears as — Bonus, Penalty, or Starting.

**Modifier Entry**: The structured form a Modifier appears in on an Ability.
