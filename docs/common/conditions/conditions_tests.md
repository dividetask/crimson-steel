# Conditions — Tests

Tests for the public entry points of the Conditions domain.

Unless a test specifies otherwise, all tests use the values in `conditions_config.yaml`:
- Potency Divisor: 10
- Death Multiplier: 2.0
- Toxicity Threshold: Attribute `cha`, Tier Scaled `true`
- Toxicity Damage Severity: `major`
- Default Potency Per Success: 1
- Default Potency Per Failure: 1
- Default Potency Decay: `"tier"`
- Frequency Rounds: `{round: 1, minute: 10, hour: 600, day: 14400, month: 432000, year: 5256000}`
- Recovery Tick: 14400 rounds (one Day)
- Natural Recovery rates as configured (Slow/Fast tables for HP Heal Rate and Ability Heal Rate)

And the catalogs in `afflictions.yaml` and `effect_names.yaml` as shipped.

Severities follow the canonical order defined in `combat_glossary.md`: `[minor, moderate, major]`. Heal Cascades pour worst-first (Major → Moderate → Minor).

Test creatures are described by their starting Conditions State. A baseline Creature has all damage counters at zero, no Temporary HP, no Afflictions, no Active Effects, `mana_spent = 0`, `magic_toxicity = 0`, `shock = 0`, `acid_counter = 0` — except where a test overrides specific fields. Mana Max is supplied by the caller per API call; the tests state it explicitly when it matters.

Tests that depend on save Rolls state the resolved Roll's `dois` (Degree of Individual Success) directly rather than driving Dice Resolution end-to-end. The save's Outcome and `successes` / `failures` derive from `dois` as defined in `dice_resolution_design.md`.

---

## Apply Hit Point Damage

**Damage with no Temporary HP lands directly on the counters.** Given `temporary_hit_points = null` and `hp_damage = {minor: 0, moderate: 0, major: 0}`. *Apply Hit Point Damage* with `{minor: 2, moderate: 1, major: 0}`: `hp_damage` becomes `{minor: 2, moderate: 1, major: 0}`. The Temporary HP grant stays null.

**Temporary HP absorbs worst-first.** Given `temporary_hit_points = {amount: 5, source_id: "spell:aid:42", ends_on_round: null}` and zero damage. *Apply Hit Point Damage* with `{minor: 0, moderate: 0, major: 3}`: Temporary HP absorbs 3 Major, leaving the pool at 2 and the damage counters untouched. No Source ID is returned (the grant is still active).

**Pool depletion clears the grant.** Given `temporary_hit_points = {amount: 5, source_id: "spell:aid:42"}` and zero damage. *Apply Hit Point Damage* with `{minor: 0, moderate: 0, major: 5}`: Temporary HP absorbs all 5 Major. The grant clears to null; the returned `displaced_source_id` is `"spell:aid:42"`. Damage counters stay at zero.

**Per-category absorption does not redistribute.** Given `temporary_hit_points = {amount: 3, source_id: "s"}` and zero damage. *Apply Hit Point Damage* with `{minor: 0, moderate: 5, major: 1}`: Temporary HP absorbs 1 Major and then 2 Moderate, leaving 3 Moderate on the counter. The pool was a running counter consumed worst-first, not a per-category cap.

**Damage exceeding the pool splits across categories.** Given `temporary_hit_points = {amount: 2, source_id: "s"}` and zero damage. *Apply Hit Point Damage* with `{minor: 1, moderate: 0, major: 4}`: Major is hit first — Temporary HP absorbs 2 of 4 Major, leaving 2 Major on the counter and 1 Minor on its counter. The pool drops to zero and the grant clears.

**Zero damage is a no-op.** *Apply Hit Point Damage* with `{minor: 0, moderate: 0, major: 0}`: no counters change. If a Temporary HP grant exists it is preserved.

---

## Apply Heal

**Heal at one Severity removes from that counter only.** Given `hp_damage = {minor: 3, moderate: 2, major: 1}`. *Apply Heal* with `{minor: 2, moderate: 0, major: 0}`: counters become `{minor: 1, moderate: 2, major: 1}`. The 2 points apply to Minor; nothing cascades.

**Cascade flows worst → best.** Given `hp_damage = {minor: 1, moderate: 0, major: 1}`. *Apply Heal* with `{minor: 0, moderate: 0, major: 3}`: Major heals 1 (capped at the counter), leaving 2 points to cascade. Moderate has zero damage, so all 2 flow into Minor. Minor heals 1 (capped). The final counters: `{minor: 0, moderate: 0, major: 0}`. The remaining 1 point past Minor is wasted.

**Excess past Minor is wasted.** Given `hp_damage = {minor: 1, moderate: 0, major: 0}`. *Apply Heal* with `{minor: 5, moderate: 0, major: 0}`: Minor heals 1 (capped). The remaining 4 points are discarded. Returned: `{minor: 1, moderate: 0, major: 0}`.

**Temporary HP is unaffected by Apply Heal.** Given `temporary_hit_points = {amount: 4, source_id: "s"}` and `hp_damage = {minor: 2}`. *Apply Heal* with `{minor: 2}`: Minor counter becomes 0; Temporary HP stays at 4 with the same Source ID.

**Apply Heal does not impose Magic Toxicity.** Given a Creature with `magic_toxicity = 0`. *Apply Heal* with any pool sizes: `magic_toxicity` stays 0. Magic-Toxicity-imposing healing (potions, magical healing) must call *Apply Magic Toxicity* separately in the caller.

---

## Apply Ability Damage / Apply Ability Heal

**Ability Damage preserves attribute insertion order.** Given no prior Ability Damage. *Apply Ability Damage* `("str", {minor: 2})`, then `("dex", {minor: 1})`: `ability_damage[minor]` is the ordered map `[("str", 2), ("dex", 1)]`. A subsequent *Apply Ability Damage* `("str", {minor: 1})` increments `str` in place to 3; the order is `[("str", 3), ("dex", 1)]`.

**Ability Heal pops FIFO within a Severity.** Given `ability_damage[minor] = [("str", 2), ("dex", 1)]`. *Apply Ability Heal* with `{minor: 2}`: `str` is first in insertion order, so it absorbs both points. The result: `[("str", 0), ("dex", 1)]`, with the zero entry pruned to `[("dex", 1)]`.

**Ability Heal cascade flows across Severities.** Given `ability_damage[major] = [("con", 1)]` and `ability_damage[minor] = [("wis", 2)]`. *Apply Ability Heal* with `{minor: 0, moderate: 0, major: 3}`: Major heals 1 (clearing `con`), 2 cascade to Moderate (no damage there), then to Minor where `wis` absorbs 2.

**Pruning zero entries keeps order of survivors.** Given `ability_damage[minor] = [("str", 1), ("dex", 1), ("con", 1)]`. *Apply Ability Heal* with `{minor: 1}`: `str` heals to 0 and is pruned. The remaining order is `[("dex", 1), ("con", 1)]` — `dex` did not move forward in insertion order despite `str` being removed.

---

## Apply Temporary Hit Points

**A first grant on an empty slot is accepted.** Given `temporary_hit_points = null`. *Apply Temporary Hit Points* with `amount = 6, source_id = "spell:aid:42", ends_on_round = null`: returns `{accepted: true, displaced_source_id: null}`. The slot now holds the grant.

**A strictly higher grant replaces the existing one.** Given `temporary_hit_points = {amount: 4, source_id: "spell:aid:7"}`. *Apply Temporary Hit Points* with `amount = 6, source_id = "spell:aid:42"`: returns `{accepted: true, displaced_source_id: "spell:aid:7"}`. The slot holds the new grant; the previous absorbed pool is discarded.

**An equal grant is rejected.** Given `temporary_hit_points = {amount: 4, source_id: "spell:aid:7"}`. *Apply Temporary Hit Points* with `amount = 4, source_id = "spell:aid:42"`: returns `{accepted: false, displaced_source_id: null}`. The existing grant is preserved unchanged. Equality is rejection — there is no information gained from swapping the Source ID.

**A lower grant is rejected.** Given `temporary_hit_points = {amount: 4, source_id: "s1"}`. *Apply Temporary Hit Points* with `amount = 3, source_id = "s2"`: returns `{accepted: false, displaced_source_id: null}`. The slot is unchanged.

**A zero-or-negative grant clears the slot.** Given `temporary_hit_points = {amount: 4, source_id: "s1"}`. *Apply Temporary Hit Points* with `amount = 0, source_id = "s2"`: returns `{accepted: true, displaced_source_id: "s1"}`. The slot is now null.

---

## Consume Shock

**Consumption returns the smaller of shock and max_consume.** Given `shock = 3`. *Consume Shock* with `max_consume = 5`: returns 3. `shock` becomes 0.

**Excess Shock persists.** Given `shock = 7`. *Consume Shock* with `max_consume = 4`: returns 4. `shock` becomes 3 — the surplus persists until subsequent calls drain it.

**Zero Shock is a no-op.** Given `shock = 0`. *Consume Shock* with `max_consume = 10`: returns 0. `shock` stays at 0.

**Zero max_consume returns zero without changing Shock.** Given `shock = 5`. *Consume Shock* with `max_consume = 0`: returns 0. `shock` stays at 5.

---

## Apply Magic Toxicity

**A positive effect below threshold applies.** Given `magic_toxicity = 4`, `charisma = 5`, `tier = 2`: Toxicity Threshold = `floor(5 × 2) = 10`. *Apply Magic Toxicity* with `amount = 3, kind = positive`: returns `{accepted: true, charisma_damage: 0}`. `magic_toxicity` becomes 7. No Charisma damage (started and ended below threshold).

**A positive effect that crosses the threshold deals damage for the overshoot.** Given `magic_toxicity = 8`, `charisma = 5`, `tier = 2` → threshold 10. *Apply Magic Toxicity* with `amount = 5, kind = positive`: not blocked (pre = 8 ≤ 10). New `magic_toxicity = 13`. Charisma damage = `max(0, 13−10) − max(0, 8−10) = 3 − 0 = 3`. Returns `{accepted: true, charisma_damage: 3}`. 3 points of Major Charisma Ability Damage are dispatched via *Apply Ability Damage*.

**Toxicity Block rejects a positive effect when current strictly exceeds threshold.** Given `magic_toxicity = 11`, `charisma = 5`, `tier = 2` → threshold 10. *Apply Magic Toxicity* with `amount = 4, kind = positive`: returns `{accepted: false, charisma_damage: 0}`. `magic_toxicity` stays at 11. The caller is expected to abort the positive effect that triggered the call.

**A positive effect with current exactly at threshold goes through.** Given `magic_toxicity = 10`, threshold 10, `amount = 1, kind = positive`: not blocked (10 is not strictly greater than 10). New `magic_toxicity = 11`. Charisma damage = `max(0, 11−10) − 0 = 1`. Returns `{accepted: true, charisma_damage: 1}`.

**Forced toxicity is never blocked.** Given `magic_toxicity = 25`, threshold 10, `amount = 4, kind = forced`. New `magic_toxicity = 29`. Charisma damage = `max(0, 29−10) − max(0, 25−10) = 19 − 15 = 4` (the entire increase lands above threshold). Returns `{accepted: true, charisma_damage: 4}`.

**Toxicity Threshold with Tier Scaled false uses the attribute alone.** Config override `Toxicity Threshold.Tier Scaled: false`. Given `charisma = 9, tier = 3`: threshold = `floor(9 × 1) = 9`, not `27`.

**Tier 0 uses the 0.5 substitution.** Given `charisma = 8, tier = 0`, Tier Scaled true: threshold = `floor(8 × 0.5) = 4`.

**Magic Toxicity counter never goes negative.** Given `magic_toxicity = 2`, *Apply Magic Toxicity* with `amount = 0`: returns `{accepted: true, charisma_damage: 0}` and the counter stays at 2 (the call is structurally a no-op).

---

## Inflict Affliction

**Inflicting a new Affliction creates an entry at Potency 1 and schedules the next resolution.** Given no Afflictions, `current_round = 100`. *Inflict Affliction* `("bleeding", inflicter_tier = 2, current_round = 100)`: `bleeding` is created with `potency = 1`, `inflicting_tier = 2`, `next_resolution_round = 101` (round-frequency default; 100 + Frequency Rounds.round). It appears last in the order.

**Inflicting without current_round leaves the schedule null.** *Inflict Affliction* `("bleeding", inflicter_tier = 2)` (no `current_round`): entry created with `next_resolution_round = null`. The caller is responsible for any scheduling.

**Inflicting an existing Affliction accumulates Potency and leaves the schedule untouched.** Given `bleeding = {potency: 3, inflicting_tier: 1, next_resolution_round: 47}`. *Inflict Affliction* `("bleeding", inflicter_tier = 2, delta = 2, current_round = 80)`: `bleeding` becomes `{potency: 5, inflicting_tier: 2, next_resolution_round: 47}`. Re-inflicting does not reschedule.

**Inflicter Tier never decreases while the entry lives.** Given `bleeding = {potency: 1, inflicting_tier: 4}`. *Inflict Affliction* `("bleeding", inflicter_tier = 1)`: `potency` becomes 2; `inflicting_tier` stays at 4.

**Unknown Affliction names raise.** *Inflict Affliction* `("not_a_real_affliction", inflicter_tier = 0)`: raises an error. The Conditions State is unchanged.

**Day-frequency Affliction uses the configured day round count.** Given `current_round = 100` and `sleeping_sickness` (`save_frequency: "day"`). *Inflict Affliction* with `current_round = 100`: `next_resolution_round = 100 + 14400 = 14500`.

**Re-inflict after decay re-inserts at the end with fresh scheduling.** Given two Active Afflictions `[bleeding, common_venom]`. After a *Resolve Affliction* resolution decays `bleeding` to zero it is deleted; order becomes `[common_venom]`. A subsequent *Inflict Affliction* `("bleeding", inflicter_tier = 1, current_round = 200)` appends at the end: `[common_venom, bleeding]`, with the new `bleeding`'s `next_resolution_round = 201`.

---

## Resolve Affliction

**A clean save decays Potency by the default decay.** Given a Tier-3 Creature with `bleeding = {potency: 3, inflicting_tier: 1, next_resolution_round: 47}` and a save resolving to `dois = 0`. Decay `"tier"` = 3. New `potency = max(0, 3 − 3) = 0`. The entry is deleted.

**A failure raises Potency.** Given a Tier-1 Creature with `common_venom = {potency: 2}` (uses global defaults) and a save resolving to `dois = -1` (failures = 1). Decay = 1; Per Failure delta = 1. Net delta = 0. New `potency = 2`. Magnitude = `1 + floor(2 / 10) = 1`. Net Magnitude = 1. 1 point of Minor HP damage is dealt.

**A success reduces Potency and the effect's Net Magnitude.** Given a Tier-2 Creature with `bleeding = {potency: 12}` (Per Success `"tier"`, Per Failure 0) and a save resolving to `dois = 1`. Decay = 2; Per Success delta = `floor(1 × 2) = 2`. Net delta = −4. New `potency = 8`. Magnitude pre-save = `1 + floor(12 / 10) = 2`. Net Magnitude = `max(0, 2 − 1) = 1`. 1 point of Minor HP damage is dealt.

**A fully-saved resolution is a no-op for the effect.** Given Magnitude 1 and `successes = 3`: Net Magnitude = 0. No HP damage, no Ability Damage, no Named Effect — but Potency still evolves.

**Potency Save Penalty is appended as a Competency entry.** Given `bleeding = {potency: 25}`. Conditions appends `("Competency", −2)` (per the Potency Divisor of 10) to the Save Input's `modifiers` list **alongside** any existing Competency entry — Dice Resolution's per-type stacking handles "lowest negative wins."

**Resolution reschedules a survivor when current_round is supplied.** Given a Tier-1 Creature with `common_venom = {potency: 5, next_resolution_round: 100}` and a save resolving to `dois = -1`. Potency evolves to 5 (decay = 1, +1 failure). The Affliction survives. *Resolve Affliction* with `current_round = 100`: `next_resolution_round = 100 + 1 = 101` (round frequency).

**Resolution does not reschedule when current_round is omitted.** Same Creature. *Resolve Affliction* with no `current_round`: potency evolves as above but `next_resolution_round` stays at 100.

**A removed Affliction discards its scheduling.** Given `bleeding = {potency: 1, next_resolution_round: 47}` and a Tier-3 save resolving to `dois = 0`. Potency decays to 0; the entry is removed. The `next_resolution_round` is discarded along with it.

**Tier substitution applies floor to Tier 0.** Given a Tier-0 Creature with `bleeding = {potency: 1}` and a save resolving to `dois = 1`. Per Success `"tier"` substitutes 0.5; `floor(1 × 0.5) = 0`. Decay `"tier"` substitutes 0.5; `floor(0.5) = 0`. Net delta = 0. New `potency = 1`. The entry survives despite a successful save.

---

## List Pending Afflictions / Resolve Due Afflictions

**Pending list returns due Afflictions in insertion order.** Given three Active Afflictions:
- `bleeding`: `next_resolution_round = 100`
- `common_venom`: `next_resolution_round = 105`
- `sleep_venom`: `next_resolution_round = 100`

*List Pending Afflictions* with `current_round = 100`: returns `[bleeding, sleep_venom]` (insertion order; `common_venom` not yet due).

**Pending list filters out Afflictions with null scheduling.** Given two Active Afflictions, one with `next_resolution_round = null` and the other with `next_resolution_round = 50`. *List Pending Afflictions* with `current_round = 100`: returns only the second.

**Resolve Due Afflictions dispatches per-Affliction Save Inputs.** Given two due Afflictions `[bleeding, common_venom]` and a `save_input_provider` callable. *Resolve Due Afflictions* with `current_round = 100`: calls `save_input_provider("bleeding")`, resolves bleeding, then calls `save_input_provider("common_venom")`, resolves common_venom. Both survivors are rescheduled to `next_resolution_round = 101`. The returned list contains the two *Resolve Affliction* result structs in order.

**Resolve Due Afflictions sees Afflictions inflicted mid-call.** Given one due Affliction `bleeding`, whose effect dispatches to a callback that inflicts `common_venom` with `current_round = 100`. *Resolve Due Afflictions* with `current_round = 100`: resolves `bleeding`, then sees the newly-due `common_venom` and resolves it as well in the same call. Behavior matches a manual one-by-one loop that re-reads the pending list each iteration.

**Pending list is empty when nothing is due.** Given a Conditions Instance with two Active Afflictions, both scheduled in the future. *List Pending Afflictions* with `current_round` before both: returns `[]`. *Resolve Due Afflictions* returns `[]`.

---

## Apply Effect / Get Modifiers

**Apply Effect appends a new entry.** Given no Active Effects. *Apply Effect* with `target_key = "str", bonus_type = "Enhancement", amount = +2, source_id = "spell:bull_strength:7"`: `effects` has one entry. The omitted `ends_on_round` defaults to null and the omitted `metadata` defaults to `{}`.

**Apply Effect with the same Source ID overwrites in place.** Given one Active Effect with `source_id = "spell:bull_strength:7", amount = +2`. *Apply Effect* with the same Source ID and `amount = +4`: the existing entry is updated to `amount = +4`; no new entry is appended.

**Get Modifiers returns the largest positive and most-negative amount per type.** Given `effects = [`
  `(target_key: "str", type: "Enhancement", amount: +2, source_id: "a"),`
  `(target_key: "str", type: "Enhancement", amount: +4, source_id: "b"),`
  `(target_key: "str", type: "Enhancement", amount: −1, source_id: "c"),`
  `(target_key: "str", type: "Circumstance", amount: +1, source_id: "d")` `]`.
*Get Modifiers* for `target_key = "str"`: returns `[("Enhancement", +4), ("Enhancement", −1), ("Circumstance", +1)]`. The `amount = +2` Enhancement entry is shadowed by the `+4`; the lone Penalty on Enhancement contributes as-is; Circumstance has only a positive Amount so no negative entry is emitted.

**Get Modifiers filters by target_key.** With effects targeting `"str"` and `"dex"`: *Get Modifiers* for `"dex"` returns only the `"dex"` entries.

**Get Modifiers respects expiry when current_round is supplied.** Given an Active Effect with `ends_on_round = 5`. *Get Modifiers* with `current_round = 4`: the entry contributes. With `current_round = 5`: the entry is filtered out (expiry boundary is inclusive). With no `current_round` argument: the entry contributes regardless.

**Removing a stronger Effect promotes the survivor at lookup time.** Given two Enhancement positives on `"str"` of amounts +4 and +2. *Get Modifiers* returns the +4. After removing the source of the +4 (via *Remove Effects by Prefix* or a fresh *Apply Effect* with the same Source ID at amount 0), the next *Get Modifiers* returns the +2.

---

## Remove Effects by Prefix

**Prefix match removes every matching Effect.** Given `effects` containing four entries with `source_id` values `["equipment:char_42:belt:body", "equipment:char_42:ring:hand", "equipment:char_99:cloak:body", "spell:aid:7"]`. *Remove Effects by Prefix* with `prefix = "equipment:char_42:"`: removes the first two entries. Returns those two entries in their original order. The remaining `effects` is `[char_99's cloak, spell:aid:7]`.

**Prefix match is literal — no globbing.** Given `effects` with Source IDs `["equipment:char_42", "equipment:char_42:belt"]`. *Remove Effects by Prefix* with `prefix = "equipment:char_42:"`: removes only the second. The first does not start with that exact string (missing the trailing colon).

**No matching entries returns an empty list.** Given `effects` with `source_id = "spell:aid:7"` only. *Remove Effects by Prefix* with `prefix = "equipment:"`: returns `[]`. `effects` is unchanged.

---

## Acid Counter

**Apply Acid Damage adds to the counter.** Given `acid_counter = 0`. *Apply Acid Damage* with `amount = 7`: counter becomes 7. Returns 7.

**Zero-or-negative apply is a no-op.** Given `acid_counter = 5`. *Apply Acid Damage* with `amount = 0`: counter stays at 5; returns 5. With `amount = -3`: same — counter stays at 5.

**Resolve Acid Turn Start halves then deals.** Given `acid_counter = 7`. *Resolve Acid Turn Start*: counter becomes `floor(7 / 2) = 3`; the Creature takes 3 Minor HP damage; the counter persists at 3. Returns 3.

**Counter dropping to zero is removed.** Given `acid_counter = 1`. *Resolve Acid Turn Start*: counter becomes `floor(1 / 2) = 0`; no Minor damage is dealt (zero is a no-op against the counters); counter is cleared.

---

## Mana

**Apply Mana Cost increments mana_spent up to Mana Max.** Given `mana_spent = 0, mana_max = 10`. *Apply Mana Cost* with `amount = 3, mana_max = 10`: returns 3; `mana_spent` becomes 3.

**Mana cost greater than available returns the actual spend.** Given `mana_spent = 8, mana_max = 10`. *Apply Mana Cost* with `amount = 5, mana_max = 10`: returns 2 (only 2 Mana were available); `mana_spent` becomes 10.

**Restore Mana decrements mana_spent toward zero.** Given `mana_spent = 5`. *Restore Mana* with `amount = 3`: returns 3; `mana_spent` becomes 2.

**Restore Mana floors at zero.** Given `mana_spent = 2`. *Restore Mana* with `amount = 5`: returns 2 (only 2 were spent and could be restored); `mana_spent` becomes 0.

**Set Mana Spent clamps to `[0, mana_max]`.** Given `mana_spent = 5`. *Set Mana Spent* with `amount = 100, mana_max = 12`: `mana_spent` becomes 12. *Set Mana Spent* with `amount = -3, mana_max = 12`: `mana_spent` becomes 0.

---

## Apply Natural Recovery

**Slow mode heals minor at the configured slow rate.** Given a Tier-1 Creature with `hp_damage = {minor: 5, moderate: 5, major: 1}`. *Apply Natural Recovery* with `recovery_ticks = 1, mode = slow, mana_max = 8, magic_toxicity_attribute_score = 4`: Heal Rate Tier 1 Minor slow `[1, 1]` → `floor((1 × 1) / 1) = 1` Minor healed. Moderate slow `[1, 7]` → `floor((1 × 1) / 7) = 0`. Major slow `[1, 30]` → 0. Final HP damage: `{minor: 4, moderate: 5, major: 1}`.

**Fast mode doubles the slow rate.** Same Creature, same starting damage. *Apply Natural Recovery* with `recovery_ticks = 1, mode = fast`: Minor fast `[2, 1]` → `floor((2 × 1) / 1) = 2` Minor healed. Moderate fast `[2, 7]` → 0. Major fast `[2, 30]` → 0. Final: `{minor: 3, moderate: 5, major: 1}`.

**Multiple Recovery Ticks accumulate.** Given Tier 1, `hp_damage = {minor: 10}`. *Apply Natural Recovery* with `recovery_ticks = 7, mode = slow`: Minor `[1, 1]` → `floor((1 × 7) / 1) = 7` healed. Final: `{minor: 3}`.

**Recovery Tick count smaller than tick_length heals zero.** Given Tier 0, `hp_damage = {minor: 5}`. *Apply Natural Recovery* with `recovery_ticks = 6, mode = slow`: Minor `[1, 7]` → `floor((1 × 6) / 7) = 0`. No healing — partial progress is not retained for a future call.

**Recovery Tick count equal to tick_length heals one.** Same setup, `recovery_ticks = 7`: `floor((1 × 7) / 7) = 1` Minor healed.

**Tier 0 Major is zero in both modes.** Given Tier 0, `hp_damage = {major: 5}`. *Apply Natural Recovery* with `recovery_ticks = 365, mode = fast`: Major `[0, 1]` → 0 healed. No matter how long a Tier 0 creature rests, the configured rate prevents any Major recovery.

**Heal caps at the current counter.** Given Tier 5, `hp_damage = {minor: 2}`. *Apply Natural Recovery* with `recovery_ticks = 1, mode = fast`: Minor `[10, 1]` would heal 10, but the counter is 2 — capped. Final: `{minor: 0}`.

**Mana restored by floor(mana_max / divisor) per Recovery Tick.** Given `mana_spent = 8, mana_max = 12`, Mana Per Recovery Tick Divisor = 4. *Apply Natural Recovery* with `recovery_ticks = 2`: per-Recovery-Tick = `floor(12 / 4) = 3`. Restored = `3 × 2 = 6`. New `mana_spent = max(8 − 6, 0) = 2`.

**Magic Toxicity decays by floor(attr / divisor) per Recovery Tick.** Given `magic_toxicity = 10`, `magic_toxicity_attribute_score = 9`, Magic Toxicity Per Recovery Tick Divisor = 4. *Apply Natural Recovery* with `recovery_ticks = 3`: per-Recovery-Tick decay = `floor(9 / 4) = 2`. Total decay = 6. New `magic_toxicity = max(0, 10 − 6) = 4`.

**Temporary HP clears regardless of duration.** Given `temporary_hit_points = {amount: 8, source_id: "s", ends_on_round: null}`. *Apply Natural Recovery* with any positive `recovery_ticks`: the grant is cleared to null. Permanent grants are not immune to natural-recovery clearing.

**Ability Damage heals FIFO across attributes.** Given Tier-1, `ability_damage[minor] = [("str", 2), ("dex", 1)]`. Ability Heal Rate Tier 1 Minor slow `[1, 7]`. *Apply Natural Recovery* with `recovery_ticks = 7, mode = slow`: `floor((1 × 7) / 7) = 1` Minor heal point. `str` (FIFO) absorbs it. Result: `[("str", 1), ("dex", 1)]`.

---

## Apply Named Effect

**Modifier mechanics are stored as Active Effects with per-mechanic Source IDs.** *Apply Named Effect* with `name = "dazzled", source_id = "spell:glitterdust:7", ends_on_round = 12`: looks up `dazzled` in `effect_names.yaml`, finds one `modifier` Mechanic (Circumstance Bonus Type, amount −1, applies to `[dex_checks, wis_checks, casting_checks]`). One Active Effect is appended (or replaced) with `bonus_type = "Circumstance"`, `amount = −1`, `source_id = "spell:glitterdust:7:0"`. The `applies_to` tag list is stored on the entry as the Target Key context.

**Unknown Effect Names raise.** *Apply Named Effect* with `name = "not_a_real_effect"`: raises an error. No Active Effects are added.

**Re-applying the same Effect Name with the same Source ID overwrites every Mechanic slot.** Given `paralyzed` already applied with `source_id = "x"` (Mechanics 0 and 1). *Apply Named Effect* with `name = "paralyzed", source_id = "x"` again: the entries at `"x:0"` and `"x:1"` are overwritten in place; nothing is duplicated.

**Affliction-dispatched named effects use a deterministic Source ID.** When *Resolve Affliction* fires on `ghoul_paralysis` and dispatches to *Apply Named Effect*, the Source ID is `"affliction:ghoul_paralysis"`. A later re-resolution of the same Affliction overwrites the same slots.

---

## Clear Expired Effects

**Active Effects past their expiry are removed.** Given `effects` containing entries with `ends_on_round` values `[3, 5, null, 10]`. *Clear Expired Effects* with `current_round = 5`: removes the entries with `ends_on_round` 3 and 5 (boundary inclusive). The entry with `null` and the entry with 10 remain.

**Expired Temporary HP is cleared and its pool lost.** Given `temporary_hit_points = {amount: 6, source_id: "s", ends_on_round: 4}`. *Clear Expired Effects* with `current_round = 4`: the grant clears to null. The 6 absorbed-pool points are discarded (no rebate).

**Permanent entries are never cleared by expiry.** Given an Active Effect with `ends_on_round = null`. *Clear Expired Effects* with any `current_round`: the entry stays.

---

## Dead?

**HP track triggers death at the threshold.** Given `max_hit_points = 20`, Death Multiplier = 2.0, and `hp_damage` summing to 40 across all Severities. *Dead?*: returns `true`. With `hp_damage` summing to 39: returns `false`.

**Fractional Death Multiplier scales the threshold.** Config override `Death Multiplier: 1.5`. Given `max_hit_points = 20`: HP threshold = `floor(1.5 × 20) = 30`. *Dead?* returns `true` at `hp_damage` summing to 30, `false` at 29.

**Any single attribute crossing the threshold triggers death.** Given `attribute_score("str") = 5`, Death Multiplier = 2.0, and `ability_damage` summing 10 against `str` across Severities. *Dead?*: returns `true`. Other attributes are below their thresholds — the rule is "any single attribute".

**Toxicity track triggers death at the threshold.** Given a precomputed Toxicity Threshold of 4, Death Multiplier = 2.0, and `magic_toxicity = 8`. *Dead?*: returns `true`. At `magic_toxicity = 7`: returns `false`.

**Death triggers on the first track to hit.** Given a Creature with HP track at 90% of its threshold and Toxicity at the threshold. *Dead?*: returns `true`. The check is a disjunction over the three tracks.

---

## Serialization

**Round-trip preserves field shapes.** Given a populated Conditions State (some HP damage, two Active Afflictions with `next_resolution_round` set, one Temporary HP grant, three Active Effects, non-zero Acid Counter and Shock). *Save State* produces a dict; *Load State* on the dict restores an equivalent instance. Iteration order of `ability_damage`, `afflictions`, and `effects` is preserved.

**Load State rejects malformed input.** Given a state dict with `hp_damage.minor = -1` or a Severity key not present in `Severities`: *Load State* raises rather than silently coercing. The previous in-memory state is left unchanged.

**Load State accepts a missing next_resolution_round.** A serialized Active Affliction without `next_resolution_round` (or with `next_resolution_round: null`) loads with that field null. Pending Afflictions / Resolve Due Afflictions ignore it until the caller schedules it.

**Load State fills defaults for omitted Conditions State fields.** Given the input dict `{}`: *Load State* produces an instance with `hp_damage` empty (all Severity counters treated as zero), `ability_damage` empty, `temporary_hit_points = null`, `mana_spent = 0`, `magic_toxicity = 0`, `shock = 0`, `acid_counter = 0`, `afflictions` empty, `effects` empty. Every field has a documented default; an empty dict represents a Creature with no Conditions state.

**Load State fills defaults for omitted Active Effect fields.** A serialized Active Effect that omits `ends_on_round` and `metadata` loads with `ends_on_round = null` (permanent) and `metadata = {}`.

**Load State fills defaults for omitted Temporary HP Grant fields.** A serialized Temporary HP Grant that omits `ends_on_round` loads with `ends_on_round = null` (permanent until explicitly removed).
