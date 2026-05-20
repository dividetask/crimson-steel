# Scenario Tests — YAML Format

A scenario test is a single self-contained YAML file: config overrides, fixtures, one action under test, and expected outputs. The runner builds the requested in-memory objects, **fills every unspecified field with a module default**, executes the action, and asserts only the fields listed in `expect:`. Anything else the action returns is ignored.

The format is deliberately terse — a test should pin down only what it's exercising. A skill-check test should not have to spell out a defender's gear; an attack test should not have to spell out the attacker's race.

## File shape

```yaml
test:       <human-readable name>          # required
config:     <flat key/value overrides>     # optional
fixtures:   <characters, weapons, …>       # optional
action:     <one operation under test>     # required
expect:     <expected outputs>             # required
```

One file = one test. A directory of files = a suite.

## `config:` — inline config overrides

Any key from any `data/*.yaml` is overridable. Keys are the same human-readable strings used in those files.

```yaml
config:
  Minimum Dice Count:  6
  Dice Count Range:    5
  Base Target Number:  6
  Combat Pool Step:    4
  Turns Per Round:     [1, 1, 1, 2, 4, 8]
```

Unspecified keys keep their `data/<file>.yaml` values. The runner does not validate that a key is "real" — it just merges the override in. A typo manifests as a no-op.

## `fixtures:` — only what the test needs

Anything not specified is generated. Defaults below.

```yaml
fixtures:
  characters:
    - name: Ash
      attributes: { str: 14 }
      skill_ranks: { athletics: 3 }
  weapons:
    longsword_plus_1:
      base: longsword
      enhancement: 1
```

### Character defaults

| Field | Default |
|---|---|
| `race` | `Human` |
| `tier` | `0` |
| `attributes` | every key (`str`, `dex`, `con`, `int`, `wis`, `cha`) = `10` unless overridden |
| `skill_ranks` | `{}` |
| `class_levels` | `{}` |
| `equipped` | `[]` |
| `conditions` | clean (no HP damage, no afflictions, full mana) |
| `prowess` | optional `{ <skill>: N }` pin — short-circuits the Ranks + Attribute calculation for that Skill so tests can lock the Prowess directly. |

### Weapon / item defaults

Pulled from the weapon catalog by `base:` if given; otherwise an unarmed strike. `enhancement: N` adds N to attack and damage. Anything else can be overridden per-key.

## `action:` — the operation under test

Exactly one. The runner dispatches on `action.kind`:

| `kind` | Owning module | What it exercises |
|---|---|---|
| `inspect_character`  | Character + Race + Advancement | Read a Character's effective derived values: `attributes`, `tier`, `skill_ranks`, `hp_max`, etc. No mutation. |
| `skill_check`        | DiceSystem + Proficiency | Skill Prowess → `{dice_count, competency_bonus, …}` partition. |
| `compute_check_details` | DiceSystem | Same partition, called directly without a Character. |
| `roll`               | DiceSystem | Single Roll: dice + TN + modifiers → DoIS, criticals. |
| `multi_roll`         | DiceSystem | Multi-Roll Check composition: DoS, success, fumble. |
| `apply_nudge`        | DiceSystem | Value Adjustment targeting. |
| `reroll_some_dice`   | DiceSystem | Reroll Operation. |
| `sweep_reroll`       | DiceSystem | Sweep Reroll. |
| `roll_initiative`    | DiceSystem | Initiative String for one or many Combatants. |
| `attack`             | Combat + DiceSystem | Full attack pipeline: per-side TN, attack roll, defense roll, severity calculation, post-damage side-effects, afflictions. |
| `apply_attack_damage`| Combat | Damage-routing half only (skip the to-hit roll). |
| `apply_affliction`   | Conditions | One Affliction tick. |
| `cast_spell`         | Casting | One Workflow D cast. |
| `consume_item`       | ItemUse | One Workflow B item use. |

New `kind`s get added as test coverage grows. Each `kind` has its own required-field list documented in the section below.

### Pinned dice

Any dice the action would otherwise roll can be pinned, removing randomness from the test:

```yaml
action:
  kind: attack
  dice:
    attack:  [5, 7, 7, 3]
    defense: [1, 2, 1]
    initiative: [10, 9, 7]   # if the action would have rolled initiative
```

Unpinned rolls go through the configured random source. If the test cares about an outcome that depends on a roll it didn't pin, it's underspecified — the runner reports that rather than silently passing.

### `attack` action fields

| Field | Required | Notes |
|---|---|---|
| `attacker` | yes | Character name from the fixtures. |
| `target`   | yes | Character name. |
| `weapon`   | yes | Weapon key from the fixtures' `weapons:` block (or a catalog entry). |
| `defense`  | yes | One of `none` (flatfoot), `parry`, `block`, `dodge`. |
| `opposed_supporters` | optional | List of `{ name:, defense: }` entries — extra Combatants who join on the defender's side as additional Opposed Rolls. |
| `dice`     | optional | Per-Roll dice pinning (see above), keyed `attack`, `defense`, or `ally:<name>`. |

## `expect:` — partial assertion

Only listed fields are checked. The runner extracts each path from the action's return value and compares for equality. Nested paths use plain YAML mapping; lists are compared element-wise.

```yaml
expect:
  attack_tn: 4
  defense_tn: 7
  damage:
    minor:    3
    moderate: 6
  afflictions:
    bleed:    5
```

The runner reports unexpected return values only if a key under `expect:` doesn't exist on the action's result — that's a typo. Extra keys on the result that aren't in `expect:` are fine.

## Examples

### Skill Prowess partition

A pure DiceSystem + Skills test — no combat state, no opponent.

```yaml
test: "Athletics with 14 STR and 3 ranks"
fixtures:
  characters:
    - name: Ash
      attributes:  { str: 14 }
      skill_ranks: { athletics: 3 }
action:
  kind:       skill_check
  character:  Ash
  skill:      athletics
expect:
  dice_count:       5
  competency_bonus: 3
```

The runner fills the rest of Ash (`dex`/`con`/`int`/`wis`/`cha` = 10, race Human, tier 0, no equipment, no conditions). The Skills module reads `Athletics`'s configured attribute and divisor from `data/skills.yaml`.

> Numbers above are illustrative. The real partition depends on `Minimum Dice Count`, `Dice Count Range`, and Athletics' configured attribute/divisor.

### Parried melee attack

Full attack pipeline with both sides' dice pinned.

```yaml
test: "Melee attack parried by a +1 longsword defender"
fixtures:
  weapons:
    longsword_plus_1:
      base:        longsword
      enhancement: 1
  characters:
    - name:     Attacker
      attributes: { str: 14 }
      equipped: [longsword_plus_1]
    - name:     Defender
      equipped: [longsword_plus_1]
action:
  kind:     attack
  attacker: Attacker
  target:   Defender
  defense:  parry
  weapon:   longsword_plus_1
  dice:
    attack:  [5, 7, 7, 3]
    defense: [1, 2, 1]
expect:
  attack_tn:  4
  defense_tn: 7
  damage:
    minor:    3
    moderate: 6
  afflictions:
    bleed:    5
```

Everything not pinned (Attacker's other attributes, Defender's stats, Tier, race, etc.) is filled in by the defaults. The runner walks the same attack pipeline the live code would (TN math → Roll resolution → Severity Calculation → side-effect routing) — it doesn't approximate any step.

### Pre-resolved damage routing

Skip the to-hit half. Useful for testing Severity Calculation in isolation.

```yaml
test: "12 physical damage with Threshold 3 and Damage Resilience 2"
fixtures:
  characters:
    - name: Defender
      damage_resilience: 2
action:
  kind:        apply_attack_damage
  target:      Defender
  amount:      12
  damage_type: physical
  threshold:   3
expect:
  severity_split:
    minor:    5
    moderate: 5
    major:    2
```

### Initiative ordering

```yaml
test: "Initiative String tie-break: 10/8 beats 10/7"
config:
  Initiative String Encoding: "X"
action:
  kind: roll_initiative
  combatants:
    - { name: A, dice: [10, 7] }
    - { name: B, dice: [10, 8] }
    - { name: C, dice: [10, 7] }
expect:
  turn_order: [B, A, C]
```

`dice:` per combatant pins the rolled values, so this test exercises only the encoding + ordering layer.

## What "the test should generate information not provided" means

Three layers of fill-in, applied in order:

1. **Config defaults** — anything missing from `config:` falls back to `data/<file>.yaml`.
2. **Fixture defaults** — Character, weapon, condition, equipment fields default per the tables above.
3. **Action defaults** — per-`kind` defaults documented alongside that `kind` (e.g. `attack` defaults to a melee attack with the attacker's first equipped weapon if `weapon:` is omitted).

A test author should never have to spell out a value the runner can compute.

## Authoring rules

- **One action per file.** Sequencing requires multiple files (or a future `actions:` list — not yet specified).
- **`expect:` is partial.** List only what the test cares about. Bloating it with every field couples tests to unrelated changes.
- **Pin dice when outcomes depend on them.** Otherwise the test is randomized and brittle.
- **Use `config:` sparingly.** Most tests should run against the canonical `data/*.yaml`; override only when exercising a config-driven behavior.

## Open questions

- **Location.** `spec/scenarios/*.yaml`? `tests/*.yaml`? Co-located under each module?
- **Runner.** RSpec example generator (`scenarios_spec.rb` walks the directory)? Standalone CLI?
- **Float comparison.** Some pipeline outputs (multipliers) are floats; equality with a tolerance, or always-snap-to-rational?
- **Sequencing.** A future `actions:` list for multi-step scenarios (cast spell → tick affliction → check HP). Out of scope for v1.
- **Negative assertions.** Today `expect:` only checks values. A future `expect_error:` for "this should raise"?
- **Catalog references.** Should `weapons:` only be defined inline, or should fixtures be able to reference `data/equipment.yaml` entries by name?
