# Abilities and Spells — Design

The abilities module is a strict **reference**: it answers "what does this spell or ability do?" in a form other modules can consume. It rolls no dice, tracks no active effects, and consumes no resources.

## Key Operations

### Variant resolution

An Entry's Variants are indexed by exactly one **Variant Axis** — `tier` (a list of integers) or `aspects` (a list of opaque labels). The two are mutually exclusive (validator rejects both). An Entry that declares neither has a single Variant.

Resolving a Variant at `axis_index` follows a fixed order:

1. **Apply Variant Overrides.** If `variant_overrides[axis_index]` is a dictionary, shallow-replace each key on a copy of the base Entry. **A `null` override value removes the key entirely** — this is how a higher tier opts out of a Concentration Block, or how one aspect of a multi-element spell drops a save the other aspects retain. List- and dictionary-valued overrides replace the base value wholesale; there is no deep merge.
2. **Resolve the Effect Hash** for `axis_index` against the merged Entry.
3. **Construct the Variant name.** If `name[axis_index]` is a non-empty string, that's the name verbatim and `prefix`/`suffix` at this index are ignored. Otherwise the name is `<prefix> <Entry name> <suffix>` with empty/null parts dropped.
4. **Substitute description tokens.** `{name}` tokens replaced from the resolved Effect Hash. When axis is `aspects`, `{aspect}` is replaced with `aspects[axis_index]`. Substitution applies to `description`, the Concentration Block's `description`, and any future display-string field.

Variant Overrides may not change `tier`, `aspects`, `prefix`, `suffix`, `name`, or `variant_overrides` itself — those are structural or have their own parallel-list mechanisms.

### Effect Hash resolution

The Effect Hash is a flat dictionary, but its values cross-reference each other through Formulas. Resolution walks entries in declaration order, evaluating each against a context that already contains every previously-resolved name:

- A list-valued entry on a multi-Variant Entry uses the value at `axis_index`.
- A string-valued entry is treated as a Formula and evaluated.
- Any other value is taken verbatim.

`tier` is always present (Tier 0 → 0.5 per project convention). `rank` is always present. Names from the Effect Hash become available as soon as they're resolved, so a later entry's Formula may reference an earlier entry's value.

Damage-expression-only variables (`success`, `critical`, `attribute`) must **not** appear in Effect Hash Formulas, Range Formulas, or Target Formulas — those are resolved before any roll. The validator does not catch this; it surfaces as an unresolved-name error at evaluation time.

### Damage Type, Severity, and Threshold

The abilities module enforces the rules linking damage Effects to the damage_types catalog:

- An Entry may declare a `damage_type` matching a name in the catalog.
- A damage Effect's Severity comes from the **explicit per-Effect form** (`"<formula> <severity> damage"`) when present, otherwise from the Entry's `damage_type`'s default Severity.
- An Entry whose `damage_type` is **`physical`** must additionally declare a non-negative integer `threshold`. Physical damage opts into Runtime Bucketing, so Severity is decided at damage-application time by combat — but the Threshold input is data the ability itself must carry.
- A `threshold` field on a non-physical Entry is a validation error.
- Every damage Effect must have a determinable Severity (explicit per-Effect or via the Entry's `damage_type`).
- An Entry with `attack_roll: true` and **no** declared damage Effects is allowed — combat computes implicit damage (`Tier + Degree of Success + attack bonus`).

Aspect-axis Entries that vary `damage_type` per aspect declare it as a parallel list (e.g. `damage_type: [fire, acid, electricity, cold]`).

### Deferred damage evaluation contract

Damage Formulas can reference roll results that aren't known at lookup time. The module returns a classified **damage object** rather than a number:

```
{ kind: 'damage', formula: '<expr>', damage_type: <string|null>, severity: <string|null>, context: { rank, tier, ...effect_hash } }
```

`severity` is the explicit per-Effect Severity if the string had one, otherwise `null` — leaving lookup of the default to the consumer, since the damage_types catalog isn't an abilities-module dependency at evaluation time.

The caller later supplies `success`, `critical`, `attribute` to evaluate. Negative damage values clamp to 0. The `success`/`critical` semantics are caller-defined: defender's save results inside a Save Outcome, caster's casting-roll results inside an Unconditional Effect.

### Effect classification

Every Effect string falls into exactly one of three kinds, by string shape:

- `"0"` or `"none"` → `{ kind: 'none' }`.
- `"<expression> damage"` or `"<expression> <severity> damage"` → damage object as above.
- Otherwise → `{ kind: 'effect', name: <string> }`. The abilities module does not check that the name exists in any catalog — that's the conditions module's job at apply time.

### Concentration Block

The Concentration Block has its **own Effect Hash, namespaced separately** — the two never share variable names at evaluation time. Resolution mirrors the top-level path.

The Concentration Block's `attack_roll` and `save` are **independent** of the Entry's top-level versions — Heal-style spells have a top-level `attack_roll: false` but a concentration `save`; an attack-style spell may have both.

### Universal forms and skills

`Universal Spell Casting Skills` and `Universal Item Forms` are appended **implicitly** at lookup time, not stored on the Entry. Data files must not list a universal entry in `skills` or `items` (validator rejects). Spells get universal skills/forms appended; Abilities (`type: ability`) do not. Item-Only Entries do **not** receive universal Item Forms — only the explicit list applies, since the universal forms (scroll, wand) wouldn't make sense for them.

### Conditional saves

A Save Spec may carry a `condition` field (`on_fail` or `on_fumble`) that gates whether the save is offered. The abilities module reports conditional saves verbatim; **dispatch is the caller's job** — the abilities module never inspects prior save results.

`fumble` outcome dispatch is also caller-side: when a save's Degree of Failure meets or exceeds the Default Fumble Threshold, the `fumble` outcome (if defined) replaces the plain `fail` outcome.

### Procedural Ability lookup

Procedural class/racial abilities live in a catalog under `abilities_config.yaml`'s `Procedural Abilities:` section, mapping ability `name` to a list of Trigger Specs. `GET_PROCEDURAL_TRIGGERS(ability_name)` returns them verbatim (or an empty list).

A Trigger Spec has three fields:

- **`on`** — the action the trigger fires during. Recognized today: `attack_check`, `healing_check`, `invoke` (meaning "the Character spends an action to use this ability").
- **`condition`** *(optional)* — a free-form scope tag the consumer evaluates. Examples: `target_flatfooted`, `target_undead`. Abilities never interprets the tag.
- **`effect`** — a structured one-shot outcome with its own `kind` field. Sketch kinds: `bonus_dice`, `scale`, `ui_reveal`, `invoke_named_effect`.

Critically, **abilities does not evaluate the trigger** — it returns the Spec, and the consuming module checks the condition and applies the effect. This keeps the abilities module ignorant of action semantics, the same way it's ignorant of dice rolls.

The catalog is **partial today** — entries are added as the corresponding action paths get designed. If a class lists ability X but X has no Procedural catalog entry, the consuming module gets nothing back — that's an explicit "not yet implemented" state, not a bug.

### Always-On Modifier read-through

Flat numeric bonuses while the Character has the ability are handled by Modifiers via the `modifiers:` field on each ability entry. `GET_ABILITY_MODIFIERS(ability_name, source: 'class'|'race')` returns the list; actual application (summing across earned abilities, posting to bonus calculations) is the Modifiers/Character path.

Always-On Modifiers and Procedural Trigger Specs are independent — an ability may have either, both, or neither. `fast_movement` has only Always-On Modifiers. `sneak_attack` has only Triggers. `magical_performance` might have both.

## Responsibilities

### Owned by the abilities domain

- Loading and validating `abilities_data` and `abilities_config`.
- Schema validation: rejecting unknown Entry Types, Schools, Casting Skills, Item Forms, Properties, Save Attributes, Save Outcome Keys, Casting Time aliases, Range names, Area Shapes, Damage Type names; checking Variant parallel-list lengths; rejecting overrides of structural fields; rejecting universal-entry leaks; rejecting Entries that declare both `tier` (as a list) and `aspects`. **Not** validated here: Effect string names against any catalog — bad names surface when conditions tries to apply them.
- Validating Severity rules: every damage Effect has a determinable Severity; `damage_type: physical` requires `threshold`; `threshold` rejected on non-physical Entries.
- Resolving Variants: applying Overrides, constructing names, performing `{name}` and `{aspect}` substitution.
- Resolving Effect Hash with axis-indexed picks and cross-reference Formula evaluation.
- Classifying Effects (none / named / damage), parsing optional inline Severity from damage Effect strings.
- Building partial contexts and evaluating damage Formulas when `success`/`critical`/`attribute` are supplied.
- Resolving the Concentration Block.
- Implicitly appending Universal Casting Skills and Universal Item Forms.
- Resolving `casting_time` to rounds, `range` to feet, `target` to either `'self'` or a count.
- Filtering and listing Entries by Type and/or School.
- **Procedural Ability catalog**: lookup of names to Trigger Specs. Returns Specs verbatim; never evaluates them.
- **Always-On Modifier read-through**: returning a class or racial ability's `modifiers:` list to its consumer.

### Explicitly *not* owned here

- **Rolling dice and resolving saves.** Dice resolution and combat.
- **Damage Type behavior.** Severity defaults, Mechanics, Runtime Bucketing live in damage_types and its consumers.
- **Computing implicit damage from attack rolls.** Combat.
- **Applying named effects.** Conditions.
- **Active-effect bookkeeping**, concentration tracking. Conditions and combat.
- **Consuming spell slots, charges, mana.** Character and item modules.
- **Mapping creatures to known spells/abilities.** Character.
- **Determining who is in an `area`.** Combat computes overlap.
- **Property mechanics.** The keyword list is validated here, but behavior of each property lives elsewhere.
- **Magic toxicity application.** Conditions reads and applies.

### Unassigned (no current owner)

- Validating that a passed `rank` is non-negative.
- Tracking which Properties exist purely for display vs. those with mechanical effects.
- Cross-domain validation that every name in `Effect Names` whose `mechanics` are non-empty corresponds to a Condition Mechanic the conditions module actually understands.
- Cross-domain validation that the `condition` and `condition_name` strings inside damage_types Mechanics resolve to real concepts.
