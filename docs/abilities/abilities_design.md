# Abilities and Spells — Design

Companion to `abilities_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The abilities module is a strict **reference**: it answers "what does this spell or ability do?" in a form other modules can consume. It rolls no dice, tracks no active effects, and consumes no resources.

## Key Operations

### Variant resolution

Multi-tier Entries are encoded as a base Entry with parallel lists indexed by tier. Resolving a Variant at a given `tier_index` follows a fixed order:

1. **Apply Variant Overrides.** If `variant_overrides[tier_index]` is a dictionary, shallow-replace each key on a copy of the base Entry. **A `null` override value removes the key entirely**, not "sets it to null" — this is how a higher tier opts out of a Concentration Block or other inherited field. List- and dictionary-valued overrides replace the base value wholesale; there is no deep merge.
2. **Resolve the Effect Hash** for `tier_index` against the merged Entry (see below).
3. **Construct the Variant name.** If `name[tier_index]` is a non-empty string, that's the name verbatim and `prefix`/`suffix` at this index are ignored. Otherwise the name is `<prefix> <Entry name> <suffix>` with empty/null parts dropped.

Variant Overrides may not change `tier`, `prefix`, `suffix`, `name`, or `variant_overrides` itself — those have their own parallel-list mechanisms or are structural. The validator must reject an Entry that tries to.

### Effect Hash resolution

The Effect Hash is a flat dictionary, but its values cross-reference each other through Formulas. Resolution walks entries in declaration order, evaluating each one against a context that already contains every previously-resolved name:

- A list-valued entry on a multi-tier Entry uses the value at `tier_index`.
- A string-valued entry is treated as a Formula and evaluated.
- Any other value is taken verbatim.

Tier 0 is treated as **0.5** in the formula context, per the project-wide convention. `rank` is always present. Names from the Effect Hash become available as soon as they're resolved, so a later entry's Formula may reference an earlier entry's value.

Damage-expression-only variables (`success`, `critical`, `attribute`) must **not** appear in Effect Hash Formulas, Range Formulas, or Target Formulas — those are resolved before any roll. The validator does not catch this; it surfaces as an unresolved-name error at evaluation time.

### Deferred damage evaluation contract

Damage Formulas can reference roll results that aren't known at lookup time. The abilities module handles this by returning a classified **damage object** rather than a number:

```
{ kind: 'damage', formula: '<expr>', damage_type: <string|null>, context: { rank, tier, ...effect_hash } }
```

The caller later supplies the missing pieces (`success`, `critical`, `attribute`) to evaluate the Formula. This keeps the abilities module ignorant of dice and saves while still letting it own the entire schema of what a damage expression means.

The `success`/`critical` semantics are caller-defined:

- **Inside a Save Outcome** → defender's save results.
- **Inside a top-level `effects` list** → caster's casting-roll results.

The classifier doesn't care which; it just attaches the partial context. Negative damage values clamp to 0 at evaluation time.

### Effect classification

Every Effect string falls into exactly one of three kinds, determined by string shape:

- `"0"` or `"none"` → `{ kind: 'none' }`.
- Matches `"<expression> damage"` → damage object (see above), inheriting the Entry's `damage_type` (which may be `null`).
- Otherwise → must be a key in `Effect Names`; returned as `{ kind: 'effect', name: <string> }`.

Validation rejects any other shape. The same classifier runs on Save Outcome values, Unconditional Effects (`effects` list), and Concentration save outcomes — they share semantics.

### Concentration Block

The Concentration Block has its **own Effect Hash, namespaced separately** from the Entry's top-level Effect Hash — the two never share variable names at evaluation time. Resolution mirrors the top-level path: resolve the block's Effect Hash, classify any Save Outcomes, substitute `{name}` placeholders into the block's `description`, convert the `action` cost to rounds the same way Casting Time is converted.

The Concentration Block's `attack_roll` and `save` are **independent** of the Entry's top-level versions — Heal-style spells have a top-level `attack_roll: false` but a concentration `save`; Fire Dart has both top-level and concentration attack rolls.

### Universal forms and skills

The configurable lists `Universal Spell Casting Skills` and `Universal Item Forms` are appended **implicitly** at lookup time, not stored on the Entry:

- Data files must not list a universal entry in an Entry's `skills` or `items` field — the validator rejects it.
- Spells get universal skills/forms appended; Abilities (`type: ability`) do not.
- Item-Only Entries do **not** receive universal Item Forms — only the explicit list applies, since the universal forms (scroll, wand) wouldn't make sense for them.

### Conditional saves

A Save Spec may carry a `condition` field (`on_fail` or `on_fumble`) that gates whether the save is offered to the target at all. The abilities module reports conditional saves verbatim with their `condition` attached; **dispatch is the caller's job** — the abilities module never inspects prior save results.

`fumble` outcome dispatch is a separate concern: when a save's Degree of Failure meets or exceeds the Default Fumble Threshold from the dice resolution config, the `fumble` outcome (if defined on the Save Spec) replaces the plain `fail` outcome. This branching also happens in the caller.

## Responsibilities

### Owned by the abilities domain

- Loading and validating `abilities_data` and `abilities_config`.
- Schema validation: rejecting unknown Entry Types, Schools, Casting Skills, Item Forms, Properties, Save Attributes, Save Outcome Keys, Effect Names, Casting Time aliases, Range names, and Area Shapes; checking Variant parallel-list lengths; rejecting overrides of structural fields; rejecting universal-entry leaks in data files.
- Resolving Variants: applying Overrides, constructing displayed names.
- Resolving Effect Hash, with tier-indexed picks and cross-reference Formula evaluation.
- Classifying Effects (none / named / damage).
- Building partial contexts and evaluating damage Formulas when `success`/`critical`/`attribute` are supplied.
- Resolving the Concentration Block (its own Effect Hash, classified saves, action-cost conversion, description substitution).
- Implicitly appending Universal Casting Skills and Universal Item Forms.
- Resolving `casting_time` to rounds, `range` to feet, and `target` to either `'self'` or a count.
- Filtering and listing Entries by Type and/or School.

### Explicitly *not* owned here

- **Rolling dice and resolving saves.** Lives in dice resolution and combat.
- **Applying named effects.** The mechanics list inside an Effect Name is consumed by the condition module; the abilities module surfaces it verbatim.
- **Active-effect bookkeeping** — which creatures have which conditions, concentration tracking. Lives in condition and combat modules.
- **Consuming spell slots, charges, mana.** Lives in character and item modules.
- **Mapping creatures to known spells/abilities.** Character module owns prepared/known lists.
- **Determining who is in an `area`.** Combat module computes overlap; the abilities module just exposes `{shape, size}`.
- **Damage-type semantics** — resistances, vulnerabilities, immunities. Lives in the damage-types module. Abilities does not validate `damage_type` strings against any list.
- **Property mechanics.** The keyword list is validated here, but the behavior of each property lives in whichever module implements it.
- **Magic toxicity application.** Abilities exposes `minimum_saturation` and `saturation` Effect Hash conventions; the condition module reads and applies them.

### Unassigned (no current owner)

- Validating `damage_type` strings against a canonical list (no list exists yet — likely belongs in the damage-types module or `docs/orphans.md` until then).
- Validating that a passed `rank` is non-negative.
- Tracking which Properties exist purely for display vs. those with mechanical effects, and where each one's mechanics live. *Likely needs a property registry per module.*
- Cross-domain validation that every name in `Effect Names` whose `mechanics` are non-empty corresponds to a Condition Mechanic the condition module actually understands. Today the abilities module accepts any `kind` field; nothing checks the consuming side agrees.
