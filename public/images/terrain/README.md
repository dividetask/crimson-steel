# Terrain textures

Repeating image fills for the Atlas map's **Terrain** layer — the painted
walls / dirt / stone floor a DM lays down to build a scene (e.g. a fort).
Each file is tiled **one tile per Grid cell** behind the grid lines.

A Terrain fill stores the **filename** in this folder as its `texture`
(`texture: wall.png` renders `/images/terrain/wall.png`, repeated). The DM
toolbar shows one brush per file present here, so **dropping a new seamless
image into this folder adds a brush with no code change** (its label is
titleized from the filename unless mapped in `TERRAIN_LABELS` in
`lib/routes/atlas.rb`). Any browser-supported format works (`.png`, `.webp`,
`.jpg`, `.gif`). Tiles render with `image-rendering: pixelated`, so small
seamless tiles stay crisp as you zoom.

## Current files

| File            | Brush       | Source tile                        |
|-----------------|-------------|------------------------------------|
| `wall.png`        | Wall        | Minetest `default_stone_brick.png` |
| `dirt.png`        | Dirt        | Minetest `default_dirt.png`        |
| `stone.png`       | Stone       | Minetest `default_cobble.png`      |
| `dirt_dark.png`   | Dark Dirt   | procedurally generated (this repo) |
| `dirt_rocky.png`  | Rocky Dirt  | procedurally generated (this repo) |
| `grass.png`       | Grass       | procedurally generated (this repo) |
| `grass_dry.png`   | Dry Grass   | procedurally generated (this repo) |
| `grass_lush.png`  | Lush Grass  | procedurally generated (this repo) |
| `thatch.png`      | Thatch Roof | procedurally generated (this repo) |
| `tileroof.png`    | Tile Roof   | procedurally generated (this repo) |
| `building.png`    | Buildings   | procedurally generated (this repo) |

To add another brush, drop a seamless tile here and (optionally) give it a
friendly label in `TERRAIN_LABELS` in `lib/routes/atlas.rb` — otherwise the
label is titleized from the filename.

## Regenerating the procedural tiles

The `grass*` / `dirt_*` / `thatch` / `tileroof` / `building` tiles are
original, procedurally-generated 16×16 pixel art (CC0). They are produced by
`bin/generate_terrain_textures.py` (Python stdlib only — no image libraries),
so they can be tweaked or extended in one place:

```
python3 bin/generate_terrain_textures.py
```

Each pixel is a pure function of `(x % 16, y % 16)` and the structured patterns
use periods that divide 16, so every tile is seamless when repeated.

## License / attribution

The `wall` / `dirt` / `stone` tiles come from **Minetest Game** and are licensed
**Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)**.

> Textures © 2010–2023 VanessaE, paramat (Minetest Game).
> Licensed under CC BY-SA 3.0 — https://creativecommons.org/licenses/by-sa/3.0/

The procedurally-generated tiles listed above are original to this project and
released under **CC0** (public domain); no attribution required. To switch any
tile to other art, replace the file with a same-named seamless image and update
this table.
