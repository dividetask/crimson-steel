# Device Tracking and Character Assignment

Crimson Steel identifies a *viewer's role* (DM vs. player) purely from where the request originates — see `CLAUDE.md` and [menu_layout.md](menu_layout.md). That rule answers "is this the DM?" but it does not answer "**which** player Character is this person?". A household may have several player devices on the LAN, and each player wants the site to open on their own sheet.

Device tracking fills that gap. The server remembers every device that connects and lets the DM bind a player Character to each one, so a returning device lands on its assigned sheet by default.

## Device identity

Identity is a per-device cookie, independent of the DM/player rule:

- On a device's first request the server mints a random UUID and sets it in a long-lived `crimson_device_id` cookie (`HttpOnly`, root path, multi-year expiry).
- Subsequent requests present the cookie, so the server recognizes the device.
- DM-vs-player is **not** stored on the device record. It is still derived from the request origin on every request (loopback = DM). The same physical machine is always the DM regardless of its device record.

The lookup runs in a `before` filter (see `lib/routes/devices.rb`) so any device that loads any page is recorded the first time it is seen and has its `last_seen` refreshed on return. Static assets do not trigger it.

## Device Registry

The `DeviceRegistry` class (`lib/device_registry.rb`) owns the device list and persists every mutation to `data/devices.json` (gitignored, like the other `data/` state files). Each record holds only what is needed to recognize the device and resolve its default sheet:

| Field          | Meaning                                                            |
|----------------|-------------------------------------------------------------------|
| `device_id`    | The UUID from the cookie (the primary key).                       |
| `character_id` | The assigned player Character's id, or `null` when unassigned.    |
| `last_seen`    | ISO-8601 timestamp of the device's most recent request.           |

A brand-new registry seeds two demo devices (`demo-phone`, `demo-tablet`) so the Devices stub has rows to show before any real player connects. The stub shortens device ids to eight characters for display, so these render as `demo-pho` and `demo-tab`.

## Device Assignment Stub

The Status page's default landing pane ([menu_layout.md](menu_layout.md), Status page layout) renders the assignment table from `views/_assignment_stub.erb`. Columns:

- **Device** — the eight-character id preview; the viewing device is badged **this device**.
- **Last Seen** — the formatted `last_seen` timestamp.
- **Assigned Character** — the bound Character's name, or *unassigned*.
- **Change** — a per-row form (a Character dropdown plus a Save button) that posts to `/devices/assign`.

The dropdown is populated from the live player Characters (those tagged `player_character`). Choosing `(unassign)` clears the binding.

`POST /devices/assign` is gated on the DM host (loopback): a player device cannot reassign itself or anyone else. It takes a `device_id` and a `character_id` (empty = unassign), writes through the registry, and redirects back.

## Character Sheets default

On the Character Sheets page (`lib/routes/character_sheets.rb`):

- A player device with an assigned Character opens on that Character's sheet by default.
- The default applies only to a bare visit. Once the player pages with the Prev/Next arrows or jumps to an explicit Character, that choice wins — players can still scroll through every player Character.
- If the assigned Character is not in the player's roster (e.g. the assignment was cleared), the page falls back to the first player Character, exactly as it did before assignment existed.
- The DM is unaffected: the DM navigates every Creature through the roster sidebar.
