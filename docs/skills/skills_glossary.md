# Skills — Glossary

Configuration data (the Skill catalog in `data/skills.yaml`) plus a small `Skills` coordinator class that turns a Skill lookup into the dice/bonus/starting-value triple a Skill Roll uses. Per-Character Ranks live on Advancement; Skills asks for them at lookup time.

## Core

**Skill**: A named capability a Character may have ranks in. Keyed in `skills_config.yaml`, bound to one Attribute. *(configurable)*

**Skill Definition**: An entry under `skills:` defining `attribute`, `description`, and optional `set` and `mandatory` flags.

**Attribute**: One of `str`, `dex`, `con`, `int`, `wis`, `cha`. The attribute modifier added when rolling the Skill.

## Skill Sets

**Skill Set**: A Skill Definition with `set: true` (key conventionally ends with `_`, e.g. `craft_`). A namespace — Characters cannot take ranks in the parent Set, only in specific children spelled `<set>_<specialty>`.

**Set Member**: A Skill keyed `<set>_<specialty>`. Members need not be listed in `skills_config.yaml` so long as the parent Set is declared; the member inherits the Set's Attribute.

(Prefix Match, Mandatory Skill, Skill Prowess: see common glossary.)

## Minimum Skills Trained

**Minimum Skills Trained**: Minimum number of Skills every Character automatically advances, computed as `floor(attribute / attribute_divisor)`. *(configurable: `attribute` default `int`, `attribute_divisor`)* The skills system does not enforce this — other modules read the config value.

## Skill Roll Inputs

**Attribute Contribution**: `floor(Effective Attribute / skill_prowess.attribute_contribution_divisor)` (default divisor 2).

**Skill Details**: The bundle returned by `Skills#skill_details(skill_name, character, advancement)` — `{ name, ranks, prowess, dice_count, starting_value, bonuses }`. The `bonuses` hash is keyed by the modifier names DiceSystem's `compute_roll_parameters` accepts (today only `"Competency Bonus"`).

## Versatile Performance

**Versatile Performance**: An ability gained one or more times. Each grant picks one **Performance** from a fixed list (Act, Comedy, Dance, Keyboard, Oratory, Percussion, Sing, String, Wind). When Skill Details is requested for a Skill the chosen Performance covers, the higher-Prowess of the requested Skill and the corresponding `perform_<choice>` is returned, keyed by the originally-requested Skill name. Choices are recorded under `advancement.versatile_performance` (one entry per grant); `Advancement#abilities` expands each grant into a separately-named ability such as `"Versatile Performance (Wind)"`.

## Module Scope

Consumed by:
- **Advancement** — `mandatory` flag and Skill existence checks.
- **Skill Roll callers** — to look up a Skill's Attribute.
- **Character creation / validation** (future) — Minimum Skills Trained.

Does not own:
- Per-Character ranks (Advancement).
- Roll mechanics (dice resolution).
- Class-skill / non-class-skill / opposed-skill categorization (Advancement, per-class).
