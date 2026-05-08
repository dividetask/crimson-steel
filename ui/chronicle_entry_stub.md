# Chronicle Entry Stub

A reusable UI component that displays a single Chronicle Entry as a card. Used on both the scene page and the notes page. The same stub renders both Notes and Creature References, branching on Entry Type.

See `ui_conventions.md` for shared rules including the Tier Color mapping used to style Creature References.

## Layout

A rectangular card with a header strip and a body region.

**Header strip** — contains:
- A title.
- A small status row showing two labels (DM-only): a Visibility label (`Hidden` or `Visible`) and an Activity label (`Active` or `Inactive`).
- For Creature References: a delete or dismiss action.

**Body region** — depends on Entry Type and which descriptions are populated. Layout details below.

The card has no roll buttons or other interactive controls beyond the affordances listed above. Editing is the parent page's responsibility — the stub may expose an Edit affordance that emits an event the parent handles.

## Parameters

Required:
- An Entry — the record from Chronicle.
- Viewer role — `dm` or `player`. Determines which fields and labels are visible.

Optional:
- For player viewers: viewing Creature ID. Used to evaluate visibility against the Entry's `hidden_from` and `owner_id`.

## Status row

Shown only when Viewer Role is `dm`. Two labels side by side:
- **Visibility label**: `Hidden` if the Entry's `public` flag is false, `Visible` if true. Note that the actual visibility for any specific player also depends on `hidden_from` and `owner_id`; this label reflects only the `public` flag.
- **Activity label**: `Active` if the Entry's `active` flag is true, `Inactive` if false.

When Viewer Role is `player`, the status row is hidden entirely.

## Title

For Notes: the Entry's `title` field, displayed prominently.

For Creature References: the referenced Creature's name, looked up from the Creatures domain via `creature_id`. When the Entry's `title` is non-empty, it is appended after the creature name (for example, "Alric Thorne, the Younger"). The title text is colored using the Tier Color associated with the Creature's tier (the Entry's `tier` override if set, otherwise the value from the Creatures domain).

## Body region

The body region renders the Entry's image and descriptions.

**Image.** When the Entry's `image` field is set, the image is shown at the top of the body region. Notes typically have no image. Creature References typically have a profile-style image.

**Descriptions.** The visible content depends on the viewer:
- DM viewer: sees both `public_description` and `dm_description` when both are non-empty. When only one is non-empty, only that one is shown.
- Player viewer: sees only `public_description`.

When body text exceeds a threshold height, truncates with a `Show more` affordance that expands the card in place.

## Composition

The Entry Stub is designed to be placed inside parent layouts. Two common parent contexts:

- **Scene view** — entries marked Active sorted by `scene_position`.
- **Notes view** — entries grouped by Chapter, sorted by `notes_position` within each Chapter.

The parent owns layout and grouping; the Entry Stub renders one card.

## Visibility filtering

The stub does not filter by visibility. A consuming page must call Chronicle's List Entries entry point with the appropriate `visible_to` filter (or use the unfiltered list when rendering as the GM) and pass each returned Entry to its own stub instance.
