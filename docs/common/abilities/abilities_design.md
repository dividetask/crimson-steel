# Abilities — Design

The Abilities module is a strict **reference**: it answers "what does this Ability do?" in a form other modules can consume. It rolls no dice, tracks no active effects, and consumes no resources.

Sibling domains:
- **Conditions** owns the per-Creature state of Stateful Abilities (Rage timer, Bardic Inspiration luck pool, etc.) and the Effect Names catalog. Conditions validates the named-effect strings Abilities emits.
- **Combat** owns the action paths that Triggers fire during, and the geometry of `area`. Combat also computes implicit damage from attack rolls when no damage Effect is declared. Combat reads Bonus Type stacking rules when summing modifier totals on a Combatant.
- **Dice Resolution** owns Roll mechanics; this module's deferred-damage Formulas are evaluated by callers after the relevant Roll.
- **Creatures** aggregates `modifiers:` entries across earned Abilities into the Creature's effective bonus totals.

## Common types

### Catalog Ability

The schema for entries in `spells.yaml` and `talents.yaml`. Looked up by display name (the key in the YAML file).

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | enum | yes | `spell` or `talent`. |
| `tier` | int or list of int | conditional | Required for Spells (the Spell's intrinsic magical density). Optional for Talents — when omitted, the using Creature's Tier supplies the value at evaluation time. A list indicates a Tier-axis Variant. Tier 0 → 0.5 in formulas. |
| `aspects` | list of string | no | An Aspect-axis Variant. Mutually exclusive with a list `tier`. |
| `school` | string | spell only | Key into `Spell Schools`. Rejected on Talents. |
| `activation_time` | string | no | Action Alias, Real-Time Alias, `"<N> turns"`, or `"<N> minutes"`. **Default `main`** when omitted on a Spell or Talent without a `trigger`. |
| `range` | string or int | no* | Named Range or feet. *Optional when `trigger` is present.* |
| `target` | string | no | `"self"`, `"object"`, an integer string, or a Formula. **Optional.** A Spell with an `area` and no `target` affects every creature in the area. A Spell with both `target` and `area` uses the named target as the area's anchor (when the Area's `anchor` is `target`). A Spell with `target` only and no `area` directly names creatures or an object. |
| `requires_willing` | bool | no | Default `false`. When `true`, the Ability only affects willing targets; unwilling targets are unaffected even if no save is offered. Implicit `true` for `target: self`. |
| `save` | list of Save Spec | no | **Default `[]`** (no save) when omitted. |
| `attack_roll` | bool | no | Default `false`. |
| `trigger` | Trigger Spec | no | Presence makes the Ability fire during another action; see Triggers below. |
| `damage_type` | string | no | Key into the damage_types catalog. Required when any damage Effect omits explicit Severity. |
| `threshold` | non-neg int | conditional | Required when `damage_type: physical`; rejected otherwise. |
| `effects` | list of Effect | no | Unconditional Effects — apply regardless of save. |
| `effect_hash` | dict | no | Named values referenced from `description` and Effect strings. |
| `channel` | Channel Block | no | Presence makes the Ability a Channeled Ability. |
| `reservoir` | Reservoir Block | no | Presence gives the Ability a Reservoir. Required when `channel.mode` is `reservoir` or `auto`. |
| `prerequisite` | string | no | Catalog Ability name of a lower-tier this spell is based upon. This prerequisite spell will sometimes be required to learn before this one can be learned. |
| `inherits_from` | string | no | Catalog Ability name of a parent Ability whose fields seed this entry's defaults. The Abilities module resolves a child by starting with the parent's resolved Ability, then shallow-overriding with the child's declared fields. Used for talent families. |
| `mana_cost` | integer | `0` | Mana spent on activation (Talents only — Spells use the per-Tier Mana Cost table in `abilities_config.yaml`). |
| `required_condition` | string | no | Names a Condition the user must currently hold for this Ability to be available. Combat surfaces the Ability only when the Creature has the named Condition active. Example: `rage` for talents that only function while raging. |
| `duration` | string | no | Free-form. |
| `description` | string | no | Free-form; `{name}` and `{aspect}` substitution. |
| `skills` | list of string | no | Keys into `Casting Skills List`. **Default `[arcana]`** when omitted. |
| `items` | list of string | spell only | Keys into `Item Forms`. **Default `[]`** when omitted. Rejected on Talents. Universal forms appended at lookup unless `item_only`. |
| `item_only` | bool | spell only | Default `false`. Suppresses universal item form appending. Rejected on Talents. |
| `polarity` | enum | spell only | One of `positive` or `forced` — the Spell's Toxicity Source Kind (see `conditions/conditions_design.md`). `positive` marks a beneficial Spell (cure, buff, voluntary attunement) whose Magic Toxicity is subject to the Toxicity Block; `forced` marks a harmful or involuntary Spell whose Toxicity always applies. **Optional** — when omitted it is inferred at resolution time (`forced` when the Spell has `attack_roll: true`, a `damage_type`, or a damage Effect string; `positive` otherwise). Rejected on Talents. |
| `area` | Area | no | Turns the Ability into AOE. |
| `properties` | list of string | no | Keys into `Properties`. |
| `prefix`, `suffix`, `name` | list of string \| null | no | Per-Variant name parts. Parallel to the Variant Axis. |
| `variant_overrides` | list of (dict \| null) | no | Sparse per-Variant overrides. |
| `modifiers` | list of Modifier Entry | no | Always-On Modifier read-through. See Operations. |
| `target_escape_save` | Target Escape Save | no | When present, the Ability's target may spend the indicated action on its own turn to attempt a new save; success ends the effect early. |
| `grants_equipment` | list of string | no | Equipment IDs the Ability grants to the Creature. Used by the Natural Attack Talent and similar; the granting Class or Race fills in the list. Schema defined here; aggregation and weapon lookup are deferred to the Equipment domain. |

### Defaults

The loader applies these defaults to a Catalog Ability that does not declare the field:

- `activation_time` → `main`
- `skills` → `[arcana]`
- `items` → `[]`
- `save` → `[]`
- `requires_willing` → `false` (or `true` if `target: self`)

Authors should omit a field when the default applies. The lookup result always carries the resolved (defaulted) value.

**Universal Item Forms are appended automatically.** Spells do not need to list `scroll` and `wand` in their `items` field — they are added at lookup time (unless `item_only: true`). List only non-universal item forms (`potion`, `oil`).

### Modifier Entry

Field on a Catalog Ability or on an entry in `modifier_abilities.yaml`. Shape:

| Field | Type | Description |
|---|---|---|
| `target` | string | What the bonus applies to (`speed`, `attack`, `perception`, etc.). The target vocabulary is owned by the consuming domain (Combat, Equipment, etc.) — Abilities does not police it. |
| `type` | string | Bonus Type Name — must name an entry in the `Bonus Types List` config. Validated by Abilities at load time. |
| `descriptors` | list of string | Optional scope tags. Free-form. |
| `add` | signed number or Formula | Value to apply. May be a Formula of `level` / `tier`. Abilities returns Formulas verbatim; consumers evaluate. |

The Abilities module validates `type` against the `Bonus Types List` and returns the Modifier Entry verbatim. Aggregation across Abilities, type-stacking rules, and Formula evaluation against the Creature's level happen in Creatures and Combat.

### Save Spec

| Field | Type | Description |
|---|---|---|
| `attribute` | enum | One of `none`, `str`, `dex`, `con`, `int`, `wis`, `cha`. |
| `condition` | enum or absent | `on_fail` or `on_fumble`. Absent means unconditional. |
| `save_target` | enum | Who rolls the save. Default `target` (the Ability's named target). Other values: `observers` (creatures who perceive the effect), `area_creatures` (every creature in the Ability's `area`), `caster` (the caster rolls). |
| `<outcome_key>` | Effect string | One entry per Save Outcome Key — `fail` (required), `success` (optional), `fumble` (optional). |

An Effect string is one of:

- `"0"` — no effect on that outcome.
- An Effect Name from `conditions/effect_names.yaml`.
- A damage Formula (per the rules in *Damage Object*).
- The directive `halved` — the spell's full output is halved per the *Halved Effect* rule below. Useful when a successful save reduces but does not negate the spell's output.

**Halved Effect.** When a Save Outcome's Effect is `halved`, the consuming domain applies a cascading downgrade to the spell's outputs (damage, healing, and named effects whose `amount:` is numeric). The cascade halves each Severity's *original* count separately — downgraded amounts are never halved a second time.

For each Severity from Major down to Minor:
1. Divide the original count by 2, rounded down. Keep the quotient at this Severity.
2. The remainder (if any) downgrades by one Severity step (Major → Moderate → Minor → discarded).
3. Add the downgraded remainder to the next-lower Severity's *added* tally (not its original count, which is halved separately in the next iteration).

**Worked example:** starting 3 Minor, 1 Moderate, 1 Major.
- Major (1): halves to 0 with remainder 1. Remainder downgrades — adds 1 Moderate.
- Moderate (original 1, ignoring the added Moderate from Major): halves to 0 with remainder 1. Remainder downgrades — adds 1 Minor.
- Minor (original 3): halves to 1 with remainder 1. Remainder is below Minor — discarded.
- Combine: Minor = 1 (halved) + 1 (from Moderate downgrade) = 2. Moderate = 0 (halved) + 1 (from Major downgrade) = 1. Major = 0.
- Final: 2 Minor, 1 Moderate, 0 Major.

### Target Escape Save

| Field | Type | Description |
|---|---|---|
| `action` | string | Activation Time string for the action the target spends on its own turn. |
| `attribute` | enum | Save attribute the target re-rolls. One of `str`, `dex`, `con`, `int`, `wis`, `cha`. |

Resolution is caller-side: Combat / Conditions presents the option to the target on its turn; on success, the effect ends.

### Channel Block

Presence of a Channel Block makes a Catalog Ability a Channeled Ability. The Combatant spends a Main Action on it each of their turns (the cast itself counts as the first such channel) or the spell ends. Reservoir-mode and auto-mode Channeled Abilities require a Reservoir Block (see below) — the Channel Block does not duplicate Reservoir mechanics.

| Field | Type | Default | Description |
|---|---|---|---|
| `mode` | enum | required | One of `fire`, `reservoir`, `maintain`, `auto`. See per-mode notes below. |
| `apply_on_cast` | bool | `false` | Controls whether the channel/discharge effect fires on the initial cast. When `true` in **fire** mode: the cast fires the channel effect (using the cast's dice). When `true` in **reservoir** mode: the cast fires the Discharge effect once using the cast's dice — the Reservoir is **not** filled by the cast. When `false`: the cast applies only the spell's top-level effect (if any); the channel/discharge effect waits until the first subsequent channel. Examples: Heal's `apply_on_cast: true` (heal damage from top-level + reduce bleeding from channel — both fire on cast); Grasp's `apply_on_cast: true` (reservoir mode — cast fires the climb boost from cast dice, no Reservoir fill); Create Illusion's `apply_on_cast: false` (cast resolves the save against the illusion; subsequent channels handle DM-adjudicated alterations). |
| `retarget` | bool | `false` | Whether the channel may pick a new target each turn (fire-mode spells with a single target). |
| `description` | string | absent | Free-form description of what the channel does each turn. |
| `attack_roll` | bool | `false` | When `true`, the channel resolves as an attack roll using the channeled dice. (fire-mode only.) |
| `save` | list of Save Spec | empty | Save Specs evaluated against the channel effect. (fire-mode only.) |
| `effect_hash` | dict | empty | Channel-effect values. Namespaced separately from the top-level `effect_hash`. |

**Channel Mode notes:**

- **fire**: each turn's channel fuels the spell's effect directly. The channeled dice serve as the Roll (when `attack_roll` or a Save is involved) or drive the effect formula (e.g. Heal's bleed reduction scales with successes on the casting check). Channel dice are Main Action Minimum to Combat Pool Remaining; Dice Cap does not apply to channeling.
- **reservoir**: each turn's channel fills an associated Reservoir Block (with `fill.source: channel_dice`). The Reservoir is consumed by its Discharge.
- **maintain**: channel is upkeep only. No fueled effect, no Reservoir. Channel always costs exactly Main Action Minimum dice. The spell's text and the GM resolve what the maintained effect looks like.
- **auto**: the cast itself fills the associated Reservoir Block (which must have `reset: persistent`). After cast, the spell self-sustains — no Main Action channel is required each turn. The Reservoir is not Discharged; instead it defines the per-turn effect's magnitude (e.g. Spiritual Weapon attacks each turn using a number of dice equal to its Reservoir). The spell ends when its declared `duration` expires.

### Reservoir Block

Presence of a Reservoir Block gives a Catalog Ability a Reservoir — a tagged counter filled from a configured source and consumed by a Discharge. Reservoirs may appear on Channeled Abilities (paired with `mode: reservoir` or `mode: auto`) or on standalone Abilities like Talents (e.g. Bardic Inspiration).

| Field | Type | Default | Description |
|---|---|---|---|
| `fill.source` | enum | required | How the Reservoir gains amount. `channel_dice` (per-channel dice add to the Reservoir, used by channeled spells) or `check_successes` (each Success on a designated Check adds one). *(configurable)* |
| `fill.ratio` | int | `1` | Multiplier applied to the Fill Source's input. Spiritual Weapon uses 1; ratios above 1 grant amplification (n channeled dice → ratio × n Reservoir). |
| `reset` | enum | `per_turn` | When the Reservoir resets to zero. `per_turn` (default) resets at the start of the holder's turn; `persistent` never resets and ends only with the owning Ability. Auto-mode Channeled Abilities use `persistent`. |
| `discharge` | Discharge | optional | Defines how the Reservoir is spent. Omitted for auto-mode reservoirs (whose amount drives a per-turn effect without being consumed). |

**Discharge**:

| Field | Type | Default | Description |
|---|---|---|---|
| `action` | enum | required | Action category for the Discharge — `bonus`, `reaction`, `free`, or `main`. |
| `amount` | int or range | `"2..dice_cap"` | The amount of Reservoir consumed per Discharge. May be a fixed integer or a range. The default `"2..dice_cap"` lets the caller spend anywhere from Reaction Action Minimum dice up to the Dice Cap. Fixed amounts (e.g. `1`) are valid for Abilities where each Discharge costs a constant. |
| `description` | string | absent | What the Discharge does. May reference the chosen amount via `{amount}`. |
| `attack_roll` | bool | `false` | Whether the Discharge resolves as an attack roll. |
| `save` | list of Save Spec | empty | Saves evaluated on the Discharge effect. |
| `effect_hash` | dict | empty | Discharge-effect values. May reference `{amount}`. |

A Reservoir Discharge with `amount: "X..dice_cap"` follows the normal Dice Cap rule when the discharge produces a Roll — Dice Cap caps the spend just like any other Roll. Channeling itself (filling the Reservoir) is the exception to Dice Cap; spending from a Reservoir is not.

### Area

| Field | Type | Default | Description |
|---|---|---|---|
| `shape` | enum | required | `line`, `cone`, `square`, `circle`. *(configurable)* |
| `size` | non-neg int | required | In 5-foot squares. Never feet. |
| `anchor` | enum | `point` | Where the area is centered. `point` (caster designates a point at cast time), `target` (centered on and moves with the Ability's named target), `caster` (centered on and moves with the caster). |
| `on_enter` | Save Block | null | Save Block applied to any Creature that enters the Zone after cast. Becomes the `on_enter` trigger of the Conditions Zone Effect when the spell creates a Zone. |
| `on_end_of_turn` | Save Block | null | Save Block applied to any Creature that ends a turn inside the Zone. Becomes the `on_end_of_turn` trigger of the Conditions Zone Effect. |

The top-level `save:` block on a spell with an `area:` doubles as the Zone's `on_create` trigger — fired on cast for every Creature already inside the Zone. The spell-domain casting routine calls Conditions' *Create Zone Effect* with the three triggers (on_create from the top-level save, on_enter, on_end_of_turn) and the area geometry; Atlas and Conditions own the Zone's lifecycle from there.

### Trigger Spec

| Field | Type | Required | Description |
|---|---|---|---|
| `on` | enum | yes | Action-name events (`attack_check`, `attack_action`, `on_hit`) fire during the Creature's own action of that name or class. Event-name triggers (`on_kill`, etc.) fire on a specific occurrence. *(configurable)* |
| `condition` | string | no | Scope tag referenced against Combat's `Trigger Conditions` catalog. Unknown values produce a load-time warning and never fire at runtime. |
| `effect` | Trigger Effect | yes | Structured one-shot outcome. |

### Trigger Effect

| Field | Type | Description |
|---|---|---|
| `kind` | string | Outcome shape. Recognized today: `bonus_dice` (adds dice to the triggering Roll), `bonus_damage` (adds damage to the triggering attack after it lands; carried by abilities like Sneak Attack and Rend), `scale` (a scaling adjustment to the Roll, e.g. reroll a die), `ui_reveal` (Combat surfaces the option to the GM without auto-firing), `invoke_named_effect` (the consuming domain applies a named effect from `conditions/effect_names.yaml`). |
| (kind-specific) | — | Further fields depending on `kind`. The Abilities module does not interpret them. |

### Damage Object (deferred damage)

Returned from Effect classification when an Effect is a damage expression.

```
{
  kind: 'damage',
  formula: '<expr>',
  damage_type: <string|null>,
  severity: <string|null>,
  context: { rank, tier, ...effect_hash }
}
```

`severity` is the explicit per-Effect Severity if the string had one, otherwise `null` — leaving lookup of the default to the consumer, since the damage_types catalog isn't an Abilities-module dependency at evaluation time. The caller later supplies `success`, `critical`, and `attribute` to evaluate.

### Effect Classification Result

One of:
- `{ kind: 'none' }` — for the literal strings `"0"` and `"none"`.
- `{ kind: 'effect', name: '<string>' }` — for any other non-damage string.
- A Damage Object — for damage expressions.

## Public entry points

### Look up a Catalog Ability by name

Input: ability name (display string), optional `axis_index` (default 0).

Returns the resolved Variant at `axis_index`:
- Inheritance resolved (if the Ability declares `inherits_from`, the parent's resolved Ability is the base and the child's declared fields shallow-override it). The parent itself is resolved first, recursively. Circular inheritance is a configuration error.
- Variant Overrides applied.
- Effect Hash resolved against the merged Ability.
- Variant name constructed.
- `{name}` and `{aspect}` substitution performed on `description` and Channel Block `description`.
- Universal Casting Skills appended (Spells only).
- Universal Item Forms appended (Spells, unless `item_only`).

Out-of-range `axis_index` is an error. Looking up a name that doesn't exist returns null.

### Look up a Stateful Ability by name

Returns `{ name, description }` from `stateful_abilities.yaml`, or null. Carries no schema — Conditions owns behavior.

### Look up an Always-On Modifier Ability by name

Returns `{ name, description, modifiers }` from `modifier_abilities.yaml`, or null. Modifier values are returned verbatim; Formulas in `add` are deferred.

### Resolve a Catalog Ability's range

Input: the Catalog Ability and an optional per-cast `reach`.

Returns range in feet:
- A bare integer `range` is returned as-is.
- A named Range is looked up in `Range Formulas` and evaluated against `rank` and the caller's `reach` (defaulting to `Default Reach Feet`).

### Resolve a Catalog Ability's activation time

Returns a structured activation result rather than a single number, since Action-aliased and Real-Time-aliased activations are not directly comparable:

```
{ kind: 'action', alias: <name>, value: <number> }      # Action Alias
{ kind: 'real_time', alias: <name>, minutes: <number> } # Real-Time Alias
{ kind: 'turns', turns: <number> }                      # "<N> turns"
{ kind: 'real_time', minutes: <number> }                # "<N> minutes"
```

Aliases are looked up in `Action Aliases` and `Real-Time Aliases`. `"<N> turns"` and `"<N> minutes"` strings are parsed directly. Conversion between turns and wall-clock minutes is owned by Combat / Timekeeping — the Abilities module never converts; callers who need both ask Combat for turn duration when they want one in terms of the other.

The `value` field on an Action result is a categorical label, not a duration. Combat maps it to an action category.

### Resolve a Catalog Ability's target

Returns `'self'` or a non-negative integer count. Formula strings evaluate against `rank` and the Effect Hash. A target count of zero means the Ability has no valid targets and cannot be cast.

### Resolve a Spell for item consumption

Input: a Spell name and the consumed Item's `tier`.

Returns the consumption view the Equipment domain routes at *Consume Item* time, or null for an unknown name:

```
{ effects: [ { <effect-key> => value }, ... ],
  polarity: 'positive' | 'forced' }
```

`tier` selects the Variant on a Tier-axis Spell (the Variant whose Tier matches the Item, falling back to the nearest in-range index); it is ignored on a single-Variant or Aspect-axis Spell. The Spell is resolved to that Variant, then its consumption-relevant outputs are flattened into the `effects` list. Each entry carries one of these keys:

- `minor_damage` / `moderate_damage` / `major_damage` — Severity-keyed magnitudes drawn from the resolved Effect Hash. The sign follows polarity: a `positive` (cure) Spell emits **negative** magnitudes (Equipment routes them to *Apply Heal*); a `forced` Spell emits **positive** magnitudes (routed to *Apply Damage*). All Severity keys present on one Variant share a single Effect Hash entry.
- `temp_hp` — a Ward magnitude from the Effect Hash.
- `mana` — a Mana-restore magnitude from the Effect Hash.
- `damage` — `{ amount, type }` from an explicit damage Effect string. The amount is the Effect's Formula evaluated with the Effect Hash plus `rank = 0` and the Variant's Tier; the damage-only variables `success` / `critical` / `attribute` default to `0` (a consumed Item rolls no casting check). An Effect string whose Formula still references an unbound name is skipped rather than raising. `type` is the Spell's Damage Type, omitted when it has none.

`polarity` is the Spell's `polarity` field when declared, otherwise the inferred value (see the field table). A Spell with no consumption-relevant Effects — e.g. a pure attack Spell whose damage is computed implicitly by Combat — returns an empty `effects` list and still reports its polarity.

This entry point is a convenience view layered on the standard lookup pipeline; it adds no new resolution rules beyond selecting the Variant and projecting its Effects into the Equipment-facing shape.

### Is a Spell Item-Only?

Input: a Spell name. Returns the Spell's `item_only` flag as a boolean — `false` for an unknown name or a Spell that does not declare it. Equipment's *Is Item-Only?* delegates here so UI surfaces can suppress non-item invocation paths without depending on Abilities directly.

### Get an Ability's Trigger

Input: ability name. Returns the Trigger Spec verbatim, or null if the Ability has no `trigger` field (or isn't a Catalog Ability). The Abilities module does not evaluate the Trigger.

### Get an Ability's Modifiers

Input: ability name, optional `source: 'class' | 'race'`. Returns the `modifiers:` list from the Ability's entry — across Catalog Abilities, `modifier_abilities.yaml`, and any other Ability flavor that carries `modifiers:`. Returns an empty list if none.

### List Catalog Abilities by Type / School

Returns Catalog Abilities matching the given `type` and/or `school` filter. Filters on un-resolved Ability data; does not iterate Variants.

### Classify an Effect string

Input: an Effect string and the context Effect Hash. Returns an Effect Classification Result. For damage expressions, parses the optional inline Severity and constructs a Damage Object with the appropriate context.

### Evaluate a deferred Damage Object

Input: a Damage Object and the caller-supplied `success`, `critical`, `attribute`. Returns the integer damage. Negative values clamp to 0.

The `success` / `critical` semantics are caller-defined: defender's save results inside a Save Outcome, caster's casting-roll results inside an Unconditional Effect.

### Resolve the Channel Block

The Channel Block has its **own Effect Hash, namespaced separately** from the top-level — the two never share variable names at evaluation time. Resolution mirrors the top-level lookup path: apply Variant Overrides to the block's fields, resolve the block's Effect Hash, substitute `{name}` and `{aspect}` in the block's description.

The Channel Block's `attack_roll` and `save` (in fire mode) and the Activation's `attack_roll` and `save` (in reservoir mode) are **independent** of the Ability's top-level versions.

**Rule: a Channeled Ability ends when channeling stops.** Any Catalog Ability with a Channel Block (fire / reservoir / maintain modes) terminates at end-of-turn on any turn where the caster did not spend a Main Action channeling it. The `duration` value is the **maximum** time the effect can be sustained, not a guaranteed duration. Auto-mode is the exception: the cast fills the Reservoir, and the spell self-sustains for its full `duration` without needing per-turn channeling.

## Operations

### Variant resolution

A Catalog Ability's Variants are indexed by exactly one **Variant Axis** — `tier` (a list of integers) or `aspects` (a list of opaque labels). The two are mutually exclusive (validator rejects both). A Catalog Ability that declares neither has a single Variant at index 0.

Resolving a Variant at `axis_index` follows a fixed order:

1. **Apply Variant Overrides.** If `variant_overrides[axis_index]` is a dictionary, shallow-replace each key on a copy of the base Ability. **A `null` override value removes the key entirely** — this is how a higher tier opts out of a Channel Block, or how one aspect of a multi-element Spell drops a save the other aspects retain. List- and dictionary-valued overrides replace the base value wholesale; there is no deep merge.
2. **Resolve the Effect Hash** for `axis_index` against the merged Ability.
3. **Construct the Variant name.** If `name[axis_index]` is a non-empty string, that's the name verbatim and `prefix`/`suffix` at this index are ignored. Otherwise the name is `<prefix> <Ability name> <suffix>` with empty/null parts dropped.
4. **Substitute description tokens.** `{name}` tokens replaced from the resolved Effect Hash. When axis is `aspects`, `{aspect}` is replaced with `aspects[axis_index]`. Substitution applies to `description`, the Channel Block's `description` (and Activation `description` in reservoir mode), and any future display-string field.

Variant Overrides may not change `tier`, `aspects`, `prefix`, `suffix`, `name`, or `variant_overrides` itself — those are structural or have their own parallel-list mechanisms.

### Effect Hash resolution

The Effect Hash is a flat dictionary, but its values cross-reference each other through Formulas. Resolution walks entries in declaration order, evaluating each against a context that already contains every previously-resolved name:

- A list-valued entry on a multi-Variant Ability uses the value at `axis_index`.
- A string-valued entry is treated as a Formula and evaluated.
- Any other value is taken verbatim.

`tier` is always present (Tier 0 → 0.5 per project convention). `rank` is always present. Names from the Effect Hash become available as soon as they're resolved, so a later entry's Formula may reference an earlier entry's value.

Damage-expression-only variables (`success`, `critical`, `attribute`) must **not** appear in Effect Hash Formulas, Range Formulas, or Target Formulas — those are resolved before any roll. The validator does not catch this; it surfaces as an unresolved-name error at evaluation time.

### Damage Type, Severity, and Threshold

The Abilities module enforces the rules linking damage Effects to the damage_types catalog:

- A Catalog Ability may declare a `damage_type` matching a name in the catalog.
- A damage Effect's Severity comes from the **explicit per-Effect form** (`"<formula> <severity> damage"`) when present, otherwise from the Ability's `damage_type`'s default Severity.
- A Catalog Ability whose `damage_type` is **`physical`** must additionally declare a non-negative integer `threshold`. Physical damage opts into Runtime Bucketing, so Severity is decided at damage-application time by Combat — but the Threshold input is data the Ability itself must carry.
- A `threshold` field on a non-physical Ability is a validation error.
- Every damage Effect must have a determinable Severity (explicit per-Effect or via the Ability's `damage_type`).
- A Catalog Ability with `attack_roll: true` and **no** declared damage Effects is allowed — Combat computes implicit damage (`Tier + Degree of Success + attack bonus`).

Aspect-axis Abilities that vary `damage_type` per aspect declare it as a parallel list (e.g. `damage_type: [fire, acid, electricity, cold]`).

### Effect classification

Every Effect string falls into exactly one of three kinds, by string shape:

- `"0"` or `"none"` → `{ kind: 'none' }`.
- `"<expression> damage"` or `"<expression> <severity> damage"` → Damage Object.
- Otherwise → `{ kind: 'effect', name: <string> }`. The Abilities module does not check that the name exists in any catalog — that's the Conditions module's job at apply time.

### Universal forms and skills

`Universal Spell Casting Skills` and `Universal Item Forms` are appended **implicitly** at lookup time, not stored on the Ability. Data files must not list a universal entry in `skills` or `items` (validator rejects). Spells get universal skills/forms appended; Talents do not. Item-Only Spells do **not** receive universal Item Forms — only the explicit list applies, since the universal forms (scroll, wand) wouldn't make sense for them.

### Conditional saves

A Save Spec may carry a `condition` field (`on_fail` or `on_fumble`) that gates whether the save is offered. The Abilities module reports conditional saves verbatim; **dispatch is the caller's job** — the Abilities module never inspects prior save results.

`fumble` outcome dispatch is also caller-side: when a save's Degree of Failure meets or exceeds the Default Fumble Threshold, the `fumble` outcome (if defined) replaces the plain `fail` outcome.

### Trigger lookup

Triggers are exposed via two paths:

- **On Catalog Abilities directly.** If a Spell or Talent has a `trigger` field, `GET_TRIGGER(name)` returns it. Procedural class/race features (sneak_attack, halfling_luck, etc.) live as Talents with a `trigger` field and typically omit `activation_time` / `range` / `target`.
- **Trigger is not evaluated here.** The Abilities module returns the Trigger Spec; the consuming module evaluates `condition` and applies `effect`. This keeps the Abilities module ignorant of action semantics, the same way it's ignorant of dice rolls.

A Catalog Ability may have a Trigger, a normal cast pipeline, both (an active Ability that also acts as a rider when the Creature performs the right action), or neither.

### Always-On Modifier read-through

Flat numeric bonuses while the Creature has the Ability are handled by Modifiers via the `modifiers:` field. `GET_ABILITY_MODIFIERS(ability_name)` returns the list across every Ability flavor (Catalog Ability, Always-On Modifier Ability, Stateful Ability that also grants passive modifiers). Actual application — summing across earned Abilities, posting to bonus calculations, evaluating Formulas in `add` against the Creature's level — is the Modifiers / Creatures path.

## Responsibilities

### Owned by the Abilities domain

- Loading and validating `spells.yaml`, `talents.yaml`, `stateful_abilities.yaml`, `modifier_abilities.yaml`, and `abilities_config.yaml`.
- Schema validation: rejecting unknown Types, Schools, Casting Skills, Item Forms, Properties, Save Attributes, Save Outcome Keys, Action Aliases, Real-Time Aliases, Range names, Area Shapes, Damage Type names, Trigger Event names, Bonus Type names, Polarity values; checking Variant parallel-list lengths; rejecting overrides of structural fields; rejecting universal-entry leaks; rejecting Abilities that declare both `tier` (as a list) and `aspects`; rejecting `school`/`items`/`item_only`/`polarity` on Talents.
- Validating Severity rules: every damage Effect has a determinable Severity; `damage_type: physical` requires `threshold`; `threshold` rejected on non-physical Abilities.
- Resolving Variants: applying Overrides, constructing names, performing `{name}` and `{aspect}` substitution.
- Resolving Effect Hash with axis-indexed picks and cross-reference Formula evaluation.
- Classifying Effects (none / named / damage), parsing optional inline Severity from damage Effect strings.
- Building partial contexts and evaluating damage Formulas when `success` / `critical` / `attribute` are supplied.
- Resolving the Channel Block.
- Implicitly appending Universal Casting Skills and Universal Item Forms.
- Resolving `activation_time` to a structured action / real-time / turns result, `range` to feet, `target` to either `'self'` or a count.
- Resolving a Spell to its Equipment-facing consumption view (routed `effects` list + `polarity`), and reporting a Spell's `item_only` flag.
- Filtering and listing Catalog Abilities by Type and/or School.
- Returning Trigger Specs verbatim from `GET_TRIGGER`.
- Returning `modifiers:` lists verbatim from `GET_ABILITY_MODIFIERS`.
- Returning `{ name, description }` for Stateful Abilities.

### Explicitly *not* owned here

- **Rolling dice and resolving saves.** Dice Resolution and Combat.
- **Damage Type behavior.** Severity defaults, Mechanics, Runtime Bucketing live in damage_types (folded into Combat) and its consumers.
- **Computing implicit damage from attack rolls.** Combat.
- **Applying named effects.** Conditions.
- **Active-effect bookkeeping, channel and Reservoir tracking.** Conditions and Combat.
- **Consuming spell slots, charges, mana.** Creatures and Item modules.
- **Mapping Creatures to known Abilities.** Creatures.
- **Determining who is in an `area`.** Combat computes overlap.
- **Property mechanics.** The keyword list is validated here, but behavior of each property lives elsewhere.
- **Magic Toxicity application.** Conditions reads and applies.
- **Evaluating Trigger conditions or applying Trigger Effects.** The consuming module's job.
- **Aggregating `modifiers:` entries into Creature bonus totals.** Creatures (with type-stacking rules from Combat).
- **Bonus Type stacking semantics** (which Bonus Type stacks with itself, which doesn't). Combat owns this.
- **Stateful Ability behavior.** Conditions.

### Unassigned (no current owner)

- Validating that a passed `rank` is non-negative.
- Tracking which Properties exist purely for display vs. those with mechanical effects.
- Cross-domain validation that every name in named-Effect strings whose `mechanics` are non-empty corresponds to a Condition Mechanic the Conditions module actually understands.
- Cross-domain validation that the `condition` and `condition_name` strings inside damage_types Mechanics resolve to real concepts.
