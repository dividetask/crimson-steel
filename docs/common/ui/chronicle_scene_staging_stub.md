# Chronicle Scene Staging Stub

A DM-only authoring panel rendered at the bottom of the scene page. Used to add Entries to the current Scene, edit existing Active Entries, and adjust their order. The stub does not render for player viewers.

See `ui_conventions.md` for shared rules, including the Tier Color mapping used by embedded Creature References.

## Layout

A single labeled panel — **DM Staging** — containing two sub-sections stacked vertically:

1. **Active Notes** — every Active Entry with `entry_type = note`, ordered by `scene_position`. Each renders as a `chronicle_entry_stub` with DM affordances enabled. Below the list, an Add Note form.
2. **Active Creature References** — every Active Entry with `entry_type = creature`, ordered by `scene_position`. Each renders as a `chronicle_entry_stub` with DM affordances enabled. Below the list, an Add Creature Reference form.

Both sub-sections share the same Active-only filter (`active = true`); inactive Entries are not surfaced here. To work with archived Entries, the DM uses `chronicle_notes_browser_stub`.

## Sub-section — Active Notes

The list renders each Active Note as a `chronicle_entry_stub`. The Add Note form below the list captures:

- `title`
- `chapter` — defaulted to the Current Chapter from Chronicle's *Get Current Chapter*; a dropdown lists every Chapter.
- `public_description`
- `dm_description`
- `image` — optional upload affordance; the stub emits an opaque identifier per Chronicle's `image` field convention.
- `shared` — checkbox.
- `hidden_from` — a checklist of player-controlled Creatures (see `chronicle_entry_stub` for the same affordance).
- `active` — defaults to `true` (the form lives in scene staging).
- Submit emits an `add_entry` event with a structured Note payload; the parent page calls Chronicle's *Add Entry*.

## Sub-section — Active Creature References

The list renders each Active Creature Reference as a `chronicle_entry_stub`. The Add Creature Reference form captures:

- `creature_id` — a Creature picker over the Creatures domain.
- `title` — optional name suffix (typically empty).
- `chapter` — defaulted to the Current Chapter.
- `public_description`
- `dm_description`
- `image` — optional upload.
- `creature_token` — optional upload.
- `tier` — optional integer Tier Override; when blank, the Creature's own Tier is used.
- `shared`, `hidden_from`, `active` — as for Notes.
- Submit emits an `add_entry` event with a structured Creature Reference payload.

## Parameters

Required:
- Viewer role — must be `dm`. The stub renders nothing for `player`.
- The Active Entry list — Chronicle's *List Entries* with `active_only = true`.
- The Chapter list — from *List Chapters*.
- The current Chapter number — from *Get Current Chapter*.
- The player-controlled Creature list — for the `hidden_from` checklists.

## DM-only

The entire stub is DM-only. The parent page hides the staging panel when the viewer role is `player` and never invokes this stub for them.

## Composition

The staging stub is embedded in the scene page below the main scene rendering. Each Entry row is a `chronicle_entry_stub` instance; the staging stub owns the surrounding panel, the section headings, and the Add forms.

## What this stub does not do

- It does not reorder Entries. Reordering uses *Set Scene Position* via affordances on the embedded `chronicle_entry_stub` or on the scene rendering itself, not this staging panel.
- It does not toggle `active`. Promoting and archiving Entries is handled inside `chronicle_entry_stub`.
- It does not surface Inactive Entries. Use `chronicle_notes_browser_stub` for the full archive.
