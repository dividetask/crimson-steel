# Abilities and Spells — Glossary

Reference module: exposes data about spells and abilities for other modules to consume. Does not track active effects on creatures — that lives in conditions and combat. *(configurable)* values come from `abilities_config.yaml`.

## Core Concepts

**Entry**: A single spell or ability definition. Loaded from the campaign data file (typically `data/compendium.json`), keyed by display name.

**Entry Type**: Each Entry has Type `spell` or `ability`. Spells and abilities share the same schema; the Type lets callers filter. *(configurable)*

**Spell**: An Entry with Type `spell`. Belongs to a Spell School, may be packaged into items, cast using one of a list of skills.

**Ability**: An Entry with Type `ability`. Has no Spell School and is not packaged into items; may declare a casting skills list (optional).

**Tier**: The magical density of an Entry. Tier 0 is treated as 0.5 in formulas (see common glossary). An Entry's `tier` is either an integer or a list of integers; a list indicates Variants.

**Rank**: The caster's investment in the casting skill used for this Entry. Supplied by the caller whenever a Formula is evaluated; the abilities module never computes rank itself.

**Variant Axis**: The dimension along which an Entry has multiple Variants. An Entry may use **at most one**: **Tier axis** (the `tier` field is a list of integers), or **Aspect axis** (the `aspects` field is a list of aspect names; `tier` remains a single integer). An Entry that declares neither has a single Variant.

**Variant**: One form of an Entry along its Variant Axis. Each Variant has its own optional `prefix`/`suffix` name parts, optional `name` override, axis-indexed values in the Effect Hash, and an optional `variant_overrides` bag. Displayed name: if `name[axis_index]` is non-null, used verbatim; otherwise `<prefix> <Entry name> <suffix>` with empties omitted. When a Variant uses `name`, its `prefix` and `suffix` at the same index are ignored.

**Aspect**: A label on the Aspect axis (`fire`, `acid`, etc.). Free-form and opaque to the abilities module; referenced from description-like strings via the `{aspect}` substitution token. The parallel `damage_type` list is what binds an aspect to a Damage Type.

**Variant Overrides**: An optional `variant_overrides` field on a multi-Variant Entry — a list parallel to the Variant Axis. Each element is `null` or a sparse dictionary of fields whose values replace the Entry's base values for that one Variant. A `null` override **value** removes the key from the merged entry. May not change `tier`, `aspects`, `prefix`, `suffix`, `name`, or `variant_overrides` itself. *(3 sentences — flagged: the null-removal semantics and the structural exclusion list are both load-bearing constraints)*

## Casting Time

**Casting Time**: How long to cast or invoke. The `casting_time` field is a string — either an alias from `Casting Time Aliases` or `"<N> rounds"` for any positive integer N. *(alias list configurable)*

**Round Length Seconds**: Number of seconds in one round. Used to convert minute / hour aliases into rounds. *(configurable)*

**Casting Time Aliases**: The named values and their round counts. Defaults: `Free Action` (0), `Bonus Action` (0.25), `Main Action` (0.5), `Full Turn` (1), `1 Minute` (10), `10 Minutes` (100), `1 Hour` (600), `1 Day` (14400). *(configurable)*

## Target

**Target**: Who or what the Entry affects. Either the literal `"self"`, an integer string, or a Formula evaluating to a non-negative integer count. Zero means the Entry has no valid targets and cannot be cast; `"self"` always means the caster regardless of rank.

## Range

**Range**: Either a string matching a key in `Range Formulas` or a bare integer (feet). *(named values configurable)*

**Range Formulas**: Mapping from named Ranges to Formula strings of `rank` and `reach`. Defaults: `Self: "0"`, `Touch: "reach"`, `Close: "5+5*rank"`, `Medium: "30+10*rank"`, `Long: "80+20*rank"`. *(configurable)*

**Reach**: Distance in feet a creature can touch without moving. Caller may supply a per-cast `reach` to `RESOLVE_RANGE`; otherwise `Default Reach Feet` is used. *(default configurable)*

## Area

**Area**: An optional `area` field turning the Entry into AOE. A dict with `shape` (one of `line`, `cone`, `square`, `circle`) and `size` (non-negative integer in 5-foot squares — never feet). The combat module figures out which creatures are in the area; this module only validates and exposes the pair. *(shapes configurable)*

## Attack

**Attack Roll**: An optional `attack_roll` boolean. When `true` the Entry resolves as an attack roll against its target; default `false`. The abilities module does not perform the roll.

**Melee vs. Ranged**: Implied by `range`: `Touch` + `attack_roll` is melee; any greater range with `attack_roll` is ranged. The schema carries no separate value.

**Attack vs. Save Convention**: Most Entries fit one of three: **Save only** (non-empty `save`, no attack), **Attack only** (empty `save`, `attack_roll: true`), **Helpful, no roll** (both absent or false). A few touch spells have both — attack lands the contact, save resolves the magical effect.

## Concentration

**Concentration Block**: An optional `concentration` field. Its presence both flags the Entry as concentration and defines the concentrate action. Fields: `action` (a Casting Time string), `apply_on_cast` (bool, default false), `retarget` (bool, default false), `description` (free-form), `attack_roll` (bool, default false), `save` (list of Save Specs), `effect_hash` (dict). The abilities module exposes the block; it does not track who is concentrating on what — that's combat. *(3 sentences — flagged: the field list is the schema spec)*

## Saves

**Saving Throw**: A Dice Resolution Check made by the target to resist or reduce an Entry's effect. Abbreviated **Save**.

**Save Spec**: One element of the Entry's `save` list. A dict with an `attribute` field, one entry per relevant Save Outcome Key, and an optional `condition` field.

**Save Attribute**: One of `none`, `str`, `dex`, `con`, `int`, `wis`, `cha`. `none` is shorthand for "no save". *(configurable)*

**Save Outcome Key**: A branch of a Save's result. Every Save Spec must define `fail`; `success` and `fumble` are optional. `fumble` applies when the defender's Degree of Failure meets or exceeds the Default Fumble Threshold and replaces the plain `fail` effect when present. *(configurable)*

**Save Effect**: An Effect (see common glossary) appearing as the value of a Save Outcome Key.

**Damage Effect Severity**: A damage Effect must have a determinable Severity from one of two sources: **explicit per-Effect Severity** baked into the string (e.g. `"3*rank major damage"`), or **implicit from the Entry's Damage Type**. Explicit wins when present. The Damage Type `physical` opts into Runtime Bucketing and counts as having a determinable Severity. A damage Effect on an Entry with neither a `damage_type` nor an explicit Severity is a validation error. *(4 sentences — flagged: each carries an independent rule the validator enforces)*

**Damage Effect Variables**: Damage-expression Formulas may reference `rank`, `tier`, any name from the Effect Hash, and roll-result variables `success` and `critical`. Inside a Save Outcome these are the **defender's** save results; inside a top-level `effects` list (Unconditional Effect) they are the **caster's** casting-roll results. The abilities module returns Formulas in deferred form; the caller evaluates them once the relevant roll is known.

**Damage Type**: A `damage_type` field on the Entry, naming an entry in the damage_types catalog (see `damage_types_glossary.md`). Attached to every damage-kind Effect on the Entry. May be omitted only when every damage Effect declares an explicit Severity in its string form. An Entry whose `damage_type` is `physical` must additionally declare a `threshold`.

**Threshold**: Optional non-negative integer field on an Entry. Required when `damage_type` is `physical`; rejected on Entries with any other damage type. For weapon-driven attacks the weapon's Threshold typically takes precedence — that decision lives in combat. (See common glossary.)

**Unconditional Effect**: An Effect that applies regardless of save or attack roll. Listed under the Entry's optional top-level `effects` field — a list of Effect strings. Use `effects` for outcomes that always happen on a successful cast; use `save` for outcomes that depend on the defender's save.

**Multiple Saves**: An Entry may list more than one Save Spec. Every Spec is offered to the target unless its `condition` restricts it.

**Conditional Save**: A Save Spec with a `condition` field. Recognized values: `on_fail` (only if the first Save Spec was a failure) and `on_fumble` (only if the first was a fumble). The abilities module reports them verbatim; the caller checks the condition.

## Properties

**Property**: A keyword flag that modifies how an Entry behaves. The `properties` field is an optional list of keywords from the configurable `Properties` table. Mechanical definitions live in the implementing module — abilities only validates names.

## Schools and Skills

**Spell School**: The magical discipline an Entry belongs to. The `school` field matches a key in `Spell Schools`. Only spell-Type Entries have a School. *(configurable)*

**Casting Skill**: A skill that may cast the Entry. The `skills` field lists keys from `Casting Skills List`. The caster picks one at casting time; that skill's ranks become `rank`. *(configurable)*

**Universal Spell Casting Skill**: A Casting Skill usable for any spell regardless of the entry's `skills` list (e.g. `evocation`). The configurable `Universal Spell Casting Skills` list is appended implicitly at lookup time; data files must not list universal skills explicitly. Abilities (Type `ability`) are unaffected.

## Items and Packaging

**Item Form**: A physical form a Spell may be packaged in. The `items` field lists keys from `Item Forms`. Empty means the Spell cannot be packaged in any non-universal form.

**Universal Item Form**: An Item Form any Spell may be packaged into without listing it (defaults: `scroll`, `wand`). Appended implicitly; data files must not list universal forms. *(configurable)*

**Valid Item Forms**: The list of Item Forms an Entry is eligible for, including universal forms added at lookup time. Item-Only Entries do **not** gain universal forms.

**Item-Only Entry**: An Entry whose `item_only` field is `true`. Cannot be cast directly — only invoked through a magic item that contains it. Still declares full casting fields so the item can resolve them.

## Effects

**Effect Hash**: The `effect_hash` field — a dictionary of named values used by the Entry's description and Save Effects. Values may be literal numbers/strings, lists indexed by the Variant Axis, or Formula strings. Names may be referenced from `description`, Save Effect strings, and other Effect Hash entries.

**Formula**: A string evaluated against a context dictionary. `rank` is always present; `tier` is present when the Entry has one assigned (Tier 0 → 0.5). Effect Hash names are added to the context first. Inside a damage expression, three additional caller-supplied variables may appear: **`success`** and **`critical`** (defender's save results for a Save Effect; caster's casting-roll results for an Unconditional Effect), and **`attribute`** (the casting skill's associated attribute value). These three are valid only inside damage expressions. *(4 sentences — flagged: the variable set and where each is valid is mechanical spec)*

**Description**: The `description` field — a free-form string with `{name}` placeholders substituted from the Effect Hash, and (for Aspect-axis Entries) `{aspect}`.

**Duration**: The `duration` field — a free-form string. Common values: `instant`, `concentration`, `"<formula> rounds"`, `"<formula> minutes"`, `permanent`. The abilities module exposes verbatim; the caller applies it.

(Effect: see common glossary. The catalog of named effects and their Mechanics lives in conditions — see `conditions_glossary.md`.)

## Magic Toxicity

(Magic Toxicity: see common glossary.)

**Magic Toxicity Effect Hash Keys**: Spells imposing toxicity expose two conventional Effect Hash names: `minimum_saturation` (minimum imposed per cast) and `saturation` (default imposed per cast). Typically Formula strings of `tier` (e.g. `"tier*2"`). Absent when the spell does not apply toxicity. The abilities module performs no validation; conditions reads and applies the resolved values.

## Procedural Class and Racial Abilities

Some abilities are **procedural**: they activate during a specific action and produce a one-shot effect with no per-creature state left behind (Sneak Attack, Channel Divinity, Improved Healing, Sense Injury). The procedural-ability catalog lives in the abilities module so callers can look up the trigger spec.

**Procedural Ability**: A class- or race-granted ability whose entire effect resolves during a specific action — no duration, no creature state. Callers ask the abilities module "does this Character have ability X, and if so, what's its trigger spec?".

**Trigger Spec**: A structured description of when a Procedural Ability fires and what it does. Has `on` (the triggering action — e.g. `attack_check`, `healing_check`, `invoke`), an optional `condition` (free-form scope tag the consuming module checks), and `effect` (the one-shot outcome).

**Stateful Counterpart**: Some abilities that *appear* class-granted are stateful (Rage, Bardic Inspiration, Trapfinding) — they live in the conditions module's Effect Names catalog or as Affliction-shaped state, not in the procedural catalog. Advancement / race ability lists still name them so the Character knows they exist; conditions owns their behavior. **Split rule: per-creature mutable state → Conditions; purely procedural lookup → Abilities.**

**Always-On Modifier**: A passive numeric bonus an ability grants while the Character has it (e.g. fast_movement's `+10` to speed). Lives on the ability's `modifiers:` field as a list of `{target, type, descriptors, add}` entries; consumed by the Modifiers class during bonus computation.

## Module Scope

The abilities module is a **reference**. Given an Entry name, it returns everything needed to resolve a cast (casting time, range, target count, save specs, casting skills, item forms, school, duration, full Effect Hash). Given a Procedural Ability name, it returns the Trigger Spec.

Does not:
- Track which creatures have which abilities prepared, or which effects are currently active.
- Roll dice, apply damage, resolve saves, or apply conditions.
- Consume spell slots, mana, or item charges.
- Evaluate Trigger Spec conditions or apply their effects (the consuming module's job).
