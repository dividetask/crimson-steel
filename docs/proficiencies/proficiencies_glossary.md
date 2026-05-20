# Proficiencies — Glossary

Defines the vocabulary used by `proficiencies_design.md` and `proficiencies_tests.md`. Proficiencies owns the canonical Skill catalog and the rules that translate a Creature's training into the integers dice resolution consumes. *(configurable)* values come from `proficiencies_config.yaml` and `skills.yaml`.

## Skills

**Skill**: A category of training listed in the Skill catalog. Each Skill has an attribute and a description. The catalog ships with the domain in `skills.yaml`.

**Set Skill**: A Skill whose key ends in `_` (e.g., `perform_`, `craft_`, `profession_`, `game_`). The catalog entry defines the family; concrete instances are created by the consuming project with a free-form suffix and inherit the family's attribute and description. A bare Set Skill key is invalid as a Creature rank lookup — Creatures store ranks only under concrete Set Instances.

**Set Instance**: A concrete Skill key formed by appending a suffix to a Set Skill's key (e.g., `perform_dance`, `craft_blacksmith`). Set Instances are not enumerated in the catalog; they are recognized at lookup time via Prefix Match.

**Restricted Skill**: A Skill listed in `Restricted Skills` in the config. The Floor Ability cannot apply to a Restricted Skill. The Substitution Map may still target it.

## Ranks and Prowess

**Proficiency Ranks**: The training a Creature has in a specific Skill (or in any other proficiency a caller queries via attribute override). Sourced from the Creature accessor.

**Attribute Contribution Divisor**: Divisor applied to an attribute value before it folds into Prowess. The same divisor applies to every Skill. *(configurable, default 2)*

**Attribute Contribution**: The contribution the driving attribute makes to Prowess — the attribute value divided by the Attribute Contribution Divisor, rounded down.

**Non-Proficiency Penalty Value**: Penalty applied to Prowess when ranks are zero. *(configurable, default −2)*

**Direct Prowess**: The Prowess computed from the queried key's own ranks (lifted by the Floor Ability when applicable) and the queried key's driving attribute.

**Substituted Prowess**: The Prowess computed from a source key's ranks and driving attribute, when the Substitution Ability is present and the Substitution Map points the source at the queried key. There may be multiple matching sources; only the highest Substituted Prowess is kept.

**Proficiency Prowess**: The higher of Direct Prowess and Substituted Prowess (when produced). The single value Proficiencies feeds to dice resolution's Prowess translator. Direct Prowess wins ties.

**Dice Cap**: The maximum dice the Creature can spend on a roll for this Proficiency. Computed by dice resolution from the Proficiency Prowess and returned alongside the Competency Modifier. Distinct from dice resolution's Maximum Dice Count (the system-wide cap on any roll) and from a Creature's Combat Pool (the dice the Creature has overall).

**Competency Modifier**: The Competency-typed bonus or penalty returned alongside the Dice Cap. Absent when the value is zero. Proficiencies emits no other modifier types.

## Substitutions

**Prefix Match**: Resolution rule for a concrete Skill key against the catalog. If the key has no exact catalog entry, Proficiencies finds the catalog entry whose key ends in `_` and is a prefix of the queried key.

**Floor Ability**: The configurable name of the ability that grants a minimum Direct Prowess ranks of `floor(granting class level / 2)` on every non-Restricted catalog Skill the Creature is queried for. The "granting class level" is the level of the Class (or other source) that granted the ability — multi-classing does not stack the minimum. The Floor Ability never affects the driving attribute, never lifts a Substituted Prowess source's ranks, and never applies to keys without a catalog entry. *(configurable, default `jack_of_all_trades`)*

**Substitution Ability**: The configurable name of the ability that lets the Prowess of a source key substitute for the Prowess of the target keys listed in the Substitution Map. The substitution uses the source key's full Prowess (its own ranks and its own driving attribute), so the substitution can change both. *(configurable, default `versatile_performance`)*

**Substitution Map**: Mapping from a source skill key to the keys whose Prowess it may substitute for. Source keys are full skill keys; they may be Set Instances (e.g., `perform_dance`) or any other catalog Skill. *(configurable)*

## Catalog interface

**Creature accessor**: The interface a Creature exposes to Proficiencies. The methods are defined in `proficiencies_design.md`; the glossary entry exists so other docs can reference the term without redefining it.
