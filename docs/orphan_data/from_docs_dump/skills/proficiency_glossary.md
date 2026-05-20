# Proficiency — Glossary

Configuration data (the Skill catalog in `data/skills.yaml`) plus a small `Proficiency` coordinator class that turns a Skill lookup into the dice/bonus/starting-value triple a Skill Roll uses. Per-Character Ranks live on Advancement; Proficiency asks for them at lookup time.

## Core

**Skill**: A named capability a Character may have ranks in. Keyed in `skills_config.yaml`, bound to one Attribute. *(configurable)*

**Skill Definition**: An entry under `skills:` defining `attribute`, `description`, and optional `set` and `mandatory` flags.

**Attribute**: One of `str`, `dex`, `con`, `int`, `wis`, `cha`. The attribute modifier added when rolling the Skill.

## Skill Sets

**Skill Set**: A Skill Definition with `set: true` (key conventionally ends with `_`, e.g. `craft_`). A namespace — Characters cannot take ranks in the parent Set, only in specific children spelled `<set>_<specialty>`.

**Set Member**: A Skill keyed `<set>_<specialty>`. Members need not be listed in `skills_config.yaml` so long as the parent Set is declared; the member inherits the Set's Attribute.

(Proficiency, Mandatory Proficiency, Prefix Match, Skill Prowess: see common glossary.)

## Minimum Skills Trained

**Minimum Skills Trained**: Minimum number of Skills every Character automatically advances, computed as `floor(attribute / attribute_divisor)`. *(configurable: `attribute` default `int`, `attribute_divisor`)* The proficiency system does not enforce this — other modules read the config value.

## Skill Roll Inputs

**Attribute Contribution**: `floor(Effective Attribute / skill_prowess.attribute_contribution_divisor)` (default divisor 2).

**Competency Bonus Base**: A flat adjustment Proficiency adds to every Skill Roll's raw Competency value before returning it. *(configurable, default `-1`)* Negative values bias every Roll toward Penalty until Prowess accumulates past the first tier.

**Untrained Competency Modifier**: An additional adjustment Proficiency applies *only* when the Character has zero ranks in the requested Skill. *(configurable, default `-1`)* Stacks with `competency_bonus_base`, so a fully untrained Skill takes a `-2` Competency hit by default.

**Skill Details**: The bundle returned by `Proficiency#skill_details(skill_name, character, advancement)` — `{ name, ranks, prowess, dice_count, starting_value, bonuses }`. The `bonuses` hash carries either a `"Competency Bonus"` or a `"Competency Penalty"` (or nothing when the net Competency lands at zero), already net of `competency_bonus_base` and any applicable `untrained_competency_modifier`.

## Versatile Performance

**Versatile Performance**: An ability gained one or more times. Each grant picks one **Performance** from a fixed list (Act, Comedy, Dance, Keyboard, Oratory, Percussion, Sing, String, Wind). When Skill Details is requested for a Skill the chosen Performance covers, the higher-Prowess of the requested Skill and the corresponding `perform_<choice>` is returned, keyed by the originally-requested Skill name. Choices are recorded under `advancement.versatile_performance` (one entry per grant); `Advancement#abilities` expands each grant into a separately-named ability such as `"Versatile Performance (Wind)"`.

## Module Scope

Consumed by:
- **Advancement** — `mandatory` flag and Skill existence checks.
- **Skill Roll callers** — to look up a Skill's Attribute and the net Competency.
- **Character creation / validation** (future) — Minimum Skills Trained.

Does not own:
- Per-Character ranks (Advancement).
- Roll mechanics (dice resolution).
- Class-skill / non-class-skill / opposed-skill categorization (Advancement, per-class).
