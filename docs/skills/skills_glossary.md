# Skills — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. The skills "module" is purely **configuration data** — there is no Skills class. The catalog is loaded by the Advancement module (see `advancement_glossary.md`) and consumed by every system that asks "is this a skill?" or "what attribute does this skill use?".

## Core

**Skill**: A named capability a Character may have ranks in. Each Skill is keyed by a string in `skills_config.yaml` and bound to one of the six Attributes. *(configurable)*

**Skill Definition**: An entry under `skills:` defining the Skill's `attribute`, `description`, and optional `set` and `mandatory` flags.

**Attribute**: One of `str`, `dex`, `con`, `int`, `wis`, `cha`. The attribute modifier added when rolling the Skill.

## Skill Sets

**Skill Set**: A Skill Definition with `set: true`. By convention the key ends with `_` (e.g. `craft_`, `perform_`, `profession_`). A Skill Set is a *namespace* — Characters cannot take ranks in the parent Set itself, only in specific children spelled `<set>_<specialty>` (e.g. `craft_smith`, `perform_dance`).

**Set Member**: A Skill keyed `<set>_<specialty>`. Members do not need to be listed in `skills_config.yaml` — any specialty is a valid member as long as the parent Set is declared. The member inherits the Set's Attribute.

**Prefix Match**: A list entry ending with `_` matches any Skill that starts with that prefix and has more content after the underscore. Used by Advancement when resolving a Skill against a Class's `class_skills` / `non_class_skills` / `opposed_skills` lists — a class entry of `perform_` qualifies any `perform_<specialty>` Skill the Character chose to advance.

## Mandatory Skills

**Mandatory Skill**: A Skill flagged `mandatory: true`. Every Class contributes ranks to a Mandatory Skill regardless of the Character's chosen-skills list — the Skill is treated as if listed under every Class's chosen-skills. Characters should not list Mandatory Skills in their per-class chosen-skills lists. The standard Mandatory Skill is `martial`.

## Minimum Skills Trained

**Minimum Skills Trained**: The minimum number of Skills every Character automatically advances, computed from one of the Character's Attributes divided by a configurable divisor. *(configurable)*

- **`attribute`**: The Attribute key consulted (default `int`).
- **`attribute_divisor`**: The divisor applied to the Attribute's value, with the result floored. A Character with Int 16 and divisor 4 trains a minimum of 4 Skills.

The skills system itself does not enforce this minimum — it's a config value other modules (Character creation tools, validation passes) read.

## Module Scope

The Skills config is consumed by:

- **Advancement** — for the `mandatory` flag (which Skills auto-advance per Class) and to know whether a Skill exists.
- **Any Skill Roll caller** — to look up the Skill's Attribute.
- **Character creation / validation** (future) — to enforce Minimum Skills Trained.

The Skills config does **not** own:

- Per-Character ranks. Those come from `Advancement#skill_ranks`.
- Roll mechanics. Those live in dice resolution.
- Class-skill / non-class-skill / opposed-skill categorization. Those are declared on each Class in `advancement_config.yaml`.
