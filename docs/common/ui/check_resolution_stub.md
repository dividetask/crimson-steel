# Check Resolution Stub

A reusable UI component that displays a Check as a sequence of Roll Resolution Stubs sharing a single table wrapper. Each Roll in the Check renders as one row inside the wrapper.

See `ui_conventions.md` for shared rules and `dice_resolution_roll_stub.md` for the child stub.

## Layout

A single table with shared column headers, then one Roll Resolution Stub row per Roll in the Check. Rolls render in the order they appear in the Check, with Supporting Rolls first followed by Opposing Rolls. A visual separator (a row, a divider line, or distinct row styling) distinguishes the two sides.

A single Confirm button sits below or beside the table, batching all Rolls into one confirmation event. Each child Roll Resolution Stub suppresses its own Confirm button.

## Parameters

Required:
- A Check — the two Roll lists.
- Per-Roll labels — for each Roll, the parameters required by the Roll Resolution Stub (Creature Name, Roll Name, modifier labels, etc.). The check stub does not generate these; the caller supplies them aligned to the Check's Roll lists.

Optional:
- Wrapper toggle — same meaning as in the Roll Resolution Stub. When false, the parent supplies the table wrapper.
- Stub identifier — supplied by a parent that needs to address this stub.

## Composition

The Check Resolution Stub is itself a parent stub for Roll Resolution Stubs:

- It renders the table wrapper and column headers.
- For each Roll, it calls the Roll Resolution Stub with `wrapper = false` and `confirm = false`.
- It assigns each child a unique stub identifier so per-Roll events (Roll button presses, Reroll button presses, etc.) address the correct child.
- It owns the batched Confirm.

A higher-level stub may in turn embed a Check Resolution Stub. In that case the Check stub's wrapper toggle is set to false and the higher-level stub supplies its own framing.

## Behavior

When the user presses Roll on an individual child, only that Roll's dice are generated. Each child manages its own Roll/Reroll/Nudge sequence independently.

When the user presses the batched Confirm, the stub raises a single application-level event with the per-Roll results from all children plus the manual override values from each child's Result column. Aggregation into a Degree of Success and Check-level Outcome is the application's responsibility — typically by calling check resolution's full-resolution entry point with the user's overrides applied.

A Roll All button rolls every child Roll Resolution Stub in sequence with a single click. The button sits alongside Confirm and is required — Checks with multiple Rolls are common, and rolling each child individually is tedious. The exact placement and label is an implementation choice, but the affordance must exist.
