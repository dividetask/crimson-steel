# Roll Resolution Stub

A reusable UI component for displaying a single Roll, rolling its dice, and applying its modifiers interactively. Backed by the public entry points of the dice resolution domain.

See `ui_conventions.md` for shared rules (dice highlighting, modifier presentation, composition).

## Layout

The stub renders one to four table rows for a single Roll, with seven columns:

| Column | Content |
|---|---|
| Character | Three lines: Creature Name, parameters line, Roll Name. Spans every row of the Roll. |
| Reroll | The Reroll or Mass Reroll modifier value as a small badge (see **Modifier columns**). Empty on the initial-dice row and the nudge row. A Roll that carries both a Reroll and a Mass Reroll renders one row per modifier; the badge sits in this column on each. |
| Nudge | The Nudge modifier value as a small badge. Empty on the other modifier rows. |
| Dice | The dice for this step (initial, post-reroll, post-mass-reroll, or post-nudge). One step per row. |
| Result | A manual-override DoIS input. Spans every row of the Roll. |
| Crits | A manual-override Critical Count input. Spans every row of the Roll. |
| Lock | A lock toggle (closed/open padlock icon) that freezes the Roll's result from further changes. Spans every row of the Roll. |

There is **no** per-Roll action button column. The header action buttons (Roll / Roll All / Confirm) live on the Rolls wrapper itself and apply to every Roll inside — never duplicated per Roll.

When `wrapper: true` the stub renders the Rolls wrapper and its two header buttons:

- First button: `Roll` when the stub was given a single Roll, `Roll All` when given more than one. CSS class stays `.btn-roll-all`. Clicking re-rolls every unlocked Roll's dice.
- Second button: `Confirm`. Clicking it captures each Roll's Result + Crits, hides the table and the header buttons, and reveals a `.rolls-results` block with one row per Roll (`<Roll Name>: Successes <n>, Crits <n>`) plus a single **Change** button at the right edge. Change un-collapses the wrapper; it does not reset anything — the dice and input values stay as the DM left them.

When `wrapper: false` the stub renders only the per-Roll `<tbody>` blocks. The parent supplies the wrapper, the buttons, and any collapse UI.

A modifier row is omitted when the Roll has no modifier of that kind. A Roll with no Reroll, no Mass Reroll, and no Nudge has only the initial-dice row. Each die can be rerolled at most once across the Reroll + Mass Reroll combination — the Mass Reroll skips any die already touched by the Reroll.

The stub must fit within its container; the parent wrapper sets the available width and the stub does not overflow it. Long dice rows wrap inside the Dice cell.

## Parameters

The stub accepts an array of Rolls — single-Roll callers pass a one-element array. Each Roll carries:

- Creature Name — string.
- Roll Name — string.
- Dice Count — integer.
- TN — integer.
- Starting Value — signed integer.
- Reroll — optional `(sign, count)`. `sign` is `+` (reroll non-Successes) or `-` (reroll Successes). `count` is the magnitude (positive integer). Omitting the Reroll suppresses the row.
- Mass Reroll — optional `(sign)`. `sign` is `+` (rerolls every non-Success that the Reroll did not already touch) or `-` (every Success). No magnitude; the badge always reads `+*` or `-*`. Omitting the Mass Reroll suppresses the row.
- Nudge — optional `(sign, count)`. `sign` is `+` or `-`. Omitting the Nudge suppresses the row.

Stub-level options:

- `wrapper` — boolean, default true. When true the stub emits a full standalone shell (`.rolls-wrapper` + header + `<table>` with `<colgroup>` + `<thead>` + per-Roll `<tbody>` blocks + a hidden `.rolls-results` collapsed-state section). When false the stub emits only the per-Roll `<tbody>` blocks; the parent supplies the wrapper, the table, and any collapse UI it wants.
- Stub identifier — optional string supplied by the parent so per-Roll events can be addressed.

## Identity (Character) column lines

1. **Creature Name** — verbatim, bold.
2. **Parameters line** — `<Dice Count> dice @ TN <TN>` followed by Starting Value when nonzero. Positive Starting Value renders as `, R+<n>`; negative renders as `, R-<n>`. Die Size is a project-wide constant from `dice_resolution_config.yaml` (`Die Size: 10` for Crimson Steel) and is not repeated on every line.
3. **Roll Name** — italic, parenthesized.

## Modifier columns (Reroll, Nudge)

Each modifier column displays a small pill-shaped badge containing one of exactly four values:

- `+x` — positive modifier of magnitude `x` (a non-negative integer).
- `-x` — negative modifier of magnitude `x`.
- `+*` — positive modifier covering the Maximum Dice Count.
- `-*` — negative modifier covering the Maximum Dice Count.

No source label (e.g., "Bardic Inspiration") is shown inside the cell. Source attribution surfaces as a tooltip:

- **Hover** the badge — the source name appears above the badge for as long as the pointer remains over it.
- **Click** the badge — the same tooltip is shown for three seconds and then dismissed. The click is a momentary affordance for keyboard/touch use; it does not trigger a reroll on its own.

The Reroll badge sits on the post-reroll row; the Mass Reroll badge sits on the post-mass-reroll row (same column). The Nudge badge sits on the post-nudge row only. Reroll-class badges may be color-coded one color, Nudge another (e.g., Reroll/Mass Reroll = warm/amber, Nudge = cool/green) for quick visual distinction.

## Dice column

Each row displays the dice for that step. Individual dice are highlighted per `ui_conventions.md`. The initial-dice row starts empty (`[ — ]` placeholder) until the parent's Roll All is invoked, at which point the stub populates the row from the dice resolution domain.

If the Roll carries a non-zero Starting Value (Starting Successes from a Bonus that pushed TN below `Minimum Target Number`, or Starting Failures from a Penalty that pushed TN above `Maximum Target Number` — see `dice_resolution_design.md`), the initial-dice cell prepends `|starting_value|` small filled squares before the rolled dice — green for Starting Successes, red for Starting Failures — so the DM can see the contribution at a glance without parsing the `R+N` / `R-N` shorthand in the parameters line. The squares carry no number and never appear on modifier rows.

Modifier rows show only the positions the modifier actually touched — a rerolled or nudged die renders with its new value in full styling, and every other position renders as an empty placeholder so dice line up across rows. A Reroll that finds no eligible dice (a `+N` reroll on a row of all Successes, say) leaves its row fully blank. A Nudge row stays populated in all but the most extreme cases: a positive Nudge always picks one die unless every die is already at Die Size, and a negative Nudge always picks one unless every die is already at 1 — see *Nudge* in `dice_resolution_design.md` for the targeting rule.

## Result and Crits columns

Each contains an input field. After Roll All, the stub auto-fills both from the final post-modifier dice:

- **Result** (DoIS) = Starting Value + (count of dice ≥ TN) − (count of natural-1 failures). A crit (rolled value equals Die Size) counts as **two** successes.
- **Crits** = count of dice whose final value equals Die Size.

Both are editable so the DM can override either value at any time. Whatever the inputs hold is what the parent wrapper consumes on Confirm — the stub never re-derives them after the DM has touched them.

## Lock column

A small padlock icon, clickable as a toggle. **Unlocked (open padlock) is the default state**; clicking flips it to the locked (closed padlock) state, and clicking again returns to unlocked. The locked icon is visually prominent (gold/dark) while the unlocked icon is muted (gray).

The Lock controls whether the row participates in the parent wrapper's Roll All:

- **Unlocked** — the Roll is included in Roll All; pressing Roll All rerolls this Roll's dice (and re-applies its Reroll and Nudge) every time.
- **Locked** — the Roll is skipped by Roll All; its current dice and Result/Crits inputs are preserved untouched.

The stub itself takes no further action when the lock is toggled — it just exposes the state to the parent wrapper.

## Composition

The Roll Resolution Stub does not render its own Rolls wrapper, Roll All, or Confirm All in production usage — it is always embedded inside a parent stub that owns those affordances. The parent stub:

- Provides the `<div>` wrapper labelled "Rolls" with the Roll All and Confirm All buttons in its header.
- Provides the surrounding `<table>` / `<colgroup>` / `<thead>` when invoking the Roll Resolution Stub with the rows-only toggle set.
- Owns the batched Confirm semantics; the Roll Resolution Stub itself never raises an "I am confirmed" event.
- Assigns a unique stub identifier to each embedded Roll so events can be routed.

The Check Resolution Stub is one such parent; other parents (e.g., a single-roll Save panel) follow the same contract.

The standalone (non rows-only) mode is provided for inspection and demos — for example, the Status page's Dice Resolution view renders each example Roll inside its own one-row Rolls wrapper. It is not intended for production composition.

## Behavior

Roll All on the parent wrapper triggers all embedded Roll Resolution Stubs in sequence: the dice resolution domain produces fresh dice for each Roll's initial row, then applies Reroll, Mass Reroll, and Nudge (in that order) to populate the corresponding rows. **Roll All re-rolls dice that have already been rolled** — each press generates new random values for every unlocked Roll. A Roll whose Lock is closed is skipped entirely, preserving its current dice and inputs.

Confirm All on the parent wrapper signals the application that the user has accepted the current Result and Crits inputs across every embedded Roll. The Roll Resolution Stub itself does nothing on Confirm All beyond contributing its current input values — the wrapper aggregates and emits the event.

Each modifier's output feeds the next step's input, matching the dice resolution domain's order of operations (Reroll → Mass Reroll → Nudge). The Mass Reroll skips any die index already rerolled by the Reroll (each die may be rerolled at most once). Re-running an earlier step invalidates downstream results on that Roll; later modifiers must be re-applied if still desired.
