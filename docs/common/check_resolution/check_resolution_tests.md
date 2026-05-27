# Check Resolution — Tests

Tests for the public entry points of the check resolution domain. Single-Roll behavior is tested in `dice_resolution_tests.md`.

Unless a test specifies a different config, all tests use the values in `dice_resolution_config.yaml`:
- Die Size: 10
- Base Target Number: 6
- Minimum/Maximum Target Number: 3 / 9
- Minimum Dice Count: 6, Dice Count Range: 5 (so Maximum Dice Count = 10)
- Default Success Threshold: 2
- Default Fumble Threshold: 2
- Default `failure_modifier`: -1, `critical_modifier`: 2

Tests that depend on randomness state the *rolled* dice as input; an implementation should expose a seam for deterministic injection.

---

## Compute Check parameters

**A solo Check has no propagation.** Given `supporting_roll_list = [Roll{ bonus_penalty_list: [('A', +2)] }]` and an empty `opposing_roll_list`: the supporting result is computed exactly as if the Roll had been passed to dice resolution directly. TN = 4, Starting Value = 0. No inversion applied (no opposing side to propagate from).

**Initiating receives inversions from every Opposing Roll.** Given a Supporting Roll with `bonus_penalty_list = [('A', +1)]` and two Opposing Rolls with `[('B', +2)]` and `[('B', +1)]` respectively: the Initiating Roll's effective list is `[('A', +1), ('B', -2), ('B', -1)]`. Per-Type stacking on Type B keeps only the lowest negative (-2). TN Net Modifier = +1 − 2 = -1. TN = 6 − (−1) = 7.

**Defending receives inversions from every Supporting Roll.** Given two Supporting Rolls with `[('A', +3)]` and `[('A', +1)]`, plus a Defending Roll with `[('B', +2)]`: the Defending Roll's effective list is `[('B', +2), ('A', -3), ('A', -1)]`. Per-Type stacking on Type A keeps only the lowest negative (-3). TN Net Modifier = +2 − 3 = -1. TN = 6 − (−1) = 7.

**Non-lead Supporting Rolls receive only the Defender's inversion.** Given two Supporting Rolls (lead has `[('A', +5)]`, second has `[]`) and a Defending Roll with `[('B', +2)]`: the second Supporting Roll's effective list is `[('B', -2)]` — it receives the Defender's inversion but not the lead's. TN Net Modifier = −2. TN = 6 − (−2) = 8.

**Non-lead Opposing Rolls receive only the Initiator's inversion.** Symmetric to the above: a non-Defending Opposing Roll's effective list contains only the inverted entries from the Initiating Roll.

---

## Resolve a Check

**A solo Check produces a Degree of Success equal to its Roll's DoIS.** Given a single Supporting Roll with no modifiers and dice that produce DoIS = +3, no Opposing Rolls: `degree_of_success = +3`. Check Outcome = `success` (≥ Default Success Threshold of 2).

**An opposed Check subtracts Opposing DoIS.** Given a Supporting Roll producing DoIS = +5 and a Defending Roll producing DoIS = +2: `degree_of_success = 5 − 2 = +3`. Check Outcome = `success`.

**Multiple Supporting Rolls aggregate.** Given three Supporting Rolls producing DoIS = +2, +1, and -1, no Opposing: `degree_of_success = 2 + 1 + (−1) = +2`. Check Outcome = `success`.

**Multiple Opposing Rolls aggregate.** Given Supporting DoIS = +4 and two Opposing Rolls producing +2 and +3: `degree_of_success = 4 − (2 + 3) = -1`. Check Outcome = `failure`.

**A Check with strongly negative Degree of Success Fumbles.** Given Supporting DoIS = -3 and no Opposing Rolls: `degree_of_success = -3`. Check Outcome = `fumble` (≤ −Default Fumble Threshold of 2).

**Check-level Fumble fires regardless of per-Roll `failure_modifier`.** Given a single Supporting Roll with `failure_modifier = 0` (the Roll's own outcome is `failure`, never `fumble`) and dice that produce DoIS = -3: the Check's `degree_of_success = -3` and Check Outcome = `fumble`. The Roll-level Fumble suppression rule does not propagate to the Check level.

**An opposed Check that nets to zero is a failure.** Given Supporting DoIS = +3 and Opposing DoIS = +3: `degree_of_success = 0`. Check Outcome = `failure` (below Success Threshold, above Fumble Threshold).

**Per-Roll results are returned alongside the aggregate.** A caller resolving a Check with two Supporting and one Opposing Roll receives `supporting_results` (length 2), `opposing_results` (length 1), `degree_of_success`, and `outcome`. Each per-Roll result includes `final_dice`, `reroll_changes`, `nudge_changes`, etc., for callers that render intermediate state.

---

## Roll and Sort

**Sort produces a permutation index.** Given three Rolls whose Dice Result Strings come out as `"986"`, `"987"`, and `"984"`: `order = [1, 0, 2]` — index 1 (`"987"`) is highest, then 0 (`"986"`), then 2 (`"984"`).

**Ties break by original list index.** Given three Rolls whose Dice Result Strings are all `"754"`: `order = [0, 1, 2]`. Earlier indices win ties.

**Roll and Sort skips propagation entirely.** Given a list of Rolls each with non-empty `bonus_penalty_list`: those entries are ignored. The dice resolution no-TN entry point doesn't read `bonus_penalty_list`, and Check Resolution does not apply cross-side propagation here.

---

## Edge cases

**Empty supporting list.** Calling Resolve a Check with `supporting_roll_list = []` is invalid. Validation is unassigned (per the design); behavior is implementation-defined until specified.

**Single Supporting Roll, single Opposing Roll, both with no modifiers.** No propagation entries to invert. Each Roll resolves independently against the Base TN.

**Same Roll in both lists.** The design does not specify behavior for this case. Validation is unassigned.

**A Roll with `value_adjustment` set on the Supporting side.** The Nudge applies to that Roll only. The Defender's dice are not nudged. Same for rerolls.
