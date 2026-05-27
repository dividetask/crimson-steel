# Dice and Resolution Mechanics — Tests

Tests for the public entry points of the dice resolution domain. Multi-Roll behavior is tested in `check_resolution_tests.md`.

Unless a test specifies a different config, all tests use the values in `dice_resolution_config.yaml`:
- Die Size: 10
- Base Target Number: 6
- Minimum/Maximum Target Number: 3 / 9
- Minimum Dice Count: 6, Dice Count Range: 5 (so Maximum Dice Count = 10)
- Default Success Threshold: 2
- Default Fumble Threshold: 2
- Default `failure_modifier`: -1, `critical_modifier`: 2

Tests that depend on randomness (the actual values dice land on) state the *rolled* dice as input rather than calling the random source. An implementation should expose a seam (test-only injection or a deterministic random source) so tests can exercise specific dice patterns. Tests that don't depend on dice values use the input directly.

---

## Translate Skill Prowess into Roll inputs

**Prowess of zero gives the minimum.** When `prowess = 0`, the function returns `dice_count = 6` and `bonus_penalty = 0`. Nothing about Prowess of zero contributes a Bonus or Penalty.

**Prowess fitting within a single Range cycle.** When `prowess = 3`, the function returns `dice_count = 9` and `bonus_penalty = 0`. Three points of Prowess raise Dice Count by 3 above the Minimum.

**Prowess at exactly one full cycle.** When `prowess = 5`, the function returns `dice_count = 6` and `bonus_penalty = 1`. One full Range of Prowess produces one point of Bonus and resets Dice Count to the Minimum.

**Prowess overflowing into a Bonus with leftover.** When `prowess = 7`, the function returns `dice_count = 8` and `bonus_penalty = 1`. The first 5 Prowess complete one cycle (+1 Bonus, dice reset to Minimum); the remaining 2 raise Dice Count to 8.

**Prowess at two full cycles.** When `prowess = 10`, the function returns `dice_count = 6` and `bonus_penalty = 2`. Two full Ranges produce +2 Bonus.

**Negative Prowess wraps to maximum dice.** When `prowess = -1`, the function returns `dice_count = 10` and `bonus_penalty = -1`. One full cycle backward produces a Penalty and wraps Dice Count to the Maximum.

**Negative Prowess with leftover.** When `prowess = -2`, the function returns `dice_count = 9` and `bonus_penalty = -1`. The negative wrap produces -1 Bonus; the remainder lands at 9.

---

## Resolve a Roll with a Target Number

**A Roll with no modifiers and middling dice.** Given a Roll with `dice_count = 6`, no bonuses or penalties, no rerolls, no nudge, and dice that land as `[6, 6, 5, 1, 3, 7]`:
- TN = 6 (Base, no modifiers).
- Starting Value = 0.
- DoIS = (+1) + (+1) + 0 + (-1) + 0 + (+1) = +2.
- Critical Count = 0.
- Roll Outcome = `success` (DoIS ≥ Default Success Threshold of 2).

**Bonus and Penalty stacking.** Given a Roll with `bonus_penalty_list = [('A', +3), ('A', +1), ('A', -2), ('B', +2)]`:
- Per-Type stacking for Type A: highest positive is +3, lowest negative is -2. Both contribute. Type B contributes +2.
- TN Net Modifier = +3 − 2 + 2 = +3.
- TN = 6 − 3 = 3 (clamps at Minimum, no overflow).
- Starting Value contribution from this list = 0 (TN clamped exactly at the boundary).

**Bonus overflow into Starting Successes.** Given a Roll with `bonus_penalty_list = [('A', +5)]` and `starting_contribution = 1`:
- TN Net Modifier = +5.
- Candidate TN = 6 − 5 = 1, below Minimum of 3. Clamped to 3, with 2 points of overflow.
- Starting Value = 1 + 2 = 3.

**Penalty overflow into Starting Failures.** Given a Roll with `bonus_penalty_list = [('A', -5)]` and `starting_contribution = 0`:
- TN Net Modifier = −5.
- Candidate TN = 6 − (−5) = 11, above Maximum of 9. Clamped to 9, with 2 points of overflow.
- Starting Value = 0 − 2 = −2.

**Bonus and Penalty cancel out.** Given a Roll with `bonus_penalty_list = [('A', +20), ('B', -20)]`:
- TN Net Modifier = +20 − 20 = 0.
- TN = 6 (unchanged from Base).
- Starting Value contribution = 0. No overflow despite the large individual values.

**A Critical Success replaces the regular Success.** Given a Roll with one die landing on Die Size (10) and `critical_modifier = 2`: the die contributes +2 (the Critical contribution), not +3 (which would be Critical + regular Success stacking). Critical Count = 1.

**A Roll that ignores Failures cannot Fumble.** Given a Roll with `failure_modifier = 0` and dice that produce DoIS = −5: outcome is `failure`, not `fumble`. The Fumble check is suppressed when `failure_modifier == 0`.

**A reroll changes a Failure into a Success.** Given a Roll with `dice_count = 6`, `positive_reroll = (1, false)`, dice that land as `[1, 4, 5, 5, 5, 5]`, and the rerolled die landing on `8`: `final_dice = [8, 4, 5, 5, 5, 5]`. The Failure was the lowest non-Success and was selected.

**A nudge promotes a near-Success.** Given a Roll with `failure_modifier = 0`, `value_adjustment = (+1, false)`, and dice `[5, 5, 5, 5, 5, 1]`: the nudge targets a 5 (which becomes a Success at +1), not the 1 (which would still be 2 — a Neutral Result, no contribution change). Because Failures are ignored on this Roll, the 1→2 shift produces a delta of 0 (0 → 0); only the 5→6 shifts produce a positive delta (+1). Tie among the 5s → lowest index wins.

**Tied delta with a Failure prefers the lower-starting die.** Given a Roll with default `failure_modifier = -1`, `value_adjustment = (+1, false)`, and dice `[5, 5, 5, 5, 5, 1]`: the 1→2 shift moves contribution from -1 (Failure) to 0 (Neutral), a delta of +1. The 5→6 shifts each have delta +1 as well (0 → +1). Per the design's tie-break rule, the die that started lowest wins for a positive nudge; the nudge targets the 1.

**Max-mode nudge shifts every die.** Given a Roll with `value_adjustment = (+1, true)` and dice `[3, 5, 9, 10]`: `final_dice = [4, 6, 10, 10]`. Every die shifts; the 10 clamps in place.

**Reroll changes report per-position rerolled values.** Given a Roll with `dice_count = 4`, `positive_reroll = (1, false)`, dice `[1, 4, 6, 7]`, and the rerolled die landing on `8`: `reroll_changes = [8, null, null, null]`. The position of the rerolled die is preserved; unchanged dice are null.

**Nudge changes report only the affected position.** Given a Roll with `value_adjustment = (+1, false)` and dice `[5, 5, 5, 1]` at TN 6: the nudge targets index 0 (the first 5 promoted to a Success). `nudge_changes = [6, null, null, null]`. Other positions stay null.

---

## Resolve a Roll without a Target Number

**Ordering-only roll.** Given a Roll with `dice_count = 6`, no rerolls, no nudge, dice `[8, 5, 7, 2, 9, 4]`: the function returns `final_dice = [8, 5, 7, 2, 9, 4]` and a Dice Result String encoding the values sorted descending. With the default config (encoding "X" — unused since values 1–9 use digits), the string is `"987542"`.

**Reroll uses bottom-quartile threshold for positive.** With Die Size 10, the positive quartile threshold is `floor(10/4) + 1 = 3`. A positive reroll only rerolls dice with value `< 3` — that is, 1s and 2s. Given dice `[1, 2, 3, 4, 5, 6]` and `positive_reroll = (3, false)`: only the 1 and 2 are eligible. The reroll selects them in lowest-first order; the 3 stays untouched even though `positive_count = 3` was requested.

**Reroll uses top-quartile threshold for negative.** The negative quartile threshold is `10 - floor(10/4) = 8`. A negative reroll only rerolls dice with value `≥ 8`. Given dice `[6, 7, 8, 9, 10, 5]` and `negative_reroll = (3, false)`: the 8, 9, and 10 are eligible.

**Nudge favors making a Critical Success.** Given dice `[8, 9, 6, 4]` and `value_adjustment = (+1, false)`: positive nudge targets the die landing closest to Die Size (10). The 9 + 1 = 10 is exactly at Die Size; it wins. The 8 would land at 9 — also close, but 10 is closer.

**Nudge tied closeness picks the die furthest from the extreme.** Given dice `[7, 9]` and `value_adjustment = (+3, false)`: both nudges produce values at or past Die Size. The 9 → 12 clamps to 10 (distance 0); the 7 → 10 lands exactly at 10 (distance 0). Tied closeness; the 7 (further from Die Size) wins. Final dice = `[10, 9]`.

**Dice Result String encoding falls back to letters when configured encoding is too short.** With Die Size 12 and `Dice Result String Encoding: "X"` (length 1, but Die Size − 9 = 3): the configured string is too short, so the fallback `"ABCDEFGHIJKLMNOPQRSTUVWXYZ"` is used. Dice `[12, 11, 10, 9]` encode as `"CBA9"`.

---

## Classify a value against outcome thresholds

**A value at or above Default Success Threshold is a success.** Given `value = 2` and `can_fumble = true`: outcome = `success`. Given `value = 5`: outcome = `success`.

**A value at exactly Default Fumble Threshold negated is a fumble.** Given `value = -2` and `can_fumble = true`: outcome = `fumble`. The Fumble check is `≤ −Threshold`, so the boundary value qualifies.

**A value between the two thresholds is a failure.** Given `value = 0` and `can_fumble = true`: outcome = `failure`. Below Success, above Fumble.

**A negative value just shy of the Fumble Threshold is a failure.** Given `value = -1` and `can_fumble = true`: outcome = `failure`. The Fumble Threshold is 2, so values from -1 up to 1 are failures.

**`can_fumble = false` suppresses the Fumble outcome.** Given `value = -5` and `can_fumble = false`: outcome = `failure`, not `fumble`. The Fumble check is skipped entirely; only Success classification runs.

**`can_fumble = false` still allows Success.** Given `value = 3` and `can_fumble = false`: outcome = `success`. The flag only suppresses Fumble; Success is unaffected.

---

## Edge cases

**Empty `bonus_penalty_list`.** A Roll with no entries produces TN = Base Target Number and Starting Value = `starting_contribution`. No per-Type stacking, no TN Net Modifier, no overflow.

**Reroll count exceeds eligible dice.** Given `dice_count = 6`, all dice are Successes, and `positive_reroll = (5, false)`: no dice are rerolled. The positive slot only targets non-Successes; with none present, the slot does nothing regardless of count.

**Nudge at boundary.** Given a Roll with `value_adjustment = (+1, false)` and dice `[10]`: clamping prevents change. The single 10 is already at Die Size; +1 clamps back to 10. The targeting picks this die anyway (it's the only candidate), but the change is a no-op.

**Standalone nudge with no eligible improvement.** Given dice `[10, 10, 10]` and `value_adjustment = (+1, false)`: every die clamps. No die's value changes. The function reports an all-null `nudge_changes` list.
