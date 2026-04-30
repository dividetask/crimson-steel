# Conditions and Buffs — Pseudocode

## Conventions

- Class names use `PascalCase`. Method names use `ALL_CAPS_WITH_UNDERSCORES` to signal pseudocode.
- Config is accessed as `conditions_config['Key Name']` using the human-readable keys defined in `conditions_config.yaml`.
- `null` should be translated to `null` in C# and `nil` in Ruby.
- Boolean-to-integer conversions use an explicit ternary `(cond) ? 1 : 0`.
- `floor(x)` returns the largest integer less than or equal to `x`.
- References to `DiceSystem.METHOD` mean calls into the dice resolution module (see `dice_resolution_pseudocode.md`).

## Common Variables/Parameters

- `current_round`: a signed integer representing the in-game round. Supplied by callers; this module never reads a clock.
- `source_id`: an opaque string used to identify a specific Effect or Temporary Hit Points grant so the caller can later modify or remove it.
- `target_key`: an opaque string naming what an Effect adjusts (e.g. `"str"`, `"save"`, `"speed"`). Conditions does not validate Target Keys.
- `bonus_type`: a string drawn from `dice_resolution_config['Bonus Types List']`.
- `sign`: one of `"bonus"` or `"penalty"`.
- `severity`: one of the values in `conditions_config['Severity Categories List']`.
- `modifiers`: a dictionary compatible with `DiceSystem.COMPUTE_ROLL_PARAMETERS` — validated by that call, not by Conditions.

---

# CLASS Conditions

## State

- `conditions_config`: dictionary of configuration values loaded from YAML.
- `dice_system`: a `DiceSystem` instance used for affliction save Rolls.
- `hit_point_damage`: dictionary mapping each severity category to a non-negative integer counter.
- `ability_damage`: ordered dictionary mapping attribute name to an ordered dictionary of severity category to non-negative integer counter.
- `temporary_hit_points`: either `null` or a dictionary `{ 'amount': int, 'source_id': string, 'ends_on_round': int-or-null }`. At most one entry at a time.
- `magic_toxicity`: a non-negative integer.
- `shock`: a non-negative integer.
- `afflictions`: ordered dictionary mapping affliction name to `{ 'severity': int, 'inflicting_tier': int }`, in insertion order.
- `effects`: ordered list of dictionaries, each `{ 'target_key': str, 'bonus_type': str, 'sign': str, 'amount': int, 'ends_on_round': int-or-null, 'source_id': str, 'metadata': dict }`, in insertion order.

---

## CONSTRUCTOR

**Description:** Loads the configuration file, binds the dice system used for save Rolls, and optionally seeds persisted state.

**Parameters:**
- `config_path`: path to `conditions_config.yaml`.
- `dice_system`: a `DiceSystem` instance. Required — Affliction Resolution cannot run without it.
- `initial_state` *(optional)*: a dictionary previously produced by `TO_DICT`. When omitted, the instance starts empty.

**Returns:** None (constructor).

1. `conditions_config = load_yaml(config_path)`
2. `store conditions_config and dice_system as instance state`
3. `if initial_state is not null:`
4. `⠀⠀LOAD_STATE(initial_state)`
5. `else:`
6. `⠀⠀hit_point_damage = { category: 0 for each category in conditions_config['Severity Categories List'] }`
7. `⠀⠀ability_damage = empty ordered dictionary`
8. `⠀⠀temporary_hit_points = null`
9. `⠀⠀magic_toxicity = 0`
10. `⠀⠀shock = 0`
11. `⠀⠀afflictions = empty ordered dictionary`
12. `⠀⠀effects = empty list`

---

## APPLY_HIT_POINT_DAMAGE

**Description:** Applies incoming hit point damage, absorbing it worst-first with Temporary Hit Points before it lands on the severity counters. Mutates `hit_point_damage` and `temporary_hit_points` in place. The incoming amounts are trusted — Damage Reduction, Damage Resilience, and any other mitigation are the caller's responsibility.

**Parameters:**
- `incoming`: a dictionary mapping each severity category to a non-negative integer. Missing keys are treated as zero. Keys not in `Severity Categories List` raise an exception.

**Returns:** A dictionary containing:
- `'absorbed'`: a dictionary mapping each severity category to the amount absorbed by Temporary Hit Points.
- `'dealt'`: a dictionary mapping each severity category to the amount that landed on the severity counter.

1. `severity_list = conditions_config['Severity Categories List']`
2. `for each key in incoming:`
3. `⠀⠀if key not in severity_list:`
4. `⠀⠀⠀⠀raise exception ('Unrecognized severity category: ' + key)`
5. `absorbed = { category: 0 for each category in severity_list }`
6. `dealt = { category: 0 for each category in severity_list }`
7. `temp_pool = (temporary_hit_points is null) ? 0 : temporary_hit_points['amount']`
8. `for each category in severity_list:`
9. `⠀⠀amount = incoming[category] if category in incoming else 0`
10. `⠀⠀absorb = min(amount, temp_pool)`
11. `⠀⠀absorbed[category] = absorb`
12. `⠀⠀temp_pool = temp_pool - absorb`
13. `⠀⠀dealt[category] = amount - absorb`
14. `⠀⠀hit_point_damage[category] = hit_point_damage[category] + dealt[category]`
15. `if temporary_hit_points is not null:`
16. `⠀⠀if temp_pool <= 0:`
17. `⠀⠀⠀⠀temporary_hit_points = null`
18. `⠀⠀else:`
19. `⠀⠀⠀⠀temporary_hit_points['amount'] = temp_pool`
20. `return { 'absorbed': absorbed, 'dealt': dealt }`

**Notes:**
- The iteration order over `Severity Categories List` drives the worst-first absorption order. The configuration lists categories from worst to lowest, so the natural iteration order is correct.
- Absorption does not carry over between severity categories: 3 Temporary Hit Points against `{ major: 1, moderate: 5 }` absorbs 1 Major and 2 Moderate. The pool does not redistribute a surplus beyond the incoming amount of a category.

---

## APPLY_HIT_POINT_HEAL_CASCADE

**Description:** Heals hit point damage worst-first. Each severity category's pool heals its own category first; any unused remainder cascades down to the next category in `Severity Categories List` order. Excess beyond the lowest category is wasted. Mutates `hit_point_damage` in place.

**Parameters:**
- `pools`: a dictionary mapping each severity category to a non-negative integer heal pool. Missing keys are treated as zero. Keys not in `Severity Categories List` raise an exception.

**Returns:** A dictionary mapping each severity category to the amount healed at that category.

1. `severity_list = conditions_config['Severity Categories List']`
2. `for each key in pools:`
3. `⠀⠀if key not in severity_list:`
4. `⠀⠀⠀⠀raise exception ('Unrecognized severity category: ' + key)`
5. `healed = { category: 0 for each category in severity_list }`
6. `remainder = 0`
7. `for each category in severity_list:`
8. `⠀⠀pool = (pools[category] if category in pools else 0) + remainder`
9. `⠀⠀available = hit_point_damage[category]`
10. `⠀⠀applied = min(pool, available)`
11. `⠀⠀healed[category] = applied`
12. `⠀⠀hit_point_damage[category] = available - applied`
13. `⠀⠀remainder = pool - applied`
14. `return healed`

---

## SET_TEMPORARY_HIT_POINTS

**Description:** Applies a Temporary Hit Points grant. Because exactly one grant is Active at a time, the new grant replaces the existing one only when its `amount` is strictly greater than the existing `amount`; otherwise the new grant is rejected and the existing grant is untouched. A nonpositive amount clears the grant.

**Parameters:**
- `amount`: a non-negative integer.
- `source_id`: an opaque string identifying the new grant.
- `ends_on_round` *(optional, default null)*: a signed integer, or null for a grant with no expiry.

**Returns:** A dictionary containing:
- `'accepted'`: boolean — whether the new grant replaced the existing one.
- `'replaced_source_id'`: the previous grant's `source_id`, or null if there was none.

1. `previous_source = (temporary_hit_points is null) ? null : temporary_hit_points['source_id']`
2. `if amount <= 0:`
3. `⠀⠀temporary_hit_points = null`
4. `⠀⠀return { 'accepted': true, 'replaced_source_id': previous_source }`
5. `current_amount = (temporary_hit_points is null) ? 0 : temporary_hit_points['amount']`
6. `if amount <= current_amount:`
7. `⠀⠀return { 'accepted': false, 'replaced_source_id': null }`
8. `temporary_hit_points = { 'amount': amount, 'source_id': source_id, 'ends_on_round': ends_on_round }`
9. `return { 'accepted': true, 'replaced_source_id': previous_source }`

**Notes:**
- Expiry for a Temporary Hit Points grant is handled by `CLEAR_EXPIRED_EFFECTS`, not here. When that method detects an expired grant it clears `temporary_hit_points` to null; the absorbed pool is lost at expiry (the glossary's "absorbs damage while Active" rule).
- Equality (`amount == current_amount`) is a rejection, not a replacement, because no information would be gained by swapping the Source ID in that case.

---

## APPLY_ABILITY_DAMAGE

**Description:** Applies damage to a specific attribute at a specific severity category. Preserves insertion order so the Ability Heal Cascade can pop FIFO. Mutates `ability_damage` in place.

**Parameters:**
- `attribute`: the attribute name (e.g. `"str"`). The module does not validate against an attribute list — the caller is trusted.
- `severity`: one of the values in `Severity Categories List`. Other values raise an exception.
- `amount`: a non-negative integer. A zero or negative amount is a no-op.

**Returns:** None.

1. `severity_list = conditions_config['Severity Categories List']`
2. `if severity not in severity_list:`
3. `⠀⠀raise exception ('Unrecognized severity category: ' + severity)`
4. `if amount <= 0:`
5. `⠀⠀return`
6. `if attribute not in ability_damage:`
7. `⠀⠀ability_damage[attribute] = ordered dictionary { category: 0 for each category in severity_list }`
8. `ability_damage[attribute][severity] = ability_damage[attribute][severity] + amount`

**Notes:**
- Initializing every severity key on first touch keeps later reads uniform. Insertion order is taken from the language's ordered dictionary semantics; the first time an attribute is damaged is its position in the cascade's FIFO queue.

---

## APPLY_ABILITY_HEAL_CASCADE

**Description:** Heals Ability Damage worst-first. Pools cascade the same way `APPLY_HIT_POINT_HEAL_CASCADE` does. Within a severity category, damage is popped across attributes in insertion order — the attribute damaged earliest heals first. Mutates `ability_damage` in place.

**Parameters:**
- `pools`: a dictionary mapping each severity category to a non-negative integer heal pool. Missing keys are treated as zero. Keys not in `Severity Categories List` raise an exception.

**Returns:** A dictionary mapping each severity category to the total amount healed at that category across all attributes.

1. `severity_list = conditions_config['Severity Categories List']`
2. `for each key in pools:`
3. `⠀⠀if key not in severity_list:`
4. `⠀⠀⠀⠀raise exception ('Unrecognized severity category: ' + key)`
5. `healed = { category: 0 for each category in severity_list }`
6. `remainder = 0`
7. `for each category in severity_list:`
8. `⠀⠀pool = (pools[category] if category in pools else 0) + remainder`
9. `⠀⠀for each attribute in ability_damage (in insertion order):`
10. `⠀⠀⠀⠀if pool == 0:`
11. `⠀⠀⠀⠀⠀⠀break`
12. `⠀⠀⠀⠀available = ability_damage[attribute][category]`
13. `⠀⠀⠀⠀applied = min(pool, available)`
14. `⠀⠀⠀⠀ability_damage[attribute][category] = available - applied`
15. `⠀⠀⠀⠀healed[category] = healed[category] + applied`
16. `⠀⠀⠀⠀pool = pool - applied`
17. `⠀⠀remainder = pool`
18. `prune empty attribute entries from ability_damage (those whose every severity counter is zero)`
19. `return healed`

**Notes:**
- Pruning empty entries after the cascade keeps `ability_damage` compact. It does not affect insertion order for attributes that still carry damage.
- The intra-category FIFO rule is what makes insertion order matter: when CON is damaged first and STR is damaged second, a partial heal at that severity reduces CON before STR.

---

## APPLY_MAGIC_TOXICITY

**Description:** Increases Magic Toxicity by the given amount. Magic Toxicity has no upper bound in this module — the caller is responsible for clamping against the creature's maximum (typically derived from an ability score) before calling, or for rejecting the call when already at the cap.

**Parameters:**
- `amount`: a non-negative integer. A zero or negative amount is a no-op.

**Returns:** The new Magic Toxicity value.

1. `if amount <= 0:`
2. `⠀⠀return magic_toxicity`
3. `magic_toxicity = magic_toxicity + amount`
4. `return magic_toxicity`

---

## CLEAR_MAGIC_TOXICITY

**Description:** Reduces Magic Toxicity by the given amount, flooring at zero.

**Parameters:**
- `amount`: a non-negative integer. A zero or negative amount is a no-op.

**Returns:** The new Magic Toxicity value.

1. `if amount <= 0:`
2. `⠀⠀return magic_toxicity`
3. `magic_toxicity = max(0, magic_toxicity - amount)`
4. `return magic_toxicity`

---

## APPLY_SHOCK

**Description:** Adds points to the Shock counter. Shock has no save and no internal decay; it is consumed only by `CONSUME_SHOCK`.

**Parameters:**
- `amount`: a non-negative integer. A zero or negative amount is a no-op.

**Returns:** The new Shock value.

1. `if amount <= 0:`
2. `⠀⠀return shock`
3. `shock = shock + amount`
4. `return shock`

---

## CONSUME_SHOCK

**Description:** Consumes Shock against a number of available dice. Returns how many points were consumed and decrements `shock` by the same amount. The caller then subtracts the returned count from the creature's combat pool. Any Shock that could not be consumed (because the available dice ran out first) remains for the next pool refresh.

**Parameters:**
- `max_consume`: a non-negative integer — the maximum amount of Shock the caller is willing to spend against the available dice.

**Returns:** An integer — the amount of Shock actually consumed. Always between 0 and `max_consume` inclusive.

1. `if max_consume <= 0 or shock == 0:`
2. `⠀⠀return 0`
3. `consumed = min(shock, max_consume)`
4. `shock = shock - consumed`
5. `return consumed`

**Notes:**
- A typical caller, on pool refresh, sets `pool = max_pool` and then `pool = pool - CONSUME_SHOCK(pool)`. If Shock exceeded `max_pool`, the overflow stays on the Shock counter and is consumed next refresh — reproducing the glossary's "if Shock is especially high it might take multiple turns to eliminate" rule without any further state.
- Consumption order matters only for reporting: the caller presents "X dice lost to Shock" based on the returned count and then works with the reduced pool.

---

## INFLICT_AFFLICTION

**Description:** Inflicts Severity of an Affliction at a specified inflicter Tier. If the Affliction is not yet present it is appended to the list in insertion order; otherwise its existing Severity is incremented and its Inflicter Tier is raised to `max(existing, new)`. The Affliction's Rule must exist in `conditions_config['Afflictions']`.

**Parameters:**
- `name`: the Affliction's configuration key.
- `amount`: a non-negative integer. A zero or negative amount is a no-op (and does not update the Inflicter Tier on a present Affliction).
- `inflicter_tier`: the Tier of the source inflicting this Affliction. Plain integer.

**Returns:** A dictionary describing the change:
- `'severity'`: integer — Severity after the inflict.
- `'inflicting_tier'`: integer — Inflicter Tier after the update.
- `'newly_added'`: boolean — whether the Affliction was newly created on this call.

1. `if name not in conditions_config['Afflictions']:`
2. `⠀⠀raise exception ('Unknown affliction: ' + name)`
3. `if amount <= 0:`
4. `⠀⠀if name in afflictions:`
5. `⠀⠀⠀⠀return { 'severity': afflictions[name]['severity'], 'inflicting_tier': afflictions[name]['inflicting_tier'], 'newly_added': false }`
6. `⠀⠀return { 'severity': 0, 'inflicting_tier': 0, 'newly_added': false }`
7. `newly_added = (name not in afflictions)`
8. `if newly_added:`
9. `⠀⠀afflictions[name] = { 'severity': 0, 'inflicting_tier': inflicter_tier }`
10. `else:`
11. `⠀⠀afflictions[name]['inflicting_tier'] = max(afflictions[name]['inflicting_tier'], inflicter_tier)`
12. `afflictions[name]['severity'] = afflictions[name]['severity'] + amount`
13. `return { 'severity': afflictions[name]['severity'], 'inflicting_tier': afflictions[name]['inflicting_tier'], 'newly_added': newly_added }`

---

## REMOVE_AFFLICTION

**Description:** Deletes an Affliction entry entirely, discarding its Severity counter and Inflicter Tier. A later `INFLICT_AFFLICTION` re-inserts the Affliction at the end of the order with whatever Inflicter Tier the new source provides.

**Parameters:**
- `name`: the Affliction's configuration key. A no-op if the Affliction is not present.

**Returns:** None.

1. `if name in afflictions:`
2. `⠀⠀delete afflictions[name]`

---

## GET_AFFLICTION

**Description:** Returns a snapshot of one Affliction's stored state plus the resolved Rule fields the caller is most likely to need (Category, Save Frequency, save attribute). Returns null if the Affliction is not present. The returned dictionary is a copy — mutating it does not affect Conditions state.

**Parameters:**
- `name`: the Affliction's configuration key.

**Returns:** Either null, or a dictionary:
- `'name'`: the Affliction's configuration key.
- `'severity'`: integer.
- `'inflicting_tier'`: integer.
- `'category'`: string from the Rule (defaults to `"other"` when omitted).
- `'save_frequency'`: string from the Rule (defaults to `"round"`).
- `'save_attribute'`: string from the Rule (defaults to `"con"`).

1. `if name not in afflictions:`
2. `⠀⠀return null`
3. `rule = conditions_config['Afflictions'][name]`
4. `entry = afflictions[name]`
5. `return {`
6. `⠀⠀'name': name,`
7. `⠀⠀'severity': entry['severity'],`
8. `⠀⠀'inflicting_tier': entry['inflicting_tier'],`
9. `⠀⠀'category': rule['category'] if 'category' in rule else 'other',`
10. `⠀⠀'save_frequency': rule['save_frequency'] if 'save_frequency' in rule else 'round',`
11. `⠀⠀'save_attribute': rule['save'] if 'save' in rule else 'con'`
12. `}`

---

## Helper: RESOLVE_TIER_SCALED_VALUE

**Description:** Internal helper. Resolves a configuration value that may be either a plain integer or the literal string `"tier"`. Per the project-wide convention, Tier 0 is treated as 0.5 in formulas; this helper returns 0.5 in that case so the caller's downstream multiplication produces the correct floored integer.

**Parameters:**
- `value`: an integer or the literal string `"tier"`.
- `creature_tier`: the creature's Tier as a plain non-negative integer.

**Returns:** A number — integer when `value` is an integer or when `creature_tier > 0`; the float `0.5` only when `value == "tier"` and `creature_tier == 0`.

1. `if value is an integer:`
2. `⠀⠀return value`
3. `if value == 'tier':`
4. `⠀⠀if creature_tier == 0:`
5. `⠀⠀⠀⠀return 0.5`
6. `⠀⠀return creature_tier`
7. `raise exception ('Unrecognized tier-scaled value: ' + string(value))`

**Notes:**
- Callers that consume the return value to update Severity must `floor` the final product (e.g. `floor(successes * per_success)`) so Severity remains integer-valued. Tier 0 with a `"tier"`-scaled per-success rate of 0.5 means two successes are needed before Severity drops by one.

---

## RESOLVE_AFFLICTION

**Description:** Ticks one Active Affliction. Every Affliction has a save: Conditions merges a Competency Penalty equal to `floor(severity / Severity Divisor)` into the modifier dict, calls the dice resolution module to roll the save, applies the Affliction's effect at magnitude reduced by raw successes (floored at zero), then evolves Severity. When Severity reaches zero the Affliction is removed. The Affliction's Inflicter Tier is preserved across resolution and only cleared when Severity reaches zero.

**Parameters:**
- `name`: the Affliction's configuration key. Must be present and have positive Severity.
- `save_input`: a dictionary `{ 'dice_count': int, 'modifiers': dict }`. The `modifiers` dict supplies the creature's save modifiers including any Inflicter-Tier or own-Tier contributions the caller wants to add. Conditions merges the Severity Save Penalty in on top.
- `creature_tier`: the resolving creature's Tier as a plain non-negative integer. Used to substitute the `"tier"` literal in Severity Per Success / Severity Per Failure / Severity Decay.
- `current_round` *(optional, default null)*: a signed integer. Required when the Affliction's effect kind is `effect`. Ignored otherwise.

**Returns:** A dictionary describing what happened:
- `'successes'`: integer — `max(0, dois)` from the save.
- `'failures'`: integer — `max(0, -dois)` from the save.
- `'severity_save_penalty'`: integer — the Competency Penalty Conditions added.
- `'magnitude'`: integer — `1 + floor(severity_before / Severity Divisor)`.
- `'net_magnitude'`: integer — `max(0, magnitude - successes)`. This is the amount actually applied.
- `'effect_kind'`: string — the Rule's effect kind.
- `'applied'`: a dictionary whose shape depends on `effect_kind` (see `APPLY_AFFLICTION_EFFECT`).
- `'severity_before'`: integer.
- `'severity_after'`: integer (0 if removed).
- `'removed'`: boolean — whether the Affliction was removed because Severity reached zero.

**Preconditions:**
- `afflictions[name]['severity'] > 0`.

1. `if name not in afflictions or afflictions[name]['severity'] <= 0:`
2. `⠀⠀raise exception ('Affliction not active: ' + name)`
3. `rule = conditions_config['Afflictions'][name]`
4. `severity_before = afflictions[name]['severity']`
5. `divisor = conditions_config['Severity Divisor']`
6. `severity_save_penalty = floor(severity_before / divisor)`
7. `merged_modifiers = copy(save_input['modifiers'])`
8. `merged_modifiers['Competency Penalty'] = merged_modifiers.get('Competency Penalty', 0) + severity_save_penalty`
9. `params = dice_system.COMPUTE_ROLL_PARAMETERS(merged_modifiers)`
10. `dice = dice_system.RAND_ROLL_DICE(save_input['dice_count'])`
11. `result = dice_system.COMPUTE_RESULTS(dice, params['tn'], params['starting_value'])`
12. `dois = result['degree_of_individual_success']`
13. `successes = max(0, dois)`
14. `failures = max(0, -dois)`
15. `magnitude = 1 + floor(severity_before / divisor)`
16. `net_magnitude = max(0, magnitude - successes)`
17. `effect_kind = rule['effect']['kind']`
18. `applied = APPLY_AFFLICTION_EFFECT(rule['effect'], net_magnitude, current_round)`
19. `per_success_raw = rule['severity_per_success'] if 'severity_per_success' in rule else conditions_config['Default Severity Per Success']`
20. `per_failure_raw = rule['severity_per_failure'] if 'severity_per_failure' in rule else conditions_config['Default Severity Per Failure']`
21. `decay_raw = rule['severity_decay'] if 'severity_decay' in rule else conditions_config['Default Severity Decay']`
22. `per_success = RESOLVE_TIER_SCALED_VALUE(per_success_raw, creature_tier)`
23. `per_failure = RESOLVE_TIER_SCALED_VALUE(per_failure_raw, creature_tier)`
24. `decay = RESOLVE_TIER_SCALED_VALUE(decay_raw, creature_tier)`
25. `delta = -floor(decay) - floor(successes * per_success) + floor(failures * per_failure)`
26. `new_severity = max(0, severity_before + delta)`
27. `removed = false`
28. `if new_severity <= 0:`
29. `⠀⠀delete afflictions[name]`
30. `⠀⠀removed = true`
31. `else:`
32. `⠀⠀afflictions[name]['severity'] = new_severity`
33. `return {`
34. `⠀⠀'successes': successes,`
35. `⠀⠀'failures': failures,`
36. `⠀⠀'severity_save_penalty': severity_save_penalty,`
37. `⠀⠀'magnitude': magnitude,`
38. `⠀⠀'net_magnitude': net_magnitude,`
39. `⠀⠀'effect_kind': effect_kind,`
40. `⠀⠀'applied': applied,`
41. `⠀⠀'severity_before': severity_before,`
42. `⠀⠀'severity_after': new_severity,`
43. `⠀⠀'removed': removed`
44. `}`

**Notes:**
- The `floor(decay)` / `floor(successes * per_success)` / `floor(failures * per_failure)` calls handle the Tier 0 = 0.5 case: a tier-0 creature with a `"tier"`-scaled per-success of 0.5 needs two successes to drop one Severity point. In Tier 1+ no fractions ever appear; the floor calls are no-ops.
- The Severity Save Penalty is added to whatever Competency Penalty the caller supplied (rather than overwriting it), so the dice resolution stacking rule remains the single source of truth — the larger of the merged Competency Penalties applies after `COMPUTE_ROLL_PARAMETERS` does its work.
- Inflicter Tier and creature Tier are not injected by Conditions. Callers that want either as a save Target Number Modifier read Inflicter Tier via `GET_AFFLICTION` and add the modifiers to `save_input['modifiers']` before calling.

---

## Helper: APPLY_AFFLICTION_EFFECT

**Description:** Internal helper. Dispatches an Affliction's `effect` payload to the appropriate Conditions method based on `kind`. Never called directly from outside the module.

**Parameters:**
- `effect_spec`: the `effect` sub-dictionary from an Affliction Rule.
- `net_magnitude`: the scaled amount to apply (raw successes already subtracted, floored at zero).
- `current_round`: the signed integer game round. Required when `effect_spec.kind == 'effect'`.

**Returns:** A dictionary describing what was applied. Shape varies by kind:
- `hit_point_damage`: the `APPLY_HIT_POINT_DAMAGE` return value, or null if `net_magnitude == 0`.
- `ability_damage`: `{ 'attribute': string, 'severity': string, 'amount': int }`, or null if `net_magnitude == 0`.
- `named_effect`: the `APPLY_NAMED_EFFECT` return value, or null if `net_magnitude == 0`.

1. `if net_magnitude == 0:`
2. `⠀⠀return null`
3. `kind = effect_spec['kind']`
4. `if kind == 'hit_point_damage':`
5. `⠀⠀return APPLY_HIT_POINT_DAMAGE({ effect_spec['severity']: net_magnitude })`
6. `else if kind == 'ability_damage':`
7. `⠀⠀APPLY_ABILITY_DAMAGE(effect_spec['attribute'], effect_spec['severity'], net_magnitude)`
8. `⠀⠀return { 'attribute': effect_spec['attribute'], 'severity': effect_spec['severity'], 'amount': net_magnitude }`
9. `else if kind == 'named_effect':`
10. `⠀⠀if current_round is null:`
11. `⠀⠀⠀⠀raise exception ('named_effect kind requires current_round')`
12. `⠀⠀ends_on_round = current_round + max(1, effect_spec['duration_rounds'])`
13. `⠀⠀return APPLY_NAMED_EFFECT(effect_spec['name'], ends_on_round, 'affliction:' + effect_spec['name'])`
14. `else:`
15. `⠀⠀raise exception ('Unknown affliction effect kind: ' + kind)`

**Notes:**
- For the `named_effect` kind, magnitude is binary: the gating `if net_magnitude == 0` at step 1 means a fully-saved tick skips the effect entirely; any landed magnitude triggers the configured duration unchanged. Severity does not stretch the duration — the Affliction Rule controls that.
- The Source ID `'affliction:' + name` is deterministic so re-application of the same Affliction overwrites its previous Named Effect entry rather than stacking duplicates.

---

## APPLY_NAMED_EFFECT

**Description:** Applies a Named Effect from `conditions_config['Named Effects']` by name. Each modifier in the catalog entry is applied via `APPLY_EFFECT`, sharing a Source ID prefix so they expire together. Afflictions dispatch through this method via the `named_effect` kind; spells and abilities call it directly.

**Parameters:**
- `name`: the Named Effect's catalog key. Unknown names raise.
- `ends_on_round`: signed integer game round at which the Effect expires, or null for a permanent Effect.
- `source_id`: opaque string used for replacement and removal. Must be non-empty. Each modifier is applied with `<source_id>:<index>` so a multi-modifier Named Effect re-application cleanly overwrites every previous slot.

**Returns:** A dictionary containing:
- `'name'`: the Named Effect's name.
- `'applied'`: a list of `APPLY_EFFECT` return values, one per modifier in the catalog entry.

1. `if name not in conditions_config['Named Effects']:`
2. `⠀⠀raise exception ('Unknown named effect: ' + name)`
3. `entry = conditions_config['Named Effects'][name]`
4. `applied = empty list`
5. `for i = 0 to length(entry['modifiers']) - 1:`
6. `⠀⠀modifier = entry['modifiers'][i]`
7. `⠀⠀modifier_source_id = source_id + ':' + string(i)`
8. `⠀⠀result = APPLY_EFFECT(`
9. `⠀⠀⠀⠀modifier['target_key'], modifier['bonus_type'], modifier['sign'],`
10. `⠀⠀⠀⠀modifier['amount'], ends_on_round, modifier_source_id, empty dictionary)`
11. `⠀⠀applied.append(result)`
12. `return { 'name': name, 'applied': applied }`

**Notes:**
- The catalog is queried at apply time, not at construction time, so editing `Named Effects` and reloading config picks up changes without reconstructing existing Conditions instances. Already-applied Effects are not retroactively updated to match a new catalog definition; they keep the modifier shape they were created with until they expire.
- Removing a Named Effect application uses the same per-modifier Source ID convention: `REMOVE_EFFECT(source_id + ':' + index)` for each known modifier index. Callers that want a single-call cancellation can iterate `effects` looking for entries whose `source_id` starts with the prefix and remove each.

---

## APPLY_EFFECT

**Description:** Applies an Effect (buff or debuff). When `source_id` matches an existing Effect, the existing entry is replaced in place — preserving its position in `effects` — by the new payload. When no existing entry matches, the new Effect is appended.

**Parameters:**
- `target_key`: opaque string naming what the Effect adjusts.
- `bonus_type`: a string from `dice_resolution_config['Bonus Types List']`. The module does not validate against that list; the dice resolution module rejects unknown types when modifiers are passed to it.
- `sign`: `"bonus"` or `"penalty"`. Other values raise an exception.
- `amount`: a non-negative integer. Sign is carried separately. A zero amount is legal and stored.
- `ends_on_round` *(optional, default null)*: signed integer game round at which the Effect expires, or null for a permanent Effect.
- `source_id`: opaque string used for replacement and for `REMOVE_EFFECT`. Must be non-empty.
- `metadata` *(optional, default empty)*: dictionary of caller-defined extra fields. Stored as-is.

**Returns:** A dictionary describing the change:
- `'replaced'`: boolean — whether an existing Effect with the same `source_id` was overwritten.
- `'previous'`: the previous Effect entry, or null.

1. `if sign not in ['bonus', 'penalty']:`
2. `⠀⠀raise exception ('sign must be bonus or penalty')`
3. `if amount < 0:`
4. `⠀⠀raise exception ('amount must be non-negative')`
5. `entry = {`
6. `⠀⠀'target_key': target_key, 'bonus_type': bonus_type, 'sign': sign,`
7. `⠀⠀'amount': amount, 'ends_on_round': ends_on_round,`
8. `⠀⠀'source_id': source_id, 'metadata': metadata`
9. `}`
10. `existing_index = null`
11. `for i = 0 to length(effects) - 1:`
12. `⠀⠀if effects[i]['source_id'] == source_id:`
13. `⠀⠀⠀⠀existing_index = i`
14. `⠀⠀⠀⠀break`
15. `if existing_index is not null:`
16. `⠀⠀previous = effects[existing_index]`
17. `⠀⠀effects[existing_index] = entry`
18. `⠀⠀return { 'replaced': true, 'previous': previous }`
19. `effects.append(entry)`
20. `return { 'replaced': false, 'previous': null }`

**Notes:**
- "Replace by Source ID" is the only stacking rule this method enforces. Higher-level "highest of each type wins" stacking is the responsibility of `GET_MODIFIERS`. Two distinct Source IDs producing the same `target_key` and `bonus_type` are stored as two entries, and `GET_MODIFIERS` picks the larger of them at lookup time.
- Callers that want cumulative extension (e.g. ghoul paralysis where a re-tick should add to the existing end round) compute the new `ends_on_round` themselves by reading the existing entry first and then calling APPLY_EFFECT.

---

## REMOVE_EFFECT

**Description:** Removes the Effect with the given Source ID. No-op if none matches.

**Parameters:**
- `source_id`: opaque string.

**Returns:** The removed Effect entry, or null if none matched.

1. `for i = 0 to length(effects) - 1:`
2. `⠀⠀if effects[i]['source_id'] == source_id:`
3. `⠀⠀⠀⠀removed = effects[i]`
4. `⠀⠀⠀⠀delete effects[i]`
5. `⠀⠀⠀⠀return removed`
6. `return null`

---

## CLEAR_EXPIRED_EFFECTS

**Description:** Removes every Effect whose `ends_on_round` is not null and is less than or equal to `current_round`. Also clears the Temporary Hit Points grant when its `ends_on_round` has passed. Effects with `ends_on_round = null` are never removed by this method.

**Parameters:**
- `current_round`: signed integer game round.

**Returns:** A dictionary containing:
- `'removed_effects'`: a list of the Effect entries that were removed, in their original `effects` order.
- `'temporary_hit_points_cleared'`: boolean — whether the Temporary Hit Points grant was removed.

1. `removed_effects = empty list`
2. `surviving = empty list`
3. `for each entry in effects (in order):`
4. `⠀⠀if entry['ends_on_round'] is not null and entry['ends_on_round'] <= current_round:`
5. `⠀⠀⠀⠀removed_effects.append(entry)`
6. `⠀⠀else:`
7. `⠀⠀⠀⠀surviving.append(entry)`
8. `effects = surviving`
9. `temp_cleared = false`
10. `if temporary_hit_points is not null and temporary_hit_points['ends_on_round'] is not null and temporary_hit_points['ends_on_round'] <= current_round:`
11. `⠀⠀temporary_hit_points = null`
12. `⠀⠀temp_cleared = true`
13. `return { 'removed_effects': removed_effects, 'temporary_hit_points_cleared': temp_cleared }`

**Notes:**
- The `<=` comparison is deliberate: an Effect created with `ends_on_round = current_round + duration` for `duration = 1` clears the next time `CLEAR_EXPIRED_EFFECTS` is called with `current_round` advanced by one. Combat callers typically invoke this at the affected creature's Start of Turn.
- Removed Effects are returned so the caller can produce log lines ("Eagle's Splendor ends on Aria"). The caller is responsible for any side effect that should accompany expiry beyond removing the Effect itself.

---

## GET_MODIFIERS

**Description:** Returns the net modifier contribution of all Active Effects whose `target_key` matches, in the shape accepted by `DiceSystem.COMPUTE_ROLL_PARAMETERS`. Within each Bonus Type, only the highest Bonus and the highest Penalty contribute, per the dice resolution stacking rule. Effects with `amount == 0` contribute nothing. Effects with `ends_on_round` already expired (relative to `current_round`, when supplied) are skipped.

**Parameters:**
- `target_key`: the string to match against each Effect's `target_key`. The module does not validate it.
- `current_round` *(optional, default null)*: signed integer game round. When provided, expired Effects are skipped without being removed; when omitted, expiry is not checked here. Use `CLEAR_EXPIRED_EFFECTS` to actually delete expired entries.

**Returns:** A dictionary suitable for merging into a `modifiers` dict. Keys have the form `<Bonus Type> Bonus` or `<Bonus Type> Penalty`. Bonus Types with no contribution are omitted entirely.

1. `highest_bonus = empty dictionary` (Bonus Type → integer)
2. `highest_penalty = empty dictionary` (Bonus Type → integer)
3. `for each entry in effects:`
4. `⠀⠀if entry['target_key'] != target_key:`
5. `⠀⠀⠀⠀continue`
6. `⠀⠀if entry['amount'] == 0:`
7. `⠀⠀⠀⠀continue`
8. `⠀⠀if current_round is not null and entry['ends_on_round'] is not null and entry['ends_on_round'] <= current_round:`
9. `⠀⠀⠀⠀continue`
10. `⠀⠀type = entry['bonus_type']`
11. `⠀⠀if entry['sign'] == 'bonus':`
12. `⠀⠀⠀⠀if type not in highest_bonus or entry['amount'] > highest_bonus[type]:`
13. `⠀⠀⠀⠀⠀⠀highest_bonus[type] = entry['amount']`
14. `⠀⠀else:`
15. `⠀⠀⠀⠀if type not in highest_penalty or entry['amount'] > highest_penalty[type]:`
16. `⠀⠀⠀⠀⠀⠀highest_penalty[type] = entry['amount']`
17. `result = empty dictionary`
18. `for each (type, value) in highest_bonus:`
19. `⠀⠀result[type + ' Bonus'] = value`
20. `for each (type, value) in highest_penalty:`
21. `⠀⠀result[type + ' Penalty'] = value`
22. `return result`

**Notes:**
- Callers that want both Conditions modifiers and equipment/class modifiers in a single Roll merge the dicts by summing same-keyed values, then pass the merged dict to `DiceSystem.COMPUTE_ROLL_PARAMETERS`. Validation (unknown Bonus Types) is performed by that call.
- This method is read-only: it never mutates `effects`. Pair with `CLEAR_EXPIRED_EFFECTS` when you also want to drop expired entries from storage.

---

## TO_DICT

**Description:** Returns a serialization-friendly snapshot of the instance's complete state. The returned dictionary contains only primitive values, lists, and nested dictionaries — no class instances or references — so the caller can hand it to JSON, YAML, or any other format. Round-trips losslessly through `LOAD_STATE`.

**Parameters:** None.

**Returns:** A dictionary with the following keys:
- `'hit_point_damage'`: dictionary mapping each severity category to its current counter.
- `'ability_damage'`: ordered dictionary mapping attribute name to an ordered dictionary of severity to counter.
- `'temporary_hit_points'`: null, or a dictionary `{ 'amount': int, 'source_id': string, 'ends_on_round': int-or-null }`.
- `'magic_toxicity'`: integer.
- `'shock'`: integer.
- `'afflictions'`: ordered dictionary mapping affliction name to `{ 'severity': int, 'inflicting_tier': int }`.
- `'effects'`: list of Effect entries in their stored order.

1. `return {`
2. `⠀⠀'hit_point_damage': shallow_copy(hit_point_damage),`
3. `⠀⠀'ability_damage': deep_copy(ability_damage),`
4. `⠀⠀'temporary_hit_points': (temporary_hit_points is null) ? null : shallow_copy(temporary_hit_points),`
5. `⠀⠀'magic_toxicity': magic_toxicity,`
6. `⠀⠀'shock': shock,`
7. `⠀⠀'afflictions': deep_copy(afflictions),`
8. `⠀⠀'effects': deep_copy(effects)`
9. `}`

**Notes:**
- Deep copies guard against the caller mutating returned containers and accidentally corrupting instance state. Implementers in languages with immutable-by-default collections may skip the copy.
- `conditions_config` and `dice_system` are deliberately excluded — they are construction inputs, not state. Reload them on the next `CONSTRUCTOR` call.

---

## LOAD_STATE

**Description:** Replaces the instance's mutable state with the contents of a previously serialized snapshot. Validates that severity categories and effect signs are recognized, but trusts attribute names, target keys, bonus types, and metadata as-is.

**Parameters:**
- `state`: a dictionary in the shape produced by `TO_DICT`. Missing top-level keys are treated as their empty defaults (so a partial snapshot is legal).

**Returns:** None.

1. `severity_list = conditions_config['Severity Categories List']`
2. `hit_point_damage = { category: 0 for each category in severity_list }`
3. `if 'hit_point_damage' in state:`
4. `⠀⠀for each (category, value) in state['hit_point_damage']:`
5. `⠀⠀⠀⠀if category not in severity_list:`
6. `⠀⠀⠀⠀⠀⠀raise exception ('Unrecognized severity category in state: ' + category)`
7. `⠀⠀⠀⠀hit_point_damage[category] = value`
8. `ability_damage = empty ordered dictionary`
9. `if 'ability_damage' in state:`
10. `⠀⠀for each (attribute, severities) in state['ability_damage'] (in order):`
11. `⠀⠀⠀⠀ability_damage[attribute] = ordered dictionary { category: 0 for each category in severity_list }`
12. `⠀⠀⠀⠀for each (category, value) in severities:`
13. `⠀⠀⠀⠀⠀⠀if category not in severity_list:`
14. `⠀⠀⠀⠀⠀⠀⠀⠀raise exception ('Unrecognized severity category in state: ' + category)`
15. `⠀⠀⠀⠀⠀⠀ability_damage[attribute][category] = value`
16. `temporary_hit_points = state['temporary_hit_points'] if 'temporary_hit_points' in state else null`
17. `magic_toxicity = state['magic_toxicity'] if 'magic_toxicity' in state else 0`
18. `shock = state['shock'] if 'shock' in state else 0`
19. `afflictions = empty ordered dictionary`
20. `if 'afflictions' in state:`
21. `⠀⠀for each (name, entry) in state['afflictions'] (in order):`
22. `⠀⠀⠀⠀if name not in conditions_config['Afflictions']:`
23. `⠀⠀⠀⠀⠀⠀raise exception ('Unknown affliction in state: ' + name)`
24. `⠀⠀⠀⠀afflictions[name] = { 'severity': entry['severity'], 'inflicting_tier': entry['inflicting_tier'] if 'inflicting_tier' in entry else 0 }`
25. `effects = empty list`
26. `if 'effects' in state:`
27. `⠀⠀for each entry in state['effects'] (in order):`
28. `⠀⠀⠀⠀if entry['sign'] not in ['bonus', 'penalty']:`
29. `⠀⠀⠀⠀⠀⠀raise exception ('Unrecognized effect sign in state: ' + entry['sign'])`
30. `⠀⠀⠀⠀effects.append(deep_copy(entry))`

**Notes:**
- `LOAD_STATE` is the seam used by `CONSTRUCTOR(initial_state=...)` and may also be called later to swap state mid-life (e.g. for time-travel debugging). The caller is responsible for passing a snapshot produced against the same `conditions_config` — this method does not migrate state across config changes.
- Unknown afflictions are rejected because their resolution rule isn't loadable; unknown attributes and target keys are accepted because they are opaque by design.

