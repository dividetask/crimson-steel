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
