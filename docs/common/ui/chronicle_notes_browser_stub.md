# Chronicle Notes Browser Stub

A Chapter-organized browser of every Chronicle Entry. Renders the full notes view as a standalone page: DM Notes, Creature References ("Characters of Interest"), and — for player viewers — the viewing Creature's own owned Notes.

See `ui_conventions.md` for shared rules, including the Tier Color mapping used by embedded Creature References.

## Layout

A vertical scroll of sections, stacked top-to-bottom:

1. **Chapter filter tabs** — `All`, followed by one tab per Chapter from Chronicle's *List Chapters* entry point (in number order). The currently-selected Chapter tab is rendered in the selected state.
2. **DM Notes** — every Entry with `entry_type = note` and `owner_id = null`, filtered by the chosen Chapter. Each Note is rendered with `chronicle_entry_stub`. Below the list, a DM-only Add Note form.
3. **Characters of Interest** — every Entry with `entry_type = creature`. Each is rendered with `chronicle_entry_stub`. Below the list, a DM-only Add Creature Reference form. This section ignores the Chapter filter.
4. **Character Notes** — when the viewer is a player, the viewing Creature's owned Notes (`entry_type = note` and `owner_id = viewing creature id`), filtered by the chosen Chapter. Each Note is rendered with `chronicle_entry_stub`. Below the list, an Add Note form locked to the viewing Creature as `owner_id`. Hidden entirely when the viewer is the Game Master.

## Parameters

Required:
- Viewer role — `dm` or `player`. Determines visibility filtering and which Add forms render.
- The Entry collection — Chronicle's *List Entries* result, already filtered for the viewer (see Visibility below).
- The Chapter list — from Chronicle's *List Chapters*.

Optional:
- Selected Chapter — a Chapter number or `null` for "All". When omitted, defaults to `null`.
- Viewing Creature ID — required when the viewer is a player. Used to scope the Character Notes section and provided to embedded `chronicle_entry_stub` instances for per-row visibility evaluation.

## Chapter filtering

Filtering is applied locally to the DM Notes and Character Notes sections only. The Characters of Interest section is unaffected — Creature References are not Chapter-scoped in this view.

- When the selected Chapter is `null`, no Chapter filtering is applied.
- When a Chapter is selected, an Entry matches when its `chapter` field equals the selected number.

## Visibility

The stub does not re-evaluate visibility. The consuming page calls Chronicle's *List Entries* with the appropriate `visible_to` filter (or no filter when the viewer is the Game Master). The result is passed in as the Entry collection. See Chronicle's *Visibility resolution* operation for the rules.

When the viewer is the Game Master, every Entry is shown and each `chronicle_entry_stub` instance surfaces its visibility status row.

## DM-only affordances

The following render only when the viewer role is `dm`:

- Add Note form below the DM Notes section.
- Add Creature Reference form below the Characters of Interest section.
- Per-Entry management affordances inside each embedded `chronicle_entry_stub` (visibility toggle, delete, image upload — see that stub for details).

The Character Notes section's Add Note form is *not* DM-only; it renders for player viewers and locks `owner_id` to the viewing Creature.

## Composition

The Notes Browser is a standalone page-level stub. Each row inside its sections is a `chronicle_entry_stub`. The browser owns layout and grouping; the entry stub owns the individual card.

## What this stub does not do

- It does not perform visibility filtering — the consuming page supplies an already-filtered Entry collection.
- It does not implement the Add forms' submit logic. Submitting emits a structured Entry payload and an `add` event the parent page resolves through Chronicle's *Add Entry* entry point.
- It does not edit Entries inline. Editing is delegated to `chronicle_entry_stub`'s edit affordance.
