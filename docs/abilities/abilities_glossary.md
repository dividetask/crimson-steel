# Abilities — Glossary

Defines the vocabulary used by `abilities_design.md` and `abilities_tests.md`. The Abilities domain is a strict **reference**: it exposes data about Spells, Talents, and granted features for other modules to consume. It does not track active effects on Creatures — that lives in Conditions. *(configurable)* values come from `abilities_config.yaml`. Schemas, field names, and operation details are defined in `abilities_design.md`; this file restricts itself to vocabulary.

## Abilities

**Ability**: A named feature a Creature can possess. May be granted by a Class or Race, or learned independently. Resolves into one or more flavors — Catalog Ability, Stateful Ability, or Always-On Modifier Ability — and a single Ability name may carry multiple flavors at once.

**Catalog Ability**: An Ability defined in the Spell or Talent catalog with a full schema.

**Type**: A Catalog Ability's broad category — Spell or Talent.

**Spell**: A magical Catalog Ability. Belongs to a Spell School and may be packaged into Item Forms.

**Talent**: A non-Spell Catalog Ability. Includes innate magical attacks, breath weapons, ki strikes, natural-attack grants, and procedural class/race features. Has no Spell School and is not packaged into Items.

**Stateful Ability**: An Ability whose behavior includes per-Creature mutable state — a counter, timer, or pool. Conditions owns the state and effect application; the Abilities domain only carries the name and a display description.

**Always-On Modifier Ability**: An Ability that grants a passive numeric bonus while the Creature has it. Modifiers owns the bonus aggregation; the Abilities domain only carries the name, description, and modifier data.

**Granted Ability**: An Ability granted to a Creature by a Class or Race. The name is resolved against the Catalog and side tables to produce the full picture of what the Creature gets.

## Variants

**Tier**: For a Spell, the Spell's intrinsic magical density. For a Talent, typically not carried — the using Creature's Tier supplies the value at evaluation time. (See common glossary for the Tier-0 → 0.5 convention.) A Catalog Ability with multiple Tiers exposes a Variant per Tier.

**Rank**: The caster's investment in the Casting Skill used for an Ability. Supplied by the caller; the Abilities module never computes it.

**Variant Axis**: The dimension along which a Catalog Ability has multiple Variants. A Catalog Ability may use **at most one**: Tier axis or Aspect axis. One with neither has a single Variant.

**Variant**: One form of a Catalog Ability along its Variant Axis. Each Variant has its own name, optional value substitutions, and optional structural overrides.

**Aspect**: A label on the Aspect axis (for example Fire or Acid). Free-form and opaque to the Abilities module; bound to a Damage Type via a parallel list.

**Variant Overrides**: A sparse per-Variant override of an Ability's base values. May replace or remove individual fields on a single Variant. Structural fields are not overridable.

## Activation Time

**Activation Time**: How long it takes to use an Ability. Applies uniformly to Spells and Talents. May be expressed as an **Action Alias** (the activation happens during the Creature's turn) or a **Real-Time Alias** (the activation has a wall-clock duration in minutes).

**Action Alias**: A categorical activation time tied to the Combat action economy — Free, Bonus, Reaction, Main, or Full Turn. Combat owns turn timing. *(configurable)*

**Real-Time Alias**: An activation time measured in wall-clock minutes — 1 minute, 10 minutes, 1 hour, 1 day. *(configurable)*

**Turn-Count Activation**: A multi-turn activation expressed directly as a turn count (e.g., a two-turn cast). Combat owns the timing.

## Target

**Target**: Who or what the Ability affects. Either the caster, an object, a fixed count of creatures, or a count computed from Rank. An Ability with an Area and no Target affects every creature in the Area. An Ability with both Target and Area uses the Target as the Area's anchor.

**Willing Target**: An Ability that only affects targets that consent. Self-targeted Abilities are always willing; other Abilities mark this explicitly. A target can always intentionally fail a save to accept an effect they would otherwise resist.

## Range

**Range**: The distance over which the Ability reaches its target. Either a configured named Range (whose distance is computed from Rank and Reach) or a fixed distance in feet.

**Range Formulas**: Configured mappings from named Ranges (Close, Medium, Long, etc.) to a distance computation. *(configurable)*

**Reach**: Distance in feet a Creature can touch without moving. Used by the Touch Range. *(default configurable)*

## Area

**Area**: Optional area-of-effect data on an Ability. Carries a shape, a size in 5-foot squares, and an Area Anchor. Combat owns which Creatures the area covers; this module only validates the shape and exposes the data. *(shape list configurable)*

**Area Anchor**: Where an Area is centered — at a point chosen at cast time, on the Ability's named target (and moving with that target), or on the caster (and moving with the caster).

## Attack

**Attack Roll**: A flag indicating the Ability resolves as an attack roll against its target. The Abilities module does not perform the roll.

**Melee vs. Ranged**: Implied by Range — Touch with an Attack Roll is melee, any greater Range with an Attack Roll is ranged.

## Channeling

**Channeled Ability**: An Ability whose effect is maintained turn-to-turn by the caster spending a Main Action on it. Identified by the presence of a Channel Block.

**Channel Block**: Optional data on a Catalog Ability that makes it a Channeled Ability and describes how channeling works for it. Names the Channel Mode and carries any mode-specific data (Reservoir Ratio, Activation, per-channel effect, etc.). Has its own Effect Hash, namespaced separately from the top-level. The Abilities module exposes the block; Combat tracks who is channeling what.

**Channel Mode**: How a Channeled Ability uses each turn's channel. One of: **fire** (the channeled dice fuel the spell's effect that turn), **reservoir** (the channeled dice accumulate as a Reservoir to be spent later), **maintain** (channeling is upkeep only, no dice-fueled effect), **auto** (the cast itself fills the Reservoir; no Main Action is required on subsequent turns to maintain).

**Reservoir**: The pool of dice held by a Reservoir-mode or auto-mode Channeled Ability. Each die in the Reservoir is available to spend on Activations. A failed Concentration Save loses the spell and its full Reservoir.

**Reservoir Ratio**: The multiplier applied when adding channeled dice to a Reservoir. Default 1 (one Reservoir die per channeled die). Spiritual Weapon uses ratio 2.

**Activation**: For a Reservoir-mode Channeled Ability, the rule for spending one Reservoir die to trigger the spell's effect. Names the action type (Bonus, Reaction, Free) and the effect produced. Each Activation always costs exactly one Reservoir die.

**Channeling**: The act of spending a Main Action on a Channeled Ability during one's turn. For fire and reservoir modes, the Combatant chooses how many dice to spend (4 up to Combat Pool Remaining — Dice Cap does not apply to channeling). For maintain mode, channeling always costs Main Action Minimum dice. Skipping a turn's channel — or spending fewer than Main Action Minimum dice — ends the spell.

**Concentration**: The broader category that includes Channeled spells and any spell with a long casting time. Concentration is interrupted by a failed Concentration Save (see Combat).

## Saves

**Saving Throw**: A Dice Resolution Check made by the target to resist or reduce an Ability's effect. Abbreviated **Save**.

**Save Spec**: One element of an Ability's save list. Names the Save Attribute, the Save Effect for each Save Outcome Key it cares about, and an optional Conditional Save flag.

**Save Attribute**: One of the six attributes, or "no save" when an Ability does not allow one. *(configurable)*

**Save Outcome Key**: A branch of a Save's result — Fail, Success, or Fumble. A Fumble triggers when the defender's Degree of Failure meets or exceeds the Default Fumble Threshold, and replaces the plain Fail effect when present. *(configurable)*

**Save Effect**: An Effect associated with a Save Outcome Key.

**Save Target**: Who rolls a Save. Default is the Ability's named target. Other values: observers of the effect, every creature in the Ability's area, or the caster.

**Multiple Saves**: An Ability may list more than one Save Spec; every Spec is offered to the target unless its Conditional Save restricts it.

**Conditional Save**: A Save Spec gated by the outcome of a prior Save. Recognized scopes: on a prior fail, or on a prior fumble.

## Properties

**Property**: A keyword flag that modifies how an Ability behaves. Mechanical definitions live in the implementing domain; the Abilities domain only validates the keyword names. *(keyword table configurable)*

## Schools and Skills

**Spell School**: The magical discipline a Spell belongs to. Only Spells have a School. *(configurable)*

**Casting Skill**: A skill that may cast an Ability. The caster picks one at activation time; that skill's ranks become Rank. *(configurable)*

**Universal Spell Casting Skill**: A Casting Skill usable for any Spell regardless of the Spell's listed skills. Appended implicitly to every Spell at lookup time. Does not apply to Talents. *(configurable)*

## Rituals

**Ritual**: An alternative casting mode available to every Spell. A Ritual lets a Creature cast a Spell once even without an Ability that grants them access to it. The Ritual incurs a gold cost and a longer cast time (both *configurable* per Spell tier in the Ritual block of `abilities_config.yaml`); the Spell itself then resolves using its normal activation time, mana cost, and any additional costs.

## Items and Packaging

**Item Form**: A physical form a Spell may be packaged in. *(configurable)*

**Universal Item Form**: An Item Form any Spell may be packaged into without listing it explicitly. Appended implicitly at lookup time. *(configurable)*

**Valid Item Forms**: A Spell's full set of eligible Item Forms, including universal forms added at lookup. Item-Only Spells do not gain universal forms.

**Item-Only Spell**: A Spell that cannot be cast directly — only invoked through a magic item that contains it. Still carries full activation data so the item can resolve it.

## Effects

**Effect**: A single effect produced by an Ability — either the absence of an effect, a named non-damage effect (passed through opaquely to Conditions), or a damage expression. Damage Effects must have a determinable Severity.

> The Conditions domain owns **Active Effect** — an instance of an Effect currently applied to a Creature — which is distinct from the Abilities **Effect** above.

**Effect Hash**: The named values an Ability uses for description substitution and Formula resolution. Names declared here become available to other Formulas in the same scope.

**Formula**: A string evaluated against a context dictionary that always includes Rank (and Tier, when assigned). Caller-supplied roll-result variables are valid only inside damage expressions.

**Description**: Display text for an Ability. May reference Effect Hash names and (for Aspect-axis Abilities) the current Aspect.

**Duration**: How long an Ability's effect persists. The Abilities module exposes the value verbatim; the caller applies it.

**Unconditional Effect**: An Effect that applies regardless of save or attack roll. Use for outcomes that always happen on a successful activation; use Save Effects for outcomes that depend on the defender's save.

**Damage Type**: The flavor of damage an Ability deals. Names an entry in the Damage Types catalog (owned by Combat).

**Damage Effect Severity**: The Severity of a damage Effect, determined either explicitly per-Effect or implicitly from the Ability's Damage Type. Explicit wins. Required for every damage Effect.

**Damage Effect Variables**: The roll-result quantities a damage Formula may reference — number of Successes, number of Critical Successes, and the casting attribute's value. Inside a Save Outcome these are the defender's results; inside an Unconditional Effect they are the caster's. The Abilities module returns Formulas in deferred form for caller evaluation.

**Threshold**: Optional data carried by an Ability whose Damage Type is physical. Required for physical damage, rejected on non-physical Abilities. For weapon-driven attacks the weapon's Threshold typically takes precedence — that decision lives in Combat.

## Triggers

**Trigger**: A rule that makes an Ability fire automatically during another action instead of by spending an action. Procedural class/race features (sneak attack, halfling luck, mark riders) carry a Trigger.

**Trigger Spec**: The structured description of a Trigger — the event it fires on, an optional scope condition, and the one-shot Trigger Effect that results.

**Trigger Event**: The action or occurrence that the Trigger fires during. Recognized today: attack checks, attack actions, hits, and on-kill. *(configurable)*

**Trigger Condition**: An optional scope tag on a Trigger Spec that the consuming domain evaluates. Free-form and opaque to the Abilities module.

**Trigger Effect**: The one-shot outcome of a Trigger. Has its own kind tag (bonus dice, scale, etc.); the Abilities module reports it verbatim and the consumer applies it.

## Magic Toxicity

(Magic Toxicity: see common glossary.)

**Magic Toxicity Effect Hash Keys**: Conventional Effect Hash names that Spells imposing toxicity expose for Conditions to read — the minimum imposed per cast and the default imposed per cast. The Abilities module performs no validation; Conditions reads and applies.

## Modifiers

**Modifier**: A named numeric adjustment to some target value on a Creature — attack, save, speed, damage reduction, a skill, etc. Carried by Always-On Modifier Abilities, Equipment, Conditions, and any other domain that grants passive bonuses or penalties.

**Bonus Type Name**: The category a Modifier belongs to. The Bonus Types List in the config is the canonical set; the category drives stacking rules in the consuming domain.

**Bonus Types List**: The canonical set of valid Bonus Type Names. The Abilities domain owns this list and validates that every Modifier names an entry in it. *(configurable)*

**Modifier Direction**: The sign-flavor a Modifier appears as — Bonus, Penalty, or Starting. The combined form `<Type> Bonus` / `<Type> Penalty` / `<Type> Starting` is what consumers reference. The Abilities module does not police which Types may appear in which Direction; the consuming domain does.

**Modifier Entry**: The structured form a Modifier appears in on an Ability — a target, a Bonus Type Name, optional scope descriptors, and a value (literal or Formula). The full schema is defined in `abilities_design.md`.

## Module Scope

The Abilities module is a **reference**. Given an Ability name it returns everything needed to resolve a use: activation data, Variant resolution, Effect classification, deferred damage Formulas, Trigger Specs, and Modifier read-through. It does not roll dice, apply effects, track state, consume resources, or evaluate Trigger conditions. Those responsibilities belong to Dice Resolution, Combat, Conditions, Modifiers, and Creatures respectively.
