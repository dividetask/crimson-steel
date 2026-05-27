# Proficiencies — Tests

Tests for the public entry points of the Proficiencies domain.

Unless a test specifies otherwise, all tests use the values in `proficiencies_config.yaml` and `skills.yaml`:
- Attribute Contribution Divisor: 2
- Non-Proficiency Penalty Value: -2
- Restricted Skills: `[restricted_magic]`
- Floor Ability: `jack_of_all_trades`
- Substitution Ability: `versatile_performance`
- Substitution Map: as configured (`perform_act → [deception, disguise]`, `perform_dance → [acrobatics, athletics]`, etc.)
- Skill catalog: as configured (`athletics: str`, `martial: dex`, `perform_: cha`, `restricted_magic: int`, etc.)

Dice resolution defaults are used for the prowess translation:
- Minimum Dice Count: 6, Dice Count Range: 5 (so dice resolution's Maximum Dice Count = 10).

Test creatures are described by what their accessor returns. A `creature` named below means an accessor with the listed `ranks_for`, `attribute_value`, `has_ability`, and `level_for_ability` responses.

---

## Compute Roll inputs for a Proficiency

### Catalog lookup and Prowess

**A trained Skill with a middling attribute.** Given `key = "athletics"`, `ranks_for("athletics") = 3`, `attribute_value("str") = 4`, no relevant abilities. Direct Prowess = `3 + floor(4 / 2) + 0 = 5`. No Substituted Prowess. Proficiency Prowess = 5. Dice resolution translates Prowess 5 to `dice_cap = 6, bonus_penalty = 1`. Returned: `{dice_cap: 6, competency_modifier: ("Competency", +1)}`.

**An untrained Skill applies the Non-Proficiency Penalty.** Given `key = "stealth"`, `ranks_for("stealth") = 0`, `attribute_value("dex") = 3`, no relevant abilities. Direct Prowess = `0 + 1 + (-2) = -1`. Returned: `{dice_cap: 10, competency_modifier: ("Competency", -1)}`.

**Zero Prowess returns a null Competency Modifier.** Given a creature whose Direct Prowess sums to exactly 0: dice resolution translates Prowess 0 to `dice_cap = 6, bonus_penalty = 0`. Returned: `{dice_cap: 6, competency_modifier: null}`.

### Set Skills

**Prefix Match resolves a Set Instance.** Given `key = "craft_blacksmith"`, no exact catalog entry. Prefix Match finds `craft_` (longest matching prefix). Driving attribute is `int` (inherited from `craft_`). The remainder of the pipeline runs against `int`.

**A Set Instance with no ranks gets the Non-Proficiency Penalty.** Given `key = "perform_dance"`, `ranks_for("perform_dance") = 0`, `attribute_value("cha") = 2`. Prefix Match resolves to `perform_`, attribute `cha`. Direct Prowess = `0 + 1 + (-2) = -1`.

**Bare Set Skill keys are invalid input.** Calling Compute Roll inputs with `key = "perform_"` or `key = "craft_"` is invalid — Creatures do not store ranks under bare Set Skill keys. Validation is the caller's responsibility.

### Attribute override (saves and unknowns)

**A save key with no catalog entry uses the override.** Given `key = "con_save"` (not in the catalog), `attribute_override = "con"`, `ranks_for("con_save") = 4`, `attribute_value("con") = 5`. Catalog lookup yields nothing; the override supplies the attribute. Direct Prowess = `4 + 2 + 0 = 6`.

**An unknown key without an override is invalid.** Given `key = "homebrew_skill"`, no catalog entry, `attribute_override = null`: the call is invalid.

**Override on a key that has a catalog entry uses the override.** Given `key = "athletics"` (catalog attribute `str`), `attribute_override = "dex"`, `attribute_value("dex") = 4`. The override wins for the attribute; Attribute Contribution comes from `dex`. Catalog-derived classification (Restricted, Floor Ability eligibility) still uses the resolved catalog entry.

### Floor Ability

The Floor Ability provides a minimum ranks of `floor(level_for_ability / 2)` on every non-Restricted catalog Skill. The Creature's actual ranks are used when they exceed the floor. The Floor Ability never changes the driving attribute.

**Floor lifts ranks above zero.** Given `key = "history"`, `ranks_for("history") = 0`, the creature has `jack_of_all_trades`, `level_for_ability("jack_of_all_trades") = 5`, `attribute_value("int") = 2`. Floor lift = 2; max(0, 2) = 2. Direct Prowess = `2 + 1 + 0 = 3`.

**Floor lifts low actual ranks up to its minimum.** Given `key = "history"`, `ranks_for("history") = 1`, the creature has `jack_of_all_trades`, `level_for_ability("jack_of_all_trades") = 8`. Floor lift = 4; max(1, 4) = 4. The minimum applies regardless of whether the Creature already has ranks.

**Actual ranks above Floor's minimum stay.** Given `key = "athletics"`, `ranks_for("athletics") = 6`, the creature has `jack_of_all_trades`, `level_for_ability("jack_of_all_trades") = 8`. Floor lift = 4; max(6, 4) = 6.

**Floor uses the granting Class's level, not the total level.** Multi-classed creature with 3 levels in the Class that granted the Floor Ability and 5 levels in another Class. `level_for_ability("jack_of_all_trades") = 3`, so floor lift = 1, regardless of the 8 total levels.

**Floor does not apply to Restricted Skills.** Given `key = "restricted_magic"`, `ranks_for("restricted_magic") = 0`, the creature has `jack_of_all_trades`, `level_for_ability("jack_of_all_trades") = 5`. Floor lift = 0 (Skill is Restricted). Direct Prowess uses ranks = 0; Non-Proficiency Penalty applies.

**Floor does not apply to keys without a catalog entry.** Given `key = "con_save"`, `attribute_override = "con"`, `ranks_for("con_save") = 0`, the creature has `jack_of_all_trades`, `level_for_ability("jack_of_all_trades") = 8`. Floor lift = 0 (no catalog entry). Direct Prowess uses ranks = 0.

### Substitution

The Substituted Prowess competes with the Direct Prowess. Each is computed from its own ranks and attribute; the higher Prowess wins. The Floor Ability never lifts a substitution source's ranks.

**Substitution wins when its Prowess exceeds Direct Prowess.** Given `key = "deception"`, `ranks_for("deception") = 0`, `ranks_for("perform_act") = 4`, the creature has `versatile_performance`, `attribute_value("cha") = 6`. Direct Prowess = `0 + 3 + (-2) = 1`. Substituted Prowess from `perform_act`: `4 + 3 + 0 = 7`. Substitution wins. Proficiency Prowess = 7.

**Substitution attribute can differ from the queried key's.** Given `key = "acrobatics"` (target attribute `dex`), `ranks_for("acrobatics") = 0`, `ranks_for("perform_dance") = 4`, the creature has `versatile_performance`, `attribute_value("dex") = 0`, `attribute_value("cha") = 6`. Direct Prowess = `0 + 0 + (-2) = -2`. Substituted Prowess: `4 + 3 + 0 = 7`. Substitution wins.

**Substitution loses when its Prowess is lower.** Given `key = "acrobatics"`, `ranks_for("acrobatics") = 4`, `ranks_for("perform_dance") = 2`, the creature has `versatile_performance`, `attribute_value("dex") = 4`, `attribute_value("cha") = 0`. Direct Prowess = `4 + 2 + 0 = 6`. Substituted Prowess: `2 + 0 + 0 = 2`. Direct Prowess wins.

**Direct Prowess wins ties.** Given `key = "persuasion"`, `ranks_for("persuasion") = 3`, `ranks_for("perform_string") = 3`, the creature has `versatile_performance`, `attribute_value("cha") = 4`. Both Prowess values are 5. Proficiency Prowess = Direct Prowess = 5.

**Substitution scans only entries whose target list contains the key.** Given `key = "stealth"` (not in any Substitution Map entry), the creature has `versatile_performance` and ranks in various perform Skills: no Substituted Prowess is produced.

**Substitution skips when the ability is absent.** Given the creature has perform ranks but `has_ability("versatile_performance") = false`: no Substituted Prowess is produced.

**Multiple matching sources pick the highest Prowess.** Given `key = "deception"` (targeted by `perform_act`, `perform_comedy`, `perform_sing`, `perform_string` in the default map). The creature has `versatile_performance`, `ranks_for("perform_act") = 1`, `ranks_for("perform_sing") = 4`, others 0, `attribute_value("cha") = 4`. Each source Prowess is computed; `perform_sing` produces the highest (`4 + 2 = 6`). Substituted Prowess = 6.

**Source key may be a non-Set-Instance Skill.** With a homebrew config adding `cooking: [persuasion]` to the Substitution Map and `cooking` to the Skill catalog (attribute `wis`): given `key = "persuasion"`, `ranks_for("cooking") = 5`, `attribute_value("wis") = 4`, the creature has `versatile_performance`. Substituted Prowess from `cooking`: `5 + 2 = 7`. The mechanism does not require the source to be a Set Instance.

### Floor Ability and Substitution together

**Floor cannot lift a substitution source's ranks.** Given `key = "deception"`, `ranks_for("deception") = 0`, `ranks_for("perform_act") = 1`, the creature has both `jack_of_all_trades` and `versatile_performance`, `level_for_ability("jack_of_all_trades") = 10`, `attribute_value("cha") = 6`. Direct Prowess: floor lift = 5, ranks = 5, Prowess = `5 + 3 = 8`. Substituted Prowess from `perform_act`: ranks = 1 (no floor lift on the source), Prowess = `1 + 3 = 4`. Direct Prowess wins; Proficiency Prowess = 8.

**Substitution can still beat a Floor-lifted Direct Prowess when the source has high ranks.** Given `key = "acrobatics"`, `ranks_for("acrobatics") = 0`, `ranks_for("perform_dance") = 8`, the creature has both abilities, `level_for_ability("jack_of_all_trades") = 4`, `attribute_value("dex") = 2`, `attribute_value("cha") = 6`. Direct Prowess: floor lift = 2, ranks = 2, Prowess = `2 + 1 = 3`. Substituted Prowess: `8 + 3 = 11`. Substitution wins; Proficiency Prowess = 11.

---

## Look up a Skill

**Exact match returns the entry.** Given `key = "athletics"`: returns `{attribute: str, description: ...}`.

**Set Instance returns the family entry.** Given `key = "perform_dance"`: returns the `perform_` catalog entry (attribute `cha`, the family description).

**Unknown key returns null.** Given `key = "homebrew"`: returns null. No prefix in the catalog matches.

**Longest prefix wins.** With a hypothetical catalog containing both `craft_` and `craft_alchemy_`, and `key = "craft_alchemy_potions"`: returns the `craft_alchemy_` entry, not `craft_`. (The default catalog has no nested set; the rule is asserted for completeness.)

---

## List Skills

**Returns the catalog map.** With the default config: returns the full Skills mapping. `perform_`, `craft_`, `profession_`, `game_` are present (Set Skills are catalog entries). No Set Instances are included.
