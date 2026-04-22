# Equipment System — Pseudocode

## Conventions

- Class names use `PascalCase`. Method names use `ALL_CAPS_WITH_UNDERSCORES` to signal pseudocode.
- Config is accessed as `equipment_config['Key Name']` using the human-readable keys defined in `equipment_config.yaml`.
- `RAND_INT(low, high)` returns a uniformly random integer in the inclusive range `[low, high]`. `RAND_FLOAT()` returns a uniform real in `[0, 1)`.
- `floor(x)` returns the largest integer less than or equal to `x`. All divisions in pricing and quantity math use `floor` unless noted.
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
