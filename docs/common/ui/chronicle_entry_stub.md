# Chronicle Entry Stub

A reusable UI component that displays a single Chronicle Entry as a card. Used on both the scene page and the notes page. The same stub renders both Notes and Creature References, branching on Entry Type.

See `ui_conventions.md` for shared rules including the Tier Color mapping used to style Creature References.

## Layout

A compact card with three regions, stacked top to bottom. The card has a fixed body height so it occupies a consistent amount of screen real estate regardless of content length; longer text is clipped visually and surfaced via the text modal described below.

**Header strip** — contains:
- The title (left).
- A compact row of status tags (right). Each tag is a small inline label; only relevant tags render — for example a Shared Entry shows a `Public` tag, an Active Entry shows an `Active` tag. A Private Entry shows a `Private` tag; an Inactive Entry shows no Activity tag. Status tags are DM-only and never render for player viewers.

**Content region** — two side-by-side panels when the Entry has an image, one full-width panel when it doesn't:
- *Image panel* (left, when an image is set) — a fixed-size square that resizes and crops the Entry's `image` to fill the panel (the image is centered and cropped to fit; aspect ratio is preserved without letterboxing).
- *Body panel* (right, or full-width when no image) — the Entry's descriptions, rendered without per-block headings. The panel has a fixed height; text that exceeds the available space is clipped by the panel's overflow.

**Footer** — collapsed by default. Holds an Edit affordance that opens an inline panel containing every authoring control (see *Edit panel* below). The footer renders for the Game Master, and for player viewers only when the Entry is editable by that viewer (the player controls the Entry's `owner_id`). The footer is absent entirely when there is nothing the viewer can change.

The card has no roll buttons. Editing happens entirely inside the Edit panel; the header is read-only.

## Parameters

Required:
- An Entry — the record from Chronicle.
- Viewer role — `dm` or `player`. Determines which fields and labels are visible.

Optional:
- For player viewers: viewing Creature ID. Used to evaluate visibility against the Entry's `hidden_from` and `owner_id`, and to decide whether the player may edit the Entry.

## Status tags

Status tags render only when Viewer Role is `dm`. They are small label chips inside the header strip, shown in this order:

- **Visibility tag** — `Public` when the Entry's `shared` flag is true, `Private` when false. This tag reflects only the `shared` flag; the actual visibility for any specific player also depends on `hidden_from` and `owner_id`.
- **Activity tag** — `Active` when the Entry's `active` flag is true. When the Entry is inactive, no Activity tag is rendered.

When Viewer Role is `player`, no status tags render and the entire status-tag row is omitted.

## Edit affordance

The Edit affordance appears in the footer as a clickable label reading `Edit` preceded by a right-pointing triangle (`▶`). The triangle rotates downward when the panel is expanded, following the standard disclosure pattern. Clicking the label expands the Edit panel in place; clicking again collapses it.

When the viewer cannot edit the Entry, the Edit affordance is omitted entirely (no triangle, no label, no panel).

Edit access rules:
- The Game Master may edit every Entry.
- A player viewer may edit an Entry when its `owner_id` equals the viewing Creature ID.
- All other viewers see no Edit affordance.

## Edit panel

When the Edit affordance is expanded, the following controls render inside an inset panel:

- **Field editors** — title, chapter selector (only for the Game Master), public description, GM-only description. For Creature References, a Tier override input (blank = use the Creature's own Tier).
- **Visibility toggles** — a `Shared with players` checkbox bound to the `shared` flag, and an `Active in current scene` checkbox bound to the `active` flag. Both are DM-only; player-owned-note editors do not see them (the parent context controls those flags on the player's behalf).
- **Hidden-from checklist** (DM-only) — a compact list of player-controlled Creatures, one checkbox per Creature. A checked entry indicates the Creature is *not* in `hidden_from`; unchecking adds the Creature, rechecking removes it. The checklist edits the Entry's `hidden_from` field only; the `shared` flag is toggled separately via the Shared checkbox above.
- **Image controls** — an Upload affordance that replaces the current image (multipart file input), and a Clear affordance that nulls the `image` field when an image is currently set. For Creature References, a second pair of Upload/Clear controls manages the `creature_token` field. Both are DM-only.
- **Delete** — a destructive action at the bottom of the panel, separated visually from the rest. Confirms before removing the Entry. DM-only.

All Edit-panel controls emit events the parent handles; the stub does not call Chronicle directly.

## Title

For Notes: the Entry's `title` field, displayed prominently.

For Creature References: the referenced Creature's name, looked up from the Creatures domain via `creature_id`. When the Entry's `title` is non-empty, it is appended after the creature name (for example, "Captain Veris, the Younger"). The title text is colored using the Tier Color associated with the Creature's tier (the Entry's `tier` override if set, otherwise the value from the Creatures domain).

## Image panel

When the Entry's `image` field is set, the image renders in the left image panel of the content region. The panel is a fixed-size square; the image is rendered to fill it edge-to-edge with `object-fit: cover` semantics — it is centered and cropped as needed without distortion. Notes typically have no image and the body panel takes the full width instead. Creature References typically have a profile-style image.

Clicking the image opens a full-screen lightbox that supports mouse-wheel zoom, click-drag pan, two-finger pinch zoom, and a double-click reset. See `ui_conventions.md` for the shared lightbox conventions.

## Body panel

The body panel renders the Entry's descriptions inline without per-block headings. The visible content depends on the viewer:

- DM viewer: sees both `public_description` and `dm_description` when both are non-empty. When only one is non-empty, only that one is shown.
- Player viewer: sees only `public_description`.

When both descriptions are visible, the GM-only description is distinguished by a tinted background (a soft amber band with an accent stripe down its leading edge) instead of a textual label. The Public description has no special background. Players never see the GM-only background because they never see the GM-only content.

The body panel has a fixed height; text exceeding that height is clipped via the panel's overflow rather than truncated at the data layer. To read the full untruncated content, the viewer clicks anywhere inside the body panel. Clicking opens a centered text modal sized for comfortable reading, with the same GM-only background applied to the GM block, scrolling enabled, and the same dismissal affordances as the image lightbox (close button, click outside the dialog, or `Esc`).

## Composition

The Entry Stub is designed to be placed inside parent layouts. Two common parent contexts:

- **Scene view** — entries marked Active sorted by `scene_position`.
- **Notes view** — entries grouped by Chapter, sorted by `notes_position` within each Chapter.

The parent owns layout and grouping; the Entry Stub renders one card.

## Visibility filtering

The stub does not filter by visibility. A consuming page must call Chronicle's *List Entries* entry point with the appropriate `visible_to` filter (or use the unfiltered list when rendering as the GM) and pass each returned Entry to its own stub instance.
