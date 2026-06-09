# Proficiencies — Design

Owns the Skill catalog, the Prowess formula, and the ability-driven substitutions (Floor Ability, Substitution Ability) that may produce a higher Prowess than the queried key alone. Pure calculation — Proficiencies holds no state. Per-Creature ranks, attributes, and ability membership are read through a Creature accessor the caller supplies.

Rank accumulation across class levels, Class skill lists, and the rule that every Class trains every Save are not Proficiencies concerns; those live in `creatures/creatures_design.md` (see *Ranks Computation* under that domain's Operations).

## Common types

### Skill catalog entry

| Field | Type | Default | Description |
|---|---|---|---|
| `attribute` | one of `str`, `dex`, `con`, `int`, `wis`, `cha` | required | The driving attribute for this Skill. |
| `description` | string | required | Human-readable description, displayed by UI surfaces. |

The catalog lives in `skills.yaml`. A Skill is a Set Skill iff its catalog key ends with `_`; there is no separate flag.

### Creature accessor

The interface the caller supplies so Proficiencies can read per-Creature data. Methods:

| Method | Returns | Description |
|---|---|---|
| `ranks_for(key)` | integer | The Creature's ranks in the given concrete key. Zero when the Creature has no entry. The key must not end in `_`. |
| `attribute_value(attr)` | integer | The Creature's value for the given attribute key. |
| `has_ability(ability_name)` | boolean | Whether the Creature has the named ability. The names Proficiencies passes are the configured Floor Ability and Substitution Ability values. |
| `level_for_ability(ability_name)` | integer | The Creature's level in the Class (or other source) that granted the named ability. Used by the Floor Ability; not the Creature's total level. |

Proficiencies never mutates the accessor and never caches values across calls.

## Public entry points

### Compute Roll inputs for a Proficiency

The main entry point. Computes Direct Prowess and (when applicable) Substituted Prowess, picks the higher Prowess, translates through dice resolution.

Inputs:

| Field | Type | Default | Description |
|---|---|---|---|
| `key` | string | required | The proficiency key being resolved. May be a catalog key, a Set Instance key, or an unknown key. The key must not end in `_`. |
| `creature` | Creature accessor | required | See common types. |
| `attribute_override` | attribute key or null | null | When non-null, used as the driving attribute and the catalog lookup is skipped for attribute purposes. Required when the key has no catalog entry. |

Pipeline:

1. **Resolve the catalog entry.** Look up `key` in the catalog. If no exact entry exists, apply Prefix Match. The result is either a catalog entry or null. If the result is null and `attribute_override` is null, the call is invalid.
2. **Determine the queried key's driving attribute.** `attribute_override` if provided; otherwise the resolved entry's `attribute`.
3. **Compute Direct Prowess.** See **Direct Prowess** below.
4. **Compute Substituted Prowess.** See **Substituted Prowess** below. Skipped entirely when not applicable.
5. **Proficiency Prowess.** `max(Direct Prowess, Substituted Prowess)`. Direct Prowess wins ties. Prowess is built from **ranks + attribute only** — it carries no bonus or penalty, because a bonus/penalty must never change the dice count (only ranks and attribute do).
6. **Translate.** Call dice resolution's *Translate Skill Prowess into Roll inputs* with the Proficiency Prowess, yielding `dice_cap` and a base `bonus_penalty`.
7. **Apply the Non-Proficiency Penalty.** When the winning Prowess source is untrained (its effective ranks are 0) **and** the queried key is **not** a Saving Throw (`*_save`), add the Non-Proficiency Penalty to `bonus_penalty`. This is a Target-Number penalty only — it never changes `dice_cap`. A Saving Throw never takes the penalty, trained or not.
8. **Return.** `{dice_cap, competency_modifier}`. The modifier is `("Competency", bonus_penalty)` when `bonus_penalty != 0`; otherwise null.

Returns:

| Field | Type | Description |
|---|---|---|
| `dice_cap` | integer | The dice count returned by dice resolution's Prowess translator. The maximum dice the Creature can spend on a roll for this proficiency. |
| `competency_modifier` | `(type_name, signed_value)` pair or null | Tagged Competency entry to be added to the Roll's `bonus_penalty_list`. Null when zero. |

### Look up a Skill

Pure conversion. Resolves a key against the catalog using Prefix Match.

Input: `key` — string. Must not end in `_`.

Returns: a Skill catalog entry, or null when the key matches nothing in the catalog.

Used by callers (e.g., UI sheets) that want a Skill's attribute or description without computing Prowess.

### List Skills

Returns the catalog as a map of key → entry. Set Skills are included; Set Instances are not (they aren't enumerated).

## Operations

### Prefix Match

Reads the Skill catalog and a queried key. Produces a catalog entry or null.

Rules:

- If the catalog has an exact match for `key`, return it.
- Otherwise, find every catalog entry whose key ends in `_` and is a prefix of `key`. Among those, the entry with the longest key wins. Return it.
- If no such entry exists, return null.

### Direct Prowess

Reads the queried key, the resolved catalog entry, the queried key's driving attribute, the Creature accessor, and the Floor Ability configuration.

- `base_ranks = creature.ranks_for(key)`.
- `floor_ranks`: when **all** of the following hold, the floor lift is `floor(creature.level_for_ability(Floor Ability) / 2)`; otherwise zero.
  - `creature.has_ability(Floor Ability)` is true.
  - The resolved catalog entry is not null (the call did not use `attribute_override` against an unknown key).
  - The resolved entry's key does not appear in `Restricted Skills`.
- `effective_ranks = max(base_ranks, floor_ranks)`.
- `Direct Prowess = effective_ranks + floor(creature.attribute_value(driving_attribute) / Attribute Contribution Divisor)`. The Non-Proficiency Penalty is **not** part of Prowess — it is a Target-Number penalty applied after translation (pipeline step 7). The Skill is **trained** when `effective_ranks > 0`; that flag (not the penalty) flows out so the caller can decide the penalty.

The Floor Ability never changes the driving attribute. It is purely a ranks lift on the queried key; the higher of (actual ranks, floor ranks) is used.

### Substituted Prowess

Reads the queried key, the Substitution Map, the Creature accessor, and the catalog.

- Skipped entirely (no Substituted Prowess produced) when **either** of these holds:
  - `creature.has_ability(Substitution Ability)` is false.
  - No entry of the Substitution Map lists the queried key as a target.
- Otherwise, for each source key in the map whose target list contains the queried key:
  - `source_ranks = creature.ranks_for(source_key)`.
  - `source_attribute = the catalog attribute of source_key`. Source keys must resolve to a catalog entry (exact match or via Prefix Match for Set Instances). A source key with no catalog match is a configuration error.
  - `source_prowess = source_ranks + floor(creature.attribute_value(source_attribute) / Attribute Contribution Divisor)`. As with Direct Prowess, no penalty is folded in; the source is **trained** when `source_ranks > 0`.
- `Substituted Prowess = max(source_prowess across all matching sources)`, carrying the winning source's trained flag.

The Floor Ability never lifts a source's ranks. The substitution operates on the source key's actual stored ranks and its catalog attribute.

The Substitution Map's source keys do not have to be Set Instances. Concrete catalog keys (e.g., `cooking`) are valid, as are Set Instances (e.g., `perform_dance`). The default config uses Set Instances because Versatile Performance is the seed use case.

### Proficiency Prowess

Compares Direct Prowess and (if produced) Substituted Prowess. The higher value is the Proficiency Prowess. Direct Prowess wins ties.

The Proficiency Prowess is fed to dice resolution's translator. The intermediate ranks and attribute are not exposed in the public return — only the translated `dice_cap` and `competency_modifier` are.

### Non-Proficiency Penalty

A flat penalty (default `-2`) for acting **untrained** — using a Skill in which the winning Prowess source has zero effective ranks. Two rules govern it:

- **It adjusts the Target Number, never the dice.** The penalty is added to the translated `bonus_penalty` (the Competency Modifier), *after* Prowess has set the dice count. Dice come only from ranks + attribute, so being untrained costs you accuracy, not dice. (This is the general rule for every bonus and penalty: only ranks and attribute move dice. A bonus *to an attribute* — a Belt of Strength, say — does change dice because it raises the attribute; a bonus *to the roll* never does.)
- **Saving Throws never take it.** A Saving Throw key (`*_save`) is exempt regardless of ranks: an untrained Save rolls its full ranks-plus-attribute Prowess with no Competency penalty. The penalty applies only to untrained Skill checks (including the Floor Ability's *untrained Skill* row).

## Cross-domain interactions

- **Dice resolution.** Proficiencies calls *Translate Skill Prowess into Roll inputs* and labels the resulting bonus/penalty with the Type Name `Competency`. Proficiencies never assembles full Rolls; that is the caller's responsibility.
- **Modifiers.** Proficiencies emits exactly one Bonus/Penalty Type — `Competency`. Other Types come from other producers and are aggregated into the Roll's `bonus_penalty_list` outside this domain.
- **Creatures.** Proficiencies depends on the Creature accessor. Concrete rank storage, level-per-class computation, and ability membership are Creatures concerns.
- **Abilities.** Two abilities are referenced by configured name: the Floor Ability (default `jack_of_all_trades`) and the Substitution Ability (default `versatile_performance`). Proficiencies queries `creature.has_ability` rather than parsing ability data directly. When the Abilities domain lands, the Substitution Map may move there; Proficiencies will read it from the new location.
- **Configuration.** Loaded from `proficiencies_config.yaml` and `skills.yaml` at boot.
