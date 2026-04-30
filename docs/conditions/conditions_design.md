# Conditions and Buffs — Design

Companion to `conditions_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The Conditions module owns **per-creature mutable state** that isn't part of the creature's base definition: damage counters, temporary hit points, magic toxicity, shock, active afflictions, and active effects. It is deliberately ignorant of who or what produces those effects — sources are identified by opaque Source IDs and Tier values, never by spell or item identity.

## Key Operations

### Damage absorption (worst-first with Temporary Hit Points)

`APPLY_HIT_POINT_DAMAGE` walks Severity Categories in `Severity Categories List` order — config lists them **worst to least serious** (Major, Moderate, Minor) so iteration produces worst-first absorption. For each category, Temporary HP absorbs `min(category_amount, temp_pool_remaining)`; the remainder lands on the category's counter.

Two non-obvious rules:

- **Per-category absorption does not redistribute.** With a 3-point Temp HP pool against `{major: 1, moderate: 5}`, Temp HP absorbs 1 Major and 2 Moderate — not 3 Major. The pool is a running counter consumed in iteration order, not a per-category cap.
- **Pool depletion empties the grant.** When the pool drops to zero or below, `temporary_hit_points` is cleared to `null` (rather than left at 0), so a subsequent grant comparison treats "no grant" as 0 rather than as an empty grant.

The incoming amounts are trusted — Damage Reduction, Damage Resilience, runtime bucketing for Physical Damage, etc., are caller responsibilities. Conditions is given pre-resolved per-Severity counts.

### Heal cascade (HP and ability damage)

A Heal supplies a per-Severity pool dictionary. Iteration follows `Severity Categories List` order (worst-first):

1. Each category's pool plus any leftover from worse categories tries to heal that category's counter.
2. Whatever is left flows down to the next category.
3. Excess past the lowest category is wasted.

The same machinery runs on Ability Damage, with one extra rule: within a category, attributes heal **FIFO** by insertion order — the first attribute damaged at that category heals first. Insertion order is preserved by the underlying ordered dictionary; pruning empty entries after the cascade keeps storage compact without disturbing remaining attributes' positions.

### Temporary Hit Points: single-grant replacement

At most one Temporary HP grant is active. New grants:

- **`amount > current_amount`** → replace; previous grant's Source ID is reported back so the caller can cancel logging on it.
- **`amount <= current_amount`** → reject; existing grant untouched (equality is rejection — there's no information gained from swapping the Source ID).
- **`amount <= 0`** → clear the grant unconditionally.

Expiry is handled by `CLEAR_EXPIRED_EFFECTS`, not here. When a Temp HP grant expires the absorbed pool is lost.

### Shock consumption with overflow

Shock has no save and no internal decay. It is consumed only by `CONSUME_SHOCK(max_consume)`, which returns `min(shock, max_consume)` and decrements `shock` by the same amount. **Shock that exceeds the available dice persists** to the next pool refresh — a typical caller pattern is `pool = max_pool - CONSUME_SHOCK(max_pool)`, and any leftover Shock continues to bite at subsequent refreshes until fully spent. The "Shock might take multiple turns to clear" rule in the glossary needs no extra state — it falls out of `min` plus persistence.

### Affliction resolution

`RESOLVE_AFFLICTION` ticks one Active Affliction. The order matters:

1. **Severity Save Penalty** — Conditions adds `floor(severity_before / Severity Divisor)` to the caller's `Competency Penalty` modifier (rather than overwriting it; the dice resolution stacking rule then handles "highest of each type wins").
2. **Roll the save** via the dice resolution module (`COMPUTE_ROLL_PARAMETERS`, `RAND_ROLL_DICE`, `COMPUTE_RESULTS`).
3. **Compute magnitude** — `1 + floor(severity_before / Severity Divisor)`. The `+1` is what makes a fresh Severity-1 affliction still produce magnitude 1.
4. **Apply the effect** at `net_magnitude = max(0, magnitude - successes)`. A fully-saved tick lands magnitude 0, which short-circuits to a no-op inside `APPLY_AFFLICTION_EFFECT`.
5. **Evolve Severity** — `delta = -floor(decay) - floor(successes * per_success) + floor(failures * per_failure)`. New severity clamped at 0; if it reaches 0, the Affliction is deleted entirely (Inflicter Tier discarded along with it).

Inflicter Tier and creature Tier modifiers are **caller-supplied** in `save_input['modifiers']`. Conditions only injects the Severity Save Penalty.

### Tier substitution

Severity Per Success / Severity Per Failure / Severity Decay each accept either a plain integer or the literal string `"tier"`. At resolution time `"tier"` is substituted with the creature's Tier, with **Tier 0 → 0.5** per the project-wide convention. Final Severity deltas always go through `floor()` so Severity stays integer-valued — a Tier-0 creature with `"tier"`-scaled per-success of 0.5 needs two successes to drop one Severity.

### Affliction state shape

Each entry stores `{severity, inflicting_tier}`. Insertion order is preserved across re-inflicts (so Affliction Order in the glossary is stable as long as Severity stays positive). When an entry's Severity decays to zero it is deleted; a later re-inflict re-inserts it at the **end** of the list, not in its previous position. Inflicter Tier accumulates as `max(existing, new)` while the entry lives, and resets when the entry is deleted.

### Effect storage and stacking

`APPLY_EFFECT` enforces exactly one stacking rule: **replace by Source ID.** When a new Effect's `source_id` matches an existing entry, the existing entry is overwritten in place (preserving its position in the list). When no match, the new Effect is appended.

The glossary's "highest Bonus and highest Penalty per Bonus Type wins" rule is not enforced at store time — `effects` may legitimately contain two Bonus entries of the same type for the same `target_key`, with different Source IDs. The rule is applied at **lookup time** by `GET_MODIFIERS`, which scans the list, picks the largest Bonus and largest Penalty per Bonus Type, and returns them in the shape dice resolution expects.

This split keeps `APPLY_EFFECT` cheap and lets the caller compose modifiers by appending freely; it also means removing a stronger Effect doesn't quietly promote a weaker one — the next `GET_MODIFIERS` just picks up whichever is now largest.

### Named Effect application

`APPLY_NAMED_EFFECT` looks up an entry in the `Named Effects` catalog and applies each of its modifiers via `APPLY_EFFECT`, using `<source_id>:<index>` for each. Two consequences:

- Re-applying the same Named Effect with the same `source_id` cleanly overwrites every previous slot (each modifier index lands on its existing slot).
- Removal requires either iterating each known index or scanning `effects` for the prefix.

The catalog is consulted at apply time, not stored on the Effect entries — editing the catalog and reloading config picks up new modifier lists, but already-applied entries retain whatever shape they were created with until they expire. Afflictions whose `effect.kind` is `named_effect` dispatch through this same method using the deterministic Source ID `'affliction:<name>'`.

## Responsibilities

### Owned by the conditions domain

- Per-creature mutable state: HP damage counters, ability damage, Temporary HP grant, Magic Toxicity counter, Shock counter, ordered list of Active Afflictions, ordered list of Active Effects.
- Damage absorption with worst-first Temp HP draining.
- Heal cascades on both HP damage and Ability Damage, with FIFO ordering of attributes within a category.
- Single-grant Temp HP replacement rule (strictly higher wins).
- Shock consumption with overflow persistence.
- Affliction resolution: Severity Save Penalty injection, magnitude formula, Tier substitution, Severity evolution, removal at zero.
- Inflicter Tier accumulation (`max(existing, new)` while entry lives).
- Effect storage with source-id replacement; stacking computed at lookup via `GET_MODIFIERS`.
- Named Effect dispatch with per-modifier Source IDs.
- Expiry sweep (`CLEAR_EXPIRED_EFFECTS`) for Effects and the Temp HP grant.
- Serialization round-trip (`TO_DICT` / `LOAD_STATE`) with validation of severities, sign values, and known affliction names.

### Explicitly *not* owned here

- **What produces an Effect.** Spells, items, abilities, conditions chains — Conditions sees only opaque Source IDs and Tier values.
- **Damage calculation.** Damage Reduction, Damage Resilience, runtime bucketing for Physical Damage (lives in damage_types/combat), and any other mitigation runs in the caller before the per-Severity counts reach `APPLY_HIT_POINT_DAMAGE`.
- **Save Roll mechanics.** Conditions calls into the dice resolution module for affliction saves; how the creature's resistance translates into `dice_count` and `modifiers` is the caller's job.
- **Maximum HP, max Temp HP, max Magic Toxicity caps.** Character module owns the maxima; the caller enforces them when applying gains.
- **Current Hit Points.** Computed by the character module from `hp_max - minor - moderate - major + temp_hp`; Conditions exposes the inputs but never the derived value.
- **Combat pool size.** `CONSUME_SHOCK` takes a `max_consume` from the caller — Conditions never asks "what's the pool".
- **Game time.** Round numbers are passed in by the caller. Expiry comparisons happen here, but the clock is external.
- **Validating Bonus Types or Target Keys against any catalog.** Bonus Type validation is delegated to the dice resolution module when modifiers are eventually used; Target Keys are opaque by design.

### Unassigned (no current owner)

- **Severity Categories List alignment.** The list lives in `conditions_config.yaml` today, and an identical list now lives in `damage_types_config.yaml` (`Severities`). Two configs declaring the same canonical list invites drift; one of them should become the source of truth (likely damage_types) and the other should reference it. The migration is small but not yet done.
- **Generic Counter mechanism.** The damage_types domain's `counter` Mechanic kind (e.g. acid's per-target counter with a `scale_self` + `deal_damage` turn-start behavior) needs a home in the conditions module. Today only `Shock` exists as a hard-coded specific counter; a generic per-creature counter framework — name, current value, and a turn-start hook list — is unspecified.
- **Cross-domain validation that Named Effect names referenced by Affliction Rules and by spell/ability `effects` lists actually appear in `Named Effects`.** Conditions validates the catalog when applying an effect, but author-time validation across the abilities and conditions configs is not done by either side.
