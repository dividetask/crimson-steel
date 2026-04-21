# Dice and Resolution Mechanics — Pseudocode

## Conventions

- Class names use `PascalCase`. Method names use `ALL_CAPS_WITH_UNDERSCORES` to signal pseudocode.
- Config is accessed as `dice_resolution_config['Key Name']` using the human-readable keys defined in `dice_resolution_config.yaml`.
- `RAND_INT(low, high)` returns a uniformly random integer in the inclusive range `[low, high]`.
- `floor(x)` returns the largest integer less than or equal to `x`.
- `null` should be translated to `null` in C# and `nil` in Ruby.
- Boolean-to-integer conversions use an explicit ternary `(cond) ? 1 : 0` so both target languages translate directly without relying on implicit coercion.

## Common Variables/Parameters

- `starting_value`: a signed integer representing starting contributions to the Roll. Positive = Starting Successes; negative = Starting Failures; zero = neither.
- `reroll_count`: a signed integer. The absolute value indicates how many dice to reroll. A positive value indicates rerolls should be used to improve the results, whereas a negative value indicates rerolls should be used to diminish the results.
- `nudge_amount`: a signed integer that should be added to the value of one of the dice.
- `failure_modifier` *(optional, default -1)*: the contribution of each Failure to the Degree of Individual Success. Set to 0 for Checks that ignore Failures.
- `critical_modifier` *(optional, default 2)*: the contribution of each Critical Success to the Degree of Individual Success. This value replaces the contribution a regular Success would otherwise provide; a Critical Success does not stack with the +1 from being a Success.

---

# CLASS DiceSystem

## State

- `dice_resolution_config`: dictionary of configuration values loaded from YAML.
- `random_source`: source of random integers.

---

## CONSTRUCTOR

**Description:** Loads the configuration file and initializes the random source.
**Parameters:**
- `config_path`: path to the YAML configuration file.
- `random_source` *(optional)*: a random source, useful for tests that need a deterministic sequence. If omitted, a default system random source is created.

**Returns:** None (constructor).

1. `dice_resolution_config = load_yaml(config_path)`
2. `if random_source is null:`
3. `⠀⠀random_source = new default_random_source()`
4. `store dice_resolution_config and random_source as instance state`

---

## RAND_ROLL_DIE

**Description:** Simulates a single die roll.
**Parameters:** None.
**Returns:** An integer value between 1 and `dice_resolution_config['Die Size']`, inclusive.

1. `result = RAND_INT(1, dice_resolution_config['Die Size'])`
2. `return result`

---

## RAND_ROLL_DICE

**Description:** Simulates rolling multiple dice and returns the results in the order rolled.
**Parameters:**
- `dice_count`: the number of dice to roll.

**Returns:** A list of integers of length `dice_count`.
**Preconditions:** `dice_count >= 1`.

1. `result = []`
2. `for i = 1 to dice_count:`
3. `⠀⠀result.append(RAND_ROLL_DIE())`
4. `return result`

---

## Helper: COMPUTE_ASCENDING_INDICES

**Description:** Internal helper. Returns the indices into `dice` in an order such that the corresponding values are non-decreasing. Implementers should prefer their language's built-in stable sort rather than translating the bubble sort shown here: in Ruby `dice.each_with_index.sort_by { |v, _| v }.map { |_, i| i }`, in C# `Enumerable.Range(0, dice.Count).OrderBy(i => dice[i]).ToList()`.

**Parameters:**
- `dice`: a list of integer die values.

**Returns:** A list of integer indices.

1. `result = list of integers from 0 to length(dice) - 1`
2. `for i = 0 to length(dice) - 2:`
3. `⠀⠀for j = 0 to length(dice) - i - 2:`
4. `⠀⠀⠀⠀if dice[result[j]] > dice[result[j + 1]]:`
5. `⠀⠀⠀⠀⠀⠀swap result[j] and result[j + 1]`
6. `return result`

---

## Helper: COMPUTE_NUDGE_EFFECT

**Description:** Internal helper. Calculates the change in a die's contribution to the Degree of Individual Success when a nudge is applied.

**Parameters:**
- `initial_value`: the die's value before nudging.
- `nudge_amount`: a signed integer. Positive = raise, negative = lower.
- `tn`: the Target Number for this Roll, used to identify Successes.
- `failure_modifier` *(optional, default -1)*.
- `critical_modifier` *(optional, default 2)*.

**Returns:** An integer — the delta (nudged contribution minus initial contribution).

1. `die_size = dice_resolution_config['Die Size']`
2. `if initial_value == die_size:`
3. `⠀⠀initial_contrib = critical_modifier`
4. `else if initial_value == 1:`
5. `⠀⠀initial_contrib = failure_modifier`
6. `else if initial_value >= tn:`
7. `⠀⠀initial_contrib = 1`
8. `else:`
9. `⠀⠀initial_contrib = 0`
10. `nudged_value = max(1, min(die_size, initial_value + nudge_amount))`
11. `if nudged_value == die_size:`
12. `⠀⠀nudged_contrib = critical_modifier`
13. `else if nudged_value == 1:`
14. `⠀⠀nudged_contrib = failure_modifier`
15. `else if nudged_value >= tn:`
16. `⠀⠀nudged_contrib = 1`
17. `else:`
18. `⠀⠀nudged_contrib = 0`
19. `return nudged_contrib - initial_contrib`

---

## COMPUTE_ROLL_PARAMETERS

**Description:** Computes the final Target Number for a Roll, along with any Starting Value produced by per-type Starting contributions and Target Number overflow. Pure calculation — no randomness. Throws an exception if `modifiers` contains any key that is not recognized.
**Parameters:**
- `modifiers`: a dictionary of modifier names to integer values. Keys are the human-readable modifier names. Missing keys are treated as 0.

**Returns:** A dictionary containing:
- `'tn'`: the final Target Number after all modifiers are applied and clamped.
- `'starting_value'`: a signed integer representing starting contributions to the Roll. Positive = Starting Successes; negative = Starting Failures; zero = neither.

**Recognized modifier keys:** For each type name listed in `dice_resolution_config['Bonus Types List']`, the three keys `'<Type> Bonus'`, `'<Type> Penalty'`, and `'<Type> Starting'`. For example, if `'Circumstance'` is in the list, the keys `'Circumstance Bonus'`, `'Circumstance Penalty'`, and `'Circumstance Starting'` are all accepted.

1. `accepted_keys = empty set`
2. `for each type_name in dice_resolution_config['Bonus Types List']:`
3. `⠀⠀add (type_name + ' Bonus') to accepted_keys`
4. `⠀⠀add (type_name + ' Penalty') to accepted_keys`
5. `⠀⠀add (type_name + ' Starting') to accepted_keys`
6. `for each key in modifiers:`
7. `⠀⠀if key not in accepted_keys:`
8. `⠀⠀⠀⠀raise exception ('Unrecognized modifier key: ' + key)`
9. `total_bonus = 0`
10. `total_penalty = 0`
11. `starting_value = 0`
12. `for each type_name in dice_resolution_config['Bonus Types List']:`
13. `⠀⠀total_bonus = total_bonus + modifier_value(modifiers, type_name + ' Bonus')`
14. `⠀⠀total_penalty = total_penalty + modifier_value(modifiers, type_name + ' Penalty')`
15. `⠀⠀starting_value = starting_value + modifier_value(modifiers, type_name + ' Starting')`
16. `tn = dice_resolution_config['Base Target Number'] - total_bonus + total_penalty`
17. `if tn < dice_resolution_config['Minimum Target Number']:`
18. `⠀⠀starting_value = starting_value + dice_resolution_config['Minimum Target Number'] - tn`
19. `⠀⠀tn = dice_resolution_config['Minimum Target Number']`
20. `else if tn > dice_resolution_config['Maximum Target Number']:`
21. `⠀⠀starting_value = starting_value - (tn - dice_resolution_config['Maximum Target Number'])`
22. `⠀⠀tn = dice_resolution_config['Maximum Target Number']`
23. `return { 'tn': tn, 'starting_value': starting_value }`

**Helper `modifier_value(modifiers, key)`:** returns `modifiers[key]` if the key exists, or `0` otherwise.

---

## COMPUTE_RESULTS

**Description:** Computes the Degree of Individual Success and the Critical Count for a Roll. Pure calculation — no randomness. To disable Failure counting for a Check, the caller passes `failure_modifier = 0`.
**Parameters:**
- `dice`: a list of integer die values.
- `tn`: the Target Number for this Roll.
- `starting_value`: a signed integer representing starting contributions to the Roll. Positive = Starting Successes; negative = Starting Failures; zero = neither.
- `failure_modifier` *(optional, default -1)*.
- `critical_modifier` *(optional, default 2)*.

**Returns:** A dictionary containing:
- `'degree_of_individual_success'`: the computed DoIS.
- `'critical_count'`: total Critical Successes.

1. `dois = starting_value`
2. `critical_count = 0`
3. `for i = 0 to length(dice) - 1:`
4. `⠀⠀value = dice[i]`
5. `⠀⠀if value == dice_resolution_config['Die Size']:`
6. `⠀⠀⠀⠀critical_count = critical_count + 1`
7. `⠀⠀⠀⠀dois = dois + critical_modifier`
8. `⠀⠀else if value >= tn:`
9. `⠀⠀⠀⠀dois = dois + 1`
10. `⠀⠀else if value == 1:`
11. `⠀⠀⠀⠀dois = dois + failure_modifier`
12. `return { 'degree_of_individual_success': dois, 'critical_count': critical_count }`

---

## APPLY_NUDGE

**Description:** Applies a value adjustment to one die. A positive `nudge_amount` raises a die; a negative `nudge_amount` lowers one. The target is the die whose nudged contribution to the Degree of Individual Success differs most from its current contribution — highest delta for a positive nudge, lowest delta for a negative nudge. On a tie, the die with the lowest index is chosen. Checks that ignore Failures should be handled by the caller passing `failure_modifier = 0`.

**Parameters:**
- `dice`: a list of integer die values.
- `nudge_amount`: a signed integer. Positive = raise, negative = lower, zero = no effect.
- `tn`: the Target Number for this Roll, used to identify Successes.
- `failure_modifier` *(optional, default -1)*.
- `critical_modifier` *(optional, default 2)*.

**Returns:** A list of the same length as `dice`, where each entry is either the new value for that die (if changed) or `null` (if unchanged). If `dice` is empty, `nudge_amount == 0`, or no nudge would change the target die's value, returns an all-null list.

1. `changes = list of null values, same length as dice`
2. `if nudge_amount == 0 or length(dice) == 0:`
3. `⠀⠀return changes`
4. `target_index = null`
5. `target_contrib = null`
6. `for i = 0 to length(dice) - 1:`
7. `⠀⠀new_contrib = COMPUTE_NUDGE_EFFECT(dice[i], nudge_amount, tn, failure_modifier, critical_modifier)`
8. `⠀⠀if target_index is null:`
9. `⠀⠀⠀⠀target_index = i`
10. `⠀⠀⠀⠀target_contrib = new_contrib`
11. `⠀⠀else if nudge_amount > 0 and new_contrib > target_contrib:`
12. `⠀⠀⠀⠀target_index = i`
13. `⠀⠀⠀⠀target_contrib = new_contrib`
14. `⠀⠀else if nudge_amount < 0 and new_contrib < target_contrib:`
15. `⠀⠀⠀⠀target_index = i`
16. `⠀⠀⠀⠀target_contrib = new_contrib`
17. `die_size = dice_resolution_config['Die Size']`
18. `target_value = max(1, min(die_size, dice[target_index] + nudge_amount))`
19. `if target_value != dice[target_index]:`
20. `⠀⠀changes[target_index] = target_value`
21. `return changes`

---

## RAND_REROLL_SOME_DICE

**Description:** Rerolls a subset of dice. A positive `reroll_count` rerolls up to that many dice that are currently neither Successes nor Critical Successes, preferring the lowest values (which are typically Failures). A negative `reroll_count` rerolls up to `|reroll_count|` dice that are currently Successes or Critical Successes, preferring the highest values (which are typically Critical Successes). No die is rerolled more than once.

**Parameters:**
- `dice`: a list of integer die values.
- `reroll_count`: a signed integer. Positive = improve the Roll, negative = worsen the Roll, zero = no effect.
- `tn`: the Target Number for this Roll, used to identify Successes.

**Returns:** A list of the same length as `dice`, where each entry is either the rerolled value or `null`. If `dice` is empty or `reroll_count == 0`, returns an all-null list.

1. `changes = list of null values, same length as dice`
2. `if reroll_count == 0 or length(dice) == 0:`
3. `⠀⠀return changes`
4. `sorted_indices = COMPUTE_ASCENDING_INDICES(dice)`
5. `remaining = absolute_value(reroll_count)`
6. `if reroll_count > 0:`
7. `⠀⠀for i = 0 to length(sorted_indices) - 1:`
8. `⠀⠀⠀⠀if remaining == 0:`
9. `⠀⠀⠀⠀⠀⠀break`
10. `⠀⠀⠀⠀die_index = sorted_indices[i]`
11. `⠀⠀⠀⠀if dice[die_index] >= tn:`
12. `⠀⠀⠀⠀⠀⠀break`
13. `⠀⠀⠀⠀changes[die_index] = RAND_ROLL_DIE()`
14. `⠀⠀⠀⠀remaining = remaining - 1`
15. `else:`
16. `⠀⠀for i = length(sorted_indices) - 1 downto 0:`
17. `⠀⠀⠀⠀if remaining == 0:`
18. `⠀⠀⠀⠀⠀⠀break`
19. `⠀⠀⠀⠀die_index = sorted_indices[i]`
20. `⠀⠀⠀⠀if dice[die_index] < tn:`
21. `⠀⠀⠀⠀⠀⠀break`
22. `⠀⠀⠀⠀changes[die_index] = RAND_ROLL_DIE()`
23. `⠀⠀⠀⠀remaining = remaining - 1`
24. `return changes`

**Notes:**
- The ascending sort gives Failures (value 1) priority on the positive branch — they're always at the start of the sorted list.
- The descending walk on the negative branch gives Critical Successes (value = Die Size) priority for the same reason.
- The `break` when a die crosses the Success threshold (step 11 for positive, step 20 for negative) works because the sorted order guarantees all remaining dice are on the same side of the threshold.
- Each die is visited at most once in either branch, so the "no die rerolled more than once" rule is satisfied without explicit bookkeeping.
