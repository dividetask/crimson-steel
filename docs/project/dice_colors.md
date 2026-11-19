# Dice Colours

Every roller's dice have their own colour, and everyone sees the same colours: on the Android app's roll cards and dice table ([action_flow.md](action_flow.md)), and on the app's own Skill rolls ([android_app.md](android_app.md)).

## The colours

Dice are light, soft colours; none of them is red or green. The **number** on a stopped die shows what it counts for:

| Die | Number |
|---|---|
| Success (TN or higher) | dark green |
| Critical Success (a 10) | deep blue |
| Critical Failure (a 1) | dark red |
| No effect (below TN) | dark grey |

While a die is still tumbling its number is dark grey.

There are 13 colours: Sky, Lavender, Peach, Butter, Aqua, Orchid, Sand, Periwinkle, Ice, Steel, Cream, Blush, and Light grey.

## Who gets which

- **Each player Character** gets its own colour automatically the first time one is needed: the first of the list (Light grey excluded) that nobody has.
- **The DM's dice** start **Light grey**. They are used for every Roll that belongs to no player Character: enemies, NPCs, and any other Roll the DM owns. A Roll the DM rolls *for* a player keeps that player's colour.
- **Nobody can pick a colour someone else already has.**

## Changing a colour

- **Players:** in the app's **Settings → Dice colour**. Colours other people have are greyed out and show who has them.
- **The DM:** on the **Status** page, under **Dice colours**: their own colour, and any player Character's (e.g. for a player without the app).

## Implementation

- `lib/dice_colors.rb` — the palette and the assignments, kept in `data/dice_colors.json` (`{ "dm": "silver", "<character id>": "sky" }`).
- `GET /api/dice_colors` (the player's colour and every colour, with who has each, by name) and `POST /api/dice_color` (`{ "color": "<key>" }`; 409 when taken). `/api/hello` carries the player's `dice_color`.
- `POST /dice_colors` (DM only) — the Status page's picker.
- Every Roll on a roll prompt (`all_rolls`) carries its owner's `color` as `#RRGGBB`.
