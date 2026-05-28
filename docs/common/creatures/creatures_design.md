# Creatures — Design

Owns the Creature record: identity, Race + Aspect, Classes + Levels + Trained Skills + per-Class Choices, Tier Override, Tier-Up Choices, Group, Tags. Computes Tier, Effective Attributes, Speed, ranks for any proficiency key, Granted Abilities, and aggregated `modifiers:` from those Abilities. Produces a Creature Accessor that other domains read through.

Sibling domains:

- **Proficiencies** consumes the Creature Accessor (`ranks_for`, `attribute_value`, `has_ability`, `level_for_ability`) to compute Prowess. Creatures does not compute Prowess itself.
- **Combat** receives a Creature Lookup Callback wired to *Look up Creature* and reads per-Combatant data through it.
- **Conditions** holds per-Creature mutable state (HP damage, Ability Damage, Effects, etc.). The Creatures record is the *baseline*; Conditions' state layers on top at the consuming domain. Death checks read Creatures' attribute scores and max HP through the Accessor.
- **Abilities** is the source of truth for what each Granted Ability does. Creatures hands ability names back to callers; mechanical detail is looked up through Abilities.
- **Equipment** does not appear in this design — equipment is associated with a Creature through Creature ID at the Equipment level, not stored on the Creature record.

## Common types

### Creature Record

The on-disk shape persisted in the `creatures_data_*.example.{json,yaml}` files (and the consuming project's runtime equivalent). See the note at the end of this common type for the multi-file pattern.

| Field | Type | Default on load | Description |
|---|---|---|---|
| `id` | string | required | Creature ID. Unique across the dataset. |
| `name` | string | required | Display name. |
| `group` | string | `""` | Group classification (`pc`, `npc`, `enemy`, etc.). |
| `tags` | list of string | `[]` | Free-form tags. |
| `race` | string | required | Key into `races.yaml`. |
| `race_aspect` | string or null | null | Key into the Race's `aspects` map. Required when the Race declares Aspects; rejected otherwise. |
| `base_attributes` | map of attribute key → integer | required | The six raw scores (`str`, `dex`, `con`, `int`, `wis`, `cha`). Every key is required; default zero is *not* assumed. |
| `classes` | list of Class Entry | `[]` | One entry per Class the Creature has levels in. |
| `advancement_track` | string | `"default"` | Key into `Tier Breakpoints`. |
| `tier_override` | integer or null | null | When set, *Get Tier* returns this verbatim and Tier Breakpoints are ignored. |
| `tier_up_choices` | map of integer (Tier) → list of attribute keys | `{}` | Per-Tier-Up Inherent Chosen Bonus picks. Validated against `Per-Tier Inherent Chosen Bonus Count`. Missing Tiers default to no picks (the Creature simply forgoes the chosen bonus at those Tiers). |
| `loot_table` | string or null | null | Optional Loot Table ID (defined in Equipment). When set, Equipment's *Collect Combat Loot* rolls this table for the Creature on top of moving its Inventory. |
| `metadata` | dict | `{}` | Caller-supplied free-form data. Creatures does not interpret. Used by consuming projects for player attribution, portrait paths, etc. |

`mana_spent`, `hp_damage`, equipped items, active Conditions, and similar runtime state are **not** stored on the Creature record — they live in Conditions, Equipment, and elsewhere, keyed by Creature ID.

The persisted dataset is split across multiple files using the pattern `creatures_data_<suffix>.example.{json,yaml}` — by project convention, one each for PCs, enemies (templates plus spawns), and NPCs. The loader concatenates every matching file into one dataset; the `id` field must be unique across every file. Creatures itself is indifferent to which file a record lives in.

### Class Entry

| Field | Type | Default | Description |
|---|---|---|---|
| `class` | string | required | Key into `classes.yaml`. May name a Sub-Class. |
| `level` | integer | required | Class Level (≥ 0). |
| `trained_skills` | list of string | `[]` | Skill keys the Creature has chosen to train in this Class. Set Instances are valid (e.g. `perform_dance`); bare Set Skill keys (ending in `_`) are not. |
| `choices` | dict | `{}` | Per-Class catalog choices. Free-form keys; the consuming Class entry interprets each one. Common keys include `spellcasting: [<spell_name>, ...]` (the spells chosen for the Class's Spellcasting-type ability — Bardic Spellcasting, Arcane Spellcasting, Druidic Spellcasting, Ranger Spellcasting, or the Cleric's `domain` resolution), `deity: <name>` and `domain: <name>` (Cleric), Bard's Versatile Performance subject, etc. Creatures stores and round-trips the dict opaquely; spells listed under `choices.spellcasting` are surfaced as Granted Abilities by *Get Granted Abilities*. |

### Race Entry (catalog)

The schema for entries in `races.yaml`. Looked up by the `race` key.

| Field | Type | Default | Description |
|---|---|---|---|
| `base_speed` | integer | `Default Base Speed` config | Race's Base Speed before Aspect and Class adjustments. |
| `racial_adjustment` | map of attribute key → integer | `{}` | Additions to Base Attributes. `all: N` is shorthand for `+N` to every attribute and is mutually exclusive with per-attribute entries on the same Race / Aspect. |
| `granted_abilities` | map of integer (Tier) → list of string | `{}` | Race Granted Ability Table. |
| `aspects` | map of aspect key → Race Aspect | `{}` | When non-empty, a Creature with this Race must pick exactly one Aspect. |

### Race Aspect (catalog)

| Field | Type | Default | Description |
|---|---|---|---|
| `racial_adjustment` | map of attribute key → integer | `{}` | Adjustments stacking on top of the Race's. |
| `speed_delta` | integer | 0 | Added to Base Speed. |
| `granted_abilities` | map of integer (Tier) → list of string | `{}` | Race Aspect Granted Ability Table. Stacks with the Race's. |

### Class Catalog Entry

The schema for entries in `classes.yaml`. Looked up by the `class` key (including Sub-Class keys).

| Field | Type | Default | Description |
|---|---|---|---|
| `martial_advancement` | enum | required | One of `aligned`, `unaligned`, `opposed`. The rate at which each Class Level adds Martial ranks. |
| `saves` | map | required | Save Attribute categorization. Has two sub-keys: `aligned` (the Save Attributes that advance at the `aligned` rate; project convention is exactly two) and `opposed` (Save Attributes that advance at the `opposed` rate explicitly; redundant with the default but available for clarity). Save Attributes in neither list default to the `Default Save Rate` (`opposed`). The two lists must be disjoint. |
| `aligned_proficiencies` | list of string | none | Skills that advance at the `aligned` rate. Mutually exclusive with `unaligned_proficiencies`. Set Skill keys (ending `_`) are valid; any Set Instance whose prefix appears here is treated the same way. |
| `unaligned_proficiencies` | list of string | none | Inverse form. Skills that advance at the `unaligned` rate; every Skill *not* listed advances at the `aligned` rate. Use when most Skills are aligned (e.g. Bard). Mutually exclusive with `aligned_proficiencies`. |
| `opposed_proficiencies` | list of string | `[]` | Skills that advance at the `opposed` rate. Combines with either `aligned_proficiencies` or `unaligned_proficiencies`; takes precedence over the default for the Skills listed here. |
| `ability_progression` | map of integer (Class Level) → list of string | `{}` | Class Ability Progression. |
| `granted_spells` | list of Catalog Ability name | `[]` | Spells every Creature of this Class learns regardless of their `choices`. Domain-specific or otherwise choice-dependent spells live elsewhere (e.g. the Cleric Class resolves additional spells from `deities.yaml` via the Creature's `choices.deity` and `choices.domain`). |
| `sub_class` | map of sub-class key → Sub-Class Entry | `{}` | Inherits the parent's tables; the Sub-Class Entry's keys shallow-override or extend. |

A Class that declares neither `aligned_proficiencies` nor `unaligned_proficiencies` has no inclusion / exclusion declaration: every trained Skill advances at the `Default Skill Rate` (`unaligned`) unless it appears in `opposed_proficiencies`. Declaring both `aligned_proficiencies` and `unaligned_proficiencies` is a configuration error.

A Class entry that omits `mana_advancement` is treated as `mana_advancement: 0`. The Class's contribution to Mana Max is `mana_advancement × Class Level`. *(configurable shape; Mana Max formula composition is in Operations.)*

| Field | Type | Default | Description |
|---|---|---|---|
| `mana_advancement` | integer | 0 | Mana per Class Level contributed by this Class. |

### Sub-Class Entry

A Sub-Class is referenced by its own key but inherits its parent's schema. The Sub-Class Entry's fields shallow-override or extend the parent:

- `martial_advancement`, `saves`, `mana_advancement`: when present, replace the parent's wholesale.
- `aligned_proficiencies`: any Skills listed are added to the merged Class's set of Aligned-rate Skills.
- `unaligned_proficiencies`: any Skills listed are added to the merged Class's set of Unaligned-rate Skills (removed from the Aligned-rate set if the parent placed them there).
- `opposed_proficiencies`: any Skills listed are added to the merged Class's set of Opposed-rate Skills.
- A Sub-Class may declare any combination of the three proficiency lists; each acts as an additive adjustment to the parent's effective categorization.
- `ability_progression`: merged key-by-key — at each Class Level, the Sub-Class's list is appended to the parent's. The parent and Sub-Class never share an Ability name at the same Level (validator rejects).

### Effective Attribute Map

The output of *Get Effective Attributes*. A map from attribute key to integer. Always carries every Attribute key the project defines, even when the Creature has no specific bonus on that attribute (the value is just the Base Attribute plus Per-Tier Inherent Bonus in that case).

### Aggregated Modifier Entry

| Field | Type | Description |
|---|---|---|
| `target` | string | Verbatim from the Modifier Entry returned by Abilities. |
| `type` | string | Bonus Type Name. |
| `descriptors` | list of string | Verbatim. |
| `amount` | signed integer | The result of evaluating the Modifier Entry's `add`. Formulas are resolved against the Creature's `level` (Total Level) and `tier` (Tier 0 → 0.5). |
| `source` | string | The Ability name the entry came from. |

The output of *Get Aggregated Modifiers* is a list of these entries. Per-Bonus-Type stacking is the consumer's responsibility — Creatures does not collapse entries.

### Random Encounter Table Entry

The schema for entries in `random_encounter_tables.yaml`. Looked up by table key (the YAML map key — typically a snake_case identifier like `slave_lords_caravan`).

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | the table key | Display name. |
| `rolls` | list of Random Encounter Row | required | Rows evaluated in order at *Roll Random Encounter* time. |

### Random Encounter Row

Shares Equipment's Loot Roll Row shape — the same Guaranteed / Independent Chance / Weighted Choice / Gated Weighted Choice variants, the same `when` filter, the same `as` publishing of a Roll Variable. The only difference is the row payload: an Random Encounter Row produces a list of Spawn Refs instead of Item Stacks. A Roll Variable published by an Random Encounter Row may be referenced in later rows' `when` filters identically to Equipment's behavior.

### Spawn Ref

One instruction inside an Random Encounter Row payload. Each Spawn Ref expands into one or more new Creature records via *Spawn Creature From Template*.

| Field | Type | Default | Description |
|---|---|---|---|
| `template_id` | string | required | Creature ID of an existing Creature record (typically tagged `enemy_template`) to clone. |
| `count` | string or integer | `1` | Number of spawns to produce. May be a dice expression (e.g. `2d4`) evaluated at roll time. |
| `name_override` | string | optional | Display name applied to every spawn produced by this Ref. When omitted, spawns inherit the template's `name`. |
| `loot_table` | string | optional | Loot Table ID stored on each spawn's Creature record, overriding the template's `loot_table`. |

## Public entry points

Function names are conceptual labels; implementations choose their own symbols. Where another domain's documentation cites a name (e.g. `creature_lookup` in Combat), the parenthetical here matches that name for traceability.

### Look up Creature (`creature_lookup`)

Inputs: Creature ID.

Behavior: Find the Creature record by ID. Construct a Creature Accessor wrapping it. Subsequent calls on the Accessor read fresh from the same record.

Returns: a Creature Accessor, or null when no Creature has that ID.

### List Creatures

Inputs: optional `group` filter (string), optional `tags` filter (list of string — entries must all be present).

Behavior: Walk every loaded Creature record and emit those that match.

Returns: a list of `(Creature ID, name)` pairs in load order. Used by stub UIs that present a roster.

### Find Creature by Name

Input: a display name (string).

Behavior: Linear scan for the first Creature whose `name` matches exactly. Case-sensitive.

Returns: a Creature Accessor, or null.

The exact-match contract keeps this entry point deterministic. Callers wanting fuzzy or prefix lookup do their own normalization on the result of *List Creatures*.

### Get Tier

Input: Creature ID (or Accessor).

Behavior:

1. If `tier_override` is non-null, return it.
2. Otherwise look up the Creature's `advancement_track` in `Tier Breakpoints`. Unknown track is an error.
3. Tier = the largest index `i` such that `breakpoints[i] ≤ Total Level`. Index 0 of every track must be 0, so a Total Level of zero produces Tier 0.

Returns: integer ≥ 0.

### Get Effective Attributes

Input: Creature ID (or Accessor).

Behavior: Run the *Effective Attribute Computation* pipeline (see Operations). Returns the full attribute map.

Returns: Effective Attribute Map.

### Get Speed

Input: Creature ID (or Accessor).

Behavior:

1. Start with the Race's `base_speed` (or `Default Base Speed` when the Race omits it).
2. Add the picked Race Aspect's `speed_delta` if any.
3. Add aggregated Speed-targeted Modifier amounts — see *Aggregated Modifier Application to Speed* in Operations.

Returns: integer Speed in feet.

Negative results are clamped at zero. The Speed value Creatures returns is the Creature's baseline; Combat / Conditions apply terrain and Condition modifiers on top.

Class-level Speed bonuses (Barbarian's Fast Movement, Monk's Unarmored Movement, etc.) are not stored on the Class entry — they live on the Granted Ability that confers them, as a `modifiers:` entry targeting `speed`. The Aggregated Modifier folds them in via step 3.

### Get Granted Abilities

Input: Creature ID (or Accessor), optional `source` filter (`race`, `class`, or absent for all).

Behavior: Concatenate:

- Race's `granted_abilities[t]` for every Tier `t` ≤ the Creature's current Tier.
- Race Aspect's `granted_abilities[t]` (if any), same rule.
- For each Class Entry, the Class's (and Sub-Class's) `ability_progression[l]` for every Class Level `l` ≤ the Creature's Class Level. Sub-Class entries appear after their parent's at the same Level.
- For each Class Entry, the Class's `granted_spells` (always-granted spells declared on the Class Catalog Entry).
- For each Class Entry, every entry in `choices.spellcasting` (the spells the player picked for the Class's Spellcasting-type ability). Only counted when the Class's progression actually granted a Spellcasting-type ability at or before the Creature's Class Level.
- For each Class Entry, choice-driven spells looked up through external catalogs (e.g. a Cleric's `choices.deity` + `choices.domain` resolves additional spells via `deities.yaml`).

Deduplicate while preserving first-encounter order. Filter by `source` when supplied.

Returns: a list of `{ name, source }` records. `source` is one of `race`, `race_aspect`, or `class:<class_key>`. The Class source carries the Class key so consumers (e.g. Floor Ability's `level_for_ability`) can recover the granting Class. Spells contributed via `choices.spellcasting` (and via deity/domain) report the granting Class as their source.

### Look up Class

Input: a Class key (or Sub-Class key).

Behavior: Resolve through `classes.yaml`. For a Sub-Class key, apply the inheritance rules (see Common types) and return the merged entry.

Returns: a Class Catalog Entry (post-merge for Sub-Classes), or null when the key matches nothing.

### Look up Race

Input: a Race key.

Returns: the Race Entry from `races.yaml`, or null. Race Aspects are accessed via the returned entry's `aspects` map.

### Get Aggregated Modifiers

Input: Creature ID (or Accessor), optional `target` filter (string).

Behavior: Walk every Granted Ability via Abilities' *Get an Ability's Modifiers*. For each Modifier Entry, evaluate `add` against `{level: Total Level, tier: Tier (0 → 0.5)}`. Build an Aggregated Modifier Entry tagged with the source Ability name. Skip entries with `add = 0`. Filter by `target` when supplied.

Returns: a list of Aggregated Modifier Entries. Order: by Granted Ability order from *Get Granted Abilities*, then by Modifier Entry index within the Ability.

Per-Bonus-Type stacking is the consumer's concern (Combat folds these into Rolls; Conditions may bucket them with its own Active Effects). This entry point does not collapse.

### Get Max Hit Points

Input: Creature ID (or Accessor).

Behavior: Evaluate `HP Formula[tier]` from `creatures_config.yaml` against the Creature's Effective Constitution. Add `hp_bonus` Aggregated Modifier amounts (per-Bonus-Type stacking applied here — see Operations).

Returns: integer ≥ 0.

### Get Max Mana

Input: Creature ID (or Accessor).

Behavior: Evaluate `Mana Formula[tier]` from `creatures_config.yaml` against the Creature's Effective Intelligence. Add per-Class Mana contributions: each Class Entry contributes `class.mana_advancement × class.level`. Add `mana_bonus` Aggregated Modifier amounts.

Returns: integer ≥ 0.

### Serialization

- **Load Creatures** — accept a dict of `id → Creature Record`. Validate every entry (see *Validation* in Operations). Replace the loaded set.
- **Save Creatures** — produce the same shape.

Creatures does not own when to persist; the consuming project drives that.

## Creature Accessor

The interface returned by *Look up Creature*. Every method reads fresh from the underlying record.

| Method | Returns | Description |
|---|---|---|
| `id` | string | Creature ID. |
| `name` | string | Display name. |
| `group` | string | Group classification. |
| `tags` | list of string | Tags. |
| `race` | `(race_key, aspect_key or null)` | Race and picked Aspect. |
| `tier` | integer | Equivalent to *Get Tier*. |
| `total_level` | integer | Sum of Class Levels. |
| `class_summary` | list of `(class_key, level)` | One per Class Entry, in stored order. Sub-Class keys are reported as themselves, not their parent's. |
| `level_for_class(class_key)` | integer | The Class Level the Creature has in the named Class (or Sub-Class). Zero when the Class is absent. |
| `attribute_value(attr)` | integer | Equivalent to *Get Effective Attributes*`[attr]`. The value Proficiencies and Combat read. |
| `base_attribute_value(attr)` | integer | The raw Base Attribute before Racial Adjustment and Inherent bonuses. UI surfaces consult this for display. |
| `ranks_for(key)` | integer | The Creature's ranks in the given concrete proficiency key. See *Ranks Computation* in Operations. The key must not end in `_`. |
| `has_ability(name)` | boolean | True iff `name` appears in the Granted Abilities list. |
| `level_for_ability(name)` | integer | The level relevant to the granting source — Class Level when granted by a Class or Sub-Class (including spells contributed via that Class's `choices.spellcasting` or `choices.deity`/`choices.domain`), the Creature's current Tier when granted by Race or Race Aspect. Used by Proficiencies' Floor Ability and similar formulas. Zero when the Creature lacks the Ability. |
| `speed` | integer | Equivalent to *Get Speed*. |
| `max_hit_points` | integer | Equivalent to *Get Max Hit Points*. |
| `max_mana` | integer | Equivalent to *Get Max Mana*. |
| `granted_abilities(source = null)` | list of `{name, source}` | Equivalent to *Get Granted Abilities*. |
| `aggregated_modifiers(target = null)` | list of Aggregated Modifier Entry | Equivalent to *Get Aggregated Modifiers*. |
| `tier_up_choices` | map of integer → list of attribute keys | The stored choices. |
| `record` | Creature Record | Read-only view of the raw record. Stubs use this for display fields Creatures has no opinion on. |

The Accessor never mutates the record. Mutations go through the *Update* entry points below.

### Update entry points

These mutate the underlying Creature Record and persist on Save Creatures.

- **Set Tier-Up Choices** — `(creature_id, tier, [attribute keys])`. Validates the list length against `Per-Tier Inherent Chosen Bonus Count`, that every entry is a recognized attribute key, and that the Creature has reached the given Tier. Replaces any existing entry for that Tier.
- **Set Tier Override** — `(creature_id, integer or null)`.
- **Set Class Level** — `(creature_id, class_key, level)`. Adds the Class Entry when absent. Removing a Class is `level = 0` with a follow-up *Prune Empty Classes*.
- **Set Trained Skills** — `(creature_id, class_key, [skill_keys])`. Replaces the list.
- **Set Class Choices** — `(creature_id, class_key, choices_dict)`. Replaces the named Class Entry's `choices` map wholesale. Cleric's `{deity: "...", domain: "..."}`, a spellcaster's `{spellcasting: [<spell_name>, ...]}`, Bard's Versatile Performance choice, etc., all route through this. The dict is stored opaquely; Creatures does not validate the keys or values beyond confirming they're a string-keyed dict.

Tier-up triggered by Class Level changes does not auto-fill `tier_up_choices` — that's a UI flow. Until the Creature's user sets the choices for a newly-reached Tier, those Tier's chosen bonuses simply don't apply.

### Spawn Creature From Template

Inputs: `template_id` (Creature ID of an existing record), optional `name_override`, optional `loot_table` override.

Behavior:
1. Read the template's Creature Record. Refuse if not found.
2. Allocate a fresh ID — one past the current maximum across every loaded Creature Record (all `creatures_data_*` files combined).
3. Deep-copy the template's fields into a new Creature Record at the new ID. Apply `name_override` and `loot_table` overrides when provided.
4. Add the new record to the dataset.

Returns: the new Creature ID.

The new record is persistent — it lives in the same dataset as PCs and templates and is round-tripped by Save Creatures. Lifecycle management (deletion after combat resolution) is the caller's responsibility. The post-combat loot stub in Equipment is the conventional caller for cleanup via *Delete Creature*.

### Delete Creature

Inputs: Creature ID.

Behavior: Remove the Creature Record from the dataset. Idempotent — no error if the ID is absent.

Returns: nothing.

Creatures does **not** cascade the delete into other domains. Callers are expected to clean up Conditions state, Equipment inventory owned by `creature:<id>`, and any Combat Combatant pointing at the deleted ID — typically via Equipment's post-combat loot stub, which composes *Collect Combat Loot* + Combat's *Remove Combatant* + *Delete Creature* in sequence.

### Roll Random Encounter

Inputs: Random Encounter Table ID, optional Random Seed (for deterministic testing).

Behavior:
1. Read the Random Encounter Table by ID.
2. Iterate the table's `rolls` in order. For each Random Encounter Row:
   - Evaluate `when` against the current Roll Variables; skip if any pair mismatches.
   - Resolve the Row by its shape (Guaranteed / Independent Chance / Weighted Choice / Gated Weighted Choice).
   - If the Row publishes via `as`, store the resulting `key` in Roll Variables. A skipped Row does not publish.
3. For each Spawn Ref in every resolved row, evaluate `count` (dice expressions roll now) and call *Spawn Creature From Template* that many times with the Ref's overrides. Collect the new Creature IDs in roll order.

Returns: the list of new Creature IDs.

*Roll Random Encounter* does not add the new Creatures to any Combat. The caller follows up with Combat's *Add Combatant* per ID.

### Load Random Encounter Tables / Save Random Encounter Tables

- **Load Random Encounter Tables** — accept a dict of `table_id → Random Encounter Table Entry`. Validate every entry (rows reference real template IDs; `count` parses; `loot_table` overrides reference real tables in Equipment). Replace the loaded set.
- **Save Random Encounter Tables** — produce the same shape.

### Add Random Encounter Table / Remove Random Encounter Table

- **Add Random Encounter Table** — `(table_id, Random Encounter Table Entry)`. Validates and inserts; refuses on duplicate ID.
- **Remove Random Encounter Table** — `(table_id)`. No-op when absent.

## Operations

### Effective Attribute Computation

Reads the Creature Record. For each attribute `a`:

1. `base = base_attributes[a]`.
2. `racial = racial_adjustment_for(race, race_aspect)[a]` — see *Racial Adjustment Resolution*.
3. `per_tier = floor(tier × Per-Tier Inherent Bonus)` — Tier uses the project-wide Tier 0 → 0.5 convention.
4. `chosen = Per-Tier Inherent Chosen Bonus Amount × count of Tier-Up Choice entries from Tier 2..tier (inclusive) that include attribute key a`. Tier 1 grants only the Per-Tier Inherent Bonus, not the Chosen Bonus — the Chosen Bonus begins at Tier 2.
5. `effective = base + racial + per_tier + chosen`.

With the default Per-Tier Inherent Bonus of 1, step 3 produces +0 at Tier 0 (`floor(0.5 × 1) = 0`), +1 at Tier 1, +2 at Tier 2, and so on — the documented "each Tier the Creature has reached past Tier 0 adds one." Tier 1 is the first Tier with a non-zero Per-Tier Inherent Bonus; Tier 2 is the first Tier with Tier-Up Choices.

### Racial Adjustment Resolution

The Race's `racial_adjustment` and the picked Race Aspect's `racial_adjustment` stack additively per attribute. The `all: N` shorthand expands to `+N` on every attribute key the project defines; mixing `all` with per-attribute entries on the same Race / Aspect is rejected at load time.

### Ranks Computation

Given a proficiency key:

1. **Save key** (`<attr>_save` where `<attr>` is a recognized attribute key, by convention used by callers that build save Rolls): for each Class Entry, the rate is `aligned` if `<attr>` is in the Class's `saves.aligned`, else `opposed` (the `Default Save Rate`). `saves.opposed` entries declared explicitly take the `opposed` rate the same way. `ranks = sum over Classes of round_down(Class Level × Proficiency Advancement Rates[rate])`. Every Class contributes to every Save Attribute — "every Class trains every Save."
2. **Martial** (literal key `"martial"`): `ranks = sum over Classes of round_down(Class Level × Proficiency Advancement Rates[class.martial_advancement])`. Martial is not categorized via Aligned / Unaligned / Opposed proficiency lists — it has its own per-Class rate field.
3. **Skill key** (any other key): for each Class Entry, run *Skill Rate Resolution* (see below) to obtain a rate of `aligned`, `unaligned`, or null. A null rate means the Creature gains no ranks for that Skill from that Class (untrained-and-not-opposed); the Skill is treated as zero contribution from that Class. `ranks = sum over Classes of round_down(Class Level × Proficiency Advancement Rates[rate])` summing only Classes that produced a non-null rate.
4. **Granted-Ability ranks** are not produced here; Abilities don't add ranks, they add Modifiers via `modifiers:`.

The Floor Ability lift is *not* applied here — Proficiencies handles that on top of the ranks Creatures returns. Creatures returns ranks; Proficiencies layers the Floor Ability.

### Skill Rate Resolution

Given a queried Skill key `k` and a merged Class entry, the rate is determined in this order. A null rate means the Creature gains no ranks from that Class for this Skill.

1. If `k` is not in the Creature's `trained_skills` for this Class, the rate is null. Untrained Skills accrue no ranks regardless of how the Class categorizes them.
2. Otherwise, if `k` (or `k`'s longest matching Set Skill prefix) appears in the Class's `opposed_proficiencies`, the rate is `opposed`.
3. Otherwise, if the Class declares `aligned_proficiencies` (inclusion form): if `k` (or its prefix) appears in the list, the rate is `aligned`; otherwise `unaligned` (the `Default Skill Rate`).
4. Otherwise, if the Class declares `unaligned_proficiencies` (inverse form): if `k` (or its prefix) appears in the list, the rate is `unaligned`; otherwise `aligned` (the inverse-form default).
5. Otherwise (the Class declares neither inclusion nor inverse form): the rate is `unaligned`.

The Set Skill prefix resolution reuses Proficiencies' *Prefix Match* rule: a bare Set Skill key (e.g. `perform_`) in any of the three lists matches every Set Instance (`perform_sing`) the Creature could train.

### Aggregated Modifier Application to Speed

After step 3 of *Get Speed*, the Creature's Aggregated Modifiers with `target = "speed"` apply with per-Bonus-Type stacking: within each Bonus Type, the largest positive amount and the most-negative amount (each appearing only if at least one entry of that sign exists) survive; sum the survivors.

This mirrors Conditions' *Get Modifiers* shape so the consuming project's Modifier handling is uniform across "always-on from Granted Abilities" (Creatures) and "active per-Creature Effects" (Conditions). Combat is the natural consumer when both are needed.

### Max Hit Points and Max Mana Formula Composition

`Max HP = floor(HP Formula[tier])` where `HP Formula` is a per-Tier list of expressions in `creatures_config.yaml`. The expressions reference `con` — substituted with the Creature's Effective Constitution at evaluation time. Project convention: Tier 0 → 0.5 in formulas; integer Tiers stay integer. The resulting integer is added to the per-Tier-Bonus-Type aggregated `hp_bonus` amount.

`Max Mana = floor(Mana Formula[tier]) + sum over Classes of (class.mana_advancement × class.level) + aggregated mana_bonus`.

Both formulas accept `+`, `-`, `*`, `/`, `()`, integer literals, and the attribute symbols `str` / `dex` / `con` / `int` / `wis` / `cha` (resolved to the Creature's Effective Attribute). Other symbols are a configuration error.

A Tier beyond the configured `HP Formula` or `Mana Formula` array is an error rather than a clamp.

### Tier-Up Choice Validation

When *Set Tier-Up Choices* is called with Tier `T` and choices `C`:

- `|C|` must equal `Per-Tier Inherent Chosen Bonus Count`. Sized lists strictly — a Creature that wants to forgo a chosen bonus at a particular Tier omits the entry from `tier_up_choices` entirely.
- Every entry of `C` must be a recognized attribute key.
- The Creature must have `tier ≥ T`. A Tier in the future cannot be pre-set.
- `T` must be ≥ 2. Tier 0 and Tier 1 have no Tier-Up Chosen Bonus — Tier 1 grants only the flat Per-Tier Inherent Bonus. The first Tier-Up that produces Chosen-Bonus picks is the transition from Tier 1 to Tier 2.

Duplicates within `C` are allowed — picking the same attribute twice doubles the bonus at that Tier.

### Class Resolution (Sub-Class merge)

Resolve a Class Entry's `class` key against `classes.yaml`:

1. If the key matches a top-level Class entry directly, return it.
2. Otherwise scan top-level Class entries for one whose `sub_class` map contains the key. Apply the Sub-Class Entry's overrides to the parent (per Common types). Return the merged entry.
3. If neither matches, raise a configuration error at load time. Lookups at runtime treat the unknown key as zero contribution and emit a warning.

The Class Entry on the Creature always carries the resolved key — whether top-level or Sub-Class — so reverse lookups (Granted Ability source attribution) name the Sub-Class when the Creature took the Sub-Class.

### Validation

Every Creature Record is validated at load time:

- `id` is unique across the dataset.
- `race` resolves in `races.yaml`. If the Race declares Aspects, `race_aspect` is non-null and matches one of them. If the Race does not declare Aspects, `race_aspect` is null.
- Each `classes[i].class` resolves through *Class Resolution*. `level ≥ 0`. `trained_skills` entries do not end in `_`. Set Instances are accepted; the Set-Skill prefix is resolved when computing ranks.
- A Class Catalog Entry does not declare both `aligned_proficiencies` and `unaligned_proficiencies` (mutually exclusive). A Sub-Class may declare any combination — each is an additive adjustment to the parent's categorization.
- Every Class Catalog Entry declares `saves.aligned` as a list of recognized attribute keys. Project convention has exactly two entries per Class; the loader does not enforce the count.
- `base_attributes` has every required attribute key.
- `tier_up_choices` Tiers are integers ≥ 2. Each entry's list length matches `Per-Tier Inherent Chosen Bonus Count`. Tier 1 (and Tier 0) entries are rejected — those Tiers do not grant Chosen Bonus picks. Tiers beyond the Creature's current Tier are flagged but not rejected (a Creature's Tier may decrease via override; the picks become inactive when Tier is below the entry's key).
- `choices` entries (notably `choices.spellcasting`) are stored opaquely. Validation that the spell names within resolve in Abilities is deferred to Abilities (warning at load, ignored at runtime).
- `advancement_track` resolves in `Tier Breakpoints`.

Malformed records are rejected with a descriptive error; one malformed record does not silently drop other valid records (the loader rejects the whole file).

## Cross-domain interactions

- **Proficiencies.** Creatures provides the Creature Accessor. Proficiencies reads `ranks_for`, `attribute_value`, `has_ability`, `level_for_ability`. Creatures does not call Proficiencies.
- **Combat.** Combat receives a `creature_lookup` callback wired to *Look up Creature* and stores Creature IDs. Combat reads through the Accessor; per-Combatant *Combat Pool* and Initiative dice counts are computed by Combat using the Accessor's `attribute_value` and `ranks_for("martial")`.
- **Conditions.** Conditions stores per-Creature mutable state keyed by Creature ID; Creatures supplies the inputs Conditions' *Dead?* and *Magic Toxicity Update* need (max HP, attribute scores, Tier, Toxicity Threshold Attribute value). Conditions is invoked *by* the consuming project, not by Creatures.
- **Abilities.** Creatures looks up `modifiers:` lists via Abilities' *Get an Ability's Modifiers*. Creatures does not interpret the Modifier `target` keys — they pass through verbatim to consumers.
- **Equipment.** Equipment ties items to Creatures by ID outside the Creature Record. Item-driven attribute or skill bonuses come back as Active Effects through Conditions / Modifier aggregation at the consumer; they do not enter the Creature Record or the Effective Attribute calculation.

## Responsibilities

### Owned by the Creatures domain

- The Creature Record and its persistence shape.
- Tier computation: Total Level → Tier Breakpoints → Tier (with Tier Override).
- Effective Attribute computation: Base + Racial Adjustment + Per-Tier Inherent Bonus + Per-Tier Inherent Chosen Bonus.
- Tier-Up Choice storage and validation.
- Race / Race Aspect resolution and Granted Ability roll-up.
- Class / Sub-Class resolution and Granted Ability roll-up.
- Per-Class `choices` storage (Spellcasting picks, deity/domain, Versatile Performance subject, etc.).
- Ranks Computation for skill, save, and Martial keys.
- Speed computation: Race + Aspect base + aggregated Speed Modifiers (Class-driven Speed bonuses come through Granted Ability `modifiers:` entries, not a Class table).
- Max HP and Max Mana formula composition.
- Modifier aggregation: walking Granted Abilities, evaluating `add` Formulas, returning Aggregated Modifier Entries.
- Producing the Creature Accessor consumed by other domains.
- `classes.yaml` and `races.yaml` catalogs.
- Load-time validation of Creature Records.

### Explicitly *not* owned here

- **Prowess and Dice Cap.** Proficiencies translates ranks to dice counts.
- **HP damage, Mana spent, Active Effects, Active Afflictions.** Conditions owns per-Creature mutable state. Creatures returns max HP and max Mana; current values are computed by Conditions against those maxes.
- **Combat Pool size.** Combat computes from `martial` ranks + Combat Pool Attribute + Turns Per Round[tier].
- **Initiative dice count.** Combat computes from Initiative Attribute + Initiative Divisor.
- **Per-Bonus-Type stacking.** Aggregated Modifiers are returned uncollapsed; consumers (Combat, Conditions) apply stacking.
- **Ability mechanics.** Spells, Talents, Stateful Abilities, Active Effects: Abilities and Conditions own those. Creatures hands names back.
- **Equipment and Currency.** Equipment owns its own state and aggregates by Creature ID.
- **Per-Creature combat state (initiative string, time tick schedule, etc.).** Combat owns those during an active fight.

### Unassigned (no current owner)

- **Languages.** A Creature's spoken / written language list. Useful for Chronicle and stubs but not currently modeled.
- **Encumbrance.** Carry capacity from Strength has no consumer yet; deferred until Equipment lands its weight rules.
- **Aging.** Tier and Level capture mechanical progression; biological aging (chronological age, lifespan) has no design.
- **Heritage events / story facts.** Background narrative belongs in Chronicle when it lands as a richer entity model; Creatures' `metadata` is the temporary home.
- **Companions and minions.** Creatures linked to one another (familiar, animal companion, summoned creature) currently use independent Creature records; a "controlling Creature" relationship is not modeled.
- **Attribute substitution.** Some Races (notably Undead) classically substitute one attribute for another in derived formulas (e.g. Charisma stands in for Constitution in HP calculations). The Race Entry schema does not yet carry a substitution map; until it does, such Creatures must either store the substituted value directly in `base_attributes` or be handled by a consumer-level shim. A future Race Entry field (e.g. `attribute_substitution: { con: cha }`) would route through *Effective Attribute Computation*.
