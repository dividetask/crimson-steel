# Abilities and Spells — Pseudocode

## Conventions

- Class names use `PascalCase`. Method names use `ALL_CAPS_WITH_UNDERSCORES` to signal pseudocode.
- Config is accessed as `abilities_config['Key Name']` using the human-readable keys defined in `abilities_config.yaml`.
- Entry data is accessed as `abilities_data[entry_name]` using the entry's display name as the key.
- `floor(x)` returns the largest integer less than or equal to `x`.
- `null` should be translated to `null` in C# and `nil` in Ruby.
- Boolean-to-integer conversions use an explicit ternary `(cond) ? 1 : 0` so both target languages translate directly without relying on implicit coercion.
- The abilities module is a read-only reference: no method in `AbilitySystem` mutates the loaded data.

## Common Variables/Parameters

- `entry_name`: the display-name key of a spell or ability entry.
- `entry`: the full dictionary loaded for a given `entry_name`.
- `rank`: the caster's rank in the casting skill being used. Required whenever a Formula is evaluated.
- `tier_index`: the index into an Entry's `tier` list when the Entry has multiple Variants. `null` for single-tier Entries.
- `context`: the dictionary of variables used to evaluate a Formula. Always contains `rank`; additionally contains `tier`, every name defined in the Entry's Effect Hash after resolution, and — only when evaluating a damage expression — `success`, `critical`, and `attribute`. Range Formulas additionally see `reach` (see `RESOLVE_RANGE`).
- `success_count`, `critical_count`, `attribute_value`: roll- and attribute-based values supplied by the caller to `EVALUATE_DAMAGE` at evaluation time. For a Save Effect, `success_count` and `critical_count` describe the defender's save; for an Unconditional Effect, they describe the caster's casting roll. `attribute_value` is the casting attribute's current value. Not available during `RESOLVE_ENTRY`.
- `reach`: the caster's reach in feet. Supplied by the caller to `RESOLVE_RANGE` (or, transitively, `RESOLVE_ENTRY`); defaults to `Default Reach Feet` from the config when omitted.

---

# CLASS AbilitySystem

## State

- `abilities_config`: dictionary of configuration values loaded from YAML.
- `abilities_data`: dictionary of Entry definitions, keyed by entry name.

---

## CONSTRUCTOR

**Description:** Loads the configuration file and the entry data file, and validates every entry. Raises if any entry fails validation.
**Parameters:**
- `config_path`: path to the YAML configuration file.
- `data_path`: path to the data file containing Entry definitions (YAML or JSON).

**Returns:** None (constructor).

1. `abilities_config = load_yaml(config_path)`
2. `abilities_data = load_data(data_path)`
3. `for each entry_name, entry in abilities_data:`
4. `⠀⠀VALIDATE_ENTRY(entry_name, entry)`
5. `store abilities_config and abilities_data as instance state`

---

## VALIDATE_ENTRY

**Description:** Checks that an Entry conforms to the schema described in the glossary. Raises a descriptive exception on any violation. Pure validation — no mutation of the Entry.
**Parameters:**
- `entry_name`: the display-name key of the entry, used only in error messages.
- `entry`: the Entry dictionary.

**Returns:** None. Raises on violation.

1. `if entry['type'] not in abilities_config['Entry Types']:`
2. `⠀⠀raise exception ('Unrecognized entry type: ' + entry['type'] + ' in ' + entry_name)`
3. `if entry['type'] == 'spell':`
4. `⠀⠀if entry['school'] not in abilities_config['Spell Schools']:`
5. `⠀⠀⠀⠀raise exception ('Unrecognized spell school in ' + entry_name)`
6. `⠀⠀for each item in entry.get('items', []):`
7. `⠀⠀⠀⠀if item not in abilities_config['Item Forms']:`
8. `⠀⠀⠀⠀⠀⠀raise exception ('Unrecognized item form in ' + entry_name)`
9. `⠀⠀⠀⠀if item in abilities_config['Universal Item Forms']:`
10. `⠀⠀⠀⠀⠀⠀raise exception ('Universal item form ' + item + ' must not be listed explicitly in ' + entry_name)`
11. `for each skill in entry.get('skills', []):`
12. `⠀⠀if skill not in abilities_config['Casting Skills List']:`
13. `⠀⠀⠀⠀raise exception ('Unrecognized casting skill in ' + entry_name)`
14. `⠀⠀if skill in abilities_config['Universal Spell Casting Skills']:`
15. `⠀⠀⠀⠀raise exception ('Universal casting skill ' + skill + ' must not be listed explicitly in ' + entry_name)`
16. `casting_time = entry['casting_time']`
17. `if casting_time not in abilities_config['Casting Time Aliases'] and not matches pattern '<positive integer> rounds':`
18. `⠀⠀raise exception ('Unrecognized casting time in ' + entry_name)`
19. `range_value = entry['range']`
20. `if range_value is a string and range_value not in abilities_config['Range Formulas']:`
21. `⠀⠀raise exception ('Unrecognized range in ' + entry_name)`
22. `if range_value is not a string and range_value is not a non-negative integer:`
23. `⠀⠀raise exception ('Range must be a named Range or a non-negative integer in ' + entry_name)`
24. `if 'area' in entry:`
25. `⠀⠀area = entry['area']`
26. `⠀⠀if area is not a dictionary:`
27. `⠀⠀⠀⠀raise exception ('area must be a dictionary in ' + entry_name)`
28. `⠀⠀if area['shape'] not in abilities_config['Area Shapes']:`
29. `⠀⠀⠀⠀raise exception ('Unrecognized area shape in ' + entry_name)`
30. `⠀⠀if area['size'] is not a non-negative integer:`
31. `⠀⠀⠀⠀raise exception ('area size must be a non-negative integer in ' + entry_name)`
32. `if 'attack_roll' in entry and entry['attack_roll'] is not a boolean:`
33. `⠀⠀raise exception ('attack_roll must be a boolean in ' + entry_name)`
34. `for each property in entry.get('properties', []):`
35. `⠀⠀if property not in abilities_config['Properties']:`
36. `⠀⠀⠀⠀raise exception ('Unrecognized property: ' + property + ' in ' + entry_name)`
37. `if 'damage_type' in entry and entry['damage_type'] is not a string:`
38. `⠀⠀raise exception ('damage_type must be a string in ' + entry_name)`
39. `for each effect in entry.get('effects', []):`
40. `⠀⠀VALIDATE_EFFECT(effect, entry_name)`
41. `for each save_spec in entry.get('save', []):`
42. `⠀⠀if save_spec['attribute'] not in abilities_config['Save Attributes List']:`
43. `⠀⠀⠀⠀raise exception ('Unrecognized save attribute in ' + entry_name)`
44. `⠀⠀if 'fail' not in save_spec:`
45. `⠀⠀⠀⠀raise exception ('Save spec missing fail branch in ' + entry_name)`
46. `⠀⠀for each key in save_spec:`
47. `⠀⠀⠀⠀if key not in ['attribute', 'condition'] and key not in abilities_config['Save Outcome Keys']:`
48. `⠀⠀⠀⠀⠀⠀raise exception ('Unrecognized save outcome key in ' + entry_name)`
49. `⠀⠀if 'condition' in save_spec and save_spec['condition'] not in ['on_fail', 'on_fumble']:`
50. `⠀⠀⠀⠀raise exception ('Unrecognized save condition in ' + entry_name)`
51. `⠀⠀for each outcome_key in abilities_config['Save Outcome Keys']:`
52. `⠀⠀⠀⠀if outcome_key in save_spec:`
53. `⠀⠀⠀⠀⠀⠀VALIDATE_EFFECT(save_spec[outcome_key], entry_name)`
54. `if entry['tier'] is a list:`
55. `⠀⠀tier_count = length(entry['tier'])`
56. `⠀⠀for each field in ['prefix', 'suffix', 'name', 'variant_overrides']:`
57. `⠀⠀⠀⠀if field in entry and length(entry[field]) != tier_count:`
58. `⠀⠀⠀⠀⠀⠀raise exception (field + ' length does not match tier count in ' + entry_name)`
59. `⠀⠀for each override in entry.get('variant_overrides', []):`
60. `⠀⠀⠀⠀if override is null:`
61. `⠀⠀⠀⠀⠀⠀continue`
62. `⠀⠀⠀⠀if override is not a dictionary:`
63. `⠀⠀⠀⠀⠀⠀raise exception ('variant_overrides entries must be null or a dictionary in ' + entry_name)`
64. `⠀⠀⠀⠀for each key in override:`
65. `⠀⠀⠀⠀⠀⠀if key in ['tier', 'prefix', 'suffix', 'name', 'variant_overrides']:`
66. `⠀⠀⠀⠀⠀⠀⠀⠀raise exception ('variant_overrides may not override ' + key + ' in ' + entry_name)`
67. `else:`
68. `⠀⠀for each field in ['prefix', 'suffix', 'name', 'variant_overrides']:`
69. `⠀⠀⠀⠀if field in entry:`
70. `⠀⠀⠀⠀⠀⠀raise exception (field + ' is only valid on multi-tier entries: ' + entry_name)`
71. `if 'concentration' in entry:`
72. `⠀⠀VALIDATE_CONCENTRATION(entry['concentration'], entry_name)`

---

## Helper: VALIDATE_EFFECT

**Description:** Internal helper. Checks that an Effect string is one of the accepted forms: `"0"`, `"none"`, a damage expression (`"<formula> damage"`), or a name that appears as a key in `Effect Names`. The `Effect Names` table maps each name to a `{description, mechanics}` dictionary; only the key existence is checked here. Used for both Save Effects (values inside save outcomes) and Unconditional Effects (entries in the top-level `effects` list). Does not evaluate Formulas — only checks that the shape is valid.
**Parameters:**
- `effect`: the raw Effect string.
- `entry_name`: the enclosing entry name, used only in error messages.

**Returns:** None. Raises on violation.

1. `if effect == '0' or effect == 'none':`
2. `⠀⠀return`
3. `if effect matches pattern '<expression> damage':`
4. `⠀⠀return`
5. `if effect in abilities_config['Effect Names']:`
6. `⠀⠀return`
7. `raise exception ('Unrecognized effect: ' + effect + ' in ' + entry_name)`

---

## Helper: APPLY_VARIANT_OVERRIDES

**Description:** Internal helper. Returns a new entry dictionary with the Variant Overrides at `tier_index` shallow-merged onto the base entry. For single-tier entries (no `tier` list) and entries without `variant_overrides`, returns the entry unchanged. The returned dictionary is the input that all per-tier resolution methods see.

A `null` value in an override means "remove this key from the merged entry" — useful for tiers that opt out of a field the base entry sets, such as removing the `concentration` block at a higher tier of a spell whose lower tiers required concentration.
**Parameters:**
- `entry`: the Entry dictionary as loaded.
- `tier_index` *(optional)*: the index into the Entry's tier list, or `null` for single-tier Entries.

**Returns:** A dictionary — either the original entry (when no merge is needed) or a new dictionary with overrides applied.

1. `if entry['tier'] is not a list:`
2. `⠀⠀return entry`
3. `if 'variant_overrides' not in entry:`
4. `⠀⠀return entry`
5. `override = entry['variant_overrides'][tier_index]`
6. `if override is null:`
7. `⠀⠀return entry`
8. `merged = entry copy`
9. `for each key, value in override:`
10. `⠀⠀if value is null:`
11. `⠀⠀⠀⠀if key in merged:`
12. `⠀⠀⠀⠀⠀⠀remove key from merged`
13. `⠀⠀else:`
14. `⠀⠀⠀⠀merged[key] = value`
15. `return merged`

**Notes:** The merge is a shallow replace — list-valued and dictionary-valued overrides replace the base value entirely. There is no deep-merge step. A `null` override value removes the key rather than setting it to null; an override that wants the key absent in the merged entry simply lists it with a null value.

---

## Helper: VALIDATE_CONCENTRATION

**Description:** Internal helper. Checks that a Concentration Block conforms to its schema. Does not evaluate Formulas — only checks shape.
**Parameters:**
- `block`: the Concentration Block dictionary.
- `entry_name`: the enclosing entry name, used only in error messages.

**Returns:** None. Raises on violation.

1. `if 'action' not in block:`
2. `⠀⠀raise exception ('Concentration block missing action in ' + entry_name)`
3. `action = block['action']`
4. `if action not in abilities_config['Casting Time Aliases'] and not matches pattern '<positive integer> rounds':`
5. `⠀⠀raise exception ('Unrecognized concentration action in ' + entry_name)`
6. `if 'apply_on_cast' in block and block['apply_on_cast'] is not a boolean:`
7. `⠀⠀raise exception ('apply_on_cast must be a boolean in ' + entry_name)`
8. `if 'retarget' in block and block['retarget'] is not a boolean:`
9. `⠀⠀raise exception ('concentration retarget must be a boolean in ' + entry_name)`
10. `if 'attack_roll' in block and block['attack_roll'] is not a boolean:`
11. `⠀⠀raise exception ('concentration attack_roll must be a boolean in ' + entry_name)`
12. `for each save_spec in block.get('save', []):`
13. `⠀⠀if save_spec['attribute'] not in abilities_config['Save Attributes List']:`
14. `⠀⠀⠀⠀raise exception ('Unrecognized save attribute in concentration of ' + entry_name)`
15. `⠀⠀if 'fail' not in save_spec:`
16. `⠀⠀⠀⠀raise exception ('Concentration save spec missing fail branch in ' + entry_name)`
17. `⠀⠀for each outcome_key in abilities_config['Save Outcome Keys']:`
18. `⠀⠀⠀⠀if outcome_key in save_spec:`
19. `⠀⠀⠀⠀⠀⠀VALIDATE_EFFECT(save_spec[outcome_key], entry_name)`

---

## GET_ENTRY

**Description:** Returns the raw Entry dictionary for the named spell or ability. Does not evaluate any Formulas; returns the entry as stored.
**Parameters:**
- `entry_name`: the display-name key of the entry.

**Returns:** The Entry dictionary.

1. `if entry_name not in abilities_data:`
2. `⠀⠀raise exception ('Unknown entry: ' + entry_name)`
3. `return abilities_data[entry_name]`

---

## LIST_ENTRIES

**Description:** Returns the list of entry names, optionally filtered by Entry Type and/or Spell School.
**Parameters:**
- `type_filter` *(optional)*: one of the values in `Entry Types`, or `null` for no type filter.
- `school_filter` *(optional)*: a Spell School key, or `null` for no school filter.

**Returns:** A list of entry-name strings.

1. `result = []`
2. `for each entry_name, entry in abilities_data:`
3. `⠀⠀if type_filter is not null and entry['type'] != type_filter:`
4. `⠀⠀⠀⠀continue`
5. `⠀⠀if school_filter is not null and entry.get('school') != school_filter:`
6. `⠀⠀⠀⠀continue`
7. `⠀⠀result.append(entry_name)`
8. `return result`

---

## Helper: TIER_VALUE

**Description:** Internal helper. Returns the numeric tier value used in formulas, treating Tier 0 as 0.5 per the project-wide convention.
**Parameters:**
- `tier`: an integer tier value.

**Returns:** A numeric value.

1. `if tier == 0:`
2. `⠀⠀return 0.5`
3. `return tier`

---

## Helper: RESOLVE_EFFECT_HASH

**Description:** Internal helper. Walks the Entry's Effect Hash, selecting per-tier values and evaluating Formula strings to produce a flat dictionary of names to numeric values. For a single-tier Entry, `tier_index` is `null` and list-valued Effect Hash entries are treated as-is (which indicates a schema error and is caught by `VALIDATE_ENTRY`).
**Parameters:**
- `entry`: the Entry dictionary.
- `tier_index` *(optional)*: the index into the Entry's tier list, or `null` for single-tier Entries.
- `rank`: the caster's rank.

**Returns:** A dictionary of resolved Effect Hash values.

1. `resolved = empty dictionary`
2. `context = { 'rank': rank }`
3. `if entry['tier'] is a list:`
4. `⠀⠀context['tier'] = TIER_VALUE(entry['tier'][tier_index])`
5. `else:`
6. `⠀⠀context['tier'] = TIER_VALUE(entry['tier'])`
7. `for each name, raw_value in entry.get('effect_hash', empty dictionary):`
8. `⠀⠀if raw_value is a list and entry['tier'] is a list:`
9. `⠀⠀⠀⠀value = raw_value[tier_index]`
10. `⠀⠀else:`
11. `⠀⠀⠀⠀value = raw_value`
12. `⠀⠀if value is a string:`
13. `⠀⠀⠀⠀value = EVALUATE_FORMULA(value, context)`
14. `⠀⠀resolved[name] = value`
15. `⠀⠀context[name] = value`
16. `return resolved`

---

## EVALUATE_FORMULA

**Description:** Evaluates a Formula string against a context dictionary. The Formula may contain numeric literals, the operators `+ - * /`, parentheses, and the `floor()` function. All division is integer division using `floor()` per the project-wide formula convention. The caller supplies every variable name the Formula may reference via `context`; any unresolved name raises an exception.
**Parameters:**
- `formula`: the Formula string.
- `context`: a dictionary of variable names to numeric values.

**Returns:** A numeric value.

**Notes:** The concrete parser is language-specific. Both target implementations MUST enforce `floor()` division and MUST reject any name not present in `context`. Attempting to evaluate a Formula without the required `rank` in `context` is a programming error and raises.

---

## RESOLVE_CASTING_TIME

**Description:** Converts an Entry's `casting_time` string into a number of rounds. Fractional rounds are preserved (e.g. a Bonus Action yields 0.25).
**Parameters:**
- `entry`: the Entry dictionary.

**Returns:** A numeric value — the casting time in rounds.

1. `casting_time = entry['casting_time']`
2. `if casting_time in abilities_config['Casting Time Aliases']:`
3. `⠀⠀return abilities_config['Casting Time Aliases'][casting_time]`
4. `if casting_time matches pattern '<N> rounds' for positive integer N:`
5. `⠀⠀return N`
6. `raise exception ('Unrecognized casting time: ' + casting_time)`

---

## RESOLVE_RANGE

**Description:** Converts an Entry's `range` field into a distance in feet, evaluating the Range Formula for the caster's rank and reach when the range is a named Range. The caller may supply a per-cast `reach` value for larger creatures; when omitted, `Default Reach Feet` from the config is used.
**Parameters:**
- `entry`: the Entry dictionary.
- `rank`: the caster's rank.
- `reach` *(optional)*: the caster's reach in feet. Defaults to `abilities_config['Default Reach Feet']`.

**Returns:** A non-negative integer — the range in feet.

1. `range_value = entry['range']`
2. `if range_value is not a string:`
3. `⠀⠀return range_value`
4. `if reach is null:`
5. `⠀⠀reach = abilities_config['Default Reach Feet']`
6. `formula = abilities_config['Range Formulas'][range_value]`
7. `return floor(EVALUATE_FORMULA(formula, { 'rank': rank, 'reach': reach }))`

---

## RESOLVE_TARGET

**Description:** Converts an Entry's `target` field into an integer count, or returns the string `'self'` unchanged. The Entry's `target` field is always a string; a bare integer target is written as `"1"`, `"2"`, etc. and evaluated through the Formula path.
**Parameters:**
- `entry`: the Entry dictionary.
- `rank`: the caster's rank.

**Returns:** Either the string `'self'` or a non-negative integer.

1. `target = entry['target']`
2. `if target == 'self':`
3. `⠀⠀return 'self'`
4. `count = floor(EVALUATE_FORMULA(target, { 'rank': rank }))`
5. `if count < 0:`
6. `⠀⠀count = 0`
7. `return count`

---

## GET_SAVE_LIST

**Description:** Returns the list of Save Specs for an Entry with each Save Effect classified into one of three kinds: `none`, `effect`, or `damage`. Named effects (`blind`, `dazzled`, etc.) are returned verbatim. Damage expressions are returned as structured objects containing the damage Formula and a partial context (with `rank`, `tier`, and Effect Hash names pre-bound) — the Formula is not evaluated here because it may reference `success` and `critical`, which are only known after the defender rolls. Callers pass the damage object to `EVALUATE_DAMAGE` with the roll results to obtain the final damage value.
**Parameters:**
- `entry`: the Entry dictionary.
- `rank`: the caster's rank.
- `tier_index` *(optional)*: the index into the Entry's tier list, or `null` for single-tier Entries.

**Returns:** A list of dictionaries. Each dictionary has an `attribute` key, an optional `condition` key, and zero or more of the Save Outcome Keys. The value at each Save Outcome Key is itself a dictionary:
- `{ 'kind': 'none' }` — the literal `"0"` or `"none"`.
- `{ 'kind': 'effect', 'name': <string> }` — a named effect from `Effect Names`.
- `{ 'kind': 'damage', 'formula': <string>, 'damage_type': <string-or-null>, 'context': <dict> }` — a damage expression carrying the Entry's `damage_type` and its partial context.

1. `effect_hash = RESOLVE_EFFECT_HASH(entry, tier_index, rank)`
2. `partial_context = effect_hash copy`
3. `partial_context['rank'] = rank`
4. `if entry['tier'] is a list:`
5. `⠀⠀partial_context['tier'] = TIER_VALUE(entry['tier'][tier_index])`
6. `else:`
7. `⠀⠀partial_context['tier'] = TIER_VALUE(entry['tier'])`
8. `damage_type = entry.get('damage_type')`
9. `result = []`
10. `for each save_spec in entry.get('save', []):`
11. `⠀⠀resolved_spec = { 'attribute': save_spec['attribute'] }`
12. `⠀⠀if 'condition' in save_spec:`
13. `⠀⠀⠀⠀resolved_spec['condition'] = save_spec['condition']`
14. `⠀⠀for each outcome_key in abilities_config['Save Outcome Keys']:`
15. `⠀⠀⠀⠀if outcome_key in save_spec:`
16. `⠀⠀⠀⠀⠀⠀resolved_spec[outcome_key] = CLASSIFY_EFFECT(save_spec[outcome_key], partial_context, damage_type)`
17. `⠀⠀result.append(resolved_spec)`
18. `return result`

---

## GET_EFFECTS

**Description:** Returns the list of Unconditional Effects for an Entry, classified into one of three kinds the same way `GET_SAVE_LIST` classifies save effects. Damage Formulas are not evaluated; the returned `damage` objects carry a partial context that the caller passes to `EVALUATE_DAMAGE` along with the caster's casting-roll success and critical counts.
**Parameters:**
- `entry`: the Entry dictionary.
- `rank`: the caster's rank.
- `tier_index` *(optional)*: the index into the Entry's tier list, or `null` for single-tier Entries.

**Returns:** A list of classified Effect dictionaries (same shape as the values in `GET_SAVE_LIST`):
- `{ 'kind': 'none' }`
- `{ 'kind': 'effect', 'name': <string> }`
- `{ 'kind': 'damage', 'formula': <string>, 'damage_type': <string-or-null>, 'context': <dict> }`

1. `effect_hash = RESOLVE_EFFECT_HASH(entry, tier_index, rank)`
2. `partial_context = effect_hash copy`
3. `partial_context['rank'] = rank`
4. `if entry['tier'] is a list:`
5. `⠀⠀partial_context['tier'] = TIER_VALUE(entry['tier'][tier_index])`
6. `else:`
7. `⠀⠀partial_context['tier'] = TIER_VALUE(entry['tier'])`
8. `damage_type = entry.get('damage_type')`
9. `result = []`
10. `for each effect in entry.get('effects', []):`
11. `⠀⠀result.append(CLASSIFY_EFFECT(effect, partial_context, damage_type))`
12. `return result`

---

## Helper: CLASSIFY_EFFECT

**Description:** Internal helper. Classifies a raw Effect string into one of three kinds. Does not evaluate the damage Formula — only attaches the partial context so the Formula can be evaluated later by `EVALUATE_DAMAGE`. Used for both Save Effects and Unconditional Effects. The `damage_type` parameter is attached to `damage`-kind classifications and ignored for the other kinds.
**Parameters:**
- `effect`: the raw Effect string.
- `partial_context`: a dictionary containing `rank`, `tier`, and every resolved Effect Hash name.
- `damage_type` *(optional)*: the Entry's `damage_type` value, or `null` when the Entry has no `damage_type`.

**Returns:** A classified Effect dictionary (see `GET_SAVE_LIST` / `GET_EFFECTS`).

1. `if effect == '0' or effect == 'none':`
2. `⠀⠀return { 'kind': 'none' }`
3. `if effect matches pattern '<expression> damage':`
4. `⠀⠀return { 'kind': 'damage', 'formula': expression, 'damage_type': damage_type, 'context': partial_context copy }`
5. `return { 'kind': 'effect', 'name': effect }`

---

## EVALUATE_DAMAGE

**Description:** Evaluates a damage-kind Effect given the relevant roll's results and the caster's casting attribute. The Formula is evaluated against a context that is the Effect's partial context extended with `success`, `critical`, and `attribute`. The caller decides which roll's counts to supply: the defender's save for a Save Effect, or the caster's casting roll for an Unconditional Effect. Passing a non-damage Effect to this method raises.
**Parameters:**
- `effect`: a classified Effect dictionary with `kind == 'damage'`.
- `success_count`: the relevant roll's success count.
- `critical_count`: the relevant roll's critical count.
- `attribute_value` *(optional)*: the casting attribute's value. Defaults to `0` when the caller omits it; formulas that don't reference `attribute` are unaffected.

**Returns:** An integer — the damage value. Negative results are clamped to 0.

1. `if effect['kind'] != 'damage':`
2. `⠀⠀raise exception ('EVALUATE_DAMAGE called on non-damage effect')`
3. `context = effect['context'] copy`
4. `context['success'] = success_count`
5. `context['critical'] = critical_count`
6. `if attribute_value is null:`
7. `⠀⠀context['attribute'] = 0`
8. `else:`
9. `⠀⠀context['attribute'] = attribute_value`
10. `value = floor(EVALUATE_FORMULA(effect['formula'], context))`
11. `if value < 0:`
12. `⠀⠀value = 0`
13. `return value`

---

## VALID_ITEM_FORMS

**Description:** Returns the full list of Item Forms an Entry may be packaged into. Every Spell is implicitly eligible for every form in `Universal Item Forms` — those forms are appended after the entry's explicit list. Abilities return an empty list. Item-Only Entries return their explicit `items` list with no implicit forms.
**Parameters:**
- `entry`: the Entry dictionary.

**Returns:** A list of Item Form strings.

1. `if entry['type'] != 'spell':`
2. `⠀⠀return []`
3. `if entry.get('item_only', false):`
4. `⠀⠀return entry.get('items', [])`
5. `forms = copy of entry.get('items', [])`
6. `for each universal in abilities_config['Universal Item Forms']:`
7. `⠀⠀if universal not in forms:`
8. `⠀⠀⠀⠀forms.append(universal)`
9. `return forms`

---

## IS_ITEM_ONLY

**Description:** Returns true if the Entry can only be invoked through a magic item and cannot be cast directly.
**Parameters:**
- `entry`: the Entry dictionary.

**Returns:** A boolean.

1. `return entry.get('item_only', false)`

---

## GET_CASTING_SKILLS

**Description:** Returns the effective list of Casting Skills for an Entry. For Entries with `type: spell`, the Universal Spell Casting Skills from the config are appended after the Entry's explicit `skills` list. For abilities, returns the explicit `skills` list unchanged.
**Parameters:**
- `entry`: the Entry dictionary.

**Returns:** A list of skill keys.

1. `skills = entry.get('skills', []) copy`
2. `if entry['type'] == 'spell':`
3. `⠀⠀for each universal in abilities_config['Universal Spell Casting Skills']:`
4. `⠀⠀⠀⠀if universal not in skills:`
5. `⠀⠀⠀⠀⠀⠀skills.append(universal)`
6. `return skills`

---

## GET_VARIANT_NAME

**Description:** Returns the displayed name of a Variant. For single-tier Entries, returns the Entry's raw name. For multi-tier Entries, an explicit `name` override at `tier_index` (when present and non-null) is used verbatim; otherwise the displayed name is constructed as `<prefix> <entry_name> <suffix>` from the prefix and suffix lists at `tier_index`, omitting any null or empty parts.
**Parameters:**
- `entry_name`: the Entry's base name.
- `entry`: the Entry dictionary.
- `tier_index` *(optional)*: the index into the Entry's tier list, or `null` for single-tier Entries.

**Returns:** A string.

1. `if entry['tier'] is not a list:`
2. `⠀⠀return entry_name`
3. `if 'name' in entry and entry['name'][tier_index] is not null and entry['name'][tier_index] != '':`
4. `⠀⠀return entry['name'][tier_index]`
5. `parts = []`
6. `if 'prefix' in entry and entry['prefix'][tier_index] is not null and entry['prefix'][tier_index] != '':`
7. `⠀⠀parts.append(entry['prefix'][tier_index])`
8. `parts.append(entry_name)`
9. `if 'suffix' in entry and entry['suffix'][tier_index] is not null and entry['suffix'][tier_index] != '':`
10. `⠀⠀parts.append(entry['suffix'][tier_index])`
11. `return join(parts, ' ')`

---

## GET_CONCENTRATION

**Description:** Returns the resolved Concentration Block for an Entry, or `null` if the Entry has no `concentration` field. The block's `description` has `{name}` placeholders substituted from the resolved concentration `effect_hash`; `save` entries are classified the same way `GET_SAVE_LIST` classifies the top-level save list. Damage Formulas are not evaluated — they are returned in the same deferred form as top-level Save Effects so the caller can pass them to `EVALUATE_DAMAGE` once the save is rolled.
**Parameters:**
- `entry`: the Entry dictionary.
- `rank`: the caster's rank.
- `tier_index` *(optional)*: the index into the Entry's tier list, or `null` for single-tier Entries.

**Returns:** Either `null` or a dictionary containing:
- `'action'`: the action cost the caster spends each turn to keep concentrating.
- `'action_rounds'`: the action cost converted to rounds, using the same rules as `RESOLVE_CASTING_TIME`.
- `'apply_on_cast'`: boolean — whether the concentration effect also fires on the initial cast.
- `'retarget'`: boolean — whether the caster picks a new target each concentrate turn.
- `'attack_roll'`: boolean.
- `'saves'`: the classified save list (same shape as `GET_SAVE_LIST`).
- `'effect_hash'`: the resolved Effect Hash for the Concentration Block.
- `'description'`: the concentration description with `{name}` placeholders substituted.

1. `if 'concentration' not in entry:`
2. `⠀⠀return null`
3. `block = entry['concentration']`
4. `effect_hash = RESOLVE_EFFECT_HASH({'tier': entry['tier'], 'effect_hash': block.get('effect_hash', empty dictionary)}, tier_index, rank)`
5. `partial_context = effect_hash copy`
6. `partial_context['rank'] = rank`
7. `if entry['tier'] is a list:`
8. `⠀⠀partial_context['tier'] = TIER_VALUE(entry['tier'][tier_index])`
9. `else:`
10. `⠀⠀partial_context['tier'] = TIER_VALUE(entry['tier'])`
11. `damage_type = entry.get('damage_type')`
12. `saves = []`
13. `for each save_spec in block.get('save', []):`
14. `⠀⠀resolved_spec = { 'attribute': save_spec['attribute'] }`
15. `⠀⠀if 'condition' in save_spec:`
16. `⠀⠀⠀⠀resolved_spec['condition'] = save_spec['condition']`
17. `⠀⠀for each outcome_key in abilities_config['Save Outcome Keys']:`
18. `⠀⠀⠀⠀if outcome_key in save_spec:`
19. `⠀⠀⠀⠀⠀⠀resolved_spec[outcome_key] = CLASSIFY_EFFECT(save_spec[outcome_key], partial_context, damage_type)`
20. `⠀⠀saves.append(resolved_spec)`
21. `description = block.get('description', '')`
22. `for each name, value in effect_hash:`
23. `⠀⠀description = description with every '{' + name + '}' replaced by value`
24. `return { 'action': block['action'],`
25. `⠀⠀⠀⠀⠀⠀⠀'action_rounds': RESOLVE_CASTING_TIME({'casting_time': block['action']}),`
26. `⠀⠀⠀⠀⠀⠀⠀'apply_on_cast': block.get('apply_on_cast', false),`
27. `⠀⠀⠀⠀⠀⠀⠀'retarget': block.get('retarget', false),`
28. `⠀⠀⠀⠀⠀⠀⠀'attack_roll': block.get('attack_roll', false),`
29. `⠀⠀⠀⠀⠀⠀⠀'saves': saves,`
30. `⠀⠀⠀⠀⠀⠀⠀'effect_hash': effect_hash,`
31. `⠀⠀⠀⠀⠀⠀⠀'description': description }`

**Notes:**
- Step 4's "synthetic entry" pattern (passing `{'tier': ..., 'effect_hash': ...}` to `RESOLVE_EFFECT_HASH`) lets the helper apply tier-indexed list values inside the Concentration Block's Effect Hash without needing a second specialized helper.
- The Concentration Block's `effect_hash` is resolved independently of the Entry's top-level `effect_hash`. The two do not share a namespace at the Formula-evaluation level.

---

## RESOLVE_ENTRY

**Description:** Convenience method that returns every resolved field for an Entry in a single dictionary. This is the method most callers should prefer — it performs one pass of validation-by-use and avoids mismatches between independently-resolved fields.
**Parameters:**
- `entry_name`: the display-name key of the entry.
- `rank`: the caster's rank.
- `tier_index` *(optional)*: the index into the Entry's tier list, or `null` for single-tier Entries.
- `reach` *(optional)*: the caster's reach in feet, forwarded to `RESOLVE_RANGE`. Defaults to `abilities_config['Default Reach Feet']`.

**Returns:** A dictionary containing:
- `'name'`: the displayed Variant name.
- `'type'`: the Entry Type.
- `'school'`: the Spell School, or `null` for abilities.
- `'casting_time_rounds'`: the casting time in rounds.
- `'casting_time_label'`: the raw `casting_time` string.
- `'range_feet'`: the range in feet.
- `'target'`: either `'self'` or a non-negative integer.
- `'area'`: the Entry's `area` dictionary `{shape, size}`, or `null` when the Entry has no `area` field.
- `'attack_roll'`: boolean — whether the Entry requires an attack roll. Defaults to `false` when the field is absent.
- `'properties'`: the list of property keywords on the Entry. Empty when the Entry has no `properties` field.
- `'damage_type'`: the Entry's `damage_type` string, or `null` when the Entry has no `damage_type`.
- `'effects'`: the list of classified Unconditional Effects from `GET_EFFECTS`. Empty when the Entry has no `effects` field.
- `'saves'`: the resolved save list from `GET_SAVE_LIST`.
- `'duration'`: the raw duration string.
- `'skills'`: the list of Casting Skills.
- `'items'`: the Valid Item Forms list.
- `'item_only'`: boolean.
- `'effect_hash'`: the resolved Effect Hash.
- `'description'`: the description string with `{name}` placeholders substituted from the resolved Effect Hash.
- `'concentration'`: the resolved Concentration Block from `GET_CONCENTRATION`, or `null` when the Entry has no `concentration` field.

1. `entry = GET_ENTRY(entry_name)`
2. `entry = APPLY_VARIANT_OVERRIDES(entry, tier_index)`
3. `effect_hash = RESOLVE_EFFECT_HASH(entry, tier_index, rank)`
4. `description = entry.get('description', '')`
5. `for each name, value in effect_hash:`
6. `⠀⠀description = description with every '{' + name + '}' replaced by value`
7. `return { 'name': GET_VARIANT_NAME(entry_name, entry, tier_index),`
8. `⠀⠀⠀⠀⠀⠀⠀'type': entry['type'],`
9. `⠀⠀⠀⠀⠀⠀⠀'school': entry.get('school'),`
10. `⠀⠀⠀⠀⠀⠀⠀'casting_time_rounds': RESOLVE_CASTING_TIME(entry),`
11. `⠀⠀⠀⠀⠀⠀⠀'casting_time_label': entry['casting_time'],`
12. `⠀⠀⠀⠀⠀⠀⠀'range_feet': RESOLVE_RANGE(entry, rank, reach),`
13. `⠀⠀⠀⠀⠀⠀⠀'target': RESOLVE_TARGET(entry, rank),`
14. `⠀⠀⠀⠀⠀⠀⠀'area': entry.get('area'),`
15. `⠀⠀⠀⠀⠀⠀⠀'attack_roll': entry.get('attack_roll', false),`
16. `⠀⠀⠀⠀⠀⠀⠀'properties': entry.get('properties', []),`
17. `⠀⠀⠀⠀⠀⠀⠀'damage_type': entry.get('damage_type'),`
18. `⠀⠀⠀⠀⠀⠀⠀'effects': GET_EFFECTS(entry, rank, tier_index),`
19. `⠀⠀⠀⠀⠀⠀⠀'saves': GET_SAVE_LIST(entry, rank, tier_index),`
20. `⠀⠀⠀⠀⠀⠀⠀'duration': entry.get('duration', ''),`
21. `⠀⠀⠀⠀⠀⠀⠀'skills': GET_CASTING_SKILLS(entry),`
22. `⠀⠀⠀⠀⠀⠀⠀'items': VALID_ITEM_FORMS(entry),`
23. `⠀⠀⠀⠀⠀⠀⠀'item_only': IS_ITEM_ONLY(entry),`
24. `⠀⠀⠀⠀⠀⠀⠀'effect_hash': effect_hash,`
25. `⠀⠀⠀⠀⠀⠀⠀'description': description,`
26. `⠀⠀⠀⠀⠀⠀⠀'concentration': GET_CONCENTRATION(entry, rank, tier_index) }`

---

## Notes on Scope

The `AbilitySystem` class is strictly a reference. It does not roll dice, resolve saves, consume resources, or track active effects. Callers that want to actually resolve a cast must combine the dictionary returned by `RESOLVE_ENTRY` with the dice resolution module and the condition/combat modules that own active-effect bookkeeping.

Formulas never reach out to other modules; every name a Formula references must be supplied in its context. This keeps the module's dependencies to exactly two: the YAML loader and the Formula evaluator.
