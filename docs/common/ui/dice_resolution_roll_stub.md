# Roll Resolution Stub

A reusable UI component for displaying a single Roll, rolling its dice, and applying its modifiers interactively. Backed by the public entry points of the dice resolution domain.

See `ui_conventions.md` for shared rules (dice highlighting, modifier presentation, composition).

## Layout

A table row (or a small table when standalone) with five columns:

| Column | Content |
|---|---|
| Action | A Roll button. Optionally a Confirm button alongside. |
| Identity | Three lines: Creature Name, parameters line, Roll Name. |
| Modifier | Three lines: blank, Reroll modifier, Nudge modifier. |
| Dice | Three lines: initial dice, post-reroll dice, post-nudge dice. |
| Result | Two manual-override fields: DoIS and Critical Count. |

Modifier and Dice rows are only shown when the corresponding modifier is configured for the Roll. A Roll with no Reroll and no Nudge has only the initial-dice row; a Roll with only a Nudge has the initial-dice row and the nudge row, and so on.

## Parameters

Required:
- Creature Name — string. The Roll's owning creature.
- Roll Name — string. A short label (e.g., the Check the Roll is part of).
- Dice Count — integer.
- TN — integer.
- Starting Value — signed integer.

Optional:
- Reroll amount and label — signed integer plus a human-readable name. Positive rerolls non-Successes; negative rerolls Successes. Zero suppresses the Reroll row entirely.
- Nudge amount and label — signed integer plus a human-readable name. Zero suppresses the Nudge row entirely.
- Wrapper toggle — boolean. When true, the stub renders its own table; when false, it emits only the inner row(s) for embedding in a parent table.
- Confirm toggle — boolean. When true, a Confirm button is shown alongside Roll. When false, the Confirm button is suppressed (the parent typically owns a batched Confirm).
- Stub identifier — string. Supplied by a parent that needs to address this child instance.

## Identity column lines

1. **Creature Name** — verbatim.
2. **Parameters line** — `<Dice Count> dice @ TN <TN>` followed by Starting Value when nonzero. Positive Starting Value renders as `, <n> starting success(es)`; negative renders as `, <n> starting failure(s)`. Pluralization adjusts for `n = 1`.
3. **Roll Name** — wrapped in parentheses.

## Modifier column lines

The first line of the Modifier column is blank — it sits next to the initial-dice row and never has content.

When a Reroll is configured, the second line shows the modifier text (e.g., `+2 Bardic Inspiration`). When the Reroll is rerunable on demand (a positive reroll with an active source), this line is rendered as a button that triggers a reroll. Otherwise it's a static label.

When a Nudge is configured, the third line shows the modifier text as a static label.

## Dice column lines

Each line displays the dice for that step. Individual dice are colored per `ui_conventions.md`. Empty until the Roll is performed; the `Roll` button populates the initial dice and any subsequent steps.

## Result column

Two manual input fields for the user to enter final values:
- DoIS input.
- Critical Count input.

These are independent of the Roll button — the user types the final values regardless of what the dice landed on. The dice display is informational; the inputs are authoritative for whatever resolution the application performs after Confirm.

## Behavior

When the Roll button is pressed: the stub generates the initial dice via the dice resolution domain's roll-with-TN entry point, then renders the dice in their respective rows. If the Roll has a Reroll modifier configured, the Reroll button (if any) becomes active and may be pressed to apply the reroll. The Nudge applies similarly.

The order in which Reroll and Nudge can be applied matches the dice resolution domain's order of operations: the Reroll's result feeds the Nudge's input. Pressing the Reroll button after a Nudge has been applied invalidates the Nudge result — the Nudge must be re-applied if still desired.

The Confirm button signals the application that the user has accepted the values in the Result column. The stub itself does not know what Confirm means; it raises an application-level event.

## Composition

When embedded in a parent stub (e.g., a check resolution stub rendering one row per Roll in a Check):
- Wrapper toggle is set to false. The parent supplies its own table and column headers.
- Confirm toggle is typically set to false. The parent owns a batched Confirm.
- The parent supplies a unique stub identifier to each child instance.
