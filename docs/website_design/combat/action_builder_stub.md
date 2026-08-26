# Action Builder

A **domain-agnostic, parameter-driven** wizard for composing one action — an
Attack, a Cast, an Item, a Special, or a bare roll. It owns the **step flow**
only, embeds the **Check Resolution roll table** as its terminal step, and emits
a single `action:confirmed` event when the DM commits. It never calls back into
its host and computes no rules of its own.

Implementation:

- **`public/js/ui/actionBuilder.js`** — the `ActionBuilder` class that drives the
  steps client-side.
- **`views/_action_builder.erb`** — the markup (a "Rolls" wrapper reusing the
  Save Resolution stub's look), which serializes the blob into
  `data-builder` and server-renders the first step's option buttons.
- Hosts precompute the blob and listen for the result: `turnAttack.js`,
  `turnCast.js`, `turnItem.js`, `turnSpecial.js`, `turnRollTable.js`, each fed by
  a `*_builder_blob` helper on the `/encounter` route
  (`lib/routes/encounter.rb` + `encounter_attack_ui.rb` / `encounter_cast_ui.rb`
  / `encounter_special.rb` / `encounter_reactions.rb`).

## The blob

The wizard reads one JSON blob from the `.action-builder` element's
`data-builder`. It is fully **precomputed by the host** — the wizard renders it
verbatim.

```
{ title, stub_id,
  rolls: [ roll, … ],     // seed the embedded Check Resolution roll table
  steps: [ step, … ] }    // walked in order; the terminal __dice step is implicit
```

### `rolls`

Each seeds one roll-group in the terminal table and is the thing every `patch`
mutates by `id`:

`{ id, side, creature_name, roll_name, die_size, base_tn, dice_count,
   starting_value, bonus_penalty_list?, no_propagate?, speed?, excluded? }`

`side` is `supporting` / `opposing` (Check Resolution nets them). A roll flagged
`excluded` starts hidden and is re-shown by a `patch`.

### `steps`

A step is one choice in the flow. Three shapes:

- **Static** — `{ key, label, options: [opt], header_options?: [opt],
  no_summary?, heading? }`. Its option buttons are server-rendered by the ERB.
- **Choice-dependent** — `{ key, label, options_by: [stepKey…],
  options_map: { "k1|k2": [opt] }, header_options_by?, header_options_map? }`.
  The wizard picks the option list at activation by joining the prior steps'
  chosen `key`s with `|` and looking it up in `options_map` (rendered in JS).
- **Luck** — `{ key: "luck:<sid>", label, dynamic: "luck", heading,
  header_options: [{ value: "<sid>|none", label: "No luck" }],
  luck: { source: { sid, label, amount, penalty }, targets: [{ roll_id, label }] } }`.
  Renders a per-source table instead of buttons (see *Luck*).

A **Target** step may also carry `multi_by` / `multi_map` (a target **count**
keyed by the chosen Spell) to switch into multi-select (see *Multi-target &
area*).

### `opt` and `patch`

Every option is a record the wizard renders and then applies:

`{ value, label, key?, group?, summary?, disabled?, auto?, kind?, cast?, spell_name?, place?, patch }`

- `key` is what `options_map` keys join on (defaults to `value`); `group` groups
  buttons on a line; `summary` is the collapsed row text; `kind: "info"` is
  non-interactive descriptive text; `auto: true` is a single forced option the
  wizard applies with no click and no summary row (e.g. a Saving Throw always at
  full Dice Cap).
- `cast: { roll }` — a Cast option declaring whether it rolls; `roll: false`
  makes the action **no-roll** (skips Luck and the roll table). `place` arms an
  area drop; `spell_name` is the resolved Spell behind the option.

The **`patch`** is the whole vocabulary the wizard understands. Each key is a
list of per-roll operations addressed by roll `id`:

| Patch key | Effect on the roll |
|---|---|
| `set_dice` `[{id,count}]` | Absolute dice count (clears any scale baseline). |
| `scale_dice` `[{id,num,den,min}]` | Scale dice relative to the chosen count (e.g. halve, floored, min). |
| `restore_dice` `[{id}]` | Undo a prior `scale_dice`. |
| `set_speed` `[{id,speed}]` | The Combat-Pool speed component. |
| `set_bpl` `[{id,bonus_penalty_list}]` | Replace the roll's **typed** bonus/penalty list. |
| `set_no_propagate` `[{id,types}]` | Bonus Types that must **not** cross to the other side. |
| `set_reroll` / `set_nudge` `[{id,sign,count,max}\|{id,clear}]` | Reroll / nudge slots. |
| `set_name` `[{id,creature_name?,roll_name?}]` | Relabel the roll-group. |
| `set_excluded` `[{id,excluded}]` | Hide / reveal a roll-group. |

## How a step works

The wizard walks `steps` in order. Picking an option:

1. **records the choice** (`{ value, label, key }`) and **applies its `patch`** —
   mutating the addressed roll-groups' `data-config` in place;
2. **re-previews every roll's TN** by asking Check Resolution
   (`CheckResolution.previewParameters`, with cross-side propagation) and updating
   the params line + TN tooltip; and
3. **collapses the step to a summary row** (label: value, with a ↶ Change) and
   **advances** to the next step with interactive options.

Pressing **Change** on a summary row re-opens that step, discards its choice and
the roll mutations it contributed, and rewinds every later step — and the roll —
back to unmade.

## What it computes — and what it doesn't

The wizard's whole job is to **mutate roll configs and read results**. It never
computes a Target Number, never stacks bonuses, never nets a Check:

- It sets each roll's `bonus_penalty_list`; **Check Resolution** does the
  per-Type stacking and cross-side propagation and hands back the TN + Starting
  Value (`previewParameters`). The builder only formats what comes back.
- On Confirm it reads each roll's Successes / Crits from the table and asks
  Check Resolution for the net Degree of Success (`degreeOfSuccess`).

This boundary is what keeps it domain-agnostic and reusable across Attacks,
Casts, Items, Specials, and Affliction saves — only the blob differs.

## Luck

A `dynamic: "luck"` step renders one table per source (a Bard's Reservoir, the
DM's pool): rows are the in-play rolls, columns are **Unsettling Words** (a
penalty — reroll high dice) and **Bardic Inspiration** (a bonus — reroll low
dice). Per roll a source may spend up to `min(its Luck, that roll's dice)`. Picks
across all Luck steps aggregate into each roll's `positive_reroll` /
`negative_reroll` slots (the max of each — they do not stack), which Dice
Resolution applies. `luckSpends(choices)` returns the confirmed spends for the
host's resolve payload.

## Multi-target & area

When the Target step's `multi_map` (keyed by the chosen Spell) is `> 1`, the step
toggles creatures (blue = selected, capped at the count) and finishes on a
**Done** control, dispatching `cast:targets-selected` — each pick becomes a
defender that rolls its own save, and the Defense step is skipped. An area Spell
option carrying `place` dispatches `cast:arm-area`; the footprint (and the
creatures it catches) return via `cast:area-placed`.

## No-roll actions & the terminal roll

When every step is resolved the wizard reveals the terminal `__dice` step — the
embedded **Check Resolution roll table** — but shows **Roll All** only when some
step actually contributed dice. A **no-roll** action (a buff Cast, a
reservoir-channel) hides the table and auto-surfaces its result; the blue title
**Confirm** stays as the only button.

## Output

On Commit the wizard emits exactly one event and does nothing else — no state
mutation, no POST, no domain call:

```
action:confirmed  (CustomEvent, bubbles)
  detail: { choices,                       // { stepKey: chosen value }
            rolls: [{ id, side, successes, crits, dice_count, speed }],
            noRoll, auto }
```

`auto` distinguishes the builder surfacing a no-roll result itself from the DM
clicking Confirm; the host (e.g. `turnAttack.js`) uses it to tell a preview apart
from the real commit, and applies the outcome in its own multi-stage flow.

## Required interfaces

The roll surface the wizard embeds is Check Resolution's; that contract and every
other cross-domain call the combat feature makes are enumerated in
[Combat — Interfaces](/compendium?view=combat_interfaces). A worked example of an
actual blob is in [Combat — Test Data](/compendium?view=combat_test_data).
