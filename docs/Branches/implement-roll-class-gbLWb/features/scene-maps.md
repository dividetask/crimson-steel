# Scene Maps

DM-side grid-map editor backed by per-cell image tokens, with a player-facing read-only view that overlays arrows and player marks.

## Glossary

- **Scene Map** — A grid attached to the active scene. Each cell may hold an image token, a player mark, or be empty.
- **Map Image Library** — A whitelisted set of token images discovered by walking `public/images/` recursively. The whitelist comes from `data/map_images.yaml` (acts as an exclusive whitelist).
- **Workshop Page** (`/maps`) — Dedicated DM-only page for building maps without the rest of the scene chrome.
- **Player Mark** — A symbol a player drops on a cell from their `/scene/<viewer_id>` view.
- **Arrow Overlay** — DM-drawn arrows that render on top of the grid for both DM and players.

## Design

The map is stored as a 2-D array of cells on the active scene. Each cell carries an optional `image` (key into the Map Image Library) and an optional list of player marks. The DM editor and `/maps` page share the same IIFE so the editing UI is identical in both places.

The DM editor exposes wheel-zoom and pan-on-empty-viewport (panning only starts on a drag that began outside any cell, so cell clicks aren't eaten). Pan/viewport scaffolding was added, removed, and re-added across the branch's history; the final state is plain zoom plus pan-on-empty for the workshop page, and plain zoom on `/scene`.

Map mutations go through dedicated endpoints:

- `POST /scene/map` creates a new map.
- `POST /scene/map/update` writes cell changes.
- `POST /scene/map/share`, `/scene/map/activate`, `/scene/map/delete` manage which map is current.
- `POST /scene/map/player_mark` records a player drop.
- `POST /scene/map/arrow`, `/scene/map/arrows/clear`, `/scene/map/player_actions/clear` manage overlays.

Image library resolution: `data/map_images.yaml` lists the allowed image paths. The server walks `public/images/` recursively, strips upload prefixes for display, and intersects with the whitelist. Unlisted files are ignored even if present on disk.

The player palette on `/scene/<viewer_id>` is a slim subset — players can place marks and trigger a Spell action but cannot edit cell tokens.

## Data shapes

```
scene.active_map = {
  id: <int>,
  width: <int>,
  height: <int>,
  cells: [[{image: <key>?, marks: [<viewer_id>...]}, ...], ...],
  arrows: [{from: [r,c], to: [r,c], color: <str>}, ...]
}
```

`map_images.yaml` is a flat list of relative paths under `public/images/` that are eligible as tokens.
