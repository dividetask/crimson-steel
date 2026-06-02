# Conditions — Design

Owns per-Creature mutable state that isn't part of the Creature's base definition: HP damage counters, Ability Damage, Temporary Hit Points, Mana Spent, Magic Toxicity, Shock, the Acid Counter, Active Afflictions, and Active Effects. Conditions is deliberately ignorant of who or what produces those effects — sources are identified by opaque Source IDs and Tier values, never by spell or item identity.

Sibling domains:

- **Combat** runs Severity Calculation, then hands Conditions a per-Severity damage map and routes Damage Type side-effects (Acid Counter, Shock) through Conditions' APIs.
- **Dice Resolution** owns Roll mechanics. Conditions builds save Rolls and invokes Dice Resolution; the per-Bonus-Type stacking rule used at Modifier Lookup matches Dice Resolution's.
- **Creatures** owns Mana Max, attribute scores, max HP, and the Charisma / Tier values that feed the Toxicity Threshold. Conditions exposes inputs; the caller folds them into derived values.
- **Abilities** declares Effect Names. Conditions is the validation seam — unknown Effect Names raise at apply time.

## Common types

### Conditions State

The full per-Creature state, sufficient to round-trip through serialization.

| Field | Type | Default on load | Description |
|---|---|---|---|
| `hp_damage` | map of Severity → integer | empty (all zeros) | Accumulated HP damage per Severity. Each counter ≥ 0. Severity keys match the canonical Severity list owned by Combat (see `encounter_glossary.md`). Missing Severity keys default to 0. |
| `ability_damage` | map of Severity → ordered map of attribute → integer | empty | Ability Damage per attribute per Severity. Insertion order across attributes is preserved so the Heal Cascade can pop FIFO. Entries with zero damage are pruned. |
| `temporary_hit_points` | Temporary HP Grant or null | null | At most one grant. Null when no grant is active. |
| `mana_spent` | integer | 0 | Mana the Creature has consumed since last at full. Non-negative; never exceeds the Creature's Mana Max (supplied by the caller). Current Mana is derived as `mana_max − mana_spent`. |
| `magic_toxicity` | integer | 0 | Magic Toxicity counter. Non-negative. |
| `shock` | integer | 0 | Shock counter. Non-negative. |
| `acid_counter` | integer | 0 | Acid Counter. Non-negative; zero means the counter is absent. |
| `afflictions` | ordered map of name → Active Affliction | empty | Insertion order preserved. |
| `effects` | list of Active Effect | empty | Append order preserved. Replace-by-Source-ID is in-place. |

Every field has a documented default, so a freshly-spawned Creature can be persisted as `{}` and Load State fills in the rest. The defaults are equivalent to "no state of that kind" — zero counters and spend, no grants, no Afflictions, no Effects.

### Module-level State

In addition to per-Creature Conditions State, Conditions tracks one module-level collection: the Zone Effects list. Zone Effects are not associated with any single Creature; they are spatial objects affecting any Creature whose Token enters their footprint. The list lives alongside the per-Creature records in the same persisted state file.

| Field | Type | Default | Description |
|---|---|---|---|
| `zone_effects` | list of Zone Effect | empty | All currently active Zone Effects across the Campaign. See *Zone Effect* below. |

### Temporary HP Grant

| Field | Type | Default | Description |
|---|---|---|---|
| `amount` | integer | required | Pool size remaining. Decreases as damage is absorbed. |
| `source_id` | string | required | Opaque caller-supplied identifier. |
| `ends_on_round` | integer or null | null | When non-null, expiry sweeps clear the grant once `Current Round ≥ ends_on_round`. Null means permanent until explicitly removed. |

### Active Affliction

| Field | Type | Default | Description |
|---|---|---|---|
| `potency` | integer | required | Current Potency. Always ≥ 1 while the entry exists. Named distinctly from Damage Severity to avoid confusion — the two concepts have no relationship. |
| `inflicting_tier` | integer | required | Highest Tier among inflicters since this entry was last absent. Accumulated as `max(existing, new)`. |
| `next_resolution_round` | integer or null | null | The absolute round count at which this Affliction next becomes due for resolution. Set when the Affliction is inflicted (`current_round + Frequency Rounds[save_frequency]`). Null when the caller chose not to schedule. |

### Active Effect

| Field | Type | Default | Description |
|---|---|---|---|
| `target_key` | string | required | Opaque key naming what the Effect adjusts. |
| `bonus_type` | string | required | Drawn from the Modifiers domain's Bonus Types List. Opaque to Conditions. |
| `amount` | signed integer | required | Magnitude of the modifier. A positive value is a Bonus; a negative value is a Penalty; zero is legal but has no mechanical effect. |
| `ends_on_round` | integer or null | null | Expiry sweep clears the entry when `Current Round ≥ ends_on_round`. Null means permanent until explicitly removed. |
| `source_id` | string | required | Opaque caller-supplied identifier. Re-applying the same `source_id` overwrites in place. |
| `metadata` | dict | `{}` | Caller-supplied. Conditions does not interpret. |

### Zone Effect

A Zone Effect lives at the Conditions module level, not on any single Creature's Conditions State. The paired spatial record lives in Atlas (see `atlas/atlas_design.md`).

| Field | Type | Default | Description |
|---|---|---|---|
| `source_id` | string | required | Opaque identifier shared with the paired Atlas Zone. Acts as the key for lookup, replacement, and removal. |
| `atlas_zone_id` | Zone ID | required | The Atlas Zone this Effect is paired with. Populated when Conditions calls Atlas's *Place Zone* during *Create Zone Effect*. |
| `triggers` | Zone Triggers | `{}` | Per-trigger Save Block. See below. |
| `ends_on_round` | integer or null | null | Same semantics as Active Effect. Null means the source domain controls removal. |
| `metadata` | dict | `{}` | Caller-supplied. Conditions does not interpret. |

**Zone Triggers**:

| Field | Type | Default | Description |
|---|---|---|---|
| `on_create` | Save Block or null | null | Surfaced for every Creature whose Token is already inside the Zone when the Zone is created. |
| `on_enter` | Save Block or null | null | Surfaced for a Creature whose Token enters the Zone via *Move Token*. |
| `on_end_of_turn` | Save Block or null | null | Surfaced when a Creature's turn ends while inside the Zone (Combat queries Conditions during end-of-turn cleanup). |

The Save Block shape is the same as the Save Spec in Abilities — a list of `{attribute, fail, success, fumble?}` entries — but Conditions treats it opaquely; Combat is the consumer that builds the Saving Throw.

### Severity Map

A `{minor: int, moderate: int, major: int}` dict using the canonical Severity keys. Used as input by *Apply Hit Point Damage* and *Apply Heal*, and as output by the damage-absorption result.

### Save Input

The Dice-Resolution-bound data Conditions needs to roll a save on the caller's behalf. Caller-supplied at every Affliction-resolution entry point.

| Field | Type | Description |
|---|---|---|
| `dice_count` | integer | Number of dice to roll. |
| `modifiers` | list of `(type_name, signed_value)` | Bonuses and Penalties to fold into the Roll. Conditions appends the Potency Save Penalty before invoking Dice Resolution. |
| any other Roll fields | as defined in `dice_resolution_design.md` | Passed through to the Roll struct as-is. |

### Toxicity Source Kind

A caller-supplied enum on every `Apply Magic Toxicity` call:

- `positive` — the Magic-Toxicity-imposing effect is beneficial (magical healing, buff, voluntary attunement). Subject to Toxicity Block.
- `forced` — any other source (harmful magic, environmental exposure). Always applies.

Toxicity Damage is computed identically regardless of Source Kind; only Toxicity Block discriminates on kind.

## Public entry points

Function names below are conceptual labels for cross-domain reference; implementations choose the actual symbols. Where another domain's documentation already cites a name (e.g. `APPLY_HIT_POINT_DAMAGE` in `encounter_design.md`), the parenthetical here matches that name for traceability.

### Apply Hit Point Damage (`APPLY_HIT_POINT_DAMAGE`)

Inputs: a Severity Map of incoming damage.

Behavior: Run *Damage Absorption* — see Operations. Mutate `hp_damage` and `temporary_hit_points` in place.

Returns: a struct with the per-Severity amount absorbed by Temporary HP, the per-Severity amount that reached the counters, and the Source ID of any Temporary HP grant that was cleared.

The incoming amounts are trusted — Damage Reduction, Damage Resilience, runtime bucketing, and Damage Type Mechanics all run in the caller before per-Severity counts reach Conditions.

### Apply Heal (`APPLY_HEAL`)

Inputs: a Severity Map of healing.

Behavior: Run the *Heal Cascade* over `hp_damage` — see Operations. Mutate counters in place. The Temporary HP grant is unaffected. *Apply Heal* never imposes Magic Toxicity — healing potions or magical healing that produce toxicity do so by calling *Apply Magic Toxicity* separately in the caller.

Returns: a Severity Map of the amount actually healed at each Severity (post-cap, post-cascade).

### Apply Ability Damage (`APPLY_ABILITY_DAMAGE`)

Inputs: an attribute key and a Severity Map of incoming damage.

Behavior: For each (Severity, amount > 0) pair, add to `ability_damage[severity][attribute]`. If the attribute had no prior damage at that Severity, append it to the end of the ordered map for that Severity (preserving FIFO).

Returns: nothing.

### Apply Ability Heal (`APPLY_ABILITY_HEAL`)

Inputs: a Severity Map of healing.

Behavior: Run the *Ability Heal Cascade* over `ability_damage` — see Operations. Within each Severity, attributes pop FIFO until the pool is drained. Entries that reach zero are pruned, preserving the order of survivors.

Returns: a per-Severity map of the amount actually healed at each Severity.

### Apply Temporary Hit Points (`APPLY_TEMP_HP`)

Inputs: an amount (integer), a Source ID, an optional Ends on Round (defaults to null — permanent until explicitly removed).

Behavior: Apply the *Single-Grant Replacement* rule — see Operations.

Returns: `{accepted: bool, displaced_source_id: string or null}`. `displaced_source_id` carries the Source ID of the previous grant when a new grant strictly replaces it, so the caller can cancel any logging on the old grant. Null when no previous grant existed, when the new grant was rejected, or when the new grant cleared an unset slot.

### Consume Shock (`CONSUME_SHOCK`)

Input: `max_consume` (non-negative integer).

Behavior: Compute `consumed = min(shock, max_consume)`. Decrement `shock` by `consumed`.

Returns: `consumed`.

The caller's typical pattern is `pool = max_pool − CONSUME_SHOCK(max_pool)`. Excess Shock persists across rounds — Conditions does not decay it on its own. The "Shock may take multiple turns to clear" rule falls out of `min` plus persistence.

### Apply Magic Toxicity (`APPLY_MAGIC_TOXICITY`)

Inputs: `amount` (non-negative integer), `kind` (Toxicity Source Kind), `charisma` (integer attribute value), `tier` (integer). The charisma and tier values are read by the caller from the Creatures domain and passed in.

Behavior: Run the *Magic Toxicity Update* pipeline — see Operations. The pipeline computes the Toxicity Threshold, applies Toxicity Block when kind is `positive`, increments `magic_toxicity` when not blocked, and dispatches *Apply Ability Damage* against Charisma for any Toxicity Damage produced by the increase crossing or already-exceeding the threshold.

Returns: `{accepted: bool, charisma_damage: integer}`. `accepted = false` indicates Toxicity Block rejected the call — the caller must also abort the positive effect that triggered the call. `charisma_damage` is the Charisma Ability Damage just inflicted (zero in most cases).

### Inflict Affliction (`INFLICT_AFFLICTION`)

Inputs: Affliction name, inflicter Tier (integer), optional Potency delta (default 1), optional `current_round` (integer).

Behavior:

1. Validate that the Affliction name exists in `conditions_afflictions.yaml`. Unknown names raise.
2. If no entry exists for this name, create one at `potency = max(1, delta)` with `inflicting_tier = inflicter_tier` and append at the end of the order. When `current_round` is supplied, schedule the new entry's `next_resolution_round` to `current_round + Frequency Rounds[save_frequency]`. When omitted, leave `next_resolution_round = null` and the caller is responsible for any scheduling.
3. Otherwise (entry exists), add `delta` to `potency` (clamped at ≥ 1) and raise `inflicting_tier` to `max(existing, inflicter_tier)`. `next_resolution_round` is left untouched — re-inflicting does not reset the schedule.

Returns: the updated Active Affliction record.

A Potency that decays to zero in a later resolution removes the entry; re-inflicting then re-inserts at the end, not in its previous position, with `next_resolution_round` set fresh from the new inflict call's `current_round`.

### Resolve Affliction (`RESOLVE_AFFLICTION`)

Inputs: Affliction name, a Save Input, optional `current_round` (integer).

Behavior: Run the *Affliction Resolution* pipeline — see Operations. When `current_round` is supplied and the Affliction survives the resolution, reschedule its `next_resolution_round` by advancing the **previous** `next_resolution_round` by `Frequency Rounds[save_frequency]` (falling back to `current_round + Frequency Rounds[save_frequency]` only when there was no prior schedule). Advancing from the previous due round rather than from "now" means a time jump leaves the Affliction owing one resolution per missed interval — it stays due until each is resolved — instead of skipping straight to the current round. When `current_round` is omitted, leave `next_resolution_round` untouched.

Returns: a struct with the resolved save's Roll Outcome, the realized Net Magnitude, the applied effect's payload (if any), the new Potency (or zero / removed if the entry was deleted), and the rescheduled `next_resolution_round` (when applicable).

### List Pending Afflictions (`LIST_PENDING_AFFLICTIONS`)

Inputs: `current_round` (integer).

Behavior: Walk `afflictions` in insertion order. Return the names of every Active Affliction whose `next_resolution_round` is non-null and at or before `current_round`.

Returns: ordered list of Affliction names.

Used by callers that want to resolve due Afflictions one by one — typically Combat at the start of a Creature's turn. The caller iterates the returned list and invokes *Resolve Affliction* for each entry, supplying a fresh Save Input each time.

### Resolve Due Afflictions (`RESOLVE_DUE_AFFLICTIONS`)

Inputs: `current_round` (integer), a `save_input_provider` callable that takes an Affliction name and returns the Save Input for that Affliction's save.

Behavior: For each name returned by *List Pending Afflictions* with the same `current_round`, in order: call `save_input_provider(name)`, then run *Resolve Affliction* with that Save Input and the same `current_round` (so each resolution reschedules). Continue until the list is drained, including any Afflictions newly added during this call (the loop reads the current list at each step rather than a snapshot — this keeps the behavior identical to a manual one-by-one loop).

Returns: an ordered list of *Resolve Affliction* result structs, one per resolution performed.

Callers that prefer fine-grained control use *List Pending Afflictions* + per-Affliction *Resolve Affliction* directly. *Resolve Due Afflictions* is a convenience for the common case where the same provider applies to every due entry.

### Apply Effect (`APPLY_EFFECT`)

Inputs: an Active Effect.

Behavior: If an existing entry in `effects` has the same `source_id`, overwrite it in place (preserving its list position). Otherwise append.

Returns: nothing.

The single stacking rule enforced here is *replace by Source ID*. The "largest positive amount and most-negative amount per Bonus Type wins" rule is **not** enforced at store time — `effects` may legitimately contain two positive entries of the same Bonus Type for the same `target_key`. That rule is applied at lookup time by *Get Modifiers*.

### Remove Effects by Prefix (`REMOVE_EFFECTS_BY_PREFIX`)

Input: `prefix` (string).

Behavior: Remove every Active Effect whose `source_id` starts with the literal prefix (no globbing). Return the removed entries in their original order.

The motivating pattern is equip/unequip: when a Creature's equipment changes, the Equipment domain calls this with `equipment:<creature_id>:` to clear every Effect it had previously applied, then re-applies the current loadout fresh. Combined with *Apply Effect*'s idempotent replace-by-Source-ID, this gives the caller "post the effect, idempotent" plus "drop everything in our namespace" — enough to reliably reconcile state from a stateful upstream.

A caller wanting per-segment matches builds prefixes that include the segment delimiter (`equipment:char_42:`, not `equipment:char_42`).

### Get Modifiers (`GET_MODIFIERS`)

Input: `target_key` (string), optional `current_round` (integer; defaults to "no expiry filter").

Behavior: Scan `effects` for entries whose `target_key` matches. Group surviving entries by Bonus Type, and within each Bonus Type pick the largest positive `amount` and the most-negative `amount` (each appearing only if at least one entry of that sign exists). Skip entries whose `ends_on_round` is non-null and `≤ current_round` when `current_round` is supplied.

Returns: a list of `(bonus_type, signed_amount)` pairs — at most two entries per Bonus Type (one positive, one negative). The shape matches what Dice Resolution's per-type stacking expects when passed in as the Roll's `bonus_penalty_list`.

Removing a stronger Effect does not quietly promote a weaker one — the next *Get Modifiers* call just picks up whichever entry is now largest in magnitude on its sign.

### Create Zone Effect (`CREATE_ZONE_EFFECT`)

Inputs: `source_id` (string), `map_id` (integer), `shape` (Zone Shape), `size` (integer), `anchor` (Atlas Anchor specification), `triggers` (Zone Triggers), optional `ends_on_round`, optional `metadata`.

Behavior:
1. Call Atlas's *Place Zone* with the shape, size, anchor, and `source_id`; record the assigned `atlas_zone_id`.
2. Add a Zone Effect to the module-level Zone Effects list. If a Zone Effect with the same `source_id` already exists, this is a configuration error — callers must *Remove Zone Effect* first.
3. The on_create trigger is **not** auto-fired by Conditions. Combat queries the Zone's `triggers.on_create` and surfaces it to the GM for each Creature whose Token is already inside the Zone (Atlas's *Zones In Position* helper supplies the membership).

Returns: the `atlas_zone_id` for the consuming domain's bookkeeping.

### Remove Zone Effect (`REMOVE_ZONE_EFFECT`)

Input: `source_id` (string).

Behavior: Look up the Zone Effect by `source_id`. If found, call Atlas's *Remove Zone* with the paired `atlas_zone_id` and drop the Conditions-side entry. If not found, no-op.

### List Zone Effects (`LIST_ZONE_EFFECTS`)

Inputs: optional `map_id` filter, optional `source_id_prefix` filter.

Returns: the Zone Effects matching the filters. Used by Combat to enumerate active Zones during turn processing, and by UI surfaces that visualize the Map.

### Get Zone Triggers (`GET_ZONE_TRIGGERS`)

Inputs: `source_id`, `trigger_kind` (`on_create` | `on_enter` | `on_end_of_turn`).

Returns: the Save Block for the requested trigger, or null when the Zone Effect has no trigger of that kind. Used by Combat when surfacing Zone events to the GM.

### Apply Acid Damage (`APPLY_ACID_DAMAGE`)

Input: `amount` (integer).

Behavior: Add `amount` to `acid_counter`. Amounts ≤ 0 are a no-op.

Returns: the new counter value.

### Resolve Acid Turn Start (`RESOLVE_ACID_TURN_START`)

Inputs: none.

Behavior: At the start of the affected Creature's turn:

1. `acid_counter = floor(acid_counter / 2)`.
2. Deal `acid_counter` Minor HP damage to this Creature (via *Apply Hit Point Damage* internally).
3. If `acid_counter == 0`, the field is cleared.

The order matters: halving runs first; the post-halving value is what gets dealt and what persists. So a counter at 7 halves to 3, deals 3 Minor damage, and persists at 3 into the next turn.

Returns: the post-halving Minor damage that was dealt.

### Apply Mana Cost (`APPLY_MANA_COST`)

Inputs: `amount` (non-negative integer), `mana_max` (non-negative integer).

Behavior: Increment `mana_spent` by `amount`, capped at `mana_max` (so a Creature cannot spend more Mana than they have available).

Returns: the amount actually spent (`min(amount, mana_max − mana_spent_before)`).

### Restore Mana (`RESTORE_MANA`)

Input: `amount` (non-negative integer).

Behavior: Decrement `mana_spent` by `amount`, floored at zero.

Returns: the amount actually restored (`min(amount, mana_spent_before)`).

`mana_max` is not needed here — a restore can never push current Mana above the cap because `mana_spent` is already bounded below by zero.

### Set Mana Spent (`SET_MANA_SPENT`)

Inputs: `amount` (integer), `mana_max` (non-negative integer).

Behavior: Set `mana_spent` to `clamp(amount, 0, mana_max)`.

Returns: the new `mana_spent`.

Callers wanting to set Mana in terms of current value (e.g. "set Mana to 7") compute `mana_max − desired_current` and pass that.

### Apply Natural Recovery (`APPLY_NATURAL_RECOVERY`)

Inputs:

- `recovery_ticks` — non-negative integer count of Recovery Ticks elapsed. In the tabletop game one Recovery Tick equals one Day; the consuming project may define a Recovery Tick as any other interval by overriding `Recovery Tick` in `conditions_config.yaml`. A caller that has only a round count can divide by the configured rounds-per-Recovery-Tick to derive this value.
- `mode` — `slow` (traveling, active) or `fast` (bed rest, attended care).
- `character_tier` — integer.
- `mana_max` — non-negative integer.
- `magic_toxicity_attribute_score` — integer (Charisma score by default).

Behavior: Roll every per-Recovery-Tick rule forward — see *Natural Recovery* in Operations.

Returns: a summary of what changed (per-Severity HP healed, per-attribute Ability Damage healed, Mana restored, Magic Toxicity decayed, Temporary HP cleared yes/no).

### Apply Named Effect (`APPLY_NAMED_EFFECT`)

Inputs: Effect Name, `source_id` (string), optional `ends_on_round` (integer).

Behavior: Look up `name` in `conditions_effect_names.yaml`. Unknown names raise. For each Mechanic in the entry's `mechanics` list:

- `modifier` kinds dispatch through *Apply Effect*, with a per-Mechanic Source ID built as `<source_id>:<index>`.
- Other kinds (`reroll`, `nudge`, `set_value`, `scale_value`, `flag`, `display`) route to whichever per-kind storage the implementation exposes, using the same `<source_id>:<index>` scheme.

Affliction resolutions whose effect kind is `named_effect` dispatch through this same entry point using the deterministic Source ID `affliction:<name>`.

Returns: the list of Mechanic Source IDs that were applied.

Two consequences of the per-Mechanic Source ID convention:

- Re-applying the same Effect Name with the same `source_id` cleanly overwrites every previous slot.
- Removal requires either iterating each known index or using *Remove Effects by Prefix*.

The catalog is consulted at apply time, not stored on the resulting entries — editing `conditions_effect_names.yaml` and reloading config picks up new Mechanic lists for *future* applications, but already-applied entries keep whatever shape they were created with until they expire or are removed.

### Clear Expired Effects (`CLEAR_EXPIRED_EFFECTS`)

Input: `current_round` (integer).

Behavior: Remove every Active Effect and Temporary HP grant whose `ends_on_round` is non-null and `≤ current_round`. When the Temporary HP grant expires, any absorbed pool is lost (no rebate).

Returns: the list of removed entries.

### Dead?

Inputs: `max_hit_points`, attribute scores (map of attribute key → integer), and the precomputed Toxicity Threshold (all read from the Creatures domain by the caller).

Behavior: Evaluate the *Death Threshold* rules — see Operations.

Returns: boolean.

### Serialization

- **Save State** — produce a Conditions State dict.
- **Load State** — accept a Conditions State dict and replace the current state. Validates field shapes; rejects malformed input.

The on-disk format is the consuming project's responsibility; Conditions provides the in-memory shape.

## Operations

### Damage Absorption (worst-first with Temporary Hit Points)

Walks Severity Categories in **reverse** of the canonical `Severities` order — worst-first. For each category, in order Major → Moderate → Minor:

- `absorbed = min(category_amount, temp_pool_remaining)`.
- `temp_pool_remaining −= absorbed`; the category's counter gains `category_amount − absorbed`.

Two non-obvious rules:

- **Per-category absorption does not redistribute.** With a 3-point Temporary HP pool against `{major: 1, moderate: 5}`, Temporary HP absorbs 1 Major and 2 Moderate — not 3 Major. The pool is a running counter consumed in iteration order, not a per-category cap.
- **Pool depletion clears the grant.** When `temp_pool_remaining` drops to zero or below, `temporary_hit_points` is set to null (rather than left as a zero-amount grant), so a subsequent grant comparison treats "no grant" as 0 rather than as an empty grant. The cleared grant's Source ID is returned to the caller so logging on it can be cancelled.

### Heal Cascade (HP and Ability Damage)

A heal supplies a Severity Map. Iteration follows the canonical Severities in **reverse** (worst-first):

1. The current category's pool plus any leftover from worse categories tries to heal that counter.
2. Whatever remains flows down to the next category.
3. Excess past the lowest category is wasted.

Capping per category is `min(pool, counter)`.

The same machinery runs on Ability Damage with one additional rule: within a Severity, attributes heal **FIFO** by insertion order. Insertion order is preserved by the underlying ordered map; pruning empty entries keeps storage compact without disturbing remaining attributes' positions.

### Single-Grant Replacement (Temporary HP)

At most one Temporary HP grant is active. On a new grant of `amount`:

- `amount > current_amount` → replace. The previous grant's Source ID is reported back. Both `source_id` and `ends_on_round` are taken from the new grant; the absorbed pool is reset to `amount`.
- `amount == current_amount` → reject. Equality is rejection — there is no information gained from swapping the Source ID.
- `0 < amount < current_amount` → reject.
- `amount ≤ 0` → clear the grant unconditionally. The previous grant's Source ID is reported back.

Expiry is handled by *Clear Expired Effects*; when a Temporary HP grant expires the absorbed pool is lost (no fallback to lower grants — there is no list to fall back to).

### Magic Toxicity Update

`Apply Magic Toxicity` computes:

1. **Toxicity Threshold.** `threshold = Toxicity Threshold formula(charisma, tier)` (see *Toxicity Threshold* below).
2. **Toxicity Block.** If `kind == positive` and `magic_toxicity > threshold` (strict — equal does not block), the call is rejected. `magic_toxicity` is unchanged; no Charisma damage is dealt; returns `{accepted: false, charisma_damage: 0}`.
3. **Apply the increase.** Otherwise, `pre = magic_toxicity`; `magic_toxicity += amount`.
4. **Toxicity Damage.** `charisma_damage = max(0, magic_toxicity − threshold) − max(0, pre − threshold)`. When positive, dispatch *Apply Ability Damage* on `cha` at the configured Toxicity Damage Severity (default Major).
5. **Return** `{accepted: true, charisma_damage}`.

The damage formula deals only the portion of the increase that lands above the threshold — the bookkeeping cleanly handles all three crossing patterns:

- Started below threshold, stayed below → zero damage.
- Started below, ended above → damage equal to the overshoot past threshold.
- Started above → damage equal to the full increase (the entire amount lands above the threshold).

Toxicity Block is the only kind-discriminating step. Toxicity Damage is computed identically for `positive` (the rare non-blocked positive case where the pre-call state was strictly at or below threshold) and `forced` calls.

### Toxicity Threshold

`Threshold(charisma, tier)` is configurable in shape so a consuming project can model "Charisma alone," "Charisma × Tier," or any other simple function of those two values without code changes. The default formula is `floor(charisma × tier_value)`, where `tier_value = max(0.5, tier)` per the project-wide Tier 0 → 0.5 convention. The config keys `Toxicity Threshold Attribute` and `Toxicity Threshold Tier Scaled` toggle this between the two common modes — see `conditions_config.yaml`.

### Affliction Resolution

`Resolve Affliction` runs one resolution of one Active Affliction. The order matters:

1. **Potency Save Penalty.** Append a `("Competency", −floor(potency_before / Potency Divisor))` entry to the Save Input's `modifiers` list rather than overwriting any existing Competency entry. Dice Resolution's per-type stacking handles "lowest Penalty of each type wins."
2. **Roll the save** via Dice Resolution. `successes = max(0, dois)`; `failures = max(0, −dois)`.
3. **Compute Magnitude.** `magnitude = 1 + floor(potency_before / Potency Divisor)`. The `+1` makes a fresh Potency-1 Affliction still produce magnitude 1.
4. **Apply the effect** at `net_magnitude = max(0, magnitude − successes)`. A fully-saved resolution lands at net magnitude 0, which short-circuits to a no-op. Effect dispatch:
   - `hit_point_damage` → call *Apply Hit Point Damage* with `{severity: net_magnitude}`.
   - `ability_damage` → call *Apply Ability Damage* with the named attribute and `{severity: net_magnitude}`.
   - `named_effect` → call *Apply Named Effect* with `source_id = "affliction:<name>"` and `ends_on_round = current_round + duration_rounds` (where supplied). Magnitude is binary — `net_magnitude > 0` applies the effect; `net_magnitude == 0` does not.
5. **Evolve Potency.** `potency_delta = −floor(potency_decay) − floor(successes × potency_per_success) + floor(failures × potency_per_failure)`. New `potency = potency_before + potency_delta`, clamped at zero. If the new Potency is zero, delete the Affliction entry entirely (Inflicter Tier and `next_resolution_round` are discarded along with it).
6. **Reschedule.** When the caller supplied `current_round` and the Affliction survived, advance `next_resolution_round` by `Frequency Rounds[save_frequency]` from its **previous** value (`next_resolution_round = previous_next_resolution_round + Frequency Rounds[save_frequency]`), falling back to `current_round + Frequency Rounds[save_frequency]` only when there was no prior schedule. This makes missed intervals accumulate: after a time jump the Affliction stays due (its new `next_resolution_round` may still be ≤ `current_round`) until one resolution has been applied for each elapsed interval, rather than skipping straight to "now". The lookup uses the Affliction Rule's `save_frequency`; an Affliction Rule without an explicit value defaults to `"round"`.

Inflicter Tier and Creature Tier modifiers are **caller-supplied** in the Save Input's `modifiers` list. Conditions only injects the Potency Save Penalty.

### Tier Substitution

Potency Per Success / Potency Per Failure / Potency Decay each accept either an integer or the literal `"tier"`. At resolution time, `"tier"` is replaced with the Creature's Tier (Tier 0 → 0.5 per project convention). Final Potency deltas always go through `floor()`.

### Effect Storage and Stacking

*Apply Effect* enforces exactly one rule: **replace by Source ID.** When a new Effect's `source_id` matches an existing entry, the existing entry is overwritten in place (preserving its list position). When no match, append.

The "largest positive amount and most-negative amount per Bonus Type wins" rule is applied at **lookup time** by *Get Modifiers*, which scans, picks the maximum positive `amount` and the minimum (most-negative) `amount` per Bonus Type for the queried `target_key`, and returns the surviving pairs in the shape Dice Resolution expects.

This split keeps *Apply Effect* cheap and lets callers compose modifiers by appending freely; it also means removing a stronger Effect does not quietly promote a weaker one — the next *Get Modifiers* call just picks up whichever is now largest in magnitude on its sign.

### Acid Counter

A non-negative integer field with hardcoded behavior — no generic counter framework. Apply increments; *Resolve Acid Turn Start* halves-and-deals at the start of the affected Creature's turn. A counter that drops to zero is removed.

Like Shock, the Acid Counter earns its own top-level field. Adding a future damage-type counter with similarly distinctive behavior means adding another top-level field plus apply/resolve operations — a code change, not a config change.

### Natural Recovery

`Apply Natural Recovery` rolls every per-Recovery-Tick rule forward.

The heal rates are expressed per (Severity, Tier, Mode) in `conditions_config.yaml` as `[amount, tick_length]` pairs — meaning "`amount` points per `tick_length` Recovery Ticks." Both numbers are integers; together they describe a rational rate (e.g. `[1, 7]` = "1 point per 7 Recovery Ticks" = 1/7 per Recovery Tick). Total healed at that Severity is `floor((amount × recovery_ticks_elapsed) / tick_length)`. A `tick_length` greater than `recovery_ticks_elapsed` therefore heals zero — partial progress is not retained between calls.

The pipeline:

1. **HP Damage healing.** For each Severity, look up the Heal Rate row at `tier` (clamped to the configured table's bounds — Tiers beyond the array are an error rather than a clamp). Select `slow` or `fast` per `mode`. Apply `floor((amount × recovery_ticks) / tick_length)` to that Severity's counter, capping at the current counter.
2. **Ability Damage healing.** Same against the Ability Heal Rate table; FIFO across attributes within each Severity per the Heal Cascade's ordering rule.
3. **Mana.** `mana_per_recovery_tick = floor(mana_max / Mana Per Recovery Tick Divisor)`. Decrement `mana_spent` by `mana_per_recovery_tick × recovery_ticks`, floored at zero.
4. **Magic Toxicity.** `tox_per_recovery_tick = floor(magic_toxicity_attribute_score / Magic Toxicity Per Recovery Tick Divisor)`. Decay `magic_toxicity` by `tox_per_recovery_tick × recovery_ticks`, floored at zero.
5. **Temporary HP.** Clears entirely, regardless of `ends_on_round`. Time is the natural enemy of Temporary HP.

The rates are tabular rather than a single divisor because different Severities heal at different cadences. A row of `[1, 7]` at Tier 0 Minor means "1 Minor heals every 7 Recovery Ticks" — short rests over fewer than 7 Recovery Ticks heal nothing at that Severity.

`mode = slow` represents recovery while travelling or otherwise active. `mode = fast` represents bed rest with active care from a healer. The two modes share the same `[amount, tick_length]` shape; the default config sets each Fast rate to exactly twice the corresponding Slow rate, but a consuming project may break that symmetry.

The duration of one Recovery Tick is configurable via `Recovery Tick` in `conditions_config.yaml` — the value is the round count of one Recovery Tick. In the tabletop game one Recovery Tick equals one Day (14400 rounds at the default Round Length); a real-time game may set the Recovery Tick to a much smaller number of rounds and adjust the `[amount, tick_length]` rates accordingly. Conditions never reads the wall clock; the caller is responsible for converting elapsed time into Recovery Ticks before calling *Apply Natural Recovery*.

### Death Threshold

A Creature is Dead when **any** of these is reached:

- `sum(hp_damage.values()) ≥ floor(Death Multiplier × max_hit_points)`.
- For any single attribute, `sum(ability_damage[severity][attribute] for severity in Severities) ≥ floor(Death Multiplier × attribute_score)`.
- `magic_toxicity ≥ floor(Death Multiplier × toxicity_threshold)`.

`Death Multiplier` is a number (integer or float). `max_hit_points`, attribute scores, and the Toxicity Threshold are read by the caller through the Creatures domain and passed in. A fractional `Death Multiplier` lets a consuming project tune lethality without altering any Creature-side maximum.

## Responsibilities

### Owned by the Conditions domain

- Per-Creature mutable state: HP damage counters, Ability Damage, Temporary HP grant, Mana Spent, Magic Toxicity, Shock, Acid Counter, ordered list of Active Afflictions (each with its own `next_resolution_round`), ordered list of Active Effects.
- Damage absorption with worst-first Temporary HP draining.
- Heal Cascades on HP Damage and Ability Damage, with FIFO ordering of attributes.
- Single-grant Temporary HP replacement rule.
- Shock consumption with overflow persistence.
- Magic Toxicity Update: Toxicity Threshold, Toxicity Block, Toxicity Damage dispatch.
- Affliction inflict / resolve: Potency Save Penalty injection, Magnitude formula, Tier substitution, Potency evolution, removal at zero, Inflicter Tier accumulation, per-Affliction Next Resolution Round scheduling, due-affliction enumeration and bulk resolution.
- Active Effect storage with replace-by-Source-ID; stacking computed at lookup via *Get Modifiers*.
- Bulk removal by Source ID prefix.
- Acid Counter: per-Creature accumulation, halve-and-deal-Minor at turn start, automatic removal at zero.
- Mana operations: cost, restore, set.
- Natural Recovery: rolls HP, Ability Damage, Mana, Magic Toxicity forward by N Periods; Temporary HP clears.
- Named Effect dispatch with per-Mechanic Source IDs; raise on unknown names.
- Expiry sweep (*Clear Expired Effects*).
- Death Threshold check.
- Serialization round-trip with validation.

### Explicitly *not* owned here

- **What produces an Effect.** Spells, items, abilities — Conditions sees only opaque Source IDs and Tier values.
- **Damage calculation.** Damage Reduction, Damage Resilience, runtime bucketing, Damage Type Mechanics all run in the caller (Combat) before per-Severity counts reach *Apply Hit Point Damage*.
- **Saving Throw mechanics.** Conditions calls Dice Resolution; how the Creature's resistance translates into `dice_count` and `modifiers` is the caller's job. The Save Input shape is the contract.
- **Maximum HP, Mana Max, Toxicity attribute values.** Owned by Creatures; passed in when needed.
- **Current Hit Points.** Computed by Creatures. Conditions exposes the inputs but never the derived value.
- **Combat Pool size.** *Consume Shock* takes `max_consume` from the caller.
- **Game time.** Round numbers, current Recovery Tick counts, and the wall-clock meaning of one Recovery Tick are all the caller's concern.
- **Classification of an effect as positive vs. forced.** *Apply Magic Toxicity*'s `kind` parameter is caller-supplied; Conditions does not infer it.
- **Validating Bonus Types or Target Keys against any catalog.**

### Unassigned (no current owner)

- **Acid Counter wiring from damage application.** Conditions owns the Acid Counter, but Combat is the natural place to call *Apply Acid Damage* when acid damage lands. The wiring point is documented in `encounter_design.md` but the Damage Type Mechanic catalog entry is the contract.
- **Toxicity Source Kind classification at the spell / item layer.** Conditions takes a `positive` / `forced` flag from the caller; assigning that flag to each Magic-Toxicity-imposing source is the responsibility of whichever upstream domain (Abilities, Equipment, Combat) constructs the call. The classification rule is not pinned to a domain today.
