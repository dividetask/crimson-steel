# Architecture — Workflows and Open Questions (Part 2)

Part 1 (`architecture-part-1.md`) covered the static structure: who
exists, what each module owns, and how they depend on each other.
This part covers what's *dynamic*: how a typical operation flows
through the modules, what's still unowned, and the architectural
questions still open.

## Cross-domain workflows

The walkthroughs below describe the logic of each operation
end-to-end, in the same language-agnostic style the rest of the
docs use. Some halves are implemented in Ruby today, some in
JavaScript, and some are not yet implemented; the workflow itself
is the spec, regardless of where the code lands.

### Workflow A — Attack

The full attack pipeline runs in two halves. The first half decides
*what damage lands*; the second half routes it through modules.

1. **Build the attacker's Roll.** Combat asks the attacker's
   Character for the attribute / skill modifiers, asks Conditions
   (via `GET_MODIFIERS`) for active buffs and debuffs on the
   relevant `target_key`, and assembles a modifier dict for
   dice resolution. The action's dice count comes from
   `Combat#action_dice_max` minus the attacker's spend.
2. **Build the defender's Opposed Roll** the same way, against the
   defender's defense action.
3. **Roll both Rolls** through `DiceSystem.RAND_ROLL_DICE` /
   `COMPUTE_ROLL_PARAMETERS` / `COMPUTE_RESULTS`. The damage type's
   `critical_value` mechanic, if any, supplies `critical_modifier`
   to the attacker's Roll — `Combat#critical_modifier_for(damage_type)`
   answers that lookup.
4. **Compute the Degree of Success** for the Check (attacker DoIS
   minus defender DoIS). A DoS ≥ Default Success Threshold means the
   attack lands.
5. **Compute raw damage.** Either:
   - the spell's declared damage Effect is evaluated through
     `AbilitySystem#evaluate_damage` with the attacker's success and
     critical counts, or
   - if the attack carries no declared damage Effect (weapon attacks,
     elemental darts), Combat infers `Tier + Degree of Success +
     attack bonus`.
6. **Route damage** via `Combat#apply_attack_damage`:
   - Look up the damage type in DamageTypes.
   - Apply pre-bucketing mechanics: `damage_per_dice` and
     `damage_multiplier` (the latter consults the
     `condition_evaluator` callback for tags like
     `target_has_metal_armor`).
   - Severity decision: declared severity for non-physical;
     runtime bucketing for physical, where the bucket size is
     `Threshold + target's Damage Resilience`. Threshold comes from
     the weapon (Equipment) or ability (Abilities) input; Damage
     Resilience is read through the `character_lookup` callback.
   - Call `Conditions#apply_hit_point_damage` on the target.
   - Apply post-damage side-effects: `apply_acid_counter` →
     `Conditions#apply_acid_damage`, `inflict` with
     `condition_name=shock` → `Conditions#apply_shock`. Other
     `condition_name` values come back tagged `unrouted` until the
     conditions module exposes the right API.

What's missing today: a single end-to-end entry point that wires
both halves into one call. Steps 1–5 are done by the caller; step 6
is `apply_attack_damage`. A future `Combat#perform_attack(attacker,
target, weapon)` would compose them.

### Workflow B — Item consumption

Already implemented in `lib/item_use.rb`.

1. Caller invokes `ItemUse#consume(owner_id, stack_index, item_form,
   spell_name, target_char_id, ...)`.
2. ItemUse reads the stack from Equipment, picks the spell's
   tier_index from the item's tier, and calls
   `AbilitySystem#resolve_entry`.
3. ItemUse inspects the resolved Effect Hash for the conventional
   keys: `minor_damage` / `moderate_damage` / `major_damage`
   (cure pools), `mana` (mana restore), `temp_hp` (ward).
4. **Saturation gate**: if the target's `Conditions#magic_toxicity`
   is at or above the supplied `target_max_toxicity`, cure and mana
   refuse to land. Ward bypasses the gate.
5. Cure pools route through `Conditions#apply_hit_point_heal_cascade`.
   Ward routes through `Conditions#set_temporary_hit_points` with a
   source id of `item:<owner>:<spell>`. Mana surfaces back as
   `unrouted: true` because mana storage isn't yet defined.
6. Compute Magic Toxicity:
   - **Potion / Oil**: `max(saturation - target_tier,
     minimum_saturation) + floor(2 * tier_value(item_tier) *
     2^max(item_tier - user_tier, 0))`.
   - **Scroll**: `max(saturation - target_tier - improved_healing
     reduction, minimum_saturation)`. The user's `improved_healing`
     ability shaves `2 * user_tier` off cure scrolls.
   - **Wand**: 0 (deferred).
7. `Conditions#apply_magic_toxicity` on the target.
8. **Decrement** the item's quantity by one for consumable forms via
   `Equipment#adjust_stack_quantity` and `cleanup_zero_quantity`.
   Wands and persistent magic items keep their quantity.

If the saturation gate fired, ItemUse returns `saturation_blocked:
true` with no applications and no quantity decrement, leaving the
caller to surface the failure cleanly.

### Workflow C — Equipping an item

Logic exists in the design docs; no orchestration class today.
Callers do the steps directly.

1. **Equip**: caller marks the stack as equipped. Stack identity
   includes `equipped`, so a freshly-equipped item is
   *not* the same Stack as an unequipped copy of the same type —
   they don't merge.
2. **Post effects**: for each effect the item should grant
   (Belt of Strength: `+2 str` Inherent bonus), the caller picks a
   deterministic `source_id` in the `equipment:<owner>:<stack_key>`
   namespace and calls `Conditions#apply_effect`. Apply-by-source-id
   is idempotent — re-applying the same id overwrites the slot.
3. **Unequip**: caller calls
   `Conditions#remove_effects_by_prefix("equipment:<owner>:<stack_key>")`
   to strip every effect the stack contributed.
4. **Loadout reset**: caller calls
   `Conditions#remove_effects_by_prefix("equipment:<owner>:")`
   to nuke the entire equipment-driven effect list, then re-applies
   the current loadout fresh. This restores correctness coarsely
   without the caller tracking which stack maps to which Effect.

The "verify-or-recreate" guarantee is implicit. Equipment never asks
Conditions whether an effect is present; it just re-applies on every
relevant change.

### Workflow D — Spell cast (direct, not via item)

Implemented in `lib/casting.rb` as a parallel-shaped orchestration to `ItemUse`.

1. Caller invokes `Casting#cast(spell_name:, caster_char_id:, target_char_id:, rank:, mana_cost:, ...)`.
2. **Mana check.** If the caster's `current_mana` is below `mana_cost`, return `error: 'insufficient_mana'` immediately — no effects, no mana spent.
3. Resolve the spell entry through `AbilitySystem#resolve_entry` at the caller-supplied rank (and tier_index / aspect_index for Variant axes).
4. **Saturation gate** (caster-side, mirroring ItemUse's target-side gate). When the caller supplies `caster_max_toxicity:` and the caster's `magic_toxicity` is at or above that cap, cure and mana effects refuse to land — return `saturation_blocked: true` with no mana spent and no applications. Ward effects bypass the gate.
5. **Spend mana** from the caster via `Conditions#apply_mana_cost`.
6. **Apply effects to the target** by reading the resolved Effect Hash for conventional keys: `minor_damage`/`moderate_damage`/`major_damage` → cure cascade, `mana` → mana restore (capped at caller-supplied `target_max_mana:`), `temp_hp` → ward grant with source id `spell:<caster>:<spell>`.
7. **Magic toxicity on the caster** (not the target — that's the item flow). Formula: `max(saturation, minimum_saturation)` from the resolved Effect Hash. No "potion overhead" term.
8. **Return deferred work** — the spell's `effects` list (damage objects with deferred `success`/`critical` evaluation) and `saves` list come back intact for caller-driven save resolution and damage routing through `Combat#apply_attack_damage`. The Concentration Block is returned for the caller to track concentration on the caster.

Mana cost defaults from the abilities catalog's `Default Mana Cost Per Tier` table (`{0: 1, 1: 4, 2: 6, 3: 8, 4: 10, 5: 12}` by default). The caller can still override via `mana_cost:`. Spells whose description notes an extra cost (Recharge, etc.) are the human DM's responsibility to add on top — the schema doesn't yet carry per-spell overrides as a structured field.

### Workflow D' — Ritual cast

`Casting#cast_ritual` is a thin extension of `cast` for rituals. Same pipeline; two adjustments:

- **Material gold cost.** `AbilitySystem#ritual_gold_cost(spell, tier)` reads `Ritual Cost.gold_per_tier`. The cost is debited from the supplied `gold_owner_id` via `Equipment#debit_wealth`. When the owner can't pay, returns `error: 'insufficient_gold'` with no mana spent and no effects.
- **Total casting time.** `AbilitySystem#ritual_casting_time_rounds(spell, tier)` returns `max(spell.casting_time_rounds, 1) + Ritual Cost.casting_time_per_tier[tier]`. The result is included in the `cast_ritual` return for the caller to advance the calendar accordingly.

If `cast()` bails on insufficient mana or the saturation gate, `cast_ritual` returns the same bail-out unchanged — gold is **not** debited because the ritual didn't happen. The Equipment dependency is supplied at construction; ritual casts raise without it.

### Workflow E — Affliction tick

Already implemented.

1. Caller invokes `Conditions#resolve_affliction(name, save_input,
   creature_tier, current_round)`.
2. Conditions injects a Severity Save Penalty equal to
   `floor(severity / divisor)` into the supplied `Competency Penalty`.
3. Calls `DiceSystem` to roll the save.
4. Computes magnitude (`1 + floor(severity / divisor)`) and
   net_magnitude (`max(0, magnitude - successes)`).
5. Applies the Affliction's effect (`hit_point_damage`,
   `ability_damage`, or `named_effect`) at net_magnitude.
6. Evolves severity: `delta = -floor(decay) -
   floor(successes * per_success) + floor(failures * per_failure)`.
7. Removes the Affliction if severity reached zero.

## Aggregated unassigned responsibilities

The per-domain Unassigned bullets, grouped by theme.

### Cluster 1 — Catalog content (HIGH PRIORITY)

The schemas and homes are defined; the actual catalog content
isn't yet populated.

- **Procedural Abilities catalog**: most class/racial stateless
  abilities (`sneak_attack`, `channel_divinity`, `improved_healing`,
  `sense_injury`, `trapfinding`'s concentration variant, etc.) have
  no entries yet. Schema: `name → triggers: [{on, condition,
  effect}]`.
- **Effect Names catalog**: stateful class/racial abilities (`rage`,
  `bardic_inspiration`, etc.) need entries with structured
  Mechanics. The catalog has the basic conditions (`blind`,
  `dazzled`, `paralyzed`, `prone`, `flustered`) but not the class-
  ability content.
- **Always-On Modifier entries** on each ability's `modifiers:`
  field in `advancement_config.yaml` and `race_config.yaml`.
  TentativeAdditions has the schema and a few examples; most
  entries are still empty.

### Cluster 2 — Cross-domain wiring

Modules exist; the bridges between them aren't pinned to a class.

- **Acid Counter wiring**: `Conditions#apply_acid_damage` exists,
  but it's `Combat#apply_attack_damage` that decides when to call
  it (via the `apply_acid_counter` mechanic). Today's wiring lives
  inline inside `apply_attack_damage`; that's fine but worth
  re-examining if more counter types arrive.
- **End-to-end attack-resolution composition**: the to-hit roll +
  damage routing pieces both exist; a single
  `Combat#perform_attack(attacker, target, weapon)` doesn't.
- **Casting orchestration** (Workflow D above) — no class today.

### Cluster 3 — Missing infrastructure

Whole concepts that aren't represented anywhere.

- **Mana tracking**. Character exposes `max_mana` (formula); nothing
  tracks current mana. ItemUse surfaces mana applications as
  `unrouted: true`. Decision needed (see open questions).
- **Per-day usage trackers** (Channel Divinity uses-per-day). No
  home decided.
- **Encumbrance**. Currency carries a `weight` field; armor and
  weapons don't. No system computes total weight.
- ~~**Skill-Roll API**~~ — resolved by the new Skills class +
  `DiceSystem#compute_check_details`.
- **Equipment deferred items**: loot tables (4 row shapes + Roll
  Variables), magical-item generation, specific/generic shop
  refresh, Game Day counter, atomic Restock, Loot Archive. All
  documented in `equipment_design.md`; none implemented.

### Cluster 4 — Validation gaps (the silent-typo cluster)

A single startup-time linter could knock out the whole list.

- Roster `race:` / class keys → real race / class.
- `parent_class`, `parent_race` → real chain target.
- Skill list entries (`class_skills`, `non_class_skills`,
  `opposed_skills`) → real skills.
- `tier_attribute_advancement` picks → real attribute keys.
- `attribute:` in `skills_config.yaml` → one of six real attributes.
- `damage_type` references in compendium → catalog entry (already
  validated when AbilitySystem is constructed with DamageTypes).
- Loot table `item:` / property references → real catalog entries.
- Material names on Armor → defined Materials.
- Damage Types `condition` / `condition_name` strings → consumer-
  recognized concepts.
- Effect strings declared by abilities → real Effect Names (raised
  today only at apply-time).
- Procedural Abilities catalog references → real class/racial
  ability names (when the catalog has content).

### Cluster 5 — Untracked / unowned state

- **Per-Character narrative state** (DM notes, custom flags). Conditions
  owns mechanical state, nothing owns narrative.
- **Persistence of identity mutations** (renames, race changes).
  Characters are read-only at startup.
- **Bonus skills enforcement**. `bonus_skills` is a Class field
  documented but unenforced.
- **`minimum_skills_trained` enforcement**. Documented but
  unenforced.
- **Class contributions to `damage_resilience` / `damage_reduction`**.
  Methods return 0 placeholders; the actual scaling rules per
  class haven't been designed.

### Cluster 6 — Edge-case / housekeeping

- **Validating dice count is within Min/Max range**.
- **Validating `rank` is non-negative**.
- **Initiative reroll edge cases** with multiple Insight iterations.
- **The reserved `none` key in `properties_weighted`** for magical-
  item generation — silently shadowed if a Property is ever named
  `none`.
- **Properties registry** distinguishing display-only from
  mechanically-effective properties.
- **Preferred starting attribute distributions per Race** (point-buy
  steering).

## Open architectural questions

The decisions that haven't been made yet, with the trade-offs as I
understand them. Each one will eventually need an answer.

### Where does mana live? (decided)

**Mana lives on Conditions** as a `current_mana` field, parallel
to the HP damage counters and magic toxicity. HP and mana are
the same kind of thing — recoverable per-creature resource — and
they recover under the same per-day rules, so they live together.

Operations: `apply_mana_cost(amount)` (floor at zero, returns
amount actually spent), `restore_mana(amount, max:)` (clamp at
the supplied cap), `set_mana(amount, max:)`. The cap (`max_mana`)
is supplied by the caller from the Character; Conditions does
not look it up itself.

ItemUse's mana applications now route through
`Conditions#restore_mana` when the caller supplies
`target_max_mana:`. Without the cap, the result is still tagged
`unrouted: true` so the caller can apply it externally.

### Natural Recovery (decided)

The thing I had previously framed as "per-day usage trackers" is
really **Natural Recovery** — the rules that govern how HP, ability
damage, mana, magic toxicity, and temp HP change as time passes.

`Conditions#apply_natural_recovery(days:, mode:, character_tier:,
mana_max:, magic_toxicity_attribute_score:)` rolls all five rules
forward. The recovery rates live in `conditions_config.yaml` under
a `Natural Recovery` block:

- **Heal Rate**: a tier-indexed table of `[low, high, unit]`
  per severity. Low is the per-period heal in `mode: short_rest`;
  high is `mode: long_term_recovery`; unit is the period length
  in days (so a major-damage row with unit 7 only heals once per
  full week).
- **Ability Heal Rate**: same shape, governs ability-damage
  recovery with FIFO popping across attributes.
- **Mana Per Day Divisor** (default 4): mana per day =
  `floor(mana_max / divisor)`.
- **Magic Toxicity Per Day Divisor** (default 4): toxicity decay
  per day = `floor(toxicity_attribute_score / divisor)` where the
  toxicity attribute is typically `cha`.

Temporary HP clears on every recovery call regardless of its
`ends_on_round`. Time is the natural enemy of temp HP.

### What about Channel Divinity-style "uses per day"?

The user pushed back on framing this as a separate concern. For
now: deferred. When we get there, the natural pattern is the same
shape as mana — a counter on Conditions, refilled by
`apply_natural_recovery` (or by a future
`apply_per_encounter_recovery` for "uses per encounter"). The
catalog entry would declare the cap and the cadence.

### Skills grew a class (decided)

Skills used to be config-only; Advancement read it for the
`mandatory` flag and the per-skill attribute lookup, and every
caller assembled its own Check spec ad hoc.

`lib/skills.rb` is now a thin coordinator with three jobs:

- **Skill resolution** — looks up the skill catalog entry, with
  Set-prefix fallback so `perform_dance` / `craft_smith` resolve to
  their parent set's attribute and metadata.
- **Skill Prowess computation** — `Ranks + floor(Attribute /
  divisor)`. Ranks come from Advancement at lookup time; Attribute
  comes from Character; divisor comes from skills config.
- **Versatile Performance routing** — when looking up a `perform_*`
  skill, the highest-prowess perform variant the Character has
  trained wins, with the requested skill name preserved on the
  return so callers can attribute the roll correctly.

`DiceSystem#compute_check_details(prowess)` is the dice-resolution
side of the partition: returns `[Dice Count, Competency Bonus,
Starting Value]` from a Prowess integer. Skills hands the Prowess;
DiceSystem partitions it; the caller folds the result into a
modifier dictionary and rolls.

This kills the "Skill-Roll API" and "validate skill list entries"
items from the Unassigned cluster.

### What's the orchestration tier?

`ItemUse` is the first orchestration class. `Combat#apply_attack_damage`
is also orchestration (it sequences DamageTypes lookups, calls
Conditions APIs, etc.) but lives inside Combat itself.

When more workflows arrive — direct casting, full attack resolution,
turn-start ticks, downtime services — they need a home. Three
options:

- **(a) Keep adding orchestration to existing modules.** Combat
  grows `perform_attack`; Conditions grows turn-start hook
  invocation; etc. The orchestration is glued to the module that
  most naturally owns its main side-effects.
- **(b) Top-level orchestration classes** like `ItemUse` and the
  hypothetical `Casting`. Each workflow gets its own class that
  composes the modules it needs.
- **(c) A single `GameSession` god-class** that holds references to
  every module and exposes high-level operations.

(b) seems cleanest based on how `ItemUse` shaped up — small
focused classes with clear participants. (a) is fine for operations
deeply tied to one module's state. (c) leads to circular dependencies
fast.

### Implementation language allocation

Today's split puts the dice-rolling half of attack resolution in
JavaScript and the damage-routing half in Ruby. The docs describe
the logic regardless of where it runs. Open question: what's the
test strategy for client-side logic? Today the Ruby spec suite has
180+ examples; the JS half has none. As the to-hit math evolves,
this asymmetry will become more uncomfortable.

### Modifiers class boundary

`Modifiers` (TentativeAdditions only) reads each ability's `modifiers:`
list and folds them into Character reads. Today's reads use the
list directly. When the Procedural Abilities catalog grows, some
abilities will have *both* always-on Modifiers (folded by Modifiers)
and Trigger Specs (used by procedural lookups). Two questions:

- Does Modifiers eventually merge into AbilitySystem (since the
  data lives in ability entries)?
- Does it become a peer of Conditions, where "active modifiers"
  are looked up the same way active Effects are?

No answer yet. The boundary will get clearer as the procedural
catalog fills in.
