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

| File        | Brush | Source tile                |
|-------------|-------|----------------------------|
| `wall.png`  | Wall  | Minetest `default_stone_brick.png` |
| `dirt.png`  | Dirt  | Minetest `default_dirt.png`        |
| `stone.png` | Stone | Minetest `default_cobble.png`      |

## License / attribution

The current tiles come from **Minetest Game** and are licensed
**Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)**.

> Textures © 2010–2023 VanessaE, paramat (Minetest Game).
> Licensed under CC BY-SA 3.0 — https://creativecommons.org/licenses/by-sa/3.0/

Note: the originally requested public-domain (CC0) texture hosts
(Poly Haven, ambientCG, OpenGameArt) are not reachable from the build
environment's network policy; Minetest Game's tiles on GitHub were the best
free, seamless, reachable option. To switch to CC0 (or any other) art, just
replace these files with same-named seamless images and update this table.
