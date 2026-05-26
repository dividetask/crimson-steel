# Check Resolution Builder Stub

A DM-driven setup wizard that gathers everything Check Resolution needs to compose a Check, then embeds the Check Resolution Stub (`check_resolution_stub.md`) below itself with the resulting Rolls. Owned by Check Resolution; the Builder knows nothing about Conditions, Combat, or any other domain — it just produces Rolls.

See `ui_conventions.md` for shared rules.

## Parameters

Every list parameter is a set of DM-pickable options. A parameter that is null or empty causes its panel to be omitted entirely.

| Parameter | Shape | Purpose |
|---|---|---|
| `target_options` | array of `{creature_ref, name}` or null | Target picker. |
| `action_options` | array of `{name, min_dice, max_dice, speed?, damage?}` or null | The acting Creature's action. `min_dice == max_dice` locks the dice spend (used for save-style actions); otherwise the panel shows dice-count buttons bounded by `actor_pool` and `max_dice`. |
| `actor_pool` | integer | Caps the dice the actor can spend on a non-locked Action. |
| `defense_options` | array of `{name, min_dice, max_dice, speed?}` or null | The defending Creature's reaction. |
| `defender_pool` | integer | Caps the defender's dice spend. |
| `supporting_actions` | array of `{creature_ref, action_name, min_dice, max_dice, pool}` | Reactions on the actor's side (allies). |
| `opposing_actions` | array of `{creature_ref, action_name, min_dice, max_dice, pool}` | Reactions on the defender's side. |
| `reroll_sources` | array of `{creature_ref, creature_name, source_name, direction, pool}` or null | One column in the Rerolls / Nudges panel per entry. Buttons render `+1..+pool` or `-1..-pool` per `direction`. |
| `mass_reroll_sources` | array of `{creature_ref, creature_name, source_name, direction}` or null | One column per entry. Single `+*` / `-*` button (no magnitude). |
| `nudge_sources` | array of `{creature_ref, creature_name, source_name, direction, pool}` or null | One column per entry. Buttons render `+1..+pool` or `-1..-pool`. |
| `rolls` | array of `{creature_name, roll_name, dice_count, tn, die_size, starting_value, side}` | The Rolls that will be composed into the embedded Check. `side` is `:supporting` or `:opposing`. The Builder seeds the Check Resolution Stub with these. |
| `stub_id` | string | Unique identifier for this Builder instance on the page. |

## Layout

A vertical stack of panels in this order, each rendered only when its corresponding parameter is populated:

1. **Select Target**
2. **Action** — for each action option, a row with name + speed + dice picker. Locked actions show `dice N (locked)` instead of buttons.
3. **Defense**
4. **Supporting Actions**
5. **Opposing Actions**
6. **Rerolls / Nudges** — a single table. The header row has one column per source; each row is one Roll. Cells contain magnitude buttons. The DM picks at most one button per cell (per source per Roll); the active button is highlighted in the source's color (positive = green, negative = red, nudge = blue). Pressing an active button toggles it off.

Below the panels the Builder embeds the Check Resolution Stub seeded with `rolls`. Reroll / Mass Reroll / Nudge selections mutate the embedded Rolls' configs so the next Roll All applies them.

## Single-option auto-select

- **Reroll Source, Mass Reroll Source, Nudge Source** — when a category has exactly one source the source column is rendered but the DM still picks magnitude. (No actor pick step is needed when the actor is implied.)
- **All other parameters** — single-option entries still render their panel for confirmation. The DM may keep the default selection (Target / Defense / Action) without clicking.

## Composition

The Builder composes upward: a parent stub (e.g. `conditions_save_resolution_stub.md`) embeds the Builder and listens for changes to the embedded Check Resolution Stub's result inputs. The Builder itself does not emit Continue / Confirm events — it just maintains the constructed Rolls; the parent decides what to do with the rolled result.

## What this stub does not do

- It does not apply any effect. Dice rolled here do not change any creature's state.
- It does not validate that selections are legal (e.g. that the actor has the dice in their pool). Validation is the caller's responsibility before the parameters reach the Builder.
- It does not understand saves, attacks, or any domain-specific concept. The same Builder serves Affliction saves, Combat attacks, and any other Check the project introduces.
