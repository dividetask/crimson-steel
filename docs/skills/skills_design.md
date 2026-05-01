# Skills — Design

The Skills domain owns the Skill catalog and the small `Skills` class that turns a Skill Roll request into the dice/bonus/starting-value triple a Roll consumes. Per-Character Skill Ranks and Versatile Performance choices still live on Advancement; the `Skills` class coordinates: asks Advancement for ranks, Character for Effective Attributes, runs the math, routes Versatile Performance.

## Key Conventions

### Skill Sets are open namespaces

A Skill Set (entry with `set: true`, key ending in `_`) is a *prefix*, not a parent record with children. The catalog never lists `craft_smith`, `craft_alchemy`, `perform_dance` as their own entries — the Set's existence is what makes any `craft_<anything>` valid. Consequences:

- **Set Members inherit the Attribute from the Set declaration.** No child entry, no override.
- **Adding a new specialty needs no config change.** A character declaring `perform_juggling` is valid as long as `perform_` is a declared Set.
- **A Character cannot train the bare Set.** `Skills#skill_details` rejects a key ending with `_`; the Set is a category, not a Skill.

### Mandatory Skills bypass chosen-skills

Implemented in `Advancement#skill_ranks`: every Class auto-contributes ranks to every Mandatory Skill, regardless of the Character's per-class chosen-skills list. Authors should leave Mandatory Skills out of chosen-skills lists. The duplicate is harmless today (the per-class iteration unions and dedupes), but listing them is misleading.

### Attribute keys are not validated

A typo in a Skill's `attribute:` field silently produces a Skill whose Attribute lookup fails downstream. There's no validation seam in the Skills config; validation lands in whichever caller actually reads the Attribute.

### Minimum Skills Trained is informational

`minimum_skills_trained` is unenforced today — it documents the rule "every Character trains at least floor(int / 4) Skills" so a future Character creation flow can enforce it.

## Key Operations

### Skill Prowess and roll-input partition

`skill_details(skill_name, character, advancement)` is the only read API. The pipeline:

1. **Resolve the Attribute** from the catalog (with Skill Set prefix fallback).
2. **Compose Skill Prowess.** Effective Attribute / `attribute_contribution_divisor` (default 2, floored) gives the Attribute Contribution. `Skill Prowess = Skill Ranks + Attribute Contribution`. Ranks come from `Advancement#skill_ranks`; Effective Attribute from `Character#attribute(attribute_key)`.
3. **Partition the Prowess** via `DiceSystem#compute_check_details`. The Skills class folds the Competency Bonus into a `bonuses` hash keyed `"Competency Bonus"` so the caller drops it into `compute_roll_parameters` unchanged.

The returned hash (`name`, `ranks`, `prowess`, `dice_count`, `starting_value`, `bonuses`) is verbatim what a Skill-Roll caller hands to dice resolution. Skills does not know about Tier, propagation, or any other modifier type.

### Versatile Performance routing

Versatile Performance maps each performance choice to two ordinary Skills:

- act → deception, disguise
- comedy → deception, intimidate
- dance → acrobatics, athletics
- keyboard → persuasion, intimidate
- oratory → persuasion, sense_motive
- percussion → animal_handling, intimidate
- sing → deception, sense_motive
- string → deception, persuasion
- wind → persuasion, animal_handling

Versatile Performance is treated as a **hardcoded special case** rather than a generic sub-choice mechanism. Each grant the character earns produces a separately-named Ability — `Versatile Performance (Wind)`, `Versatile Performance (Oratory)`, etc. — so the chosen performance is visible directly on the character sheet without a secondary sub-choice list to render.

When `skill_details` is called for one of the listed Skills, Skills scans the Character's abilities list for any name starting with `"Versatile Performance"`, parses the performance from the parentheses, intersects with the inverted skill→performance map, and computes a result for each matching `perform_<performance>` Skill. The single best Prowess wins; the returned `name` is always the originally requested Skill — a `sense_motive` lookup that resolves through `perform_oratory` still reports `sense_motive` to the caller.

The hardcoding lives in `Skills#chosen_performances` and `Advancement#abilities`. Other "use Skill A in place of Skill B" abilities will need their own special case or a generalization pass.

### Multi-grant choice storage

The character entry records one performance per Versatile Performance grant under `advancement.versatile_performance` as an ordered list:

```yaml
advancement:
  versatile_performance: [wind, oratory]
```

Each entry corresponds to one grant in the order grants are earned. `Advancement#abilities` expands each qualifying grant into one `Ability(name: "Versatile Performance (Performance)")`. Fewer choices than grants → extras appear as bare `"Versatile Performance"` so the gap is visible on the sheet; more choices than grants → extras are ignored.

The `Ability#sub_choices` accessor remains on the struct for any future ability that needs generic sub-choice storage; Versatile Performance no longer uses it.

## Responsibilities

### Owned by the skills domain

- The catalog of Skills, their Attributes, descriptions, and the `set` / `mandatory` flags.
- The `minimum_skills_trained` config block.
- The `attribute_contribution_divisor` config and the Skill Prowess formula.
- The `versatile_performance` performance→skill map and the routing rule.
- Skill Set Member prefix resolution at lookup time.

### Explicitly *not* owned here

- **Per-Character skill ranks** — Advancement.
- **Class-skill / non-class-skill / opposed-skill categorization** — Class definitions in `advancement_config.yaml`.
- **Mandatory-skill auto-contribution logic** — Advancement reads the flag and applies the rule.
- **Dice/Bonus/Starting partition math** — DiceSystem owns `compute_check_details`; Skills only supplies the Prowess.
- **Roll mechanics, propagation, Roll Modifiers** — dice resolution.
- **Per-grant choice storage on the Character entry** — Advancement reads the YAML.

### Unassigned (no current owner)

- **Enforcement of `minimum_skills_trained`.**
- **Validation that `attribute:` values are one of the six recognized Attributes.**
- **Tier / Inherent contributions.** Whatever else a Skill Roll picks up beyond Ranks and Attribute is the caller's responsibility.
