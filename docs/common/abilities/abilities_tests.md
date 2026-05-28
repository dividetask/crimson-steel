# Abilities — Tests

Tests for the public entry points of the Abilities domain. Unless a test specifies a different config, all tests use the values in `abilities_config.yaml`. Where a test references a Catalog Ability, the definition is given inline (these tests don't depend on the actual contents of `spells.yaml` / `talents.yaml`).

---

## Look up a Catalog Ability by name

**Single-Variant Ability returns its base form.** Given a Talent `Intimidating Shout` with `tier: 1`, no `aspects` list, no `variant_overrides`, and a `description` of `"A thunderous shout. Targets that fail a Wisdom save are frightened and must flee."`:
- Looking it up with `axis_index = 0` returns the Ability with `tier = 1` and the description verbatim.
- Looking it up with `axis_index = 1` is an error (out of range).

**Tier-axis Variant picks the right tier and applies the prefix.** Given a Spell `Ward` with `tier: [0, 1, 2, 3, 4, 5]`, `prefix: [Trivial, Lesser, Simple, Improved, Advanced, Superior]`, and `effect_hash.temp_hp: [3, 5, 8, 12, 16, 20]`:
- Lookup at `axis_index = 2` returns name `"Simple Ward"`, resolved `temp_hp = 8`, and the description with `{temp_hp}` replaced by `8`.
- Lookup at `axis_index = 0` returns name `"Trivial Ward"` and `temp_hp = 3`.

**Aspect-axis Variant substitutes `{aspect}` in the description.** Given a Spell `Elemental Dart` with `aspects: [fire, acid, electricity, cold]`, `name: [Fire Dart, Acid Dart, Electricity Dart, Cold Dart]`, and description `"A ranged dart of {aspect}."`:
- Lookup at `axis_index = 1` returns name `"Acid Dart"` (from the `name` list, ignoring `prefix`/`suffix`) and description `"A ranged dart of acid."`.

**Variant Overrides replace fields wholesale, and `null` removes a key.** Given an Ability with base `duration: "rank minutes"` and `variant_overrides: [null, { duration: "rank hours" }, { duration: null }]`:
- At index 0, the merged Ability keeps `duration: "rank minutes"`.
- At index 1, the merged Ability has `duration: "rank hours"`.
- At index 2, the merged Ability has no `duration` key.

**Variant Overrides may not change structural fields.** An override that sets `tier`, `aspects`, `prefix`, `suffix`, `name`, or `variant_overrides` is a validation error at load time.

**Declaring both `tier` (as a list) and `aspects` is a validation error.** The two axes are mutually exclusive.

**Looking up a name that doesn't exist returns null.**

---

## Resolve a Catalog Ability's range

**A bare integer range is returned as-is.** A Spell with `range: 1000` resolves to 1000 feet regardless of `rank`.

**A named range evaluates its formula against `rank`.** Default `Range Formulas` from config:
- `Close` with `rank = 0` → `5 + 5*0 = 5` feet.
- `Close` with `rank = 3` → `5 + 5*3 = 20` feet.
- `Medium` with `rank = 2` → `30 + 10*2 = 50` feet.
- `Long` with `rank = 4` → `80 + 20*4 = 160` feet.

**Touch range uses caller-supplied `reach` when provided, else `Default Reach Feet`.**
- `Touch` with no `reach` → `Default Reach Feet` (5).
- `Touch` with `reach = 10` → 10.

**Self range returns 0 regardless of rank.**

**An unknown named range is a validation error at load time** (not at resolution).

---

## Resolve a Catalog Ability's activation time

**Action Aliases resolve to action results.** With default config:
- `Free Action` → `{ kind: 'action', alias: 'Free Action', value: 0 }`.
- `Bonus Action` → `{ kind: 'action', alias: 'Bonus Action', value: 0.25 }`.
- `Reaction` → `{ kind: 'action', alias: 'Reaction', value: 0.1 }`.
- `Main Action` → `{ kind: 'action', alias: 'Main Action', value: 0.5 }`.
- `Full Turn` → `{ kind: 'action', alias: 'Full Turn', value: 1 }`.

**Real-Time Aliases resolve to real-time results in minutes.** With default config:
- `1 Minute` → `{ kind: 'real_time', alias: '1 Minute', minutes: 1 }`.
- `1 Hour` → `{ kind: 'real_time', alias: '1 Hour', minutes: 60 }`.
- `1 Day` → `{ kind: 'real_time', alias: '1 Day', minutes: 1440 }`.

**Explicit `"<N> turns"` is parsed directly.**
- `"3 turns"` → `{ kind: 'turns', turns: 3 }`.

**Explicit `"<N> minutes"` is parsed directly.**
- `"5 minutes"` → `{ kind: 'real_time', minutes: 5 }`.

**Unknown aliases are a validation error at load time.**

**A Catalog Ability with a `trigger` field and no `activation_time` resolves to `{ kind: 'action', alias: 'Free Action', value: 0 }`** (the Ability fires during another action's pipeline, not on its own).

**The Abilities module never converts between Action and Real-Time results.** A caller that needs a Real-Time activation in turns (or vice versa) asks Combat for turn duration and does the math itself; Abilities does not own turn-to-minute conversion.

---

## Resolve a Catalog Ability's target

**The literal `"self"` returns `'self'` regardless of rank.**

**An integer string returns the integer.** `target: "1"` returns 1.

**A formula evaluates against `rank` and the Effect Hash.**
- `target: "1+rank"` with `rank = 3` returns 4.
- `target: "1+rank/2"` with `rank = 4` returns 3 (integer division per the Formula's evaluation rules).

**A formula evaluating to zero is allowed but means the Ability has no valid targets.** The caller decides whether to surface this as a UI error.

---

## Get an Ability's Trigger

**A Catalog Ability with no `trigger` field returns null.**

**A Catalog Ability with a `trigger` field returns it verbatim.** Given a Talent `Sneak Attack` with:
```
trigger:
  on: attack_check
  condition: target_flatfooted
  effect:
    kind: bonus_dice
    dice: "1 + (level - 1) / 2"
```
`GET_TRIGGER("Sneak Attack")` returns that dict verbatim. The Abilities module does not evaluate the `condition` or apply the `effect`.

**A Stateful or Always-On Modifier Ability never has a Trigger.** `GET_TRIGGER` returns null for any name not in `spells.yaml` or `talents.yaml`.

**Unknown Trigger Events are a validation error at load time.** Only values in the configured `Trigger Events` list are accepted in `trigger.on`.

---

## Get an Ability's Modifiers

**A Catalog Ability with no `modifiers:` field returns an empty list.**

**An Always-On Modifier Ability returns its `modifiers:` list verbatim.** Given an entry `fast_movement` in `modifier_abilities.yaml` with:
```
modifiers:
  - target: speed
    type: racial
    add: 10
```
`GET_ABILITY_MODIFIERS("fast_movement")` returns `[{target: speed, type: racial, add: 10}]`. Formula `add` values are returned as strings; evaluation against the Creature's level is the Modifiers / Creatures path.

**A Catalog Ability may also carry `modifiers:`.** A Talent that combines an active component with a passive bonus carries both on the same entry; `GET_ABILITY_MODIFIERS` returns the list, and the Catalog lookup returns the rest.

**Looking up a name that exists in no catalog returns an empty list.** This is distinct from null — `GET_ABILITY_MODIFIERS` always returns a list.

---

## Classify an Effect string

**The literal `"none"` or `"0"` classifies as `none`.**

**A non-damage string classifies as a named effect.** `"frightened"` → `{ kind: 'effect', name: 'frightened' }`. The Abilities module does not check that `frightened` exists in any catalog — that's Conditions' job at apply time.

**A damage expression without explicit Severity uses the Ability's Damage Type.** A Spell with `damage_type: fire` and an Effect `"4*rank damage"` classifies as a Damage Object with `damage_type: 'fire'`, `severity: null`, `formula: "4*rank"`. The consumer looks up `fire`'s default Severity from the damage_types catalog.

**A damage expression with explicit Severity records it verbatim.** `"3*rank major damage"` classifies as a Damage Object with `severity: 'major'`, `formula: "3*rank"`. The explicit Severity wins over any `damage_type` default.

**Physical damage carries Threshold via the Ability, not the Effect string.** A Spell with `damage_type: physical` and `threshold: 4` has its Threshold available on the Ability; the Damage Object still has `severity: null` for non-explicit forms — physical Severity is decided at damage-application time by Combat (Runtime Bucketing).

**A damage Effect with neither explicit Severity nor an Ability `damage_type` is a validation error at load time.**

**A `threshold` field on an Ability whose `damage_type` is not `physical` is a validation error.**

---

## Evaluate a deferred Damage Object

Given a Damage Object from a Spell `Scorching Ray` with:
- `formula = "4*rank + 2*success + 3*critical"`
- `damage_type = 'fire'`, `severity = null`
- `context = { rank: 3, tier: 2 }`

**Apply caller-supplied save outcome.** With `success = 1`, `critical = 0`, the evaluated damage is `4*3 + 2*1 + 3*0 = 14`.

**Negative results clamp to 0.** If a defender's `success` is large enough to drive the formula negative, the returned damage is 0, not negative.

**`attribute` is available inside damage expressions.** A Spell with `effects: ["attribute/2 + 2 damage"]` and caller `attribute = 8` evaluates to `8/2 + 2 = 6`.

**Damage-only variables in non-damage Formulas surface as evaluation errors.** Putting `success` into an Effect Hash Formula or a Range Formula produces an unresolved-name error when that formula is evaluated.

---

## Resolve the Channel Block

**The Channel Block has its own Effect Hash, namespaced separately.** Given a Spell with top-level `effect_hash: { damage: "3*rank" }` and `channel.effect_hash: { bleed: "2*rank" }`:
- The top-level damage Formula evaluates with `{ rank, tier, damage }` in scope.
- The channel block's Formulas evaluate with `{ rank, tier, bleed }` — `damage` is **not** in scope inside the block, and `bleed` is **not** in scope at the top level.

**Channel `attack_roll` and `save` are independent of the top-level.** A Spell with top-level `attack_roll: false` may still have `channel.attack_roll: true` (the channel action requires its own attack roll).

**Variant Overrides can replace or remove the entire Channel Block.** A variant override of `channel: null` removes the block from that Variant.

**`{name}` and `{aspect}` substitution applies inside the Channel Block's `description`.** Same substitution rules as the top-level description.

---

## Universal forms and skills appending

**Spells receive Universal Spell Casting Skills.** With `Universal Spell Casting Skills: [evocation]`, looking up a Spell with `skills: [arcana]` returns `skills: [arcana, evocation]`.

**Talents do not.** A Talent with `skills: [arcana]` returns `skills: [arcana]` unchanged.

**Item-Only Spells do not receive Universal Item Forms.** A Spell with `item_only: true` and `items: [potion]` returns `items: [potion]` unchanged; the universal `scroll` and `wand` are not appended.

**Listing a universal skill or form explicitly in data is a validation error at load time.**

---

## Conditional saves

**Saves with `condition` are returned verbatim.** A Spell with two Save Specs, the second carrying `condition: on_fumble`, returns both Specs unchanged. The Abilities module does not check the prior save's outcome.

**`fumble` Outcome Key is optional.** A Save Spec defining only `fail` and `success` is valid; when the defender's Roll fumbles, the consumer falls back to the `fail` effect.

**Every Save Spec must define `fail`.** Omitting `fail` is a validation error at load time.

---

## Filter Catalog Abilities by Type and School

**Filtering by `type: spell` returns only Spells.** Talents are excluded.

**Filtering by `school: resonance` returns only Spells whose `school` field matches.** Talents (which have no `school`) are excluded from any school filter.

**Filters compose.** `type: spell, school: resonance` returns Spells in the resonance school.

**Filtering operates on un-resolved Ability data.** The Variant Axis is not iterated — a multi-Variant Spell appears in the result list once, not once per Variant.

---

## Stateful Ability lookup

**A Stateful Ability returns name and description only.** `GET_STATEFUL("ki_pool")` returns `{ name: "ki_pool", description: "A pool of ki points usable for various monk abilities. ..." }`. No schema fields are exposed; behavior lives in Conditions.

**Looking up a name that isn't in `stateful_abilities.yaml` returns null.**

---

## Always-On Modifier Ability lookup

**Returns name, description, and modifiers.** `GET_MODIFIER_ABILITY("fast_movement")` returns the full entry from `modifier_abilities.yaml`.

**Entries with no `modifiers:` field (modifiers-pending) return an empty `modifiers` list.** The description is still available; consumers that need the numeric data wait for the Modifiers domain to specify the shape.
