# Conditions and Buffs — Glossary

Tracks per-creature mutable state: injuries, ability damage, current mana, ongoing afflictions, buffs/debuffs, temporary hit points, magic toxicity, Shock, the Acid Counter. Deliberately ignorant of the spells, abilities, weapons, or creatures producing those effects. Depends on dice resolution for Bonus Type / Target Number Modifier definitions and for save rolls. *(configurable)* values come from `conditions_config.yaml`.

## Core Concepts

**Creature**: The subject that owns one Conditions instance. Every participant in a Check has its own Conditions state; the module never compares state across creatures.

(Round: see common glossary.)

**Current Round**: A signed integer passed in by the caller when time-sensitive work is needed. The module never reads the clock itself.

**Ends on Round**: A signed integer attached to a time-bounded Active Effect. The Effect remains while Current Round < Ends on Round; removed when `CLEAR_EXPIRED_EFFECTS` is called with Current Round ≥ this value. No Ends on Round means permanent until explicitly removed.

**Source ID**: An opaque identifier supplied by the caller when an Active Effect or Temporary Hit Point grant is applied. Used only for later lookup and removal.

**Source ID Namespace**: A convention where a caller uses a colon-prefixed Source ID (e.g. `equipment:char_42:belt_str:body`, `affliction:bleeding`) so it can later operate on **all** of its grants via `REMOVE_EFFECTS_BY_PREFIX`. Conditions does not interpret namespaces — it only matches the prefix string.

## Hit Points and Damage

**Minor / Moderate / Major Damage**: Counters of HP damage in each Severity Category. Each accumulates independently; never cascades between categories.

(Severity: see common glossary, where it appears as `minor` / `moderate` / `major`. The conditions module reads the canonical list at startup from `damage_types_config.yaml`.)

**Temporary Hit Points**: A pool that absorbs incoming HP damage before the severity counters. Exactly one grant is active at a time: a new grant replaces the existing one only when its amount is strictly higher; the new grant's Source ID and Ends on Round replace the old. Damage absorption proceeds worst-first (Major → Moderate → Minor).

**Current Hit Points**: Computed by the character module as `hp_max - minor - moderate - major + temporary_hit_points`. Conditions exposes the inputs; Character owns the concept.

**Heal Cascade**: A worst-first healing operation. A heal specifies three pools (`major`, `moderate`, `minor`); each pool heals its damage type, with any remainder draining into the next worse-first pool. Excess beyond Minor is wasted.

## Mana

**Current Mana**: Non-negative integer counter. Stored directly (rather than as a "spent" counter) because Mana Max is variable. Cap enforcement and Mana Max derivation live on the character module — operations that risk exceeding the cap accept a `max:` parameter.

**Mana Cost**: A non-negative integer spend via `APPLY_MANA_COST(amount)`. Floors at zero; returns the actual amount spent.

**Mana Restore**: A non-negative integer gain via `RESTORE_MANA(amount, max:)`. Clamped at the supplied `max:`.

## Natural Recovery

**Natural Recovery**: The accumulated effect of time passing — HP damage healing, ability damage healing, mana refilling, magic toxicity decaying, temporary HP clearing. Applied via `APPLY_NATURAL_RECOVERY(days:, mode:, ...)`. Rates come from the `Natural Recovery` block in `conditions_config.yaml`.

**Recovery Mode**: One of `short_rest` or `long_term_recovery`. Selects the *low* or *high* column from each Heal Rate row.

**Heal Rate**: A tier-indexed table defining how HP Damage heals per period at each Severity. Each entry is `[low, high, unit]` — *low* points/period in `short_rest`, *high* in `long_term_recovery`, *unit* the period length in days. Structured as `tier * 3 + severity_index` rows, severity_index following the canonical Severities order. Higher tiers heal faster; Minor heals fastest at every tier; Major heals slowest. *(3 sentences — flagged: layout, indexing, and ordering rules are each load-bearing for config authors)*

**Ability Heal Rate**: A second tier-indexed table with the same `[low, high, unit]` shape governing Ability Damage recovery. Each heal point pops one queued Ability Damage point at that severity in FIFO order across attributes.

**Mana Per Day Divisor**: Integer dividing `mana_max` to produce daily mana regen. `mana_per_day = floor(mana_max / divisor)`. Default 4. *(configurable)*

**Magic Toxicity Per Day Divisor**: Integer dividing the configured toxicity attribute (typically `cha`) to produce daily decay. Default 4. *(configurable)*

## Ability Damage

**Ability Damage**: Damage dealt to ability scores. Stored per attribute per Severity Category; insertion order across attributes is preserved so the Ability Heal Cascade can pop FIFO.

**Ability Heal Cascade**: Heal Cascade applied to Ability Damage. Heal pool cascades Major → Moderate → Minor; within a Severity, damage pops from attributes in the order first affected.

## Magic Toxicity

(Magic Toxicity: see common glossary.)

## Shock

**Shock**: A counter of battlefield disorientation. Each point removes one die from the creature's combat pool on the next pool refresh. If the pool is exhausted before Shock reaches zero, remaining Shock persists across rounds. Shock has no save.

**Shock Consumption**: The operation where the caller asks Conditions "how much Shock can I consume against up to N dice", receives the amount, and decrements the counter. Conditions does not know combat pool size — the caller passes it in.

## Acid Counter

**Acid Counter**: A non-negative integer counter representing residual corrosive damage. Combat calls `APPLY_ACID_DAMAGE(amount)` to add to the counter (creating it if absent). At the start of the affected creature's turn, `RESOLVE_ACID_TURN_START` halves the counter (floored) and deals the post-halving value as **minor** HP damage to the same creature; a counter at zero is removed. *(2 sentences — but covers the full apply/resolve cycle)*

Like Shock, the Acid Counter is a built-in top-level field with hardcoded behavior. New damage-type counters with similarly distinctive behavior will be added the same way.

## Afflictions

**Affliction**: An ongoing condition with a severity counter and a data-driven resolution rule (bleeding, common venom, ghoul paralysis, sleeping sickness). Each Affliction is named by a key in `conditions_config.yaml`.

**Severity**: A non-negative integer counter for a single Affliction. Higher Severity produces larger effects per resolution and a larger save Target Number Penalty. Accumulates when re-inflicted; decreases on save successes; increases on save failures.

**Active Affliction**: An Affliction with Severity > 0. Creatures may carry multiple simultaneously.

**Affliction Order**: Active Afflictions are held in insertion order. When Severity decays to zero the Affliction is deleted; re-inflicting later re-inserts at the end.

**Affliction Category**: A free-form string label for presentation/grouping (`poison`, `disease`, `other`). Conditions stores but does not branch on it. *(per-Affliction)*

**Inflicter Tier**: The highest Tier among all sources that inflicted this Affliction since it last reached zero Severity. First-class field on every Active Affliction. `INFLICT_AFFLICTION` accepts the inflicter's Tier and stores `max(existing, new)`. Callers that compute a save TN penalty based on Inflicter Tier read it back via `GET_AFFLICTION` and fold the modifier into the dict passed to `RESOLVE_AFFLICTION`. *(4 sentences — flagged: storage shape, accumulation rule, and caller responsibility are all load-bearing)*

**Save Frequency**: Free-form string describing how often the Affliction is meant to resolve (`round`, `minute`, `hour`, `day`, `month`, `year`). Stored but not acted on by Conditions. *(per-Affliction)*

**Affliction Rule**: The data-driven spec of what an Affliction does in `conditions_config.yaml`. Specifies: optional save attribute (defaults `con`), Affliction Category, Save Frequency, Severity Per Success / Failure / Decay, and Affliction Effect Kind.

**Severity Divisor**: The divisor in `magnitude = 1 + floor(severity / divisor)`. Same Divisor for every Affliction — no per-Affliction override. *(globally configurable only)*

**Severity Per Success**: Amount Severity decreases per net save-roll success. Default 1; per-Affliction overrides allowed (integer or literal `"tier"`). Bleeding overrides to `"tier"`; sleeping sickness to 0. *(configurable globally + per-Affliction)*

**Severity Per Failure**: Amount Severity increases per net save-roll failure. Default 1; per-Affliction overrides allowed. Bleeding overrides to 0. *(configurable globally + per-Affliction)*

**Severity Decay**: Amount Severity decreases each resolution, independent of save successes. Default `"tier"`; per-Affliction overrides allowed. Applied in addition to the per-success reduction. *(configurable globally + per-Affliction)*

**Tier Substitution**: When a Severity Per Success / Failure / Decay value is the literal `"tier"`, it is substituted with the creature's Tier at resolve time (Tier 0 → 0.5). Final result is floored.

**Severity Save Penalty**: A Competency Penalty of `floor(severity / severity_divisor)` automatically added to the save's modifier dict. Inflicter Tier and creature Tier are **not** added by Conditions — the caller's responsibility.

**Affliction Resolution**: The operation that ticks one Active Affliction. Rolls the save (after merging in Severity Save Penalty), applies the effect at magnitude reduced by raw successes (floored at zero), then evolves Severity by `−decay − (successes × severity_per_success) + (failures × severity_per_failure)`, clamped at zero. Severity reaching zero removes the Affliction. `successes = max(0, dois)`, `failures = max(0, −dois)` from the save's Degree of Individual Success. *(4 sentences — flagged: each step is part of the resolution algorithm)*

**Affliction Effect Kind**: The shape of what Affliction Resolution produces. Closed list — new kinds require code change:

- `hit_point_damage` — deals damage to a specified Severity Category.
- `ability_damage` — deals damage to a specified attribute at a specified Severity Category.
- `named_effect` — applies an Effect Name by name and duration.

**Effect Name**: A reusable named non-damage effect defined under `Effect Names` in `conditions_config.yaml`. **Single source of truth** for the catalog across the project — abilities reference Effect Names by name without validating; conditions raises at apply time when a name does not match. Each entry specifies a `description` and a list of structured Mechanics. Examples: `blind`, `dazzled`, `paralyzed`, `prone`, `bleeding`. `APPLY_NAMED_EFFECT` is the entry point; the Affliction `named_effect` kind dispatches through it.

**Effect Mechanic**: One element of an Effect Name's `mechanics` list. A dict with a `kind` field plus kind-specific fields. Recognized kinds:

- **`modifier`** — a TN modifier. Fields: `modifier_type` (key from `Bonus Types List`), `sign` (`bonus`/`penalty`), `magnitude`, `applies_to` (list of free-form scope tags), optional `notes`.
- **`reroll`** — triggers a Reroll Operation. Field: `scope`; optional `applies_to`, `sign`, `magnitude`, `notes`.
- **`nudge`** — triggers a Value Adjustment. Fields: `applies_to`, `sign`, `magnitude`; optional `notes`.
- **`set_value`** — overrides a derived value. Fields: `target`, `value` (integer or formula).
- **`scale_value`** — multiplies a derived value. Fields: `target`, `factor`.
- **`flag`** — sets a boolean state. Field: `flag`.
- **`display`** — a free-form rule the program does not encode. Field: `text` — surfaced for the DM.

The conditions module dispatches each Mechanic to the appropriate consumer (dice resolution for modifier/reroll/nudge; itself for set_value/scale_value/flag; presentation for display). Scope tags, target names, and flag names are intentionally free-form.

## Active Effects (Buffs and Debuffs)

**Active Effect**: A typed modifier applied to the creature, tracked as a tuple of `target_key`, Bonus Type, sign, amount, optional Ends on Round, Source ID, and optional metadata. Generic representation of buffs (Eagle's Splendor) and debuffs (Paralyzed, Shaken). Only Active Effects whose Ends on Round is permanent or strictly greater than Current Round contribute to modifier lookups. The module never inspects what an Effect does. *(4 sentences — flagged: replaces the previous `Effect` term; merges activity-window semantics with the tuple shape)*

**Target Key**: An opaque string naming what the Active Effect adjusts (attribute names, derived keys like `save`/`initiative`/`speed`/`damage_reduction`, named skill keys). Conditions does not validate against any list.

**Bonus Type**: The TN Modifier type governing stacking. Drawn from `Bonus Types List` in `dice_resolution_config.yaml`. Stacking follows the dice resolution rule: within a single `target_key` and Bonus Type, only the highest Bonus and the highest Penalty apply, net is their arithmetic sum.

**Sign**: One of `bonus` or `penalty`. Explicit (rather than implied by amount) so the stacking rule can be enforced without inferring intent from a signed amount.

**Amount**: A non-negative integer magnitude. Sign is carried separately. Zero is legal but has no mechanical effect.

**Modifier Lookup**: The query `GET_MODIFIERS(target_key)` returning net Bonus and net Penalty per Bonus Type, after stacking, limited to Active Effects whose Target Key matches.

## Interactions with Dice Resolution

Conditions depends on dice resolution for two things:

- **Modifier stacking**: Active Effect aggregation follows dice resolution's "highest Bonus and highest Penalty per Bonus Type apply" rule. Bonus Types List is shared, not redeclared.
- **Save Rolls for Afflictions**: Conditions uses `DiceSystem.COMPUTE_ROLL_PARAMETERS`, `RAND_ROLL_DICE`, and `COMPUTE_RESULTS`. Caller supplies `modifiers` and `dice_count`.

## Serialization

**Conditions State**: The full persistent state of one creature's Conditions — damage counters, Magic Toxicity, Shock, Temporary HP grant, Affliction list, Active Effect list. Sufficient fidelity to recreate via `LOAD_STATE`. The module does not own the storage format.
