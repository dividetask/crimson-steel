# Combat — Test Data

A worked example of the actual [Action Builder](/compendium?view=action_builder)
blob, to read alongside the contract. **The blob is not a standalone dummy
file** — the `/encounter` route builds it live from combat state through the
`*_builder_blob` helpers (`attack_builder_blob`, `cast_builder_blob`, …). This
page shows the *shape* one of those helpers emits, so the fields in the contract
have something concrete to point at.

The wizard reads the blob from the `.action-builder` element's `data-builder`
(serialized by `views/_action_builder.erb`). It always has two parts: the seed
`rolls` and the ordered `steps`.

## `rolls`

The seed roll-groups the terminal Check Resolution table renders and every
`patch` mutates by `id`. An attack seeds the attacker (supporting) and the target
(opposing):

| Field | Meaning |
|---|---|
| `id` | Address a `patch` targets (`attacker`, `target`, `shield`, …). |
| `side` | `supporting` / `opposing` — Check Resolution nets them. |
| `creature_name` / `roll_name` | Row labels (a `set_name` patch may relabel them). |
| `die_size`, `base_tn`, `dice_count`, `starting_value` | Seed roll params. |
| `bonus_penalty_list` | Typed bonuses/penalties; a `set_bpl` patch replaces it. |
| `speed`, `excluded` | Pool-speed component; whether the group starts hidden. |

## `steps`

Walked in order. A **static** step server-renders its `options`; a
**choice-dependent** step (`options_by` + `options_map`) is rendered in JS, its
option list keyed by the joined `key`s of the steps it depends on; a **luck**
step (`dynamic: "luck"`) renders a per-source reroll table. Each option carries
the `patch` it applies to the seed rolls — that is the entire mechanism.

## What the example exercises

- A **static** Target step (`header_options` quick-picks per creature).
- A **`set_dice`** patch on the Weapon & dice step (the pool cost is `speed + n`;
  unaffordable counts are `disabled`).
- A **choice-dependent** Defense step (`options_by: [target, action]`), whose
  options — Dodge / Block / Parry — carry `set_bpl` (typed modifiers Check
  Resolution stacks) and `set_speed` patches.
- An **`auto`** Saving-Throw option (applied with no click, no summary row).
- A **luck** step aggregating into `positive_reroll` / `negative_reroll`.

```test
# Illustrative blob (stripped from the rendered page, kept in source) — the
# shape attack_builder_blob emits. Real values come from live combat state.
title: "Seraphina attacks Olga"
stub_id: "attack-7"
rolls:
  - { id: attacker, side: supporting, creature_name: "Seraphina", roll_name: "attack",
      die_size: 10, base_tn: 6, dice_count: 4, starting_value: 0,
      bonus_penalty_list: [{ type: inherent, value: 3 }], speed: 2 }
  - { id: target, side: opposing, creature_name: "Olga", roll_name: "defense",
      die_size: 10, base_tn: 6, dice_count: 0, starting_value: 0, bonus_penalty_list: [] }
steps:
  - key: target
    label: "Target"
    header_options: [{ value: 2, label: "Olga" }]
    options:
      - { value: 2, label: "Olga", key: "olga",
          patch: { set_name: [{ id: target, creature_name: "Olga" }] } }
  - key: action
    label: "Weapon & dice"
    options:
      - { value: "longsword|4", key: "longsword", group: "Longsword", label: "4 dice",
          summary: "Longsword — 4 dice", patch: { set_dice: [{ id: attacker, count: 4 }], set_speed: [{ id: attacker, speed: 2 }] } }
      - { value: "longsword|6", key: "longsword", group: "Longsword", label: "6 dice", disabled: true }   # pool can't afford speed+6
  - key: defense
    label: "Target's defense"
    options_by: [target, action]
    options_map:
      "olga|longsword":
        - { value: "none", label: "No defense", key: "none", auto: false,
            patch: { set_dice: [{ id: target, count: 0 }] } }
        - { value: "dodge", label: "Dodge", key: "dodge",
            patch: { set_dice: [{ id: target, count: 5 }], set_speed: [{ id: target, speed: 2 }],
                     set_bpl: [{ id: target, bonus_penalty_list: [{ type: circumstance, value: 1 }] }],
                     set_no_propagate: [{ id: target, types: [circumstance] }] } }
        - { value: "parry", label: "Parry (Gary)", key: "parry",
            patch: { set_dice: [{ id: target, count: 5 }], set_speed: [{ id: target, speed: 3 }],
                     set_bpl: [{ id: target, bonus_penalty_list: [{ type: guidance, value: 2 }] }] } }
  - key: "luck:bryn"
    label: "Luck"
    dynamic: luck
    heading: "Bryn (Bardic Inspiration)"
    header_options: [{ value: "bryn|none", label: "No luck" }]
    luck: { source: { sid: bryn, label: "Bryn", amount: 3, penalty: false },
            targets: [{ roll_id: attacker, label: "Seraphina" }] }
```
