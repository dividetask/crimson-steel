# Conditions and Buffs — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `conditions_config.yaml`. This module depends on the dice resolution module; when Bonus Type and Target Number Modifier terms appear below, their full definitions live in `dice_resolution_glossary.md`.

## Scope and Ignorance

The Conditions module tracks every piece of per-creature state that is not part of the creature's base definition: injuries, ongoing afflictions, short-lived buffs and debuffs, temporary hit points, magic toxicity, shock, and generic Counters (e.g. the Acid Counter). It is deliberately ignorant of the spells, abilities, weapons, or creatures that produce those effects. A buff is an opaque tuple of `target_key`, Bonus Type, sign, amount, and an end time; the module never asks what `target_key` means. Affliction rules and Counter behaviors are data-driven — the module contains generic machinery for resolving them and reads the specific behavior of bleed, poison, paralysis, or acid-counter from `conditions_config.yaml`. New effects, new afflictions, and new counters are added by editing config, not by editing this module.

The canonical list of Severity Categories used by hit-point damage and ability damage is owned by the damage_types domain (see `damage_types_glossary.md`); the conditions module reads the list at startup from `damage_types_config.yaml` rather than redeclaring it.

## Core Concepts

**Creature**: The subject that owns one Conditions instance. Every participant in a Check has its own Conditions state. The module never compares state across creatures.

**Round**: The in-game time unit used by this module. Rounds are signed integers incremented elsewhere (by the Combat module) as play advances. Real time is irrelevant; durations are always expressed in Rounds.

**Current Round**: A signed integer passed into Conditions by the caller when time-sensitive work is needed (expiry, tick). The module never reads the clock itself.

**Ends on Round**: A signed integer attached to a time-bounded Effect. The Effect remains Active while the Current Round is less than Ends on Round, and is removed the first time `CLEAR_EXPIRED_EFFECTS` is called with a Current Round greater than or equal to this value. An Effect with no Ends on Round is permanent until explicitly removed.

**Source ID**: An opaque identifier supplied by the caller when an Effect or Temporary Hit Point grant is applied. The module treats Source IDs as opaque strings — it only uses them to look up and remove a specific grant later. Typical callers use the spell/ability name, a combat log entry id, or the caster's combat id.

## Hit Points and Damage

**Minor Damage**: A counter of hit point damage dealt in the Minor severity category. Accumulates; never cascades into Moderate or Major.

**Moderate Damage**: A counter of hit point damage dealt in the Moderate severity category. Accumulates; never cascades into Minor or Major.

**Major Damage**: A counter of hit point damage dealt in the Major severity category. Accumulates; never cascades into Minor or Moderate.

**Severity Category**: One of `minor`, `moderate`, or `major`. Used for both hit point damage and ability damage. The canonical list lives in `damage_types_config.yaml` under `Severities`; the conditions module reads it at startup and does not hard-code the values.

**Temporary Hit Points**: A pool that absorbs incoming hit point damage before it hits the severity-category counters. Exactly one Temporary Hit Points grant is active at a time: applying a new grant replaces the existing one when the new amount is strictly higher than the current amount, and is rejected otherwise. The new grant's Source ID and Ends on Round replace the existing grant's. Damage absorption proceeds worst-first: Major first, then Moderate, then Minor.

**Current Hit Points**: The creature's usable hit points after damage and temporary hit points have been accounted for. The Conditions module exposes the three damage counters and the Temporary Hit Points pool; the character module computes `hp_max - minor - moderate - major + temporary_hit_points` and owns the concept of Current Hit Points.

**Heal Cascade**: A worst-first healing operation. A heal specifies three pools (`major`, `moderate`, `minor`). The Major pool heals Major Damage first; any remainder drains into the Moderate pool, which heals Moderate Damage; any remainder drains into the Minor pool, which heals Minor Damage. Excess beyond Minor Damage is wasted.

## Ability Damage

**Ability Damage**: Damage dealt to a creature's ability scores (`str`, `dex`, etc.). Stored per attribute per Severity Category; insertion order across attributes is preserved so the Ability Heal Cascade can pop damage FIFO.

**Ability Heal Cascade**: The Heal Cascade operation applied to Ability Damage. The heal pool cascades Major → Moderate → Minor as in Hit Point healing. Within a single Severity Category, damage is popped from attributes in the order they were first affected.

## Magic Toxicity

**Magic Toxicity**: A creature's accumulated burden from repeated magical healing or other concentrated magic. Represented as a single signed integer current value. Magic Toxicity never goes below zero. The module tracks the current value only; the creature's maximum (typically derived from an ability score) lives on the character module, and the caller enforces the cap when applying new Magic Toxicity.

## Shock

**Shock**: A counter representing battlefield disorientation. Each point of Shock removes one die from the creature's combat pool on the next pool refresh. If the combat pool is exhausted before the Shock counter reaches zero, the remaining Shock persists across rounds and continues to remove dice from subsequent refreshes until it is fully consumed. Shock has no save — it is applied by an effect as a raw amount and consumed only by being spent against dice.

Shock has unique consumption semantics (driven by combat-pool refreshes rather than turn-start hooks), so it lives as a distinct top-level field rather than as one entry in the generic Counter system below.

**Shock Consumption**: The operation in which the caller asks Conditions "how much Shock can I consume against up to N dice", receives the amount consumed, and decrements the internal Shock counter. Conditions does not know how large the combat pool is; the caller computes the available dice count and passes it in.

## Counters

**Counter**: A generic per-creature accumulator with a name, a non-negative integer current value, and a turn-start behavior defined by the `Counters` catalog in `conditions_config.yaml`. Counters are the home for stateful damage-type effects like the Acid Counter — each point of Acid Damage applied to a target adds to the target's `acid` Counter, and at the start of the target's turn the Counter scales itself and deals derived damage. Other domains (notably damage_types) describe *which* Counter to apply; the Counters catalog defines what happens at turn start; the conditions module owns the per-creature value.

**Counter Catalog Entry**: One entry in `Counters`, keyed by the Counter's name. Each entry has an `on_turn_start` list — a sequence of Counter Hooks executed when the resolving caller invokes `RESOLVE_COUNTER_TURN_START` at the start of the affected creature's turn. The catalog defines behavior; it does not define which creatures have which Counters.

**Counter Hook**: One step in a Counter's `on_turn_start` list. A dictionary with a `kind` field. The recognized kinds are:

- **`scale_self`** — multiplies the Counter's current value by `factor` with an explicit rounding rule (`floor` or `ceil`). The mutated value is the new Counter value. Acid uses `{kind: scale_self, factor: 0.5, rounding: floor}`.
- **`deal_damage`** — invokes `APPLY_HIT_POINT_DAMAGE` against the same creature with a Severity and an `amount_formula` evaluated against `{self: <current counter value>}`. The damage reads the counter *after* any preceding `scale_self` hook in the same list. Acid uses `{kind: deal_damage, amount_formula: "self", severity: minor}`.

The hook list is closed today — adding a new kind requires a code change. The Counters catalog is open: any new Counter that fits the existing hook vocabulary can be added by config.

**Active Counter**: A Counter whose current value is greater than zero. A Counter whose value reaches zero (whether from `scale_self` rounding down or from explicit clearing) is removed from the creature's state.

## Afflictions

**Affliction**: An ongoing condition with a severity counter and a data-driven resolution rule. Examples: bleeding, common venom, ghoul paralysis, sleeping sickness. Each Affliction is named by a configuration key in `conditions_config.yaml`.

**Severity**: A non-negative integer counter for a single Affliction. Higher Severity produces larger effects per resolution and a larger save Target Number Penalty. Severity accumulates when an Affliction is re-inflicted, decreases on saves with successes, and increases on saves with failures (subject to per-Affliction tuning).

**Active Affliction**: An Affliction whose Severity is greater than zero. Creatures may carry multiple Active Afflictions simultaneously.

**Affliction Order**: Active Afflictions are held in insertion order — the order in which they were first inflicted (or re-inflicted after being removed). When Severity decays to zero an Affliction is deleted from the list, so re-inflicting it later re-inserts it at the end.

**Affliction Category**: A free-form string label describing how the Affliction is presented and grouped — typical values are `poison`, `disease`, or `other`. The Conditions module does not validate the Category and does not branch on it; presentation layers (combat tracker, log) consume it. Defined per-Affliction in `conditions_config.yaml`. *(per-Affliction)*

**Inflicter Tier**: The highest Tier among all sources that have inflicted this Affliction since it last reached zero Severity. Stored as a first-class field on every Active Affliction — not as opaque metadata. `INFLICT_AFFLICTION` accepts the inflicter's Tier as a parameter and stores `max(existing, new)`. Callers that compute a save Target Number Penalty based on Inflicter Tier read it back via `GET_AFFLICTION` and fold the resulting modifier into the dict they pass to `RESOLVE_AFFLICTION`.

**Save Frequency**: A free-form string describing how often this Affliction is meant to be resolved — typical values are `round`, `minute`, `hour`, `day`, `month`, `year`. The Conditions module stores the value but does not act on it; the Combat / downtime modules read it to decide when to invoke `RESOLVE_AFFLICTION`. *(per-Affliction)*

**Affliction Rule**: The data-driven specification of what an Affliction does, defined in `conditions_config.yaml`. A Rule specifies: (1) the optional save attribute (defaults to `con`); (2) the Affliction Category and Save Frequency; (3) the Severity Per Success, Severity Per Failure, and Severity Decay (each defaulting to a global value, optionally overridden); (4) the Affliction Effect Kind produced on resolution.

**Severity Divisor**: The divisor in the standard Affliction magnitude formula `magnitude = 1 + floor(severity / divisor)`. The same Divisor applies to every Affliction — Affliction Rules may not override it. *(configurable globally only)*

**Severity Per Success**: The amount by which Severity decreases for each net success on the save Roll. Defaults to 1 across all Afflictions; specific Afflictions may override with either a plain integer or the literal `"tier"` (substituted with the creature's Tier at resolve time, with Tier 0 treated as 0.5). Bleeding overrides this to `"tier"`; sleeping sickness overrides it to 0. *(configurable globally; per-Affliction overrides allowed)*

**Severity Per Failure**: The amount by which Severity increases for each net failure on the save Roll. Defaults to 1 across all Afflictions; specific Afflictions may override with either a plain integer or the literal `"tier"`. Bleeding overrides this to 0 (no failure scaling). *(configurable globally; per-Affliction overrides allowed)*

**Severity Decay**: The amount by which Severity decreases each time the Affliction is resolved, independent of save successes. Defaults to `"tier"` (creature's Tier, with Tier 0 treated as 0.5); specific Afflictions may override. The decay is applied in addition to the per-success reduction described under Severity Per Success. *(configurable globally; per-Affliction overrides allowed)*

**Tier Substitution**: When a Severity Per Success / Severity Per Failure / Severity Decay value is the literal string `"tier"`, it is substituted with the creature's Tier at resolve time. Tier 0 is treated as 0.5 in the substitution per the project-wide convention; the final integer applied to Severity is floored. Plain-integer values are used as-is. Tier values otherwise are always integers — formulas never produce a fractional result outside the Tier 0 case.

**Severity Save Penalty**: A Competency Penalty equal to `floor(severity / severity_divisor)` that the Conditions module automatically adds to the save's modifier dict before invoking the dice resolution module. The Penalty represents the affliction's hold on the creature growing harder to shake as Severity rises. Inflicter Tier and creature Tier are not added by the Conditions module — those modifiers are the caller's responsibility.

**Affliction Resolution**: The operation that ticks one Active Affliction. Every Affliction has a save. The Conditions module rolls the save via the dice resolution module after merging in the Severity Save Penalty, applies the Affliction's effect at magnitude reduced by raw successes (floored at zero), then evolves Severity by `−decay − (successes × severity_per_success) + (failures × severity_per_failure)`, clamped at zero. If Severity reaches zero the Affliction is removed. `successes` and `failures` are derived from the save's Degree of Individual Success: `successes = max(0, dois)`, `failures = max(0, −dois)`.

**Affliction Effect Kind**: The shape of what Affliction Resolution produces. One of:

- `hit_point_damage`: deals damage to a specified Severity Category. The Affliction Rule names the category; the underlying damage mechanic lives in the Conditions module, not in the Affliction Rule.
- `ability_damage`: deals damage to a specified attribute at a specified Severity Category. As above, the Affliction Rule names what to damage; the mechanic is generic.
- `named_effect`: applies a Named Effect (see below) by name. The Affliction Rule supplies only the effect's name and duration. What the named Effect does — its modifiers, Bonus Type, sign, amount — is defined once in the Named Effects catalog and reused by every source that applies it.

The list is closed — new effect kinds require a code change. The set of Afflictions that use these kinds is open, as is the set of Named Effects.

**Named Effect**: A reusable buff, debuff, or status defined once in `conditions_config.yaml` under `Named Effects`. Each entry specifies a description and a list of modifiers (each with `target_key`, Bonus Type, sign, and amount). Afflictions, spells, and abilities reference Named Effects by name and supply a duration — they never redefine what the Effect does. Examples: `paralyzed`, `prone`, `eagles_splendor`. The Conditions module exposes `APPLY_NAMED_EFFECT` to apply one by name; the Affliction `named_effect` kind dispatches through the same path.

## Effects (Buffs and Debuffs)

**Effect**: A typed modifier applied to the creature, tracked as a tuple of `target_key`, Bonus Type, sign, amount, optional Ends on Round, Source ID, and optional metadata. Effects are the generic representation of buffs like Eagle's Splendor as well as debuffs like Paralyzed or Shaken. The module never inspects what an Effect does — it only stores Effects and reports them when queried.

**Target Key**: An opaque string naming what the Effect adjusts. Typical values are attribute names (`str`, `dex`), derived keys (`save`, `initiative`, `speed`, `damage_reduction`), or named skill keys (`perform_percussion`). The Conditions module does not validate Target Keys against any list; validation (if any) is the caller's responsibility.

**Bonus Type**: The Target Number Modifier type governing how the Effect stacks. Drawn from the `Bonus Types List` in `dice_resolution_config.yaml` (Competency, Circumstance, Morale, Guidance, Inherent, Ascendancy). Effect stacking follows the dice resolution rule: within a single `target_key` and Bonus Type, only the highest Bonus and the highest Penalty apply, and their net effect is their arithmetic sum.

**Sign**: One of `bonus` or `penalty`. A `bonus` Effect improves the creature's result on Rolls for which the Target Key is relevant; a `penalty` worsens it. The sign is explicit rather than implied by amount so the stacking rule ("highest Bonus and highest Penalty each apply") can be enforced without inferring intent from a signed amount.

**Amount**: A non-negative integer magnitude. The sign is carried separately. An Effect with amount zero is legal but has no mechanical effect.

**Active Effect**: An Effect that is either permanent (no Ends on Round) or whose Ends on Round is strictly greater than the Current Round. Only Active Effects contribute to modifier lookups.

**Modifier Lookup**: The query `GET_MODIFIERS(target_key)` that returns the net Bonus and net Penalty for each Bonus Type, after stacking, limited to Active Effects whose Target Key matches.

## Interactions with Dice Resolution

The Conditions module depends on the dice resolution module for two things:

- **Modifier stacking**: the rule "highest Bonus and highest Penalty per Bonus Type apply" for Effect aggregation follows the same definition as dice resolution. The Bonus Types List is shared; it lives in `dice_resolution_config.yaml` and is imported, not redeclared.
- **Save Rolls for Afflictions**: when an Affliction Rule specifies a save, Conditions uses `DiceSystem.COMPUTE_ROLL_PARAMETERS`, `RAND_ROLL_DICE`, and `COMPUTE_RESULTS` to determine successes. The caller supplies a `modifiers` dict and `dice_count` that describe the creature's resistance to that save — Conditions does not know how saves are computed for a creature.

## Serialization

**Conditions State**: The complete persistent state of one creature's Conditions instance. A dictionary of damage counters, Magic Toxicity, Shock, Temporary Hit Points grant, Affliction list, and Effect list, with enough fidelity to recreate an equivalent instance via `LOAD_STATE`. The module does not own the storage format; callers serialize the dictionary to JSON, YAML, or whatever the host uses.
