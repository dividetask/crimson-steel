# Proficiencies — Glossary

Defines the vocabulary used by `proficiencies_design.md` and `proficiencies_tests.md`. Proficiencies owns the canonical Skill catalog and the rules that translate a Creature's training into the integers dice resolution consumes. *(configurable)* values come from `proficiencies_config.yaml` and `skills.yaml`.

## Skills

**Skill**: A category of training listed in the Skill catalog. Each Skill has an attribute and a description.

**Set Skill**: A group of skills that share an Attribute and common theme.

**Set Skill Prefix**: The first words shared by all Skills in a Set Skill.

## Ranks and Prowess

**Attribute Contribution Divisor**: Divisor applied to an attribute value before it folds into Prowess. The same divisor applies to every Skill. *(configurable, default 2)*

**Attribute Contribution**: The contribution the driving attribute makes to Prowess.

**Non-Proficiency Penalty**: Penalty applied to Skill Checks for Skills a Creature has no Proficiency Ranks in. *(configurable, default −2)*

**Direct Prowess**: A Creature's Prowess in a specific Skill which does not account for Prowess in Skills that can be Substituted for the relevant Skill.

**Substituted Prowess**: A Creature's Prowess in a Skill that can be substitued for the relevant Skill.

**Proficiency Prowess**: A Creature's Prowess for a Skill when accounting for Direct Prowess and Substituted Prowess.

**Competency Modifier**: The Competency bonus or penalty associated with a Skill calculated from the Creature's Prowess and any applicable Non-Proficiency Penalties.
