# Android App

A native Android client for Crimson Steel DM Tools. It has its own GUI (not a WebView) and gets everything from the Ruby server over the local Wi-Fi network. It is a **player** device: it shows one Character, the one the DM assigned to it.

The Gradle project lives in `android/` and is built by `build_branches.sh` (see the claude-basics repository). Built APKs are committed to `android/versions/`.

## Connecting

The app never asks for an IP address, and never probes other devices on the network one by one. It tries, in order:

1. **The last server** it used (remembered on the phone).
2. **Broadcast discovery.** The app broadcasts a UDP probe, `CRIMSON_STEEL_DISCOVER 1`, to port **47567** on every Wi-Fi subnet broadcast address and on `255.255.255.255`, up to three times. The server answers with JSON: `{"service":"crimson-steel","version":1,"http_port":4567,"name":"<campaign name>"}`. The reply's source address is the server's address. See `lib/lan_discovery.rb`.

If both fail the app shows *No server found* with **Search again** (and, when the phone has a VPN on, a note that the VPN may be in the way). If the connection drops later, it searches again by itself.

**VPNs and firewall apps.** The app always uses the phone's normal network route and never routes around a VPN. Firewall apps such as NetGuard work as a VPN: Android sends every app's traffic into their tunnel (`tun0`), and they drop what the player has blocked. If Crimson Steel is blocked there, broadcast discovery may still get a reply — Android sends local broadcasts (`255.255.255.255`) straight out on Wi-Fi, outside the tunnel — but the web connection that follows is blocked, and the app shows *No server found* with a note that a VPN or firewall app is on. The player allows Crimson Steel in the firewall app. Settings shows whether a VPN is on (`LocalNetwork`, `ACCESS_NETWORK_STATE` permission).

The server starts the UDP responder when run with `ruby app.rb`, and from `config.ru` when started with rackup or puma (set `CRIMSON_STEEL_HTTP_PORT` if you pass rackup a different `-p`). It uses Ruby's standard library only, and prints one line per probe it answers — `[discovery] probe from <phone address> — told it to use port 4567` — so the DM can see whether a phone's search arrives.

The server and the phone must be on the same network. Guest networks with "client isolation" block discovery. A firewall on the server must allow UDP 47567 (discovery) and TCP 4567 (the web server).

## Which Character the app shows

The app is identified exactly like a browser, by the server-issued `crimson_device_id` cookie ([device_assignment.md](device_assignment.md)), which it saves and sends on every request. Until the DM assigns the device a Character on the web **Status** page, the app shows *Waiting for the DM to assign this device a character* with the device's short id. It re-checks every few seconds.

A request from the app is never the DM: it does not come from the server host's loopback address.

## Layout

- A bar at the top of every screen, as in the Sudoku Trainer: the **character name** on the left (or *Crimson Steel* before a Character is assigned), the app version small and grey so screenshots show which build they came from, and a **gear** button that opens Settings.
- A tab row under it selects one of five screens:
  - **Sheet** — the character sheet.
  - **Initiative** — the Combat Pool, the turn order, and on the player's turn their action options (see *Initiative screen*).
  - **Items** — the inventory (see *Inventory screen*).
  - **Notes** — the Chronicle notes this Character can see, grouped by chapter. Tap a note to expand it.
  - **Scene** — the current chapter, the in-game time, and the Chronicle entries the DM has made active (scene notes and the characters present).

The gear is also on the *Looking for the server*, *No server found* and *Waiting for the DM* screens, so the debug log can be saved when the app can't connect.

The screen on display is refreshed from the server: Initiative every 2 seconds, Sheet / Items / Scene every 5, Notes every 10. A screen is only rebuilt when the server's answer changed.

## Player visibility

The API answers only for the assigned Character and uses the same rules as the web pages for players:

- The initiative list carries names and turn order only. No HP, Mana, Toxicity or Conditions are sent for any combatant.
- Notes and scene entries are filtered per Character (`visible_to`). Only the public text is sent, never `dm_description`.

## Character sheet

Shows vitals (HP, Mana, magic toxicity, Damage Reduction, Damage Resilience), the six Attributes, every Skill, and the character's Abilities.

Rollable entries:

- Each Attribute has a **Check** and a **Save**, each shown with its Dice Count and TN.
- Each **Skill**.

The server computes every Roll's Dice Count, final TN and Starting Value (Proficiencies, Dice Resolution, and the Character's items and active Modifiers), so the app and the web sheet always agree. The app only throws and scores the dice ([dice_resolution_design.md](../common/dice_resolution/dice_resolution_design.md)). The full Dice Cap is always rolled from the sheet; only combat actions let the player commit fewer dice.

Abilities are descriptive only (tap to expand) and are not rollable.

## Rolling

1. Tapping a rollable entry asks whether this is a **Public roll** or a **Test roll**.
2. The roll dialog shows d10s tumbling onto the screen and settling on their values, colored by state (Failure red, Success green, Critical Success blue, Neutral plain — the web sheet's colors).
3. The result line shows the Degree of Individual Success, the Roll Outcome, and the Critical Count.

| | Public roll | Test roll |
|---|---|---|
| Sent to the DM's Roll Log | Yes — `POST /dm/roll`, the same fields the web sheet's compact roll sends | Never; not shared with anyone |
| Can be rolled again from the dialog | No — one roll, like the web sheet's compact roll | Yes |

The public roll's badge reads *sent to DM* once the server confirms it, or *NOT sent* if it could not reach the server.

## Initiative screen

This is the player's half of the web app's Turn Action Stub ([turn_action_stub.md](../common/ui/turn_action_stub.md)): the player picks an action and how many dice to commit. Targets, defenses, rolling and applying the result stay with the DM.

Top to bottom:

1. **Combat Pool** — one small d10 per Combat Pool die. Remaining dice are filled, spent dice are hollow. The fill color depends on how much of the pool is left: more than half green, a quarter to a half amber, under a quarter red. Below it: Main Actions left this turn and Mana. The dice shown subtract this turn's pending requests (see below).
2. **Initiative order** — the round and every combatant, with the acting one highlighted. On the player's turn the list compacts to a single row, `<name> (you) — Your turn`; tapping it shows the full list, and *Hide initiative* compacts it again.
3. **Action options** (player's turn only) — grouped under **Main Action**, **Bonus Action** and **Free Action**; an empty group is not shown.

"The player's turn" means the party's Phase is Combat, combat is running, and the player's Combatant is the acting one. When there is no combat the screen says so.

The options come from the same server code that builds the DM's turn menu (`api_turn_options` in `lib/routes/api.rb` reuses the Attack, Cast, Item and Special builders), so they match what the DM can pick:

| Option | Group | Dice | Combat Pool cost | Mana |
|---|---|---|---|---|
| Attack: `<weapon>` (one per equipped weapon, natural attack, and Unarmed) | Main | 2 up to the weapon's Martial Dice Cap | weapon Speed + dice | — |
| Move | Main | — | Move Cost (4) | — |
| Cast: `<spell>` (known spells and spells from an equipped Wand or Ring) | the spell's activation | rolled spells: Action Minimum (Main 4 / Bonus 2) up to the casting skill's Dice Cap | dice (no-roll spells: the Action Minimum) | Mana Cost Per Tier |
| Use: `<potion or scroll>` | the spell's activation | as Cast | as Cast | — |
| `<Ability>` with a free / bonus / main activation (e.g. Rage, Bardic Inspiration) | its activation | channeled Abilities: the Action Minimum up to the pool | Action Minimum (Free 0, Bonus 2, Main 4) | the Ability's `mana_cost` |
| `<Spell> (conc)` for each active persistent Spell | Main | — | — | — |
| End Turn | Free | — | — | — |

Spells that take a minute or longer to cast are not offered, as on the web.

### Requests

**Attacks** are different: they run step by step — the target chooses a defense on their own phone, allies and Luck holders are asked, everyone rolls on their phone, and the DM approves each step and finishes it in the pre-filled Attack builder. See [action_flow.md](action_flow.md). Everything else below is a plain request.

Tapping an option opens it: a dice-count picker (counts the pool can't afford are disabled), then **Request**. A request **spends nothing**. It is sent to the server (`POST /api/turn/requests`), listed under *Requested this turn* with an **Undo last** button, and shown to the DM in a **Player requests** box at the top of the turn panel on the web Encounter page. The DM resolves it with the normal Attack / Move / Cast / Item / Special flow, which does the spending, or presses **Dismiss**.

Requests belong to the turn they were made in. Once the turn moves on they disappear. They are kept in memory, so restarting the server clears them.

The server rejects a request when it isn't the player's turn, the option is unknown or unaffordable, or the dice count isn't one of the choices. The app additionally greys out options that this turn's pending requests have already used up: Combat Pool, Mana, and the two Main Actions.

**End Turn** asks for confirmation and sends an *End Turn* request; the DM advances the turn.

## Inventory screen

The same three sections and actions as the web sheet's inventory stub ([equipment_inventory_stub.md](../common/ui/equipment_inventory_stub.md)), through the same web routes:

| Section | Actions |
|---|---|
| Equipped | **Unequip** (`/inventory/unequip`) |
| Carried | **Equip** for equippable items (`/inventory/equip`); **Discard** to the Sell Pile, asking how many when the stack has more than one (`/inventory/discard`) |
| Sell Pile | **Claim**, asking how many (`/inventory/claim`); **Equip** to claim one and equip it (`/inventory/claim_equip`) |

The Sell Pile's **Delete** stays DM-only, as on the web.

## Settings

Reached from the gear at the top of every screen. **Done** (or back) returns to where the player was.

| Section | Contents |
|---|---|
| App | The version (`BuildConfig.VERSION_NAME`, e.g. `v0.006 a (1a2b)`). |
| Connection | The server address, the device id (the first 8 characters, as in the DM's device table), the assigned Character, whether a VPN is on, and this phone's network addresses. **Search for the server again** forgets the remembered server and searches from scratch. |
| Debug log | **Save debug log** saves a copy as `crimson-steel-debug-<date>-<time>.log` in the phone's **Downloads** folder (Android 10+: straight into Downloads, no permission; Android 8–9: the system "save as" picker). There is no share sheet. **View log** shows the newest 300 lines on screen. **Clear log** empties it, after a confirmation. |

## Debug log

A plain-text file in the app's private storage (`debug.log`), one line per event: `yyyy-MM-dd HH:mm:ss.SSS [tag] message`. It is capped at 512 KB; past that the oldest half is dropped. Lines are also written to logcat.

What is logged:

- `session` — app start (version, Android release, phone model), each search step and its result, the connection (server, campaign, device id, Character), forgetting the server.
- `discovery` — the phone's network interfaces and broadcast addresses, every probe sent (or the error), every reply received, and timeouts.
- `http` — every request that fails or changes status, and every POST (turn requests, inventory actions, public rolls), with the status and time taken; the device id the first time the server issues it. Repeated polling GETs with an unchanged status are not repeated in the log.
- `main` — which screen is showing (searching, no server, waiting, playing), losing the server, being unassigned.
- `crash` — any uncaught exception, with its stack trace, before the app closes.

The saved file starts with a header: the version, Android release and phone model, the server, device id and Character, whether a VPN is on, the phone's network addresses, and the time it was saved. Nothing secret is logged; the device cookie only ever appears as its first 8 characters.

## API

All endpoints answer JSON for the device's assigned Character, or `409 {"error":"unassigned"}` before the DM assigns one. Implemented in `lib/routes/api.rb`.

| Endpoint | Returns / does |
|---|---|
| `GET /api/hello` | Server identity, campaign name, the device's short id, and the assigned Character (or `null`). |
| `GET /api/sheet` | The character sheet with server-computed Rolls. |
| `GET /api/inventory` | Equipped, carried and Sell Pile rows, as the web inventory stub shows them. |
| `GET /api/initiative` | Combat state, turn order (no vitals), the player's pool / Main Actions / Mana, and on their turn the options and this turn's requests. |
| `POST /api/turn/requests` | Body `{ "key": "<option key>", "dice": <n> }`. Records a request for the DM. |
| `POST /api/turn/requests/:id/delete` | Withdraws one of this turn's requests. |
| `GET /api/prompts`, `POST /api/prompts/:flow_id/:task_id` | Attack steps waiting on this player, and answering one ([action_flow.md](action_flow.md)). |
| `GET /api/notes` | Chronicle entries visible to the Character (public text only), with chapter names. |
| `GET /api/scene` | Current chapter, in-game time, and the active Chronicle entries visible to the Character. |
| `POST /encounter/player_requests/:id/dismiss` | DM only: dismiss a request from the turn panel. |

## Not yet decided

- How a device is assigned to the DM, so the DM can use the app (see [device_assignment.md](device_assignment.md)).
- Images for notes and scene entries.
- Rerolls and Nudges.
- What the player sees after the DM resolves a request (for example the result).
