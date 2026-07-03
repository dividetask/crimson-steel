#!/usr/bin/env python3
"""Generate the Atlas Terrain texture tiles.

Emits small (16x16) seamless PNG tiles into public/images/terrain/. Each tile
is a repeating map fill painted one tile per Grid cell (see that folder's
README and docs/common/ui/atlas_stub.md -> Terrain). The tiles are original,
procedurally-generated pixel art (CC0) — no external assets or image libraries
required (stdlib zlib + struct only), so they can be regenerated or tweaked in
this one place.

Seamlessness: every pixel color is a pure function of (x % 16, y % 16), and the
structured patterns use periods that divide 16, so a tile abuts itself with no
visible seam. Tiles render with image-rendering: pixelated, so 16px art stays
crisp as the map zooms.

Run: python3 bin/generate_terrain_textures.py
"""

import os
import struct
import zlib

SIZE = 16
OUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'public', 'images', 'terrain')


# ----- PNG output (truecolor + alpha, 8-bit) -----

def write_png(path, pixels):
    """pixels: SIZE-length list of rows, each a SIZE-length list of (r,g,b,a)."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0 (None) for this scanline
        for (r, g, b, a) in row:
            raw += bytes((r & 255, g & 255, b & 255, a & 255))

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    ihdr = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) +
           chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


# ----- helpers -----

def rnd(x, y, seed):
    """Deterministic value hash in [0, 1). Periodic in (x, y) mod 16 because
    callers pass already-wrapped coordinates, so the noise tiles seamlessly."""
    n = (x * 374761393 + y * 668265263 + seed * 69069) & 0xffffffff
    n = (n ^ (n >> 13)) * 1274126177 & 0xffffffff
    n = (n ^ (n >> 16)) & 0xffff
    return n / 0x10000


def clampb(v):
    return 0 if v < 0 else 255 if v > 255 else int(round(v))


def shade(color, amount):
    """Lighten (amount > 0) / darken (amount < 0) an (r, g, b) by 0..1."""
    r, g, b = color
    if amount >= 0:
        return (clampb(r + (255 - r) * amount), clampb(g + (255 - g) * amount), clampb(b + (255 - b) * amount))
    return (clampb(r * (1 + amount)), clampb(g * (1 + amount)), clampb(b * (1 + amount)))


# ----- textures -----

def speckle(base, x, y, seed, light=0.28, dark=0.22):
    """Organic per-pixel scatter around a base color — the shared look for the
    grass and dirt tiles. Bright flecks, mid tints, dark gaps, and fine noise."""
    n = rnd(x, y, seed)
    if n > 0.90:
        return shade(base, light)          # a bright fleck (blade / grain)
    if n > 0.72:
        return shade(base, light * 0.45)
    if n < 0.10:
        return shade(base, -dark)          # a shadowed gap
    return shade(base, (rnd(x, y, seed + 1) - 0.5) * 0.10)


def grass(x, y):
    return speckle((74, 124, 52), x, y, 11)


def grass_dry(x, y):
    # Sun-bleached khaki with the odd green blade left in.
    if rnd(x, y, 71) > 0.86:
        return speckle((92, 120, 54), x, y, 72)   # surviving green tuft
    return speckle((168, 152, 86), x, y, 73, light=0.22, dark=0.20)


def grass_lush(x, y):
    # Deep, damp meadow green.
    return speckle((40, 92, 44), x, y, 75, light=0.30, dark=0.26)


def dirt_dark(x, y):
    # Damp, tilled earth — darker and browner than the base dirt.
    if rnd(x, y, 81) > 0.93:
        return shade((54, 40, 28), 0.0)           # a wet clod
    return speckle((84, 60, 40), x, y, 82, light=0.20, dark=0.26)


def dirt_rocky(x, y):
    # Stony ground: pale brown scattered with small grey pebbles.
    n = rnd(x, y, 85)
    if n > 0.86:
        return shade((150, 148, 140), (rnd(x, y, 86) - 0.5) * 0.30)   # pebble
    if n < 0.10:
        return shade((92, 76, 58), 0.0)           # shadow pocket
    return speckle((132, 112, 88), x, y, 87, light=0.16, dark=0.16)


def thatch(x, y):
    base = (194, 163, 79)              # straw
    band = y % 4                       # 4 straw courses of 4px each
    seam = -0.34 if band == 0 else 0.0  # dark overlap line at each course top
    streak = (rnd(x // 4, y, 21) - 0.5) * 0.34   # 4px-wide horizontal strands
    fiber = (rnd(x, y, 22) - 0.5) * 0.08
    return shade(base, seam + streak + fiber)


def tileroof(x, y):
    base = (176, 78, 44)              # terracotta
    row = y // 8
    xoff = 4 if row % 2 else 0        # offset alternate courses like scales
    yy = y % 8
    xx = (x - xoff) % 8
    grad = 0.22 - (yy / 7.0) * 0.44   # each tile: lit at top, shadowed toward lip
    edge = 0.0
    if yy == 0:
        edge = -0.42                  # shadow line where the next course overlaps
    if xx == 0:
        edge = -0.30                  # groove between adjacent tiles
    tint = (rnd(x // 8, row, 31) - 0.5) * 0.10
    return shade(base, grad + edge + tint)


def building(x, y):
    base = (138, 138, 132)           # stone / slate blocks
    row = y // 4                      # 4px courses
    xoff = (row % 2) * 4             # running-bond offset
    xx = (x - xoff) % 8              # 8px blocks
    yy = y % 4
    if xx == 0 or yy == 0:
        return shade(base, -0.42)    # mortar joint
    tint = (rnd((x - xoff) // 8, row, 61) - 0.5) * 0.16   # per-block variation
    grain = (rnd(x, y, 62) - 0.5) * 0.05
    return shade(base, tint + grain)


TEXTURES = {
    'grass.png': grass,
    'grass_dry.png': grass_dry,
    'grass_lush.png': grass_lush,
    'dirt_dark.png': dirt_dark,
    'dirt_rocky.png': dirt_rocky,
    'thatch.png': thatch,
    'tileroof.png': tileroof,
    'building.png': building,
}


def main():
    out = os.path.normpath(OUT_DIR)
    for name, fn in TEXTURES.items():
        pixels = [[fn(x, y) + (255,) for x in range(SIZE)] for y in range(SIZE)]
        write_png(os.path.join(out, name), pixels)
        print('wrote', os.path.join('public/images/terrain', name))


if __name__ == '__main__':
    main()
