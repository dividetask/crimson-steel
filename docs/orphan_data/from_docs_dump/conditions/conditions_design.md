# Conditions and Buffs — Design

The Conditions module owns **per-creature mutable state** that isn't part of the creature's base definition: damage counters, temporary hit points, magic toxicity, shock, active afflictions, and active effects. It is deliberately ignorant of who or what produces those effects — sources are identified by opaque Source IDs and Tier values, never by spell or item identity.

## Key Operations

### Damage absorption (worst-first with Temporary Hit Points)

`APPLY_HIT_POINT_DAMAGE` walks Severity Categories in **reverse** of the canonical `Severities` order — worst-first absorption: Major, then Moderate, then Minor. For each category, Temporary HP absorbs `min(category_amount, temp_pool_remaining)`; the remainder lands on the category's counter.

Two non-obvious rules:

- **Per-category absorption does not redistribute.** With a 3-point Temp HP pool against `{major: 1, moderate: 5}`, Temp HP absorbs 1 Major and 2 Moderate — not 3 Major. The pool is a running counter consumed in iteration order, not a per-category cap.
- **Pool depletion empties the grant.** When the pool drops to zero or below, `temporary_hit_points` is cleared to `null` (rather than left at 0), so a subsequent grant comparison treats "no grant" as 0 rather than as an empty grant.

The incoming amounts are trusted — Damage Reduction, Damage Resilience, runtime bucketing, etc., are caller responsibilities.

### Heal cascade (HP and ability damage)

A Heal supplies a per-Severity pool dictionary. Iteration follows `Severities` in **reverse** (worst-first):

1. Each category's pool plus any leftover from worse categories tries to heal that counter.
2. Whatever is left flows down to the next category.
3. Excess past the lowest category is wasted.

The same machinery runs on Ability Damage with one extra rule: within a category, attributes heal **FIFO** by insertion order. Insertion order is preserved by the underlying ordered dictionary; pruning empty entries keeps storage compact without disturbing remaining attributes' positions.

### Temporary Hit Points: single-grant replacement

At most one Temporary HP grant is active. New grants:

- **`amount > current_amount`** → replace; previous grant's Source ID is reported back so the caller can cancel logging on it.
- **`amount <= current_amount`** → reject (equality is rejection — there's no information gained from swapping the Source ID).
- **`amount <= 0`** → clear unconditionally.

Expiry is handled by `CLEAR_EXPIRED_EFFECTS`. When a Temp HP grant expires the absorbed pool is lost.

### Shock consumption with overflow

Shock has no save and no internal decay. It is consumed only by `CONSUME_SHOCK(max_consume)`, which returns `min(shock, max_consume)` and decrements `shock` by the same amount. **Shock that exceeds the available dice persists** to the next pool refresh — a typical caller pattern is `pool = max_pool - CONSUME_SHOCK(max_pool)`, and any leftover Shock continues to bite at subsequent refreshes until fully spent. The "Shock might take multiple turns to clear" rule needs no extra state — it falls out of `min` plus persistence.

### Affliction resolution

`RESOLVE_AFFLICTION` ticks one Active Affliction. The order matters:

1. **Severity Save Penalty** — Conditions adds `floor(severity_before / Severity Divisor)` to the caller's `Competency Penalty` modifier (rather than overwriting it; the dice resolution stacking rule then handles "highest of each type wins").
2. **Roll the save** via dice resolution.
3. **Compute magnitude** — `1 + floor(severity_before / Severity Divisor)`. The `+1` is what makes a fresh Severity-1 affliction still produce magnitude 1.
4. **Apply the effect** at `net_magnitude = max(0, magnitude - successes)`. A fully-saved tick lands magnitude 0, which short-circuits to a no-op.
5. **Evolve Severity** — `delta = -floor(decay) - floor(successes * per_success) + floor(failures * per_failure)`. New severity clamped at 0; if it reaches 0, the Affliction is deleted entirely (Inflicter Tier discarded along with it).

Inflicter Tier and creature Tier modifiers are **caller-supplied** in `save_input['modifiers']`. Conditions only injects the Severity Save Penalty.

### Tier substitution

Severity Per Success / Severity Per Failure / Severity Decay each accept either an integer or the literal `"tier"`. At resolution, `"tier"` is substituted with the creature's Tier (Tier 0 → 0.5). Final Severity deltas always go through `floor()`.

### Affliction state shape

Each entry stores `{severity, inflicting_tier}`. Insertion order is preserved across re-inflicts. When an entry's Severity decays to zero it is deleted; a later re-inflict re-inserts it at the **end** of the list, not in its previous position. Inflicter Tier accumulates as `max(existing, new)` while the entry lives.

### Effect storage and stacking

`APPLY_EFFECT` enforces exactly one stacking rule: **replace by Source ID.** When a new Effect's `source_id` matches an existing entry, the existing entry is overwritten in place (preserving its position). When no match, append.

The "highest Bonus and highest Penalty per Bonus Type wins" rule is not enforced at store time — `effects` may legitimately contain two Bonus entries of the same type for the same `target_key`. The rule is applied at **lookup time** by `GET_MODIFIERS`, which scans, picks the largest Bonus and largest Penalty per Bonus Type, and returns them in the shape dice resolution expects.

This split keeps `APPLY_EFFECT` cheap and lets the caller compose modifiers by appending freely; it also means removing a stronger Effect doesn't quietly promote a weaker one — the next `GET_MODIFIERS` just picks up whichever is now largest.

### Acid Counter (built-in)

The Acid Counter is a non-negative integer field on the Conditions instance with hardcoded behavior — no generic counter framework. Two operations:

- **`APPLY_ACID_DAMAGE(amount)`** — adds `amount` to the counter. Zero or negative is a no-op.
- **`RESOLVE_ACID_TURN_START`** — at the start of the affected creature's turn, halves the counter (`floor(value / 2)`), then deals the post-halving value as **minor** Hit Point Damage to the same creature. A counter that drops to zero is removed.

The order matters: halving runs first, the post-halve value is what gets dealt as damage. So a counter at 7 halves to 3, deals 3 minor damage, and persists at 3 for next turn.

Like Shock, the Acid Counter has its own consumption model and earns its own top-level field. Adding a future damage-type counter means adding another top-level field plus apply / resolve operations — a code change, not a config change.

### Mana

Current Mana is a non-negative integer field, parallel to the HP damage counters and magic toxicity:

- **`APPLY_MANA_COST(amount)`** — decrements current mana, floored at zero. Returns the actual amount spent.
- **`RESTORE_MANA(amount, max:)`** — increments, clamped at `max:`. The caller supplies the cap (typically `Character#max_mana`) — Conditions does not look it up itself, mirroring how Magic Toxicity caps are passed in.
- **`SET_MANA(amount, max:)`** — sets to a specific value, clamped to `[0, max]`.

Storing current mana directly (rather than tracking "mana spent" subtracted from a max) keeps the field independent of Mana Max — a buff that raises max_mana shouldn't suddenly retroactively spend more.

### Natural Recovery

`APPLY_NATURAL_RECOVERY(days:, mode:, character_tier:, mana_max:, magic_toxicity_attribute_score:)` rolls every per-day rule forward:

1. **HP damage healing** — for each Severity, look up the Heal Rate row at `tier * 3 + severity_index`. Compute `periods = floor(days / unit)` and `amount = (mode == 'short_rest' ? low : high) * periods`. Cap at the current damage counter.
2. **Ability damage healing** — same against the Ability Heal Rate table; FIFO across attributes within each severity.
3. **Mana** — `mana_per_day = floor(mana_max / Mana Per Day Divisor)`. Restore `mana_per_day * days`, clamped at `mana_max`.
4. **Magic Toxicity** — `tox_per_day = floor(magic_toxicity_attribute_score / Magic Toxicity Per Day Divisor)`. Decay by `tox_per_day * days`, floored at 0.
5. **Temporary HP** — clears entirely, regardless of `ends_on_round`. Time is the natural enemy of temp HP.

The recovery rates are **tabular** rather than a single divisor because different severities heal at different cadences — minor damage might heal 2 points per day at tier 3, while major damage might heal 1 point per week. The `unit` field encodes the cadence.

`mode: short_rest` uses the *low* values; `mode: long_term_recovery` uses the *high* values. The two modes share the same unit values — a major-damage row with unit 7 still requires 7 elapsed days before any major heal lands.

### Effect Name application

`APPLY_NAMED_EFFECT` looks up an entry in the `Effect Names` catalog and applies each modifier-kind Mechanic via `APPLY_EFFECT`, using `<source_id>:<index>` for each. Mechanics of other kinds (`flag`, `set_value`, `scale_value`, `display`, `reroll`, `nudge`) route to whichever per-kind storage the conditions module exposes.

Unknown names raise here — this is the validation seam for Effect strings declared upstream by abilities.

Two consequences of the per-modifier Source ID convention:

- Re-applying the same Effect Name with the same `source_id` cleanly overwrites every previous slot.
- Removal requires either iterating each known index or scanning `effects` for the prefix.

The catalog is consulted at apply time, not stored on the Effect entries — editing the catalog and reloading config picks up new modifier lists, but already-applied entries retain whatever shape they were created with until they expire. Afflictions whose `effect.kind` is `named_effect` dispatch through this same method using the deterministic Source ID `'affliction:<name>'`.

### Bulk removal by Source ID prefix

`REMOVE_EFFECTS_BY_PREFIX(prefix)` removes every Effect whose `source_id` starts with the given prefix and returns the removed entries. It is the cleanup primitive that lets a caller treat a Source ID Namespace as a unit of ownership.

The motivating use case is equip/unequip in equipment: when a Character's equipped set fully changes, equipment calls `REMOVE_EFFECTS_BY_PREFIX('equipment:<char_id>:')` to nuke every effect equipment had previously applied, then re-applies the current loadout fresh. The "current state matches actual equipped items" guarantee is restored coarsely without equipment having to track which slot maps to which Effect.

`APPLY_EFFECT`'s exact-match-by-source-id replacement (idempotent re-application) and `REMOVE_EFFECTS_BY_PREFIX`'s coarse cleanup combine to make Effect application from a stateful caller reliable: every apply is "post the effect, idempotent if already there" and every cleanup is "drop everything in our namespace."

The prefix match is a literal `startswith` — no globbing. A caller wanting per-segment matches builds prefixes that include the segment delimiter (`equipment:char_42:` rather than `equipment:char_42`).

## Responsibilities

### Owned by the conditions domain

- Per-creature mutable state: HP damage counters, ability damage, Temporary HP grant, current Mana, Magic Toxicity counter, Shock counter, Acid Counter, ordered list of Active Afflictions, ordered list of Active Effects.
- Damage absorption with worst-first Temp HP draining.
- Heal cascades on HP damage and Ability Damage, with FIFO ordering of attributes.
- Single-grant Temp HP replacement rule.
- Shock consumption with overflow persistence.
- Affliction resolution: Severity Save Penalty injection, magnitude formula, Tier substitution, Severity evolution, removal at zero.
- Inflicter Tier accumulation while entry lives.
- Effect storage with source-id replacement; stacking computed at lookup via `GET_MODIFIERS`.
- Bulk removal by Source ID prefix.
- Acid Counter: per-creature accumulation, halve-and-deal-minor at turn start, automatic removal at zero.
- Mana: `APPLY_MANA_COST`, `RESTORE_MANA`, `SET_MANA`.
- Natural Recovery: rolls HP, ability, mana, toxicity forward by N days; Temp HP clears.
- Named Effect dispatch with per-modifier Source IDs.
- Expiry sweep (`CLEAR_EXPIRED_EFFECTS`).
- Serialization round-trip with validation.

### Explicitly *not* owned here

- **What produces an Effect.** Spells, items, abilities — Conditions sees only opaque Source IDs and Tier values.
- **Damage calculation.** Damage Reduction, Damage Resilience, runtime bucketing run in the caller before per-Severity counts reach `APPLY_HIT_POINT_DAMAGE`.
- **Save Roll mechanics.** Conditions calls dice resolution; how the creature's resistance translates into `dice_count` and `modifiers` is the caller's job.
- **Maximum HP, max Temp HP, max Magic Toxicity caps.** Character module owns the maxima; the caller enforces them when applying gains.
- **Current Hit Points.** Computed by Character from `hp_max - minor - moderate - major + temp_hp`; Conditions exposes the inputs but never the derived value.
- **Combat pool size.** `CONSUME_SHOCK` takes a `max_consume` from the caller.
- **Game time.** Round numbers are passed in by the caller.
- **Validating Bonus Types or Target Keys against any catalog.**

### Unassigned (no current owner)

- **Acid Counter wiring from damage application.** Conditions owns the Acid Counter, but combat is the natural place to call `APPLY_ACID_DAMAGE` when acid damage lands. That wiring isn't pinned to a class today.
