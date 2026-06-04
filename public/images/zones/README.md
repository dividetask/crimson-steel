# Zone textures

Image fills for spell-area Zones on the Atlas map. A spell's `area.texture`
key (in `docs/common/abilities/spells.yaml`) names the file: texture `web`
renders `/images/zones/web.png`, clipped to the Zone's shape. A Zone with no
`texture` (or a missing file) falls back to a solid **purple** fill.

## Files to add (PNG with transparency, roughly square)

| File          | Spell           | Source image shared        | Status |
|---------------|-----------------|----------------------------|--------|
| `web.png`     | Web             | black spider web           | wired  |
| `entangle.png`| Entangle        | green tangle of vines      | wired  |
| `mist.png`    | Obscuring Mist  | grey cloud / fog           | wired  |
| `grease.png`  | Grease          | oily rainbow slick         | mapping ready — Grease's area is an aspect list and isn't auto-placed on the map yet |

Drop the four shared images here under those exact names. Any other area spell
(Darkness, Silence, Create Pit, …) currently has no `texture` and renders as the
purple fallback until one is assigned in `spells.yaml`.
