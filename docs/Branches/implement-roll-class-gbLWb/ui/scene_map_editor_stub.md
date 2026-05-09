# Scene Map Editor Stub

DM-only grid editor for the active scene map. Used both inline on `/scene` and full-page on `/maps`.

## Layout

A bordered viewport showing the grid:

1. **Toolbar** — Zoom in / zoom out / reset, image-token picker (slim palette), arrow tool, clear-arrows, clear-player-actions.
2. **Grid** — Square cells bound to track width. Each cell may show an image token, a player mark, or be empty.
3. **Arrow overlay** — DM-drawn arrows render on top of the grid.

Pan: drag-on-empty-viewport pans the grid. Drag starting on a cell does not pan (cell clicks are not eaten). Wheel scrolls zoom.

## Parameters

Required:
- Active map id.
- Viewer role — DM only.

## Visibility

DM only. Players see the read-only `scene_grid_stub` view (no toolbar, no edit, with an arrow-overlay layer and player-mark drop affordance).

## Data sources

- Active map cells from scene state.
- Image tokens from the Map Image Library (`data/map_images.yaml` whitelist intersected with `public/images/` walk).
- Arrow overlays and player marks from scene state.
