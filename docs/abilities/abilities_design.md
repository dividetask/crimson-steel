# Abilities and Spells — Design

Companion to `abilities_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The abilities module is a strict **reference**: it answers "what does this spell or ability do?" in a form other modules can consume. It rolls no dice, tracks no active effects, and consumes no resources.

## Key Operations

### Variant resolution

An Entry's Variants are indexed by exactly one **Variant Axis** — either `tier` (a list of integers) or `aspects` (a list of opaque labels). The two are mutually exclusive; the validator rejects an Entry that declares both. An Entry that declares neither has a single Variant.

Resolving a Variant at a given `axis_index` follows a fixed order:

1. **Apply Variant Overrides.** If `variant_overrides[axis_index]` is a dictionary, shallow-replace each key on a copy of the base Entry. **A `null` override value removes the key entirely**, not "sets it to null" — this is how a higher tier opts out of a Concentration Block, or how one aspect of a multi-element spell drops a save the other aspects retain. List- and dictionary-valued overrides replace the base value wholesale; there is no deep merge.
2. **Resolve the Effect Hash** for `axis_index` against the merged Entry (see below).
3. **Construct the Variant name.** If `name[axis_index]` is a non-empty string, that's the name verbatim and `prefix`/`suffix` at this index are ignored. Otherwise the name is `<prefix> <Entry name> <suffix>` with empty/null parts dropped.
4. **Substitute description tokens.** `{name}` tokens are replaced from the resolved Effect Hash. When the Variant Axis is `aspects`, the `{aspect}` token is replaced with `aspects[axis_index]`. Substitution applies to the Entry's `description`, the Concentration Block's `description`, and any other display-string field a future schema addition introduces.

Variant Overrides may not change `tier`, `aspects`, `prefix`, `suffix`, `name`, or `variant_overrides` itself — those are structural or have their own parallel-list mechanisms. The validator rejects an Entry that tries to.

The same parallel-list field names (`prefix`, `suffix`, `name`, `variant_overrides`) work for both axes — when both are present in an Entry, the validator already rejected the Entry, so resolution never needs to disambiguate.

### Effect Hash resolution

The Effect Hash is a flat dictionary, but its values cross-reference each other through Formulas. Resolution walks entries in declaration order, evaluating each one against a context that already contains every previously-resolved name:

- A list-valued entry on a multi-Variant Entry uses the value at `axis_index`.
- A string-valued entry is treated as a Formula and evaluated.
- Any other value is taken verbatim.

Tier 0 is treated as **0.5** in the formula context, per the project-wide convention. `tier` is always present in the context (single-value Entries supply their `tier`; aspect-axis Entries supply the Entry's flat `tier`). `rank` is always present. Names from the Effect Hash become available as soon as they're resolved, so a later entry's Formula may reference an earlier entry's value.

Damage-expression-only variables (`success`, `critical`, `attribute`) must **not** appear in Effect Hash Formulas, Range Formulas, or Target Formulas — those are resolved before any roll. The validator does not catch this; it surfaces as an unresolved-name error at evaluation time.

### Damage Type, Severity, and Threshold

The abilities module enforces the rules that link damage Effects to the damage_types catalog (`damage_types_glossary.md`):

- An Entry may declare a `damage_type` matching a name in the catalog. The validator rejects unknown names.
- A damage Effect's Severity comes from the **explicit per-Effect form** (`"<formula> <severity> damage"`) when present, otherwise from the Entry's `damage_type`'s default Severity.
- An Entry whose `damage_type` is **`physical`** must additionally declare a non-negative integer `threshold`. Physical damage opts into Runtime Bucketing, so its Severity is decided at damage-application time by combat — but the Threshold input is data the ability itself must carry.
- A `threshold` field on an Entry whose `damage_type` is anything other than `physical` is a validation error.
- An Entry with at least one damage Effect must have a determinable Severity for **every** damage Effect: each Effect either supplies its own Severity in the string, or the Entry's `damage_type` does. A damage Effect with neither is a validation error.
- An Entry with `attack_roll: true` and **no** declared damage Effects (in `effects` or in any Save Outcome) is allowed — the combat module computes implicit damage from the attack outcome (`Tier + Degree of Success + attack bonus`). The abilities module exposes `attack_roll`, the inferred melee/ranged kind (from `range`), and the casting skill list; it does not encode the implicit damage formula.

Aspect-axis Entries that vary `damage_type` per aspect declare `damage_type` as a parallel list (e.g. `damage_type: [fire, acid, electricity, cold]`).

### Deferred damage evaluation contract

Damage Formulas can reference roll results that aren't known at lookup time. The abilities module handles this by returning a classified **damage object** rather than a number:

```
{ kind: 'damage', formula: '<expr>', damage_type: <string|null>, severity: <string|null>, context: { rank, tier, ...effect_hash } }
```

`damage_type` is the Entry's resolved damage type (per-Variant when on the aspect axis). `severity` is the explicit per-Effect Severity if the string had one, otherwise `null` — leaving lookup of the default to the consumer, since the damage_types catalog isn't an abilities-module dependency at evaluation time.

The caller later supplies the missing pieces (`success`, `critical`, `attribute`) to evaluate the Formula. Negative damage values clamp to 0 at evaluation time. The `success`/`critical` semantics are caller-defined: defender's save results inside a Save Outcome, caster's casting-roll results inside an Unconditional Effect.

### Effect classification

Every Effect string falls into exactly one of three kinds, determined by string shape:

- `"0"` or `"none"` → `{ kind: 'none' }`.
- Matches `"<expression> damage"` or `"<expression> <severity> damage"` (where `<severity>` is `minor`, `moderate`, or `major`) → damage object as above.
- Otherwise → must be a key in `Effect Names`; returned as `{ kind: 'effect', name: <string> }`.

Validation rejects any other shape. The same classifier runs on Save Outcome values, Unconditional Effects (`effects` list), and Concentration save outcomes.

### Concentration Block

The Concentration Block has its **own Effect Hash, namespaced separately** from the Entry's top-level Effect Hash — the two never share variable names at evaluation time. Resolution mirrors the top-level path: resolve the block's Effect Hash, classify any Save Outcomes, substitute `{name}` and `{aspect}` placeholders into the block's `description`, convert the `action` cost to rounds the same way Casting Time is converted.

The Concentration Block's `attack_roll` and `save` are **independent** of the Entry's top-level versions — Heal-style spells have a top-level `attack_roll: false` but a concentration `save`; an attack-style spell may have both top-level and concentration attack rolls.

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
- Schema validation: rejecting unknown Entry Types, Schools, Casting Skills, Item Forms, Properties, Save Attributes, Save Outcome Keys, Effect Names, Casting Time aliases, Range names, Area Shapes, and Damage Type names; checking Variant parallel-list lengths; rejecting overrides of structural fields; rejecting universal-entry leaks in data files; rejecting Entries that declare both `tier` (as a list) and `aspects`.
- Validating Severity rules: every damage Effect must have a determinable Severity (explicit per-Effect or via the Entry's `damage_type`); `damage_type: physical` requires `threshold`; `threshold` is rejected on non-physical Entries.
- Resolving Variants along whichever axis the Entry uses: applying Overrides, constructing displayed names, performing `{name}` and `{aspect}` substitution.
- Resolving Effect Hash, with axis-indexed picks and cross-reference Formula evaluation.
- Classifying Effects (none / named / damage), including parsing the optional inline Severity from damage Effect strings.
- Building partial contexts and evaluating damage Formulas when `success`/`critical`/`attribute` are supplied.
- Resolving the Concentration Block (its own Effect Hash, classified saves, action-cost conversion, description substitution).
- Implicitly appending Universal Casting Skills and Universal Item Forms.
- Resolving `casting_time` to rounds, `range` to feet, and `target` to either `'self'` or a count.
- Filtering and listing Entries by Type and/or School.

### Explicitly *not* owned here

- **Rolling dice and resolving saves.** Lives in dice resolution and combat.
- **Damage Type behavior.** Severity defaults, Mechanics, and Runtime Bucketing live in the damage_types domain and its consumers (combat, conditions, dice resolution). Abilities only validates names and links damage Effects to types.
- **Computing implicit damage from attack rolls.** Combat module computes `Tier + Degree of Success + attack bonus` for attack-roll Entries that declare no explicit damage Effects.
- **Applying named effects.** The mechanics list inside an Effect Name is consumed by the condition module; the abilities module surfaces it verbatim.
- **Active-effect bookkeeping** — which creatures have which conditions, concentration tracking. Lives in condition and combat modules.
- **Consuming spell slots, charges, mana.** Lives in character and item modules.
- **Mapping creatures to known spells/abilities.** Character module owns prepared/known lists.
- **Determining who is in an `area`.** Combat module computes overlap; the abilities module just exposes `{shape, size}`.
- **Property mechanics.** The keyword list is validated here, but the behavior of each property lives in whichever module implements it.
- **Magic toxicity application.** Abilities exposes `minimum_saturation` and `saturation` Effect Hash conventions; the condition module reads and applies them.

### Unassigned (no current owner)

- Validating that a passed `rank` is non-negative.
- Tracking which Properties exist purely for display vs. those with mechanical effects, and where each one's mechanics live. *Likely needs a property registry per module.*
- Cross-domain validation that every name in `Effect Names` whose `mechanics` are non-empty corresponds to a Condition Mechanic the condition module actually understands. Today the abilities module accepts any `kind` field; nothing checks the consuming side agrees.
- Cross-domain validation that the `condition` and `condition_name` strings inside damage_types Mechanics resolve to real concepts in the consuming modules (mirrors the same gap on the abilities side).
