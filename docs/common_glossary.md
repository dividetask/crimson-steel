# Common Glossary

Terms defined in two or more module glossaries are consolidated here, organized by the module most responsible for the concept. Module glossaries reference these definitions rather than duplicating them.

## Advancement

**Tier**: A Creature's overall progression. Drives an Inherent bonus, Ascendancy bonus or penalty in Opposed Checks, and the HP and mana formulas. Tier 0 counts as one half in formulas and as zero when indexing tier-keyed tables (project-wide convention). Computed by Advancement from total class levels and tag-keyed breakpoints unless a Tier Override is set.

**Tier Override**: An override that bypasses Advancement's auto-computed Tier. When set, every Tier query returns the override.

**Save Attribute**: One of the six attributes (Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma). Classes and Entries reference saves by the attribute that drives them.

## Damage Types

(See `combat/combat_glossary.md`.) Combat owns **Damage Type**, **Severity**, **Threshold**, **Damage Resilience**, and the Damage Type catalog (including the Damage Type Mechanics for Radiant, Fire, Acid, Electricity, Cold, and the physical types). Other domains reference these terms by name without redefining.

## Proficiency

Proficiencies-owned terms (Skill, Proficiency Ranks, Direct/Substituted/Proficiency Prowess, Prefix Match, Dice Cap, Competency Modifier, etc.) are defined in `proficiencies/proficiencies_glossary.md`. The "every Class trains every save" rule is a Creatures/Advancement concern and lives in that domain's glossary when written.

## Conditions

**Magic Toxicity**: A Creature's accumulated exposure to magical effects. Increases over time and has no hard maximum.

**Toxicity Threshold**: A per-Creature derived value that gates positive effects which would impose Magic Toxicity. Computed from the Creature's Charisma and Tier per the Conditions design. *(configurable)*

**Toxicity Block**: The rule that an effect imposing Magic Toxicity is rejected outright when current Magic Toxicity exceeds the Toxicity Threshold and the effect is classified as positive (magical healing, buffs, etc.). Natural healing is not blocked.

**Toxicity Damage**: Ability Damage to Charisma inflicted when Magic Toxicity rises further past the Toxicity Threshold from any non-positive source. See Conditions for the magnitude rule.

## Abilities

(See `abilities/abilities_glossary.md`.) Abilities owns **Ability** (the umbrella for anything a Class or Race grants), **Catalog Ability**, **Spell**, **Talent**, **Stateful Ability**, **Always-On Modifier Ability**, **Granted Ability**, **Effect** (the per-Ability effect string), **Trigger Spec**, and the Variant / Effect Hash / Channeling / Reservoir vocabulary. Other domains reference these terms by name without redefining.

Note: the Conditions domain owns **Active Effect** — an instance of an Effect currently applied to a Creature — which is distinct from the Abilities **Effect** above.
