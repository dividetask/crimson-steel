# Proficiency — Design

The proficiency domain owns the Skill catalog and the small `Proficiency` class that turns a Skill Roll request into the dice/bonus/starting-value triple a Roll consumes. Per-Character Skill Ranks and Versatile Performance choices still live on Advancement; the `Proficiency` class coordinates: asks Advancement for ranks, Character for Effective Attributes, runs the math, folds in the configured Competency adjustments, routes Versatile Performance.

## Key Conventions

### Skill Sets are open namespaces

A Skill Set (entry with `set: true`, key ending in `_`) is a *prefix*, not a parent record with children. The catalog never lists `craft_smith`, `craft_alchemy`, `perform_dance` as their own entries — the Set's existence is what makes any `craft_<anything>` valid. Consequences:

- **Set Members inherit the Attribute from the Set declaration.** No child entry, no override.
- **Adding a new specialty needs no config change.** A character declaring `perform_juggling` is valid as long as `perform_` is a declared Set.
- **A Character cannot train the bare Set.** `Proficiency#skill_details` rejects a key ending with `_`; the Set is a category, not a Skill.

### Mandatory Proficiencies bypass chosen-skills

Implemented in `Advancement#skill_ranks`: every Class auto-contributes ranks to every Mandatory Proficiency (the `martial` Skill plus every Save Attribute), regardless of the Character's per-class chosen-skills list. Authors should leave Mandatory Proficiencies out of chosen-skills lists. The duplicate is harmless today (the per-class iteration unions and dedupes), but listing them is misleading.

### Attribute keys are not validated

A typo in a Skill's `attribute:` field silently produces a Skill whose Attribute lookup fails downstream. There's no validation seam in the proficiency config; validation lands in whichever caller actually reads the Attribute.

### Minimum Skills Trained is informational

`minimum_skills_trained` is unenforced today — it documents the rule "every Character trains at least floor(int / 4) Skills" so a future Character creation flow can enforce it.

## Key Operations

### Skill Prowess and roll-input partition

`skill_details(skill_name, character, advancement)` is the only read API. The pipeline:

1. **Resolve the Attribute** from the catalog (with Skill Set prefix fallback).
2. **Compose Skill Prowess.** Effective Attribute / `attribute_contribution_divisor` (default 2, floored) gives the Attribute Contribution. `Skill Prowess = Skill Ranks + Attribute Contribution`. Ranks come from `Advancement#skill_ranks`; Effective Attribute from `Character#attribute(attribute_key)`.
3. **Partition the Prowess** via `DiceSystem#compute_check_details`. That gives a raw `competency_bonus` (or `competency_penalty`), `dice_count`, and `starting_value`.
4. **Fold in the Competency adjustments.** Proficiency adds `competency_bonus_base` to the raw Competency unconditionally and `untrained_competency_modifier` when the Character has zero ranks in this Skill. The signed sum becomes either a single `Competency Bonus` or `Competency Penalty` (or nothing, if it lands at zero) in the returned `bonuses` hash.

The returned hash (`name`, `ranks`, `prowess`, `dice_count`, `starting_value`, `bonuses`) is verbatim what a Skill-Roll caller hands to dice resolution. Proficiency does not know about Tier, propagation, or any other modifier type.

### Untrained vs. trained

`competency_bonus_base` is a calibration knob — a constant offset on every Skill Roll regardless of training. Default `-1`: a baseline Roll always pays a one-point Competency tax until Prowess accumulates past the first tier. `untrained_competency_modifier` is the *additional* hit a Character takes for never having put any ranks in the Skill. Default `-1`. Stacking with the base, a fully untrained Skill is therefore -2 Competency.

Proficiency keys on `ranks == 0`, not on `prowess == 0`: a high-Wisdom Character is still untrained in Insight if they've never put a rank in it. The Attribute Contribution alone doesn't lift the untrained status.

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

When `skill_details` is called for one of the listed Skills, Proficiency scans the Character's abilities list for any name starting with `"Versatile Performance"`, parses the performance from the parentheses, intersects with the inverted skill→performance map, and computes a result for each matching `perform_<performance>` Skill. The single best Prowess wins; the returned `name` is always the originally requested Skill — a `sense_motive` lookup that resolves through `perform_oratory` still reports `sense_motive` to the caller.

The hardcoding lives in `Proficiency#chosen_performances` and `Advancement#abilities`. Other "use Skill A in place of Skill B" abilities will need their own special case or a generalization pass.

### Multi-grant choice storage

The character entry records one performance per Versatile Performance grant under `advancement.versatile_performance` as an ordered list:

```yaml
advancement:
  versatile_performance: [wind, oratory]
```

Each entry corresponds to one grant in the order grants are earned. `Advancement#abilities` expands each qualifying grant into one `Ability(name: "Versatile Performance (Performance)")`. Fewer choices than grants → extras appear as bare `"Versatile Performance"` so the gap is visible on the sheet; more choices than grants → extras are ignored.

The `Ability#sub_choices` accessor remains on the struct for any future ability that needs generic sub-choice storage; Versatile Performance no longer uses it.

## Responsibilities

### Owned by the proficiency domain

- The catalog of Skills, their Attributes, descriptions, and the `set` / `mandatory` flags.
- The `minimum_skills_trained` config block.
- The `attribute_contribution_divisor` config and the Skill Prowess formula.
- The `competency_bonus_base` and `untrained_competency_modifier` config and their fold-in into the returned `bonuses` hash.
- The `versatile_performance` performance→skill map and the routing rule.
- Skill Set Member prefix resolution at lookup time.

### Explicitly *not* owned here

- **Per-Character skill ranks** — Advancement.
- **Class-skill / non-class-skill / opposed-skill categorization** — Class definitions in `advancement_config.yaml`.
- **Mandatory-skill auto-contribution logic** — Advancement reads the flag and applies the rule.
- **Dice/Bonus/Starting partition math** — DiceSystem owns `compute_check_details`; Proficiency only supplies the Prowess and folds the configured Competency adjustments into the result.
- **Roll mechanics, propagation, Roll Modifiers** — dice resolution.
- **Per-grant choice storage on the Character entry** — Advancement reads the YAML.

### Unassigned (no current owner)

- **Enforcement of `minimum_skills_trained`.**
- **Validation that `attribute:` values are one of the six recognized Attributes.**
- **Tier / Inherent contributions.** Whatever else a Skill Roll picks up beyond Ranks and Attribute is the caller's responsibility.
