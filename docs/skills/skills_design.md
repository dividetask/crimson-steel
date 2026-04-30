# Skills — Design

Companion to `skills_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

There is no Skills class. The Skills domain is a flat config catalog read by Advancement (and by future callers that need to look up a Skill's Attribute or check whether a name is a Skill). This doc captures the conventions that govern the catalog so editors can extend it safely.

## Key Conventions

### Skill Sets are open namespaces

A Skill Set (entry with `set: true`, key ending in `_`) is a *prefix*, not a parent record with children. The catalog never lists `craft_smith`, `craft_alchemy`, `perform_dance` as their own entries — the Set's existence is what makes any `craft_<anything>` valid.

This means:

- **Set Members inherit the Attribute from the Set declaration.** No child entry, no override mechanism — the Set is the source of truth.
- **Adding a new specialty needs no config change.** A character declaring `perform_juggling` in their chosen-skills list is valid as long as `perform_` is a declared Set.
- **A Character cannot train the bare Set.** Code paths that look up a Skill by exact name should reject a key that ends with `_`; the Set is a category, not a Skill.

### Mandatory Skills bypass chosen-skills

The `mandatory: true` flag on `martial` is the single example today. The behavior is implemented in `Advancement#skill_ranks`: every Class auto-contributes ranks to every Mandatory Skill, regardless of the Character's per-class chosen-skills list. This is *additive* — even if the Character also lists `martial` in a Class's `skills:`, the auto-contribution is the only source.

Authors should leave Mandatory Skills out of chosen-skills lists. The duplicate is harmless today (the per-class iteration unions the chosen list with the mandatory list and dedupes), but listing them is misleading.

### Attribute keys are not validated

A typo in a Skill's `attribute:` field (e.g. `attribute: dexterity` instead of `attribute: dex`) silently produces a Skill whose Attribute lookup fails downstream. There's no validation seam in the Skills config itself; validation lands in whichever caller actually reads the Attribute.

### Minimum Skills Trained is informational

`minimum_skills_trained` is a config value with no current enforcement. It documents the rule "every Character trains at least floor(int / 4) Skills" so a Character creation flow can enforce it; today nothing checks. The value is read by future tooling, not by Advancement.

## Responsibilities

### Owned by the skills domain

- The catalog of Skills, their Attributes, descriptions, and the `set` / `mandatory` flags.
- The `minimum_skills_trained` config block.

### Explicitly *not* owned here

- **Per-Character skill ranks** — Advancement.
- **Class-skill / non-class-skill / opposed-skill categorization** — Class definitions in `advancement_config.yaml`.
- **Mandatory-skill auto-contribution logic** — Advancement reads the flag and applies the rule.
- **Roll mechanics** — dice resolution.
- **Validating Skill Set Member names** (e.g. confirming `craft_alchemy` resolves to `craft_`'s Attribute) — every caller does its own prefix lookup against `set: true` entries.

### Unassigned (no current owner)

- **Enforcement of `minimum_skills_trained`.** A Character creation flow or import-time validator could check that every Character has trained at least the minimum.
- **Validation that `attribute:` values are one of the six recognized Attributes.** Today a typo silently breaks downstream lookups.
- **A Skill-Roll API.** Today every caller assembles its own `dice_count + modifiers` and passes them to dice resolution; nothing canonicalizes "roll Skill X for this Character".
