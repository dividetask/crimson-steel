# Zone textures

Image fills for spell-area Zones on the Atlas map. A spell's `area.texture`
key (in `docs/common/abilities/spells.yaml`) is the **filename** in this folder:
`texture: web.png` renders `/images/zones/web.png`, clipped to the Zone's shape.
A Zone with no `texture` (or a missing file) falls back to a solid **purple**
fill. Any image format the browser supports works (`.png`, `.webp`, …).

## Current files

| File                  | Spell           | Image                 |
|-----------------------|-----------------|-----------------------|
| `web.png`             | Web             | black spider web      |
| `entangle.png`        | Entangle        | green tangle of vines |
| `obscuringmist.png`   | Obscuring Mist  | grey cloud / fog      |
| `grease.webp`         | Grease (area)   | oily rainbow slick    |

Area spells without a `texture` (Darkness, Silence, Create Pit, …) render as
the purple fallback until one is assigned in `spells.yaml`.
