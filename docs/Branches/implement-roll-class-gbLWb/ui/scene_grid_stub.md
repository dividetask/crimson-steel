# Scene Grid Stub

Player-facing read-only view of the active scene map. Displays cells visible to the viewer and accepts player marks.

## Layout

1. **Grid** — Square cells. Cells the viewer cannot see are blanked.
2. **Arrow overlay** — DM-drawn arrows render on top.
3. **Player mark affordance** — Click a cell to drop a mark labeled with the viewer's id.

## Parameters

Required:
- Viewer id.

## Visibility

Per-cell visibility is enforced server-side: cells flagged visible to the viewer's PC render their image token; others render empty.

## Data sources

- Active map cells from scene state, filtered by the viewer's per-cell visibility list.
- Arrow overlays and player marks from scene state.
