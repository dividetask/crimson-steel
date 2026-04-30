# Abilities and Spells — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `abilities_config.yaml`. The abilities module is a **reference** module: it exposes data about spells and abilities for other modules to consume, but does not track which effects are currently active on any creature. Active-effect bookkeeping lives in the condition and combat modules.

## Core Concepts

**Entry**: A single spell or ability definition. Entries are loaded from the campaign's data file (typically `data/compendium.json`) and keyed by the entry's display name.

**Entry Type**: Each Entry has a Type of either `spell` or `ability`. Spells and abilities share the same schema so the module can expose them uniformly; the Entry Type lets callers filter. *(configurable — the accepted values are defined under `Entry Types`.)*

**Spell**: An Entry with Type `spell`. Spells belong to a Spell School and may be packaged into items (potions, oils, scrolls, wands). Spells are cast using one of a list of skills.

**Ability**: An Entry with Type `ability`. Abilities do not have a Spell School and are not packaged into items. An Ability may still declare a list of casting skills (for example, a performance-based Ability that uses `perform_`), but the field is optional.

**Tier**: The magical density of an Entry. Tier 0 is treated as **0.5** in all formulas, per the project-wide tier convention. An Entry's `tier` field is either a single integer or a list of integers; a list indicates that the Entry has multiple Variants.

**Rank**: The caster's investment in the casting skill used for this Entry. Rank is a context variable supplied by the caller whenever an Entry's Formula is evaluated. The abilities module never computes rank itself.

**Variant Axis**: The dimension along which an Entry has multiple Variants. An Entry may use **at most one** Variant Axis:

- **Tier axis** — the `tier` field is a list of integers. Variants are indexed by tier and Tier 0 is treated as 0.5 in formulas.
- **Aspect axis** — the `aspects` field is a list of aspect names. Variants are indexed by aspect; the Entry's `tier` is a single integer that applies to every aspect.

An Entry may not declare both `tier` as a list and an `aspects` list. An Entry that declares neither has a single Variant.

**Variant**: One of the multiple forms of an Entry along its Variant Axis. Each Variant has its own optional `prefix` and `suffix` name components, an optional explicit name override, its own axis-indexed values in the Effect Hash, and an optional bag of per-Variant field overrides (`variant_overrides`). The displayed name of a Variant is constructed in two ways:

- If the Entry has a `name` list and `name[axis_index]` is a non-null string, that string is used verbatim as the Variant's displayed name.
- Otherwise, the displayed name is `<prefix> <Entry name> <suffix>`, omitting any null or empty parts.

The `name` override exists for Variants whose names don't share a clean prefix/suffix structure with the Entry's base name — e.g. a single Entry whose tier-0 form is "Vicious Mockery" and tier-1 form is "Biting Words". When a Variant uses `name`, its `prefix` and `suffix` entries at the same index are ignored.

**Aspect**: A label on the Aspect axis. Aspect names (`fire`, `acid`, etc.) are free-form labels; the abilities module treats them as opaque and does not cross-validate against any other catalog. The label can be referenced from `description`, `concentration.description`, and any other description-like string via the `{aspect}` substitution token, which is replaced with the current Variant's aspect name at lookup time. The parallel `damage_type` list is what binds an aspect to a Damage Type — the aspect name itself has no automatic semantics.

**Variant Overrides**: An optional `variant_overrides` field on a multi-Variant Entry. A list parallel to the Entry's Variant Axis (`tier` list or `aspects` list). Each element is either `null` (no overrides for that Variant) or a sparse dictionary of fields whose values replace the Entry's base values for that one Variant. Use Variant Overrides for fields that need to differ per-Variant in ways the parallel-list mechanism (`prefix`/`suffix`/`name`/Effect Hash lists) doesn't already cover — e.g. `attack_roll: true` at tier 1 but not at tier 0, or a different `effects` list at higher tiers.

Override values replace the base value entirely; there is no list-merge or dictionary-merge step. **A `null` override value means "remove this key from the merged entry"** rather than "set the key to null" — useful for Variants that should opt out of an inherited field (e.g. removing the `concentration` block at higher tiers of a spell whose lower tiers required concentration).

A Variant Override may not change `tier`, `aspects`, `prefix`, `suffix`, `name`, or `variant_overrides` itself — those are structural or have their own parallel-list mechanisms. Any other top-level field on the Entry may be overridden.

## Casting Time

**Casting Time**: How long it takes to cast or invoke an Entry. The `casting_time` field is a string for ease of reading. It may be either an alias defined in `Casting Time Aliases` (e.g. `"Bonus Action"`, `"1 Hour"`) or a string of the form `"<N> rounds"` for any positive integer `N`. *(alias list is configurable.)*

**Round Length Seconds**: The number of seconds in one round. Used to convert Casting Time aliases that describe minutes or hours into a number of rounds. *(configurable)*

**Casting Time Aliases**: The table of named Casting Time values and the number of rounds each represents. *(configurable.)* The default aliases are `Free Action` (0), `Bonus Action` (0.25), `Main Action` (0.5), `Full Turn` (1), `1 Minute` (10), `10 Minutes` (100), `1 Hour` (600), and `1 Day` (14400).

## Target

**Target**: Who or what the Entry affects. The `target` field is either the literal string `"self"`, an integer written as a string (e.g. `"1"`, `"3"`), or a Formula string that evaluates to a non-negative integer count (e.g. `"1+rank/2"`).

When the resolved target count is zero, the Entry has no valid targets and cannot be cast. When the Target is `"self"`, the Entry always affects exactly the caster regardless of the caster's rank.

## Range

**Range**: How far the Entry can reach. The `range` field is either a string matching a key in `Range Formulas`, or a bare integer indicating an explicit distance in feet. *(named Range values are configurable.)*

**Range Formulas**: The mapping from named Ranges (`Self`, `Touch`, `Close`, `Medium`, `Long`) to Formula strings evaluated against `rank` and `reach` to produce a distance in feet. The default formulas are `Self: "0"`, `Touch: "reach"`, `Close: "5+5*rank"`, `Medium: "30+10*rank"`, `Long: "80+20*rank"`. *(configurable)*

**Reach**: The distance, in feet, that a creature can touch without moving. The caller may supply a per-cast `reach` value to `RESOLVE_RANGE` to handle larger creatures with a longer reach. When the caller omits it, the abilities module substitutes `Default Reach Feet` from the config. *(default value is configurable)*

## Area

**Area**: An optional `area` field on an Entry that turns the Entry from a single-target effect into an area-of-effect. When present, `area` is a dictionary with two fields:

- `shape`: one of `line`, `cone`, `square`, or `circle`.
- `size`: a non-negative integer measured in 5-foot squares — never in feet, regardless of shape.

The shape interpretation is documented under `Area Shapes` in the config: a line is `size` squares long; a cone has `size` squares of slant length; a square is `size` squares on each side; a circle has `size` squares of radius. The abilities module validates the shape against the config and exposes the `{shape, size}` pair to the caller; the combat module figures out which creatures are in the area. An Entry without an `area` field affects only its declared `target` count of creatures within `range`. *(shapes are configurable.)*

## Attack

**Attack Roll**: An optional `attack_roll` boolean. When `true`, the Entry resolves as an attack roll against its target. When omitted, the default is `false`. The abilities module exposes this flag but does not perform the roll — attack resolution lives in the combat module.

The attack's nature (melee vs. ranged) is implied by the Entry's `range`: a `Touch` Entry with `attack_roll: true` is a melee attack; an Entry at any greater range with `attack_roll: true` is a ranged attack. The schema does not carry a separate melee/ranged value.

**Attack vs. Save Convention**: Most Entries fall into one of three categories:
- **Save only** — the target rolls a Saving Throw. The Entry has a non-empty `save` list and no `attack_roll` (or `attack_roll: false`).
- **Attack only** — the caster rolls an attack. The Entry has an empty `save` list and `attack_roll: true`.
- **Helpful, no roll** — the Entry is purely beneficial (e.g. Heal). Both `save` and `attack_roll` are absent or false.

A small number of Entries have both `attack_roll: true` and a `save`; these are almost always touch spells, where the attack resolves whether contact is made and the save resolves the magical effect after contact lands.

## Concentration

**Concentration Block**: An optional `concentration` field on an Entry. The presence of this block is what marks an Entry as a concentration Entry — it both flags the Entry as concentration and defines what the concentrate action does. The block is a dictionary with the following fields:

- **`action`**: The action cost the caster spends each turn to keep concentrating. A Casting Time string (e.g. `Bonus Action`, `Main Action`).
- **`apply_on_cast`** *(optional, default false)*: When `true`, the concentration effect also fires once on the initial cast — useful when the cast and the concentrate action share an effect (e.g. Heal's bleed-reduction triggers on cast and on every concentrate action).
- **`retarget`** *(optional, default false)*: When `true`, the caster picks a new target each concentrate turn. When `false`, the concentrate action operates on the original target chosen at cast time. Heal stays on its target (`false`); Vicious Mockery and the elemental darts let the caster mock or hurl at any valid target each turn (`true`).
- **`description`** *(optional)*: A free-form string describing what the concentrate action does. The same `{name}` substitution rules as the Entry's main description apply.
- **`attack_roll`** *(optional, default false)*: Whether the concentrate action requires its own attack roll. Independent of the Entry's top-level `attack_roll`; some concentration effects (Fire Dart's repeated darts) involve attacks while others (Heal's bleed reduction) do not.
- **`save`** *(optional)*: A list of Save Specs governing the concentrate action, with the same schema as the Entry's top-level `save`.
- **`effect_hash`** *(optional)*: A dictionary of named values used by the concentration `description` and any Save Effects in `save`. Resolved with the same rules as the Entry's main Effect Hash.

The abilities module does not track which casters are concentrating on which Entries, nor does it apply the concentration effect — both responsibilities live in the combat module. The module simply exposes the Concentration Block so callers know what the concentrate action is supposed to do.

## Saves

**Saving Throw**: A Dice Resolution Check made by the target of an Entry to resist or reduce its effect. Abbreviated **Save**. The abilities module does not perform saves; it only declares which saves an Entry grants.

**Save Spec**: One element of the Entry's `save` list. A Save Spec is a dictionary with an `attribute` field (one of the Save Attributes) and one entry per relevant Save Outcome Key. A Save Spec may also include a `condition` field (see Conditional Saves below).

**Save Attribute**: The attribute the target uses to make the Save. One of `none`, `str`, `dex`, `con`, `int`, `wis`, `cha`. The value `none` indicates the Entry grants no save and appears only as shorthand for "no save" on an Entry whose `save` list contains a single Save Spec. An Entry may also omit the `save` field entirely or use an empty list to indicate no save. *(configurable)*

**Save Outcome Key**: The name of a branch of a Save's result. Every Save Spec must define `fail`; `success` and `fumble` are optional. A Save Spec that omits an optional outcome has no additional effect on that branch. `fumble` applies when the defender's Degree of Failure meets or exceeds the Default Fumble Threshold defined in `dice_resolution_config.yaml`, and when present replaces the plain `fail` effect. *(configurable)*

**Save Effect**: An Effect (see below) that appears as the value of a Save Outcome Key. The same shape as any other Effect.

**Effect**: A single effect string. An Effect is one of:
- The literal `"0"` or `"none"` — no effect.
- A non-empty string that is not a damage expression — treated as a named non-damage effect (e.g. `blind`, `dazzled`, `bleeding`). The abilities module passes the name through opaquely. Validation against the conditions module's Effect Names catalog happens later when the effect is applied; the abilities module deliberately does not maintain or consult an effect-names list of its own.
- A damage expression of the form `"<formula> damage"` or `"<formula> <severity> damage"` — a formula that evaluates to a damage amount, optionally with an explicit Severity.

A damage Effect must have a determinable Severity. Severity comes from one of two sources:
- **Explicit per-Effect Severity**, baked into the string between the formula and the word `damage` (e.g. `"3*rank major damage"`). Recognized values are `minor`, `moderate`, and `major`. Wins when present.
- **Implicit from the Entry's Damage Type**, looked up in `damage_types_config.yaml`. The Severity declared on the Damage Type applies to every damage Effect on the Entry that omits an explicit Severity. The Damage Type `physical` opts into Runtime Bucketing (see `damage_types_glossary.md`) and counts as having a determinable Severity.

A damage Effect on an Entry with neither a `damage_type` nor an explicit Severity is a validation error.

Damage-expression Formulas may reference `rank`, `tier`, any name from the Effect Hash, and two roll-result variables: **`success`** and **`critical`**. Their meaning depends on which roll the caller is reporting back:
- For an Effect inside a Save Outcome, `success` and `critical` are the **defender's** save results.
- For an Effect inside a top-level `effects` list (an Unconditional Effect), `success` and `critical` are the **caster's** casting-roll results.

The abilities module does not roll dice; it returns Formulas in a deferred form so the caller evaluates them once the relevant roll is known.

The abilities module does not own the catalog of named effects, their structured Mechanics, or the validation that an Effect string corresponds to a real entry — those all live in the conditions module. See `conditions_glossary.md` for the Effect Name term and the recognized Mechanic kinds.

**Damage Type**: A `damage_type` field on an Entry. A name from the damage_types catalog (see `damage_types_glossary.md`), attached to every damage-kind Effect produced by the Entry across `effects`, `save` outcomes, and the Concentration Block. The abilities module validates the name against the catalog but defers resolution semantics (resistances, vulnerabilities, type-specific mechanics) to the damage_types module and its consumers.

An Entry's `damage_type` may be omitted only when every damage Effect on the Entry declares an explicit Severity in its string form. An Entry whose `damage_type` is `physical` must additionally declare a `threshold`.

**Threshold**: An optional non-negative integer field on an Entry, used by Runtime Bucketing to split Physical Damage points across the Severity pools. Required when `damage_type` is `physical`; rejected on Entries with any other damage type. For weapon-driven attacks, the weapon's Threshold typically takes precedence over the Entry's — that decision lives in combat.

**Unconditional Effect**: An Effect that applies regardless of any save or attack roll. Listed under the Entry's optional top-level `effects` field — a list of Effect strings. Use the `effects` field for outcomes that always happen on a successful cast (e.g. damage that the save does not affect); use the `save` field for outcomes that depend on the defender's save.

**Multiple Saves**: An Entry may list more than one Save Spec. Every Save Spec is offered to the target unless it has a `condition` that restricts when it applies.

**Conditional Save**: A Save Spec with a `condition` field that restricts when the save is granted. Recognized conditions are `on_fail` (only offered if the first Save Spec was a failure) and `on_fumble` (only offered if the first Save Spec was a fumble). The abilities module reports conditional saves verbatim; the caller is responsible for checking the condition and applying the save only when appropriate.

## Properties

**Property**: A keyword flag that modifies how an Entry behaves but carries no numeric data of its own. The `properties` field on an Entry is an optional list of property keywords from the configurable `Properties` table. Mechanical definitions for each property live in whichever module implements its effect — the abilities module only validates that property names are recognized and exposes the list to callers.

## Schools and Skills

**Spell School**: The magical discipline an Entry belongs to. The `school` field is a string matching a key in `Spell Schools`. Only Entries with Type `spell` have a School; Entries with Type `ability` do not. *(configurable)*

**Casting Skill**: A skill that may be used to cast the Entry. The `skills` field is a list of skill keys from `Casting Skills List`. The caster picks one of the listed skills at casting time; that skill's ranks determine the caster's `rank` when the Entry's Formulas are evaluated. *(list is configurable)*

**Universal Spell Casting Skill**: A Casting Skill that can be used to cast any spell, regardless of whether the spell's entry lists it. The configurable `Universal Spell Casting Skills` list names these skills — `evocation` is the standard example. The abilities module implicitly appends the universal skills to every spell's effective skill list at lookup time; data files must not list universal skills in an entry's `skills` field. Abilities (Entries with `type: ability`) are unaffected because they are not spells. *(configurable)*

## Items and Packaging

**Item Form**: A physical object form in which a Spell may be packaged. The `items` field is a list of keys from `Item Forms`. An empty list means the Spell cannot be packaged into any non-universal item form.

**Universal Item Form**: An Item Form that any Spell may be packaged into without being listed in the Entry's `items` field. The configurable `Universal Item Forms` list names them — the standard entries are `scroll` and `wand`. The abilities module implicitly appends the universal forms to every Spell's Valid Item Forms at lookup time; data files must not list universal forms in an entry's `items` field. *(configurable)*

**Valid Item Forms**: The list of Item Forms an Entry is eligible for, including the universal forms added by the module at lookup time. The abilities module exposes this list; the caller decides which form to produce. Item-only Entries do not gain universal forms — they may only be invoked through the explicit Item Forms their entry lists.

**Item-Only Entry**: An Entry whose `item_only` field is `true`. An Item-Only Entry cannot be cast directly by a caster; it can only be invoked through a magic item that contains it. An Item-Only Entry still declares a full set of casting fields (skills, range, save, etc.) so that the magic item can resolve them when the item is used.

## Effects

**Effect Hash**: The `effect_hash` field — a dictionary of named values used by the Entry's description and its Save Effects. Values may be literal numbers or strings, lists indexed by the Entry's Variant Axis (used when `tier` is a list or `aspects` is present), or Formula strings. Names in the Effect Hash may be referenced from the `description`, from Save Effect strings, and from other Effect Hash entries that are themselves Formulas.

**Formula**: A string that is evaluated against a context dictionary to produce a numeric value. The variable `rank` is always present; when an Entry has a tier assigned, `tier` is also present and carries the tier of the Variant being evaluated (with Tier 0 treated as 0.5). Names from the Effect Hash are added to the context before any Effect or description string is resolved. When a Formula inside an Effect's damage expression is evaluated, three additional variables may be supplied by the caller:

- **`success`** and **`critical`** — roll-result counts. Their meaning depends on context: for a Save Effect they are the defender's save results; for an Unconditional Effect they are the caster's casting-roll results.
- **`attribute`** — the value of the casting skill's associated attribute (e.g. Cha for `perform_`, Int for `arcana`). Useful for spells whose damage scales with the caster's stats, such as a `attribute/2 + 2` formula.

These three variables are only valid inside damage expressions — they must not be referenced from the Effect Hash or from the Range/Target formulas, because those are resolved before any roll is made.

**Description**: The `description` field — a free-form string displayed to the user. The description may contain `{name}` placeholders, substituted from the Effect Hash at display time, and (for Aspect-axis Entries) the `{aspect}` placeholder, replaced with the current Variant's aspect name.

**Duration**: The `duration` field — a free-form string indicating how long the Entry's effect lasts. Common values include `instant`, `concentration`, `"<formula> rounds"`, `"<formula> minutes"`, and `permanent`. The abilities module does not interpret Duration strings; it exposes them verbatim for the caller to apply.

## Magic Toxicity

**Magic Toxicity**: A measure of a creature's accumulated exposure to magical effects, also called magic saturation. The condition itself is owned by the condition module; the abilities module's only role is to expose how much toxicity a spell imposes on its target via two conventional names in the Effect Hash:

- `minimum_saturation` — the minimum amount of magic toxicity the spell imposes per cast.
- `saturation` — the default amount the spell imposes per cast.

Both are typically Formula strings of `tier` (e.g. `"tier*2"`, `"tier*5"`). When a spell does not apply magic toxicity, both keys are absent from its Effect Hash. The abilities module performs no validation on whether these keys are present; it surfaces the resolved values through the standard Effect Hash so the condition module can read and apply them.

Per the project-wide convention, the term **magic toxicity** is preferred over "mana saturation"; the two refer to the same mechanic.

## Procedural Class and Racial Abilities

Some abilities granted by classes and races (named in `advancement_config.yaml` under each class's `abilities:` list and in `race_config.yaml` similarly) are **procedural** — they activate during a specific action and produce a one-shot effect with no per-creature state left behind. Sneak Attack, Channel Divinity, Improved Healing, and Sense Injury all fit. The procedural-ability catalog lives in the abilities module so callers (combat, dice resolution, healing) can look up the trigger spec for a name.

**Procedural Ability**: A class- or race-granted ability whose entire effect resolves during a specific action. The ability has no duration and creates no state on the creature using it. Lookup happens at action-time: combat (or whichever caller is running the action) asks the abilities module "does this Character have ability X, and if so, what's its trigger spec?".

**Trigger Spec**: A structured description of when a Procedural Ability fires and what it does. Each Spec has an `on` field (the action that triggers it — e.g. `attack_check`, `healing_check`, `invoke`), an optional `condition` field (a free-form scope tag the consuming module checks — e.g. `target_flatfooted`, `target_undead`), and an `effect` field describing the one-shot outcome.

**Stateful Counterpart**: Some abilities that *appear* class-granted are actually stateful — Rage (entered for N rounds), Bardic Inspiration (luck-points counter), Trapfinding (concentration). These are **not** in the procedural catalog; they live in the conditions module's Effect Names catalog, the Acid-Counter-style hardcoded counters, or as Affliction-shaped state. The advancement / race ability list still names them so the Character knows they exist; the conditions module owns their behavior and per-creature state.

The split rule: any per-creature mutable state → Conditions; purely procedural lookup → Abilities.

**Always-On Modifier**: A passive numeric bonus an ability grants while the Character has it (e.g. fast_movement's `+10` to speed). Lives directly on the ability entry's `modifiers:` field in `advancement_config.yaml` (or `race_config.yaml`), as a list of `{target, type, descriptors, add}` entries — see those configs for the schema. The Modifiers class consumes this list during Character bonus computation. Always-On Modifiers are simpler than full Trigger Specs: no `on` action, no `condition`, just a constant addition.

## Module Scope

The abilities module is strictly a **reference**. Given an Entry name, it returns every piece of information needed to resolve a cast: the casting time in rounds, the range in feet, the target count, the list of save specs, the valid casting skills, the valid item forms, the school, the duration string, and the full Effect Hash. Given a Procedural Ability name, it returns the Trigger Spec. It does not:

- Track which creatures have which abilities or spells prepared.
- Track which effects are currently active.
- Roll dice, apply damage, or apply conditions.
- Resolve saves.
- Consume spell slots, mana, or item charges.
- Evaluate Trigger Spec conditions or apply their effects — that's the consuming module's job (combat for `attack_check` triggers, healing for `healing_check`, etc.).

Those responsibilities belong to the character, combat, condition, and item modules respectively. The abilities module's single job is to answer "what does this spell, ability, or class feature do?" in a form those other modules can consume directly.
