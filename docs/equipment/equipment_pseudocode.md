# Equipment System — Pseudocode

## Conventions

- Class names use `PascalCase`. Method names use `ALL_CAPS_WITH_UNDERSCORES` to signal pseudocode.
- Config is accessed as `equipment_config['Key Name']` using the human-readable keys defined in `equipment_config.yaml`.
- `RAND_INT(low, high)` returns a uniformly random integer in the inclusive range `[low, high]`. `RAND_FLOAT()` returns a uniform real in `[0, 1)`.
- `floor(x)` returns the largest integer less than or equal to `x`. Divisions involving integer Quantities (e.g., bundle counts) use `floor`; divisions involving Gold prices are real-valued because prices may be fractional (e.g., 7.75 gp for a magical arrow).
- `null` should be translated to `null` in C# and `nil` in Ruby.
- Equality on floats should use a tolerance of `1e-9` for price comparisons; prices can be fractional (e.g., 7.75 gp).
- This module does not share the `DiceSystem` class. Loot Tables evaluate arbitrary dice strings (`"2d6 + 3"`) via a local helper, `RAND_ROLL_DICE_EXPRESSION`. `DiceSystem` is for the success-counting d10 resolution system and is not used here.
- Inventory data is written back to the same yaml file it was loaded from. The `Equipment` class is the sole writer; other modules must not touch `loot.yaml`, `loot_tables.yaml`, or `shops.yaml` directly.

## Common Variables/Parameters

- `owner_id`: a string identifying an Owner. Character IDs are bare strings (`"alice"`). The party is the reserved string `"party"`. Ground Piles use `"ground:<location>"`. Specific Shops use `"shop:<id>"`. Active Generic Shops use `"generic_shop:<id>"`.
- `item_stack`: a dictionary of inventory fields. Required: `item`. Optional: `quantity`, `tier`, `properties`, `stored_spell`, `durability_damage`, `name`, `restock_target`, `value_in_gold`.
- `table_id`: the string id of a Loot Table.
- `constraint`: a Magical Item Constraint (see GENERATE_MAGICAL_ITEM).
- `days_elapsed`: a non-negative integer passed to ADVANCE_TIME.

## Identity Fields

The Stack Identity of an Item Stack is the tuple of:

1. `item`
2. `tier` (default 0 when absent)
3. `properties` (default empty list; order-sensitive)
4. `stored_spell` (default null)
5. `durability_damage` (default 0)
6. `name` (default null — the Name Override, not the generated name)
7. `value_in_gold` (default null; present only on Gems)

Two stacks match if and only if all seven fields are equal. The `quantity` and `restock_target` fields are NOT identity fields.

---

# CLASS Equipment

## State

- `equipment_config`: dictionary loaded from `equipment_config.yaml`.
- `loot`: dictionary from `owner_id` to `{ 'inventory': [item_stack, ...], 'source_file': string }`. Covers Characters, the Party, Ground Piles.
- `loot_tables`: dictionary from `table_id` to `{ 'table': table_data, 'source_file': string }`.
- `option_lists`: dictionary from list name to a list of weighted options (aggregated across all loot-table files).
- `specific_shops`: dictionary from `shop_id` (without the `"shop:"` prefix) to `{ 'template': table_id, 'inventory': [...], 'source_file': string }`.
- `generic_shop_templates`: dictionary from `shop_id` (without the `"generic_shop:"` prefix) to `{ 'template': table_id, 'source_file': string }`.
- `active_generic_shops`: dictionary from `shop_id` to `{ 'stock': [item_stack, ...], 'generated_at_day': integer }`.
- `current_day`: non-negative integer; the Game Day counter.
- `random_source`: source of random numbers (`RAND_INT`, `RAND_FLOAT`).

---

## CONSTRUCTOR

**Description:** Loads all yaml files and initializes the random source.
**Parameters:**
- `data_dir`: directory containing `equipment_config.yaml`, `loot.yaml`, `loot_tables.yaml`, `shops.yaml`, and any matching `loot-*.yaml`, `loot_tables-*.yaml`, `shops-*.yaml`.
- `random_source` *(optional)*: a random source, useful for deterministic tests. If omitted, a default system random source is created.

**Returns:** None.

1. `equipment_config = load_yaml(data_dir + '/equipment_config.yaml')`
2. `if random_source is null:`
3. `⠀⠀random_source = new default_random_source()`
4. `LOAD_LOOT_FILES(data_dir)`
5. `LOAD_LOOT_TABLE_FILES(data_dir)`
6. `LOAD_SHOP_FILES(data_dir)`
7. `store all state on the instance`

---

## LOAD_LOOT_FILES

**Description:** Reads `loot.yaml` plus every `loot-*.yaml` in the data directory, populating `loot`. Entries from later files concatenate with earlier ones; duplicate `owner_id`s are an error (raise). Each Owner records the file it was loaded from.

**Parameters:**
- `data_dir`: same as CONSTRUCTOR.

**Returns:** None; mutates `loot`.

1. `loot = empty dictionary`
2. `file_paths = [data_dir + '/loot.yaml'] + sorted(glob(data_dir + '/loot-*.yaml'))`
3. `for each file_path in file_paths:`
4. `⠀⠀data = load_yaml(file_path) or empty dictionary`
5. `⠀⠀for each (owner_key, owner_data) in iterate_owner_entries(data):`
6. `⠀⠀⠀⠀if owner_key in loot:`
7. `⠀⠀⠀⠀⠀⠀raise exception ('Duplicate owner: ' + owner_key + ' in ' + file_path)`
8. `⠀⠀⠀⠀loot[owner_key] = { 'inventory': owner_data['inventory'] or [], 'source_file': file_path }`

**Helper `iterate_owner_entries(data)`** yields `(owner_id, {'inventory': [...]})` pairs for each recognized section in a loot file:
- `data['characters']` — each key is a Character ID. Yielded as `(character_key, {...})`.
- `data['party']` — yielded as `('party', {...})` at most once.
- `data['ground_piles']` — a list of `{location, inventory}`. Yielded as `('ground:' + location, {'inventory': inventory})`.

---

## LOAD_LOOT_TABLE_FILES

**Description:** Reads `loot_tables.yaml` plus every `loot_tables-*.yaml`, populating `loot_tables` and `option_lists`. Duplicate `table_id`s across files are an error.

**Parameters:**
- `data_dir`: same as CONSTRUCTOR.

**Returns:** None; mutates `loot_tables` and `option_lists`.

1. `loot_tables = empty dictionary`
2. `option_lists = empty dictionary`
3. `file_paths = [data_dir + '/loot_tables.yaml'] + sorted(glob(data_dir + '/loot_tables-*.yaml'))`
4. `for each file_path in file_paths:`
5. `⠀⠀data = load_yaml(file_path) or empty dictionary`
6. `⠀⠀for each (table_id, table_data) in (data['loot_tables'] or empty):`
7. `⠀⠀⠀⠀if table_id in loot_tables:`
8. `⠀⠀⠀⠀⠀⠀raise exception ('Duplicate loot table: ' + table_id + ' in ' + file_path)`
9. `⠀⠀⠀⠀loot_tables[table_id] = { 'table': table_data, 'source_file': file_path }`
10. `⠀⠀for each (list_name, options) in (data['option_lists'] or empty):`
11. `⠀⠀⠀⠀if list_name in option_lists:`
12. `⠀⠀⠀⠀⠀⠀raise exception ('Duplicate option list: ' + list_name + ' in ' + file_path)`
13. `⠀⠀⠀⠀option_lists[list_name] = options`

---

## LOAD_SHOP_FILES

**Description:** Reads `shops.yaml` plus every `shops-*.yaml`, populating `specific_shops`, `generic_shop_templates`, `active_generic_shops`, and `current_day`. Duplicate shop IDs across files are an error. The `current_day` counter lives under `state.current_day` in `shops.yaml` (not in the glob files); if absent it defaults to 0.

**Parameters:**
- `data_dir`: same as CONSTRUCTOR.

**Returns:** None; mutates the shop-related state and `current_day`.

1. `specific_shops = empty dictionary`
2. `generic_shop_templates = empty dictionary`
3. `active_generic_shops = empty dictionary`
4. `current_day = 0`
5. `base_path = data_dir + '/shops.yaml'`
6. `file_paths = [base_path] + sorted(glob(data_dir + '/shops-*.yaml'))`
7. `for each file_path in file_paths:`
8. `⠀⠀data = load_yaml(file_path) or empty dictionary`
9. `⠀⠀if file_path == base_path and 'state' in data:`
10. `⠀⠀⠀⠀current_day = data['state']['current_day'] or 0`
11. `⠀⠀for each (shop_id, shop_data) in (data['specific_shops'] or empty):`
12. `⠀⠀⠀⠀if shop_id in specific_shops:`
13. `⠀⠀⠀⠀⠀⠀raise exception ('Duplicate specific shop: ' + shop_id)`
14. `⠀⠀⠀⠀specific_shops[shop_id] = { 'template': shop_data['template'], 'inventory': shop_data['inventory'] or [], 'source_file': file_path }`
15. `⠀⠀for each (shop_id, shop_data) in (data['generic_shop_templates'] or empty):`
16. `⠀⠀⠀⠀if shop_id in generic_shop_templates:`
17. `⠀⠀⠀⠀⠀⠀raise exception ('Duplicate generic shop: ' + shop_id)`
18. `⠀⠀⠀⠀generic_shop_templates[shop_id] = { 'template': shop_data['template'], 'source_file': file_path }`
19. `⠀⠀for each (shop_id, active_data) in (data['active_generic_shops'] or empty):`
20. `⠀⠀⠀⠀active_generic_shops[shop_id] = { 'stock': active_data['stock'] or [], 'generated_at_day': active_data['generated_at_day'] or 0 }`

---

## SAVE

**Description:** Writes every in-memory owner, loot table, and shop record back to the yaml file it was loaded from. Owners created at runtime (no `source_file` recorded) are written to the base file for their kind: `loot.yaml` for Characters, Party, and Ground Piles; `shops.yaml` for Shops; `loot_tables.yaml` for Loot Tables and Option Lists. Always invoked from a single writer to avoid interleaved writes.

**Parameters:**
- `data_dir`: same as CONSTRUCTOR.

**Returns:** None.

1. `group loot by source_file (defaulting missing files to data_dir + '/loot.yaml')`
2. `for each (file_path, owner_entries) in grouped loot:`
3. `⠀⠀build a dictionary with 'characters', 'party', 'ground_piles' sections populated from owner_entries`
4. `⠀⠀write yaml to file_path`
5. `group loot_tables by source_file; attach option_lists to their originating files`
6. `write each loot_tables file path with its 'loot_tables' and 'option_lists' sections`
7. `group specific_shops and generic_shop_templates by source_file (defaulting missing files to data_dir + '/shops.yaml')`
8. `build shops.yaml content for the base file: include 'state': { 'current_day': current_day } and 'active_generic_shops': active_generic_shops`
9. `build content for every other shops-*.yaml file: only the specific_shops / generic_shop_templates that originated there`
10. `write each shop file`

**Notes:**
- `active_generic_shops` and `current_day` always live in the base `shops.yaml`, never in glob files. This keeps transient state in one predictable place.
- `option_lists` follow the `loot_tables` source_file grouping. A list added at runtime is written to `loot_tables.yaml`.
- SAVE is idempotent: calling it twice in a row produces identical files.

---

## STACK_IDENTITY_TUPLE

**Description:** Internal helper. Returns the ordered tuple of identity fields for an Item Stack. Two stacks are considered identical when their identity tuples compare equal. See `Identity Fields` at the top of this document.

**Parameters:**
- `stack`: an Item Stack.

**Returns:** A tuple of seven values.

1. `return (`
2. `⠀⠀stack['item'],`
3. `⠀⠀stack['tier'] or 0,`
4. `⠀⠀stack['properties'] or empty list,`
5. `⠀⠀stack['stored_spell'] or null,`
6. `⠀⠀stack['durability_damage'] or 0,`
7. `⠀⠀stack['name'] or null,`
8. `⠀⠀stack['value_in_gold'] or null`
9. `)`

**Notes:**
- `properties` equality is element-wise and order-sensitive: `[Elemental(Fire), Subdual]` does not match `[Subdual, Elemental(Fire)]`. This is intentional — the Naming Convention uses property order when generating display names, so order is a meaningful identity component.

---

## STACKS_MATCH

**Description:** Internal helper. Returns true if two Item Stacks have matching Stack Identity.

**Parameters:**
- `a`, `b`: Item Stacks.

**Returns:** Boolean.

1. `return STACK_IDENTITY_TUPLE(a) == STACK_IDENTITY_TUPLE(b)`

---

## FIND_MATCHING_STACK_INDEX

**Description:** Searches an inventory for the index of the first Stack whose identity matches a template Stack. Returns `null` when no match exists.

**Parameters:**
- `inventory`: a list of Item Stacks.
- `template`: an Item Stack whose identity is the search key.

**Returns:** A non-negative integer index, or `null`.

1. `for i = 0 to length(inventory) - 1:`
2. `⠀⠀if STACKS_MATCH(inventory[i], template):`
3. `⠀⠀⠀⠀return i`
4. `return null`

---

## MERGE_INVENTORY_STACKS

**Description:** Returns a new inventory list in which any Stacks sharing identity have been combined into a single Stack with summed Quantity. Preserves the order of first occurrence. `restock_target` from the first Stack in each group is kept; later Stacks' `restock_target` values are discarded (a merge conflict warning is logged if they differ).

**Parameters:**
- `inventory`: a list of Item Stacks.

**Returns:** A new list of Item Stacks.

1. `merged = empty list`
2. `for i = 0 to length(inventory) - 1:`
3. `⠀⠀current = inventory[i]`
4. `⠀⠀match_index = FIND_MATCHING_STACK_INDEX(merged, current)`
5. `⠀⠀if match_index is null:`
6. `⠀⠀⠀⠀append a shallow copy of current to merged`
7. `⠀⠀else:`
8. `⠀⠀⠀⠀merged[match_index]['quantity'] = (merged[match_index]['quantity'] or 1) + (current['quantity'] or 1)`
9. `⠀⠀⠀⠀if current has 'restock_target' and merged[match_index].get('restock_target') != current['restock_target']:`
10. `⠀⠀⠀⠀⠀⠀log warning ('merge discarded conflicting restock_target for ' + current['item'])`
11. `return merged`

---

## CLEANUP_ZERO_QUANTITY

**Description:** Removes every Stack with `quantity <= 0` from an Owner's inventory. Intended for periodic cleanup (e.g., at server startup or after a large batch of removals). Stacks with a `restock_target` set are NOT removed even when empty — the target is a directive that survives depletion.

**Parameters:**
- `owner_id`: the Owner whose inventory to clean.

**Returns:** The number of Stacks removed.

1. `entry = loot[owner_id]`
2. `if entry is null: return 0`
3. `original_length = length(entry['inventory'])`
4. `entry['inventory'] = [s for s in entry['inventory'] if (s['quantity'] or 0) > 0 or 'restock_target' in s]`
5. `return original_length - length(entry['inventory'])`

---

## GET_INVENTORY

**Description:** Returns the Inventory list for an Owner. Creates an empty Inventory for unknown Owner IDs so that subsequent ADD_ITEM calls succeed without a pre-registration step. The returned list is a live reference — callers must not mutate it directly; all mutations go through ADD_ITEM / REMOVE_ITEM / ADJUST_STACK_QUANTITY.

**Parameters:**
- `owner_id`: the Owner to look up.

**Returns:** A list of Item Stacks.

1. `if owner_id not in loot:`
2. `⠀⠀loot[owner_id] = { 'inventory': empty list, 'source_file': null }`
3. `return loot[owner_id]['inventory']`

**Notes:**
- A `null` source_file means "not yet persisted to a file." SAVE routes such Owners to the base file for their kind.
- Shop inventories are NOT stored in `loot`; use `specific_shops[shop_id]['inventory']` directly for those. This keeps Shop refresh logic from accidentally touching Character inventories and vice versa.

---

## ADD_ITEM

**Description:** Adds an Item Stack to an Owner's Inventory. If an existing Stack matches the input's identity, the input's Quantity is added to it; otherwise the input is appended as a new Stack. The input's `restock_target`, if present, overwrites any existing target on a merged Stack (unlike the passive merge in MERGE_INVENTORY_STACKS — an explicit ADD_ITEM is taken as an authoritative update).

**Parameters:**
- `owner_id`: target Owner.
- `item_stack`: the Stack to add. `quantity` defaults to 1. Must be positive; use REMOVE_ITEM to subtract.

**Returns:** The index of the affected Stack.

1. `inventory = GET_INVENTORY(owner_id)`
2. `quantity = item_stack['quantity'] or 1`
3. `if quantity <= 0:`
4. `⠀⠀raise exception ('ADD_ITEM requires positive quantity; got ' + quantity)`
5. `match_index = FIND_MATCHING_STACK_INDEX(inventory, item_stack)`
6. `if match_index is null:`
7. `⠀⠀append a shallow copy of item_stack (with quantity set) to inventory`
8. `⠀⠀return length(inventory) - 1`
9. `else:`
10. `⠀⠀inventory[match_index]['quantity'] = (inventory[match_index]['quantity'] or 1) + quantity`
11. `⠀⠀if 'restock_target' in item_stack:`
12. `⠀⠀⠀⠀inventory[match_index]['restock_target'] = item_stack['restock_target']`
13. `⠀⠀return match_index`

---

## REMOVE_ITEM

**Description:** Removes a Quantity from a specific Stack (by index). Clamps at 0 rather than going negative. Does not delete the Stack — cleanup of zero-Quantity Stacks is deferred to CLEANUP_ZERO_QUANTITY (and Stacks with a `restock_target` persist regardless). Raises if `stack_index` is out of range.

**Parameters:**
- `owner_id`: target Owner.
- `stack_index`: the Inventory index of the Stack to decrement.
- `quantity`: amount to remove. Must be positive.

**Returns:** The actual amount removed (may be less than `quantity` if the Stack had fewer units on hand).

1. `inventory = GET_INVENTORY(owner_id)`
2. `if stack_index < 0 or stack_index >= length(inventory):`
3. `⠀⠀raise exception ('REMOVE_ITEM: stack_index out of range')`
4. `if quantity <= 0:`
5. `⠀⠀raise exception ('REMOVE_ITEM requires positive quantity; got ' + quantity)`
6. `available = inventory[stack_index]['quantity'] or 0`
7. `removed = min(quantity, available)`
8. `inventory[stack_index]['quantity'] = available - removed`
9. `return removed`

---

## ADJUST_STACK_QUANTITY

**Description:** Signed adjustment to a Stack's Quantity by index. Positive delta increases the Stack; negative delta decreases it, clamped at 0. This is the generic primitive; ADD_ITEM and REMOVE_ITEM are ergonomic wrappers for the common cases.

**Parameters:**
- `owner_id`: target Owner.
- `stack_index`: the Inventory index.
- `delta`: signed integer (or float for Currency). Zero is a no-op.

**Returns:** The Stack's new Quantity.

1. `inventory = GET_INVENTORY(owner_id)`
2. `if stack_index < 0 or stack_index >= length(inventory):`
3. `⠀⠀raise exception ('ADJUST_STACK_QUANTITY: stack_index out of range')`
4. `current = inventory[stack_index]['quantity'] or 0`
5. `new_quantity = max(0, current + delta)`
6. `inventory[stack_index]['quantity'] = new_quantity`
7. `return new_quantity`

---

## TRANSFER_ITEM

**Description:** Moves a Quantity of a specific Stack from one Owner to another. Atomically: either the source is decremented and the destination incremented, or neither happens. Uses ADD_ITEM on the destination side so the transferred Stack merges with any existing matching Stack.

**Parameters:**
- `from_owner`, `to_owner`: Owner IDs.
- `stack_index`: the Inventory index on `from_owner`.
- `quantity`: amount to transfer. Must be positive.

**Returns:** The actual amount transferred (may be less than `quantity`).

1. `source_inventory = GET_INVENTORY(from_owner)`
2. `if stack_index < 0 or stack_index >= length(source_inventory):`
3. `⠀⠀raise exception ('TRANSFER_ITEM: stack_index out of range')`
4. `source_stack = source_inventory[stack_index]`
5. `available = source_stack['quantity'] or 0`
6. `transferred = min(quantity, available)`
7. `if transferred == 0: return 0`
8. `recipient_stack = shallow copy of source_stack with quantity = transferred, restock_target removed`
9. `REMOVE_ITEM(from_owner, stack_index, transferred)`
10. `ADD_ITEM(to_owner, recipient_stack)`
11. `return transferred`

**Notes:**
- `restock_target` is a property of the source Owner's intent and does not travel with a transferred Stack.
- Transfers between Characters and Shops go through this same entry point even though Shop inventories are stored separately — callers addressing a Shop use the `"shop:<id>"` Owner ID and internal plumbing routes to `specific_shops[id]['inventory']`. (The routing detail is a CONSTRUCTOR / SAVE concern; TRANSFER_ITEM itself does not need to distinguish.)

---

## ITEM_DEFINITION

**Description:** Internal helper. Returns the config block for a named Item Type, or `null` if no definition exists. Searches Weapons, Armor, Ammunition, Currency in that order. The name `"Gem"` returns a synthetic definition indicating the Gem category.

**Parameters:**
- `item_name`: a string matching a key in `equipment_config`.

**Returns:** A dictionary `{ 'category': string, 'definition': dict }`, or `null`.

1. `if item_name in equipment_config['Weapons']:`
2. `⠀⠀return { 'category': 'Weapon', 'definition': equipment_config['Weapons'][item_name] }`
3. `if item_name in equipment_config['Armor']:`
4. `⠀⠀return { 'category': 'Armor', 'definition': equipment_config['Armor'][item_name] }`
5. `if item_name in equipment_config['Ammunition']:`
6. `⠀⠀return { 'category': 'Ammunition', 'definition': equipment_config['Ammunition'][item_name] }`
7. `if item_name in equipment_config['Currency']:`
8. `⠀⠀return { 'category': 'Currency', 'definition': equipment_config['Currency'][item_name] }`
9. `if item_name == 'Gem':`
10. `⠀⠀return { 'category': 'Gem', 'definition': empty dictionary }`
11. `return null`

---

## PROPERTY_COST

**Description:** Internal helper. Returns the Gold cost of a single Magical Property entry as it would appear on an Item Stack. Looks up the property by name in the appropriate property catalog (weapon or armor); subtypes do not affect cost in this module.

**Parameters:**
- `property_entry`: either a string (property name only) or a dictionary `{ 'name': <string>, 'subtype': <string> }`.
- `catalog_key`: `'Weapon Properties'` or `'Armor Properties'` — which catalog to look up in.

**Returns:** A real-valued Gold cost (≥ 0). Unknown properties raise.

1. `if property_entry is a string:`
2. `⠀⠀property_name = property_entry`
3. `else:`
4. `⠀⠀property_name = property_entry['name']`
5. `catalog = equipment_config[catalog_key]`
6. `if property_name not in catalog:`
7. `⠀⠀raise exception ('Unknown property: ' + property_name + ' in ' + catalog_key)`
8. `return catalog[property_name]['cost']`

---

## ITEM_UNIT_PRICE

**Description:** Returns the Gold cost of a single copy of an Item configuration. Dispatches on category:

- **Weapon, Armor**: `base_price + tier_surcharge + Σ property_cost`.
- **Ammunition**: `(base_price / bundle_size) + (tier_surcharge + Σ property_cost) / 100`. Mundane ammunition is sold in bundles, but `ITEM_UNIT_PRICE` always reports the per-unit cost.
- **Currency**: `value_in_gold` from the Currency config.
- **Gem**: `stack['value_in_gold']`. Raises if absent.
- **Unknown category**: raises unless the Stack carries an explicit `unit_price` override.

**Parameters:**
- `stack`: an Item Stack.

**Returns:** A real-valued Gold price for one unit (not multiplied by Quantity).

1. `info = ITEM_DEFINITION(stack['item'])`
2. `if info is null:`
3. `⠀⠀if 'unit_price' in stack: return stack['unit_price']`
4. `⠀⠀raise exception ('Unknown item: ' + stack['item'])`
5. `tier = stack['tier'] or 0`
6. `tier_surcharge = equipment_config['Tier Surcharges'][tier] or 0`
7. `properties = stack['properties'] or empty list`
8. `if info['category'] == 'Weapon':`
9. `⠀⠀property_sum = Σ PROPERTY_COST(p, 'Weapon Properties') for p in properties`
10. `⠀⠀return info['definition']['base_price'] + tier_surcharge + property_sum`
11. `if info['category'] == 'Armor':`
12. `⠀⠀property_sum = Σ PROPERTY_COST(p, 'Armor Properties') for p in properties`
13. `⠀⠀return info['definition']['base_price'] + tier_surcharge + property_sum`
14. `if info['category'] == 'Ammunition':`
15. `⠀⠀property_sum = Σ PROPERTY_COST(p, 'Weapon Properties') for p in properties`
16. `⠀⠀bundle_size = info['definition']['bundle_size']`
17. `⠀⠀mundane_unit = info['definition']['base_price'] / bundle_size`
18. `⠀⠀magical_unit = (tier_surcharge + property_sum) / 100`
19. `⠀⠀return mundane_unit + magical_unit`
20. `if info['category'] == 'Currency':`
21. `⠀⠀return info['definition']['value_in_gold']`
22. `if info['category'] == 'Gem':`
23. `⠀⠀if 'value_in_gold' not in stack: raise exception ('Gem stack missing value_in_gold')`
24. `⠀⠀return stack['value_in_gold']`
25. `raise exception ('Unhandled item category: ' + info['category'])`

**Notes:**
- Ammunition uses weapon-property costs because magical ammunition applies the same Weapon Properties (Elemental, Subdual, etc.). The property catalog enforces applicability separately (`applies_to: [ammo]`).
- `unit_price` override on a Stack is an escape hatch for items whose category this module does not yet handle (e.g., Consumables in the "second-pass" category set).

---

## ITEM_VALUE_IN_GOLD

**Description:** Returns the per-unit Gold value of an Item Stack for wealth math. Distinct from ITEM_UNIT_PRICE: this is how much the item is *worth as payment*, which is meaningful only for Currencies and Gems. All other items return `null` (they cannot be spent directly).

**Parameters:**
- `stack`: an Item Stack.

**Returns:** A real-valued per-unit Gold value, or `null`.

1. `info = ITEM_DEFINITION(stack['item'])`
2. `if info is null: return null`
3. `if info['category'] == 'Currency':`
4. `⠀⠀return info['definition']['value_in_gold']`
5. `if info['category'] == 'Gem':`
6. `⠀⠀return stack['value_in_gold']`
7. `return null`

---

## TOTAL_WEALTH_IN_GOLD

**Description:** Sums the Gold-equivalent value of every Currency Stack and Gem Stack on an Owner. Non-Currency, non-Gem Stacks contribute 0.

**Parameters:**
- `owner_id`: the Owner.

**Returns:** A real-valued Gold total ≥ 0.

1. `inventory = GET_INVENTORY(owner_id)`
2. `total = 0`
3. `for each stack in inventory:`
4. `⠀⠀value = ITEM_VALUE_IN_GOLD(stack)`
5. `⠀⠀if value is null: continue`
6. `⠀⠀total = total + (stack['quantity'] or 0) * value`
7. `return total`

---

## CAN_AFFORD

**Description:** Returns whether an Owner's Total Wealth is sufficient to cover a Gold cost. Uses a tolerance of `1e-9` to absorb floating-point error in fractional prices.

**Parameters:**
- `owner_id`, `cost_in_gold`.

**Returns:** Boolean.

1. `return TOTAL_WEALTH_IN_GOLD(owner_id) + 1e-9 >= cost_in_gold`

---

## DEBIT_WEALTH

**Description:** Removes Gold from an Owner's Inventory to pay a cost. Coins are spent cheapest-first (Copper before Silver before Gold) and may be spent fractionally. If coins are exhausted before the cost is covered, Gems are spent next, cheapest-first by `value_in_gold`; a Gem that would overpay is still fully consumed, and the overpayment is returned to the Owner as Gold. If the Owner's Total Wealth is insufficient, DEBIT_WEALTH makes no changes and returns `false`.

**Parameters:**
- `owner_id`: the Owner being debited.
- `cost_in_gold`: a non-negative real. Zero is a no-op that returns `true`.

**Returns:** Boolean — `true` if the debit succeeded, `false` if the Owner could not afford it.

1. `if cost_in_gold < 0: raise exception ('DEBIT_WEALTH requires non-negative cost')`
2. `if cost_in_gold == 0: return true`
3. `if not CAN_AFFORD(owner_id, cost_in_gold): return false`
4. `inventory = GET_INVENTORY(owner_id)`
5. `remaining = cost_in_gold`
6. `# Spend coins cheapest-first, fractionally.`
7. `coin_types = list of (currency_name, value_in_gold) pairs from equipment_config['Currency'], sorted ascending by value_in_gold`
8. `for each (currency_name, value_in_gold) in coin_types:`
9. `⠀⠀if remaining <= 1e-9: break`
10. `⠀⠀stack_index = FIND_MATCHING_STACK_INDEX(inventory, { 'item': currency_name })`
11. `⠀⠀if stack_index is null: continue`
12. `⠀⠀quantity_available = inventory[stack_index]['quantity'] or 0`
13. `⠀⠀gold_available = quantity_available * value_in_gold`
14. `⠀⠀if gold_available <= remaining + 1e-9:`
15. `⠀⠀⠀⠀inventory[stack_index]['quantity'] = 0`
16. `⠀⠀⠀⠀remaining = remaining - gold_available`
17. `⠀⠀else:`
18. `⠀⠀⠀⠀units_to_spend = remaining / value_in_gold`
19. `⠀⠀⠀⠀inventory[stack_index]['quantity'] = quantity_available - units_to_spend`
20. `⠀⠀⠀⠀remaining = 0`
21. `# Spend gems cheapest-first if needed; overpayment returns as Gold.`
22. `if remaining > 1e-9:`
23. `⠀⠀gem_stack_indices = indices of every stack with stack['item'] == 'Gem', sorted by stack['value_in_gold'] ascending`
24. `⠀⠀for each gem_index in gem_stack_indices:`
25. `⠀⠀⠀⠀if remaining <= 1e-9: break`
26. `⠀⠀⠀⠀gem_value = inventory[gem_index]['value_in_gold']`
27. `⠀⠀⠀⠀while (inventory[gem_index]['quantity'] or 0) > 0 and remaining > 1e-9:`
28. `⠀⠀⠀⠀⠀⠀inventory[gem_index]['quantity'] = inventory[gem_index]['quantity'] - 1`
29. `⠀⠀⠀⠀⠀⠀if gem_value <= remaining + 1e-9:`
30. `⠀⠀⠀⠀⠀⠀⠀⠀remaining = remaining - gem_value`
31. `⠀⠀⠀⠀⠀⠀else:`
32. `⠀⠀⠀⠀⠀⠀⠀⠀change = gem_value - remaining`
33. `⠀⠀⠀⠀⠀⠀⠀⠀remaining = 0`
34. `⠀⠀⠀⠀⠀⠀⠀⠀ADD_ITEM(owner_id, { 'item': 'Gold', 'quantity': change })`
35. `return true`

**Notes:**
- Coin stacks are allowed to hold fractional Quantities (the example inventory shows Gold at 147.5). Spending 0.37 gp worth of Silver (from a 10-unit stack) leaves 6.3 Silver on that stack. Integer-only Quantities are a caller convention, not a module invariant.
- Gem Stacks, by contrast, are integer-Quantity and a single Gem unit is the smallest indivisible purchase unit. Giving change as Gold preserves the Owner's exact-minus-cost wealth after the debit.
- The affordability check in step 3 uses TOTAL_WEALTH_IN_GOLD, which already counts Gems. There is no case where the function proceeds past step 3 and then runs out of items — total wealth and the spending loop draw from the same pool.
- Zero-Quantity coin stacks are left in place; a later CLEANUP_ZERO_QUANTITY removes them (currency stacks have no restock_target by default, so they will be cleaned).

---

## CREDIT_WEALTH

**Description:** Adds Gold to an Owner's Inventory as a Gold Currency stack. The counterpart to DEBIT_WEALTH; used whenever a Shop pays the party for an item, the party loots coins, or a Gem's overpayment is returned as change.

**Parameters:**
- `owner_id`: the Owner being credited.
- `amount_in_gold`: a non-negative real. Zero is a no-op.

**Returns:** None.

1. `if amount_in_gold < 0: raise exception ('CREDIT_WEALTH requires non-negative amount')`
2. `if amount_in_gold == 0: return`
3. `ADD_ITEM(owner_id, { 'item': 'Gold', 'quantity': amount_in_gold })`

**Notes:**
- Always credits in Gold, never in Silver or Copper. Callers who need to hand out small change explicitly can compose ADD_ITEM calls of their own; this function's job is just to increase the Gold-equivalent wealth by the specified amount.

---

## RAND_ROLL_DICE_EXPRESSION

**Description:** Evaluates a Dice Expression string like `"2d6 + 3"` and returns the integer result. This is a utility evaluator for arbitrary dice — it is *not* a wrapper around `DiceSystem`, which uses a fixed Die Size and a success-counting rubric. Accepts `NdM` terms, integer constants, and `+`/`−` joiners. Whitespace is ignored. An integer input is returned unchanged.

**Parameters:**
- `expression`: a string, an integer, or `null`. `null` and empty strings return 0.

**Returns:** An integer (may be negative if the expression produces a negative net).

1. `if expression is null: return 0`
2. `if expression is an integer: return expression`
3. `compact = expression with all whitespace removed`
4. `if compact is empty: return 0`
5. `tokens = regex scan of compact for '[+-]?(\d+d\d+|\d+)'`
6. `rebuilt = join tokens with no separator`
7. `if rebuilt != compact: raise exception ('Invalid dice expression: ' + expression)`
8. `total = 0`
9. `for each token in tokens:`
10. `⠀⠀sign = (token starts with '-') ? -1 : 1`
11. `⠀⠀body = token with any leading '+' or '-' removed`
12. `⠀⠀if body contains 'd':`
13. `⠀⠀⠀⠀count_str, sides_str = body split on 'd'`
14. `⠀⠀⠀⠀count = integer(count_str); sides = integer(sides_str)`
15. `⠀⠀⠀⠀if count <= 0 or sides <= 0: raise exception ('Invalid dice term: ' + token)`
16. `⠀⠀⠀⠀term = 0`
17. `⠀⠀⠀⠀for i = 1 to count:`
18. `⠀⠀⠀⠀⠀⠀term = term + RAND_INT(1, sides)`
19. `⠀⠀⠀⠀total = total + sign * term`
20. `⠀⠀else:`
21. `⠀⠀⠀⠀total = total + sign * integer(body)`
22. `return total`

**Notes:**
- The rebuild-and-compare check (step 7) rejects malformed input such as `"2d"`, `"d6"`, or `"2d6 ** 3"` that would otherwise be silently partially parsed.
- Negative totals are allowed and surface when an expression subtracts more than it adds (`"1 - 1d4"` can produce `0`, `-1`, `-2`, `-3`). Callers that need a lower bound should clamp after the call.

---

## RESOLVE_QUANTITY

**Description:** Internal helper. Normalizes a Quantity spec into a number. A Quantity spec is either a plain number (returned as-is) or a Dice Expression (evaluated via RAND_ROLL_DICE_EXPRESSION and clamped to non-negative). Missing quantity defaults to 1.

**Parameters:**
- `quantity_spec`: a number, a string, or `null`.

**Returns:** A non-negative number.

1. `if quantity_spec is null: return 1`
2. `if quantity_spec is a number: return quantity_spec`
3. `rolled = RAND_ROLL_DICE_EXPRESSION(quantity_spec)`
4. `return max(0, rolled)`

---

## ADD_LOOT_TABLE

**Description:** Registers a Loot Table at runtime. Later persisted by SAVE to `loot_tables.yaml` (since no source file is associated with a runtime-created table).

**Parameters:**
- `table_id`: unique string id. Raises if already registered.
- `table`: the table body (`{ 'rolls': [...] }`, with optional per-table metadata).

**Returns:** None.

1. `if table_id in loot_tables: raise exception ('Loot table already registered: ' + table_id)`
2. `loot_tables[table_id] = { 'table': table, 'source_file': null }`

---

## GET_LOOT_TABLE

**Description:** Returns the table body for a registered Loot Table. Raises if the id is unknown (callers that want a soft lookup should check `table_id in loot_tables` first).

**Parameters:**
- `table_id`: the registered id.

**Returns:** The table body.

1. `if table_id not in loot_tables: raise exception ('Unknown loot table: ' + table_id)`
2. `return loot_tables[table_id]['table']`

---

## ROLL_LOOT_TABLE

**Description:** Rolls every row of a Loot Table in order and returns the list of Item Stacks produced. Empty rows (nothing dropped) are omitted from the result. The returned stacks are **not** merged with each other — merge happens when the caller feeds them into ADD_ITEM. Currencies (Gold, Silver, Copper) and Gems appear in the list as ordinary stacks; Loot Tables do not have a separate `gold` field.

**Parameters:**
- `table_id`: the id of the Loot Table to roll.

**Returns:** A list of Item Stacks (possibly empty).

1. `table = GET_LOOT_TABLE(table_id)`
2. `results = empty list`
3. `for each row in (table['rolls'] or empty):`
4. `⠀⠀rolled = ROLL_ROW(row)`
5. `⠀⠀if rolled is not null: append rolled to results`
6. `return results`

---

## ROLL_ROW

**Description:** Rolls one row of a Loot Table and returns either an Item Stack or `null` (nothing dropped). Dispatches on row shape:

- **Guaranteed** (`{slot, item}`): always returns a resolved copy of `item`.
- **Independent Chance** (`{slot, chance, item}`): returns `item` with probability `chance`.
- **Weighted Choice** (`{slot, options: [...]}` or `{slot, options: "<list_name>"}`): picks one option by cumulative probability; the remainder (when `sum(chance) < 1`) means nothing drops.
- **Gated Weighted Choice** (`{slot, chance, options: [...]}`): first rolls `chance` to decide whether to descend into the weighted choice.

The `slot` field is a label used for human-readable identification only; ROLL_ROW does not consume it.

**Parameters:**
- `row`: a row dictionary.

**Returns:** An Item Stack or `null`.

1. `options = row['options']`
2. `if options is a string:`
3. `⠀⠀if options not in option_lists: raise exception ('Unknown option list: ' + options)`
4. `⠀⠀options = option_lists[options]`
5. `if options is a list:`
6. `⠀⠀if 'chance' in row and RAND_FLOAT() >= row['chance']:`
7. `⠀⠀⠀⠀return null`
8. `⠀⠀return ROLL_WEIGHTED(options)`
9. `if 'chance' in row:`
10. `⠀⠀if RAND_FLOAT() >= row['chance']: return null`
11. `⠀⠀return RESOLVE_ITEM_SPEC(row['item'])`
12. `if 'item' in row:`
13. `⠀⠀return RESOLVE_ITEM_SPEC(row['item'])`
14. `return null`

---

## ROLL_WEIGHTED

**Description:** Picks one option from a weighted-choice list. Each option carries a `chance` ∈ `[0, 1]`; their sum is permitted to be less than 1 (the remainder means "nothing"). An option whose body is `{chance, from: "<list_name>"}` recurses into another Option List when selected — useful for cross-tier overflow (e.g., "5% of a tier-1 roll actually grabs from tier-2").

**Parameters:**
- `options`: a list of option dictionaries.

**Returns:** An Item Stack or `null`.

1. `total = Σ (option['chance'] or 0) for option in options`
2. `if total > 1 + 1e-9: log warning ('weighted options sum > 1.0 (got ' + total + ')')`
3. `pick = RAND_FLOAT()`
4. `running = 0`
5. `for each option in options:`
6. `⠀⠀running = running + (option['chance'] or 0)`
7. `⠀⠀if pick < running:`
8. `⠀⠀⠀⠀if 'from' in option:`
9. `⠀⠀⠀⠀⠀⠀sub_list_name = option['from']`
10. `⠀⠀⠀⠀⠀⠀if sub_list_name not in option_lists: raise exception ('Unknown option list: ' + sub_list_name)`
11. `⠀⠀⠀⠀⠀⠀return ROLL_WEIGHTED(option_lists[sub_list_name])`
12. `⠀⠀⠀⠀return RESOLVE_ITEM_SPEC(option['item'])`
13. `return null`

---

## RESOLVE_ITEM_SPEC

**Description:** Internal helper. Converts an `item` spec from a Loot Table row into a fresh Item Stack. Two spec shapes are recognized:

- **Literal Stack**: a dictionary with an `item` key. A shallow copy is returned with `quantity` resolved through RESOLVE_QUANTITY (so specs like `{item: Arrow, quantity: "1d6+4"}` work).
- **Inline Magical Row**: a dictionary with a `magical` key. The `magical` value is a Magical Item Constraint; generation is dispatched to GENERATE_MAGICAL_ITEM (A5).

Specs with neither key raise.

**Parameters:**
- `spec`: a dictionary.

**Returns:** An Item Stack.

1. `if 'magical' in spec:`
2. `⠀⠀return GENERATE_MAGICAL_ITEM(spec['magical'])`
3. `if 'item' in spec:`
4. `⠀⠀stack = shallow copy of spec`
5. `⠀⠀stack['quantity'] = RESOLVE_QUANTITY(spec['quantity'])`
6. `⠀⠀return stack`
7. `raise exception ('Invalid item spec in loot table: ' + spec)`

**Notes:**
- The copy is shallow; mutable nested fields (`properties` list) are shared with the spec. Callers that mutate a resolved stack must deep-copy first. In practice ROLL_LOOT_TABLE's results flow into ADD_ITEM, which stores them as-is, and the Loot Table spec is treated as read-only after load — so the shallow copy is safe.
- Inline Magical Rows may appear at any position a literal `item` can, including inside Option Lists: `{chance: 0.1, item: {magical: {category: melee, tier: [1]}}}`.

---

## PICK_WEIGHTED_KEY

**Description:** Internal helper. Picks one key from a `{key: weight}` dictionary, proportional to weight. Zero-weight entries are never picked. Raises if the dictionary is empty or all weights are zero.

**Parameters:**
- `weights`: a dictionary from arbitrary keys to non-negative numeric weights.

**Returns:** One of the keys.

1. `total_weight = Σ value for value in weights.values()`
2. `if total_weight <= 0: raise exception ('PICK_WEIGHTED_KEY: no positive weights')`
3. `pick = RAND_FLOAT() * total_weight`
4. `running = 0`
5. `for each (key, weight) in weights:`
6. `⠀⠀running = running + weight`
7. `⠀⠀if pick < running: return key`
8. `return last key in weights  # floating-point tail edge case`

---

## ELIGIBLE_ITEMS_FOR_CATEGORY

**Description:** Internal helper. Returns the list of Item Type names that match a constraint category. The category tags align with the `applies_to` vocabulary used in the property catalogs:

| Category tag | Eligible Item Types |
|---|---|
| `melee` | Weapons with `category` ∈ `{One Handed, Two Handed}` |
| `ranged` | Weapons with `category == Ranged` (both projectile and thrown) |
| `ammo` | All entries in Ammunition |
| `all_armor` | All entries in Armor (including Shields) |
| `all_body` | Armor entries with `category != Shield` |

Unknown category tags raise.

**Parameters:**
- `category_tag`: a string.

**Returns:** A list of Item Type name strings.

1. `if category_tag == 'melee':`
2. `⠀⠀return [name for (name, w) in equipment_config['Weapons'] if w['category'] in ('One Handed', 'Two Handed')]`
3. `if category_tag == 'ranged':`
4. `⠀⠀return [name for (name, w) in equipment_config['Weapons'] if w['category'] == 'Ranged']`
5. `if category_tag == 'ammo':`
6. `⠀⠀return list of keys in equipment_config['Ammunition']`
7. `if category_tag == 'all_armor':`
8. `⠀⠀return list of keys in equipment_config['Armor']`
9. `if category_tag == 'all_body':`
10. `⠀⠀return [name for (name, a) in equipment_config['Armor'] if a['category'] != 'Shield']`
11. `raise exception ('Unknown magical-item category: ' + category_tag)`

---

## PROPERTY_CATALOG_FOR

**Description:** Internal helper. Returns which property catalog applies to a given magical-item category.

**Parameters:**
- `category_tag`: a string.

**Returns:** `'Weapon Properties'` or `'Armor Properties'`.

1. `if category_tag in ('melee', 'ranged', 'ammo'): return 'Weapon Properties'`
2. `if category_tag in ('all_armor', 'all_body'): return 'Armor Properties'`
3. `raise exception ('Unknown category for property catalog: ' + category_tag)`

---

## ELIGIBLE_PROPERTIES

**Description:** Internal helper. Filters a `properties_weighted` dictionary down to only properties that are applicable to the picked tier and category. A property is eligible when it is listed in the constraint's weights, its `min_tier` is ≤ the picked tier, and its `applies_to` list includes the category tag.

**Parameters:**
- `properties_weighted`: `{property_name: weight}` from the constraint.
- `category_tag`: the magical-item category.
- `tier`: the picked tier (integer ≥ 1).

**Returns:** A filtered `{property_name: weight}` dictionary.

1. `catalog = equipment_config[PROPERTY_CATALOG_FOR(category_tag)]`
2. `eligible = empty dictionary`
3. `for each (property_name, weight) in properties_weighted:`
4. `⠀⠀if property_name not in catalog:`
5. `⠀⠀⠀⠀raise exception ('Unknown property in constraint: ' + property_name)`
6. `⠀⠀property_def = catalog[property_name]`
7. `⠀⠀if property_def['min_tier'] > tier: continue`
8. `⠀⠀if category_tag not in property_def['applies_to']: continue`
9. `⠀⠀eligible[property_name] = weight`
10. `return eligible`

---

## PICK_TIER

**Description:** Internal helper. Picks a tier integer from the constraint. Uses `tier_weights` if present, otherwise picks uniformly from the `tier` list. Raises if neither is present or both are empty.

**Parameters:**
- `constraint`: a Magical Item Constraint.

**Returns:** An integer tier ≥ 1.

1. `tier_list = constraint['tier'] or empty list`
2. `if length(tier_list) == 0: raise exception ('Magical constraint missing tier list')`
3. `tier_weights = constraint['tier_weights']`
4. `if tier_weights is not null:`
5. `⠀⠀restricted = { t: tier_weights[t] for t in tier_list if t in tier_weights }`
6. `⠀⠀if length(restricted) == 0: raise exception ('tier_weights does not cover any tier in the list')`
7. `⠀⠀return PICK_WEIGHTED_KEY(restricted)`
8. `return tier_list[RAND_INT(0, length(tier_list) - 1)]`

---

## PICK_ITEM_TYPE

**Description:** Internal helper. Picks one Item Type name from the set eligible for the category. Uses `items_weighted` if present (restricted to the intersection of eligible names and listed keys); otherwise picks uniformly.

**Parameters:**
- `constraint`: a Magical Item Constraint.
- `eligible_names`: the list from ELIGIBLE_ITEMS_FOR_CATEGORY.

**Returns:** An Item Type name string.

1. `if length(eligible_names) == 0: raise exception ('No eligible items for category: ' + constraint['category'])`
2. `items_weighted = constraint['items_weighted']`
3. `if items_weighted is not null:`
4. `⠀⠀restricted = { name: items_weighted[name] for name in eligible_names if name in items_weighted }`
5. `⠀⠀if length(restricted) == 0: raise exception ('items_weighted does not cover any eligible item')`
6. `⠀⠀return PICK_WEIGHTED_KEY(restricted)`
7. `return eligible_names[RAND_INT(0, length(eligible_names) - 1)]`

---

## GENERATE_MAGICAL_ITEM

**Description:** Generates a random magical Item Stack given a Magical Item Constraint. The algorithm: pick a tier, pick an Item Type eligible for the category, filter properties down to those eligible for the tier + category intersection, pick one property, and resolve its subtype (uniformly from the property's subtype list when the property declares `has_subtype: true`).

Produced Stack shape: `{ item, tier, properties: [{name, subtype?}], quantity: 1 }`. The caller can override quantity afterward if needed (e.g., for magical ammunition).

**Parameters:**
- `constraint`: a Magical Item Constraint. Required keys: `category`, `tier`, `properties_weighted`. Optional keys: `tier_weights`, `items_weighted`.

**Returns:** A fresh Item Stack.

1. `if 'category' not in constraint: raise exception ('Magical constraint missing category')`
2. `if 'properties_weighted' not in constraint: raise exception ('Magical constraint missing properties_weighted')`
3. `category_tag = constraint['category']`
4. `tier = PICK_TIER(constraint)`
5. `eligible_names = ELIGIBLE_ITEMS_FOR_CATEGORY(category_tag)`
6. `item_name = PICK_ITEM_TYPE(constraint, eligible_names)`
7. `eligible_props = ELIGIBLE_PROPERTIES(constraint['properties_weighted'], category_tag, tier)`
8. `if length(eligible_props) == 0:`
9. `⠀⠀raise exception ('No properties eligible at tier ' + tier + ' for category ' + category_tag)`
10. `property_name = PICK_WEIGHTED_KEY(eligible_props)`
11. `catalog = equipment_config[PROPERTY_CATALOG_FOR(category_tag)]`
12. `property_def = catalog[property_name]`
13. `property_entry = { 'name': property_name }`
14. `if property_def['has_subtype']:`
15. `⠀⠀subtypes = property_def['subtypes'] or empty list`
16. `⠀⠀if length(subtypes) == 0: raise exception ('Property ' + property_name + ' declares has_subtype but has no subtypes list')`
17. `⠀⠀property_entry['subtype'] = subtypes[RAND_INT(0, length(subtypes) - 1)]`
18. `stack = { 'item': item_name, 'tier': tier, 'properties': [property_entry], 'quantity': 1 }`
19. `return stack`

**Notes:**
- Exactly one property is applied per generated item, matching the default item-design rule ("typically only one property per item"). Multi-property generation is not provided here; a loot table that wants a multi-property item should specify it as a literal stack.
- The generator picks a tier first and then filters properties; a tier for which no properties are eligible raises at step 9. Authors whose `tier_weights` allow a tier with no eligible properties will find out quickly.
- Subtype selection is uniform across the property's declared subtypes. Weighted subtypes are not supported at the constraint level; an author who wants to bias, say, Fire over Cold can achieve it by splitting the definition of Elemental into per-subtype properties (or by using literal stacks in the table).
- The returned Stack's `properties` list uses the dict form `{name, subtype}` consistently, matching the Loot and display-name conventions used elsewhere in the module.
