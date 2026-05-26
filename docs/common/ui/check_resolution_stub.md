# Check Resolution Stub

A reusable UI component that displays a Check as a sequence of Roll Resolution Stubs sharing a single table wrapper. Each Roll in the Check renders as one row inside the wrapper.

See `ui_conventions.md` for shared rules and `dice_resolution_roll_stub.md` for the child stub.

## Layout

A "Rolls" wrapper (a bordered container with a header bar) holds a single table with shared column headers, then one Roll Resolution Stub row group per Roll in the Check. The header bar shows the title "Rolls" on the left and the two batched action buttons (Roll All, Confirm All) on the right. Rolls render in the order they appear in the Check, with Supporting Rolls first followed by Opposing Rolls.

No labelled side-divider row is drawn between Supporting and Opposing Rolls — the ordering itself is the convention, and additional rows would only add visual noise to a single composite table. Callers that want a visual separation are free to add their own framing outside the stub.

The Roll All and Confirm All buttons sit in the wrapper header — no per-Roll Roll or Confirm button is rendered, since the Roll Resolution Stub has no action column.

## Parameters

Required:
- A Check — the two Roll lists.
- Per-Roll labels — for each Roll, the parameters required by the Roll Resolution Stub (Creature Name, Roll Name, modifier labels, etc.). The check stub does not generate these; the caller supplies them aligned to the Check's Roll lists.

Optional:
- Wrapper toggle — same meaning as in the Roll Resolution Stub. When false, the parent supplies the table wrapper.
- Stub identifier — supplied by a parent that needs to address this stub.

## Composition

The Check Resolution Stub is itself a parent stub for Roll Resolution Stubs:

- It renders the Rolls wrapper (header bar + bordered container) and the surrounding table with column headers.
- For each Roll, it invokes the Roll Resolution Stub with the rows-only toggle set so the child emits only its table rows.
- It assigns each child a unique stub identifier so per-Roll events address the correct child.
- It owns the batched Roll All and Confirm All in the wrapper header.

A higher-level stub may in turn embed a Check Resolution Stub. In that case the Check stub's wrapper toggle is set to false and the higher-level stub supplies its own framing.

## Behavior

There is no per-Roll Roll button. Pressing Roll All in the wrapper header generates dice for every child Roll Resolution Stub in sequence; each child applies its own Reroll and Nudge after its initial dice are produced. Rolls whose Lock is closed are skipped.

When the user presses Confirm All, the stub raises a single application-level event with the per-Roll results from all children plus the manual override values from each child's Result and Crits columns. Aggregation into a Degree of Success and Check-level Outcome is the application's responsibility — typically by calling check resolution's full-resolution entry point with the user's overrides applied.
