# Skills — Design

Companion to `skills_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The Skills domain owns the Skill catalog (a flat config table keyed by Skill name) **and** the small `Skills` class that turns a Skill Roll request into the dice/bonus/starting-value triple a Roll consumes. Per-Character Skill Ranks and the Versatile Performance choice list still live on Advancement; the Skills class is a coordinator that asks Advancement for ranks and Character for Effective Attributes, runs the math, and routes Versatile Performance lookups.

## Key Conventions

### Skill Sets are open namespaces

A Skill Set (entry with `set: true`, key ending in `_`) is a *prefix*, not a parent record with children. The catalog never lists `craft_smith`, `craft_alchemy`, `perform_dance` as their own entries — the Set's existence is what makes any `craft_<anything>` valid.

This means:

- **Set Members inherit the Attribute from the Set declaration.** No child entry, no override mechanism — the Set is the source of truth.
- **Adding a new specialty needs no config change.** A character declaring `perform_juggling` in their chosen-skills list is valid as long as `perform_` is a declared Set.
- **A Character cannot train the bare Set.** `Skills#skill_details` rejects a key that ends with `_`; the Set is a category, not a Skill.

### Mandatory Skills bypass chosen-skills

The `mandatory: true` flag on `martial` is the single example today. The behavior is implemented in `Advancement#skill_ranks`: every Class auto-contributes ranks to every Mandatory Skill, regardless of the Character's per-class chosen-skills list. This is *additive* — even if the Character also lists `martial` in a Class's `skills:`, the auto-contribution is the only source.

Authors should leave Mandatory Skills out of chosen-skills lists. The duplicate is harmless today (the per-class iteration unions the chosen list with the mandatory list and dedupes), but listing them is misleading.

### Attribute keys are not validated

A typo in a Skill's `attribute:` field (e.g. `attribute: dexterity` instead of `attribute: dex`) silently produces a Skill whose Attribute lookup fails downstream. There's no validation seam in the Skills config itself; validation lands in whichever caller actually reads the Attribute.

### Minimum Skills Trained is informational

`minimum_skills_trained` is a config value with no current enforcement. It documents the rule "every Character trains at least floor(int / 4) Skills" so a Character creation flow can enforce it; today nothing checks. The value is read by future tooling, not by `Skills`.

## Key Operations

### Skill Prowess and roll-input partition

`skill_details(skill_name, character, advancement)` is the only read API. The pipeline:

1. **Resolve the Attribute.** The Skill's `attribute:` is read from the catalog. Skill Set Members (`perform_oratory`, `craft_smith`) inherit from the parent Set's declaration; the catalog never lists Set Members directly.
2. **Compose Skill Prowess.** The Effective Attribute is divided by `skill_prowess.attribute_contribution_divisor` (default 2, floored per the project-wide convention) to produce the Attribute Contribution. `Skill Prowess = Skill Ranks + Attribute Contribution`. Ranks come from `Advancement#skill_ranks`; the Effective Attribute comes from `Character#attribute(attribute_key)`.
3. **Partition the Prowess.** The integer Prowess is handed to `DiceSystem#compute_check_details`, which returns `[Dice Count, Competency Bonus, Starting Value]` per the rules in `dice_resolution_design.md`. The Skills class folds the Competency Bonus into a `bonuses` hash keyed `"Competency Bonus"` so the caller can drop it into `compute_roll_parameters` unchanged.

The returned hash (`name`, `ranks`, `prowess`, `dice_count`, `starting_value`, `bonuses`) is verbatim what a Skill-Roll caller hands to dice resolution. Skills does not know about Tier, propagation, or any other modifier type — those are added by upstream effect layers before the Roll runs.

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

When `skill_details(skill, character, advancement)` is called for one of the listed Skills, Skills inverts the map to find which performances cover it, intersects with the Character's chosen performances (read from `advancement.abilities` — the matching Ability struct's `sub_choices`), and computes a full result for each surviving `perform_<choice>` Skill. The single best Prowess wins, and its triple replaces the requested Skill's. The returned `name` is always the originally requested Skill — a `sense_motive` lookup that resolves through `perform_oratory` still reports `sense_motive` to the caller.

The performance map and the ability name are both configurable; today only `versatile_performance` is recognized, but the loader is generic in shape and will extend cleanly when other "use Skill A in place of Skill B" abilities arrive.

### Sub-choice storage

Per-grant choices for abilities like Versatile Performance live on the Character's `advancement:` block as a top-level list, e.g.:

```yaml
advancement:
  versatile_performance: [oratory, sing]
```

Each entry is one grant. `Advancement.from_entry` reads the list and stashes it under `ability_sub_choices['versatile_performance']`; `Advancement#abilities` then attaches the list to the matching `Ability` struct via its `sub_choices` accessor. New ability names with their own sub-choice lists register in `Advancement.extract_ability_sub_choices` without changing the entry shape.

## Responsibilities

### Owned by the skills domain

- The catalog of Skills, their Attributes, descriptions, and the `set` / `mandatory` flags.
- The `minimum_skills_trained` config block.
- The `skill_prowess.attribute_contribution_divisor` config value and the `Skill Prowess = Ranks + floor(Attribute / divisor)` formula.
- The `versatile_performance` performance→skill map and the routing rule "highest Prowess wins; requested name is preserved."
- Skill Set Member prefix resolution at lookup time.

### Explicitly *not* owned here

- **Per-Character skill ranks** — Advancement.
- **Class-skill / non-class-skill / opposed-skill categorization** — Class definitions in `advancement_config.yaml`.
- **Mandatory-skill auto-contribution logic** — Advancement reads the flag and applies the rule.
- **Dice/Bonus/Starting partition math** — DiceSystem owns `compute_check_details`; Skills only supplies the Prowess.
- **Roll mechanics, propagation, Roll Modifiers** — dice resolution.
- **Per-grant choice storage on the Character entry** — Advancement reads the YAML and exposes the list through `Ability#sub_choices`.

### Unassigned (no current owner)

- **Enforcement of `minimum_skills_trained`.** A Character creation flow or import-time validator could check that every Character has trained at least the minimum.
- **Validation that `attribute:` values are one of the six recognized Attributes.** Today a typo silently breaks downstream lookups.
- **Tier / Inherent contributions.** Skills folds Ranks and Attribute into Prowess; whatever else a Skill Roll picks up (Inherent Bonus from Tier, Circumstance modifiers from the situation) is the caller's responsibility.
