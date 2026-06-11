# Action Builder Stub

A reusable, **domain-agnostic** wizard for composing an action — an Attack, a Cast, a Special — from DM-driven choices, then (and only then) rolling it. It is a **shared/common UI stub**, not owned by Check Resolution: it owns the *step flow* and **composes in the Check Resolution roll table** (the shared roll stub) as its terminal step, showing the *Roll All* affordance **only when a step actually rolls dice**. A no-roll action (a buff Cast, a reservoir pour) never mounts that affordance — the DM just confirms. The Builder knows nothing about Conditions, Combat, or any other domain; the host precomputes the blob and acts on the confirmed result.

See `ui_conventions.md` for shared rules, `check_resolution_stub.md` for the roll table it composes, and `dice_resolution_roll_stub.md` for the underlying Roll.

## Parameters

Every list parameter is a set of DM-pickable options. A parameter that is null or empty causes its step to be omitted.

| Parameter | Shape | Purpose |
|---|---|---|
| `target_options` | array of `{creature_ref, name}` or null | Target picker. |
| `action_options` | array of `{name, min_dice, max_dice, speed?, damage?}` or null | The acting Creature's action. `min_dice == max_dice` locks the dice spend (used for save-style actions); otherwise the panel shows dice-count buttons bounded by `actor_pool` and `max_dice`. |
| `actor_pool` | integer | Caps the dice the actor can spend on a non-locked Action. |
| `defense_options` | array of `{name, min_dice, max_dice, speed?}` or null | The defending Creature's reaction. |
| `defender_pool` | integer | Caps the defender's dice spend. |
| `supporting_actions` | array of `{creature_ref, action_name, min_dice, max_dice, pool}` | Reactions on the actor's side (allies). |
| `opposing_actions` | array of `{creature_ref, action_name, min_dice, max_dice, pool}` | Reactions on the defender's side. |
| `reroll_sources` | array of `{creature_ref, creature_name, source_name, direction, pool}` or null | Each source becomes a labelled group of magnitude buttons in the Rerolls step. |
| `mass_reroll_sources` | array of `{creature_ref, creature_name, source_name, direction}` or null | Each source becomes a single ± button in the Mass Rerolls step. |
| `nudge_sources` | array of `{creature_ref, creature_name, source_name, direction, pool}` or null | Each source becomes a labelled group of magnitude buttons in the Nudges step. |
| `rolls` | array of `{creature_name, roll_name, dice_count, tn, die_size, starting_value, side}` | The Rolls that will appear in the embedded dice table. `side` is `:supporting` or `:opposing`. |

## Shell

The Builder shares one Rolls wrapper with whatever stub embeds it. The wrapper's `.rolls-header` carries the title (left) and a single `.rolls-actions` slot (right). Only the currently active step's controls live in the slot at any given moment — they sit where Roll All / Confirm sit on the embedded Check Resolution roll table. None and Change buttons match Roll All in size so the header never resizes when a step changes.

Once every interactive step is resolved, the slot swaps to the embedded Check Resolution roll table's Roll All + Confirm buttons and the dice table (until then hidden) appears — **but the Roll All affordance is mounted only when the flow rolls dice**. A no-roll action (a buff Cast, a reservoir pour) suppresses Roll All and the Luck steps, leaving just Confirm; its dice are charged/banked, not rolled.

## Step model

Steps are walked in this order; each step whose parameter list is null/empty is skipped silently.

- **Target**
- **Action** — an Action step with a single locked entry (`min_dice == max_dice`) is *omitted* entirely because there is nothing for the DM to choose; the caller treats the action as decided.
- **Defense**
- **Supporting Actions**
- **Opposing Actions**
- **Rerolls** — one labelled magnitude-button group per source (positive sources show `+1..+pool`, negative sources show `-1..-pool`). A single `None` button covers the whole step.
- **Mass Rerolls** — single `+*` or `-*` button per source; `None` covers the step.
- **Nudges** — same shape as Rerolls.

Each pick mutates the dice table's roll-group config so the next Roll All applies it. `None` clears any pick on that step before completing it.

## Step lifecycle

Each step is in one of three states:

- **pending** — hidden. The Roll All / Confirm All buttons are themselves a pending "check" step until every interactive step ahead of them resolves.
- **active** — the step's controls (None + the per-source buttons) occupy `.rolls-actions`.
- **complete** — the controls vanish from the header; a single-line summary row (`<Step Label>: <choice> [Change]`) appears in the step-summary stack between the header and the dice table.

Pressing Change on a completed step's summary re-opens that step, clears its modifier on every Roll, and rewinds every later step (and the dice table) back to pending. The host stub is responsible for re-hiding any post-roll surfaces it owns (e.g., the effect preview in `conditions_save_resolution_stub.md`).

## Reroll palette

Magnitude buttons use the Roll Resolution stub's modifier palette: warm amber for Reroll + Mass Reroll, green for Nudge. Direction (`+` / `−`) is carried on the button label's sign only.

## Out of scope

- This pattern does not pick *which* Roll is being composed; the host stub provides the seed Rolls.
- It does not validate that selections are legal (e.g. that the actor has the dice in their pool). Validation is the caller's responsibility before the parameters reach the Builder.
- It does not understand saves, attacks, or any domain-specific concept. The same pattern serves Affliction saves, Combat attacks, and any other Check the project introduces.

## Implementation

The reusable, domain-agnostic implementation is `views/_action_builder.erb` + `public/js/ui/actionBuilder.js`. The host precomputes the full blob (`rolls` + ordered `steps`, each option carrying a `patch` that mutates the seed Rolls — `set_dice` / `set_tn` / `set_name` / `set_excluded` / `set_reroll` / `set_nudge` — and steps may be choice-dependent via `options_by` + `options_map`). A step may also carry header quick-pick buttons (rendered top-right): a fixed `header_options` list, or — when the quick-picks depend on earlier choices — a choice-dependent `header_options_by` + `header_options_map` (same keying as `options_map`), which the builder renders into the step's header as it activates. A step may instead be `dynamic` — its body is generated client-side from the live Rolls when it activates. The Luck step is `dynamic: 'luck'`: one such step per source (`luck.source` = a Bard's Reservoir or the DM, `luck.targets` = the candidate Rolls), rendered as a table (rows = in-play Rolls, columns = a Bardic Inspiration bonus and an optional Unsettling Words penalty) whose amounts are bounded by `min(source Luck, that Roll's dice)`. Picks across all Luck steps are composed onto each Roll's standard reroll modifiers — `positive_reroll` / `negative_reroll` (the max of each sign, no stacking) — which **Roll Resolution** (not the builder) applies in a single pass; the builder only sets the data. `ActionBuilder.luckSpends(choices)` yields the per-source debits for the host's resolve payload. The builder runs entirely client-side and emits a single `action:confirmed` `CustomEvent` (`{ choices, rolls: [{ id, side, successes, crits, dice_count }] }`); the host acts on it. The three Combat consumers each precompute the blob and mount the builder: Attack (`GET /encounter/attack_builder`, `public/js/ui/turnAttack.js`), Cast (`GET /encounter/cast_builder`, `public/js/ui/turnCast.js`), and Special (`GET /encounter/special_builder`, `public/js/ui/turnSpecial.js`).

A Cast's **Dice** step shows how the Builder mounts Check Resolution only when needed: a *variable* count (a rolled cast, or a reservoir pour) lists buttons from the spell's **Action Minimum** (Main 4 / Bonus 2) up to the casting-skill Dice Cap; a *known* count (a no-roll buff costs exactly its Action Minimum) is auto-applied with **no button** — its option carries `auto: true`, so the step is skipped. For any no-roll Cast, the Luck steps are skipped and Roll All is not mounted (`cast: { roll: false }` on the spell option). The Save Resolution stub still uses its own `StepMachine` pending convergence onto this component.
