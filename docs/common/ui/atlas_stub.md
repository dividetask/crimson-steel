# Atlas Stub

A reusable UI component that renders the Active Map (or a specified Map) with its Tokens, supporting pan and zoom. The same stub serves the scene view and the dedicated map page.

See `ui_conventions.md` for shared rules, including the Tier Color mapping used by default Token icons.

## Layout

A two-region card:

1. **Toolbar** — a thin strip across the top with: a Map picker dropdown (Active Map highlighted, archived Maps grouped under a collapsible *Archived* section), zoom in / zoom out / reset-view buttons, a *Recenter* affordance, and the **Drawing tools** (see below). DM-only affordances: *Add Map*, *Edit Map*, *Archive Map*, *Unarchive Map*, *Delete Map*, *Place Token*, *Clear Tokens*. The toolbar is hidden when the parent passes `chrome = false` (e.g. to embed the stub inside a tooltip preview).
2. **Canvas** — the main region. Renders the Map Image (or a blank canvas) and overlays Token icons at their stored positions. Fills the available width and height of the parent container.

## Parameters

Required:
- Viewer role — `dm` or `player`. Determines which toolbar affordances appear and whether hidden Tokens render.

Optional:
- Map ID — the Map to render. When omitted, the stub renders the Active Map. When the Active Map is null and no Map ID is supplied, the canvas displays an empty-state message (`No active map`).
- Viewing Creature ID — used for visibility filtering of Tokens and for the *Move Token* affordance (a player viewer may move only Tokens whose `owner_id` matches).
- `chrome` — boolean, default true. When false, the toolbar is suppressed and the canvas fills the card.
- Combat roster — optional list of Creature IDs that are Combatants in the active Combat. When supplied, the stub may visually distinguish Tokens whose `creature_id` is in the roster (see *Token rendering* below). The stub does not call Combat directly; the parent supplies the list.

## Pan and zoom

The canvas implements two interactions:

- **Pan** — click-and-drag on empty canvas (or two-finger drag on touch) translates the viewport. There is no boundary on pan extent; the user may scroll beyond the Map's declared `width` and `height` in either direction, because Tokens may be placed there.
- **Zoom** — scroll wheel (or pinch) adjusts the zoom factor centered on the cursor. Buttons in the toolbar offer the same operation. Zoom is clamped to `[Minimum Zoom, Maximum Zoom]` from `atlas_config.yaml`. On first open of a Map the initial zoom is `Suggested Initial Zoom`; subsequent visits restore the most recent zoom and pan (held in UI state, not in Atlas state).

The stub never resizes or paginates the underlying Map. A Map with `width = 10000` renders the same way as `width = 50` — the user pans and zooms to navigate.

The stub does not call Atlas to record pan or zoom. Viewport state is the UI's own concern.

## Token rendering

For every Token on the rendered Map (filtered per *Visibility filtering* below), the stub draws a square icon at `(x, y)` with side length equal to the Token's `size` (multiplied by the current zoom factor). Tokens are square; `(x, y)` is the Token's top-left corner in Map Units.

Icon precedence:
1. The Token's `image` field, when set.
2. The Creature's token image, looked up via the Creatures domain (stored under the Creature's `metadata.creature_token`).
3. A `?` marker on a Tier-colored square (per `ui_conventions.md`) — Creatures with no icon show a `?` rather than initials.

When the parent supplies a Combat roster, Tokens whose `creature_id` is in the roster are outlined with a Combatant ring. Tokens whose `creature_id` matches the active Combat's `acting_combatant_id` (the parent supplies this separately) get a thicker, animated ring.

When a Token's referenced Creature does not exist (deleted from the Creatures domain), the icon falls back to a neutral `?` marker. (If a Creature's `creature_token` path fails to load, the icon also falls back to the `?` marker.)

## Hover behavior

Hovering over a Token surfaces an `atlas_token_tooltip` (see the matching tooltip spec). Triggering and positioning are the application's choice; this stub guarantees only that each rendered Token has a stable element to attach the tooltip to.

On touch devices where hover is not available, a tap-to-pin variant displays the tooltip; a second tap dismisses it.

## Drag-and-drop

A Token may be dragged to a new position. The drag updates the Token's visual position locally during the drag and commits via Atlas's *Move Token* on release. Dragging is gated by viewer role and ownership:

- DM viewer: may drag every Token.
- Player viewer: may drag only Tokens whose `owner_id` matches the Viewing Creature ID.

Dragging is suppressed entirely when `chrome = false`.

### Placing a Token

The DM-only *Place Token* affordance opens a picker of the active Combatants. Choosing one **arms placement**: the next press on the canvas drops the Token at that cell, and the DM may drag before releasing to position it (a ghost follows the cursor, snapped to Grid cells; release commits *Place Token* at that cell). `Esc` cancels an armed placement. This replaces dropping the Token at a fixed default position — it lands where the DM puts it.

### Placing a spell area

A Cast's "Place on the map" option (an area Spell, per `turn_action_stub.md` → Cast) **arms area placement**: the next press on the canvas drops the spell's footprint at that cell, snapped to the Grid. Unlike a Token, the footprint is **not yet committed** — it is a local, dashed preview that lives only in the canvas until the cast is committed, and the caster may **re-aim it** by dragging the footprint to a new cell. Both the initial drop and each subsequent move recompute which Combatant Tokens the footprint catches and report them to the cast panel (via `cast:area-placed`), so the affected creatures — and their Saving Throws — update to match wherever the effect currently sits. Nothing is persisted to the Map until the cast is committed; re-aiming before that point is free.

## Drawing tools

The toolbar carries a group of drawing tools that create Atlas **Annotations** (see `atlas_design.md` → *Manage Annotations*). A tool is a mode: while one is active, pointer gestures on the canvas draw instead of panning. Selecting *Select* mode returns to pan/drag.

- **Arrow** — drag from tail to head; commits an `arrow` Annotation on release. Arrows are drawn freely (no snapping).
- **Shape** — drag a bounding box; commits a `shape` Annotation. The DM picks the shape kind (`rect` or `ellipse`). Shape corners **snap to Grid corners** (whole Map Units, offset by the Grid Origin) so rectangles and ellipses align to cells, and shapes render with a **solid fill**.
- **Text** — click to place an anchor, type into an inline field, and commit a `text` Annotation. (No browser prompt — the field is inline, per the project's UI conventions.)

Each tool commits through Atlas's *Add Annotation* with the current viewer's role as the Annotation's `author`; the canvas then renders every Annotation on the Map beneath the Token layer. Snapping is applied client-side before the call — Atlas itself stores the supplied points verbatim (it neither snaps nor clamps).

A **Clear Drawings** affordance removes Annotations via *Clear Annotations On Map*. For the DM it clears every Annotation on the Map; for a player it clears only their own (scoped by `author`).

### Role gating

The drawing tools obey the viewer role:

- **DM** — the **Arrow** tool (with a color swatch that sets the new Annotation's color), the **Shape** tool (rect / ellipse), and the **Text** tool; plus *Clear Drawings* (clears all).
- **Player** — four fixed-color **arrow** buttons instead of a generic Arrow tool, each drawing an `arrow` of a preset color: **Attack** (red), **Move** (blue), **Sneak** (purple), **Careful** (yellow). Players also get *Clear Drawings* scoped to their own arrows. The Shape and Text tools (and the color swatch) are not offered to players.

Atlas itself does not enforce this (it records whatever `author`/`type` it is given); the stub is the gate, refusing to surface the Shape and Text tools to a player and tagging every player-drawn Annotation with `author = player`.

### Player arrows are transient

Player arrows are momentary tactical suggestions, not durable map state. **Whenever the DM makes any change to the Map** — moving or placing a Token, drawing, switching or editing the Map, clearing Tokens, and so on — every player-drawn Annotation on the Active Map is removed (the host calls *Clear Annotations On Map* scoped to `author = player` on each DM mutation). DM-drawn Annotations persist until the DM clears them. This keeps the map readable: a player points somewhere, the DM acts, and the suggestion clears itself.

## Visibility filtering

- DM viewer: every Token on the rendered Map is shown, regardless of `hidden`.
- Player viewer: Tokens with `hidden = true` are not shown. Tokens with `hidden = false` are shown regardless of `owner_id`.

The stub does the filtering itself for performance reasons; the parent does not need to pre-filter the Token list.

## Map picker

The Map picker dropdown in the toolbar lists Maps from Atlas's *List Maps*:

- Default section: every Map with `archived = false`. The Active Map is marked.
- *Archived* section: every Map with `archived = true`. Collapsed by default. Selecting an archived Map opens it in view-only mode — *Set Active Map* is unavailable until the Map is unarchived. (DM-only affordances *Unarchive Map* and *Delete Map* remain.)
- *New Map* affordance: visible only to the DM. Opens an Add Map dialog.

The Map picker is hidden when `chrome = false`.

## Composition

The stub is designed for two parent contexts:

- **Scene view** — embedded alongside the Chronicle Entry list. The map renders the Active Map; toolbar shrinks to the essentials.
- **Dedicated map page** — full-bleed canvas with the full toolbar.

In both cases the stub renders one canvas instance. Multiple canvases on the same page are permitted (e.g. a battle map and a region overview side by side); each takes a separate Map ID parameter.

## What this stub does not do

- It does not interpret Map Units. The Map's units are a Campaign convention; the stub treats them as opaque numbers and applies the current zoom factor.
- It does not snap Tokens to Grid cells. Snapping, if desired, is a UI extension that intercepts drag-and-drop before the Atlas *Move Token* call.
- It does not draw line-of-sight or fog of war. Those are future extensions.
- It does not subscribe to Combat. The parent page is responsible for passing the Combat roster (and `acting_combatant_id`) when it wants Combatant highlighting.
