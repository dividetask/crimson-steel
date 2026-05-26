# Menu Layout and Pages

Defines the website's top navigation menu and the set of pages it links to. The DM/player split is the identification rule described in `CLAUDE.md` (loopback request = DM, anything else = player).

## Menu bar

The menu bar sits at the top of every page. It matches the page content's width (centered, with the same maximum width as `.page`) and has a solid black background. Its contents lay out in a single horizontal row.

The bar has two regions:

1. **Menu items** (left) — the links listed in the next section, in the listed order.
2. **Right-aligned group** — pushed to the far right of the bar, in this order:
   - **View-As toggle** (DM only) — When the DM is currently viewing the site as a DM, the button reads `View As Player`; pressing it switches the session to the player view and the button label flips to `View As DM`. Pressing it again returns to the DM view. Players never see this button.
   - **Server address** — the server's IP address (and port, if non-default), shown as plain text at the far-right edge of the bar, immediately to the right of the View-As toggle.

When a DM is viewing as a player, the menu obeys the player visibility rules for the duration of the override.

## Menu items

Listed in display order. Each item links to the page named in the next section.

| # | Label             | Destination URL    | Visible to |
|---|-------------------|--------------------|------------|
| 1 | Home              | `/`                | DM + Player |
| 2 | Character Sheets  | `/character-sheets`| DM + Player |
| 3 | Scene             | `/scene`           | DM + Player |
| 4 | Store             | `/store`           | DM + Player |
| 5 | Notes             | `/notes`           | DM + Player |
| 6 | Social            | `/social`          | DM + Player |
| 7 | Status            | `/status`          | DM only    |

`Home` always points at the website root (`/`). The root is not a page in its own right — it immediately redirects to `/character-sheets`, which is the default landing page. Clicking `Home` therefore lands the viewer on Character Sheets.

## Pages

Each page is listed with a short description and its access rule. Detailed page content is defined elsewhere; this section only fixes which viewers may reach each page.

| Page              | URL                | Description                                                                 | Access     |
|-------------------|--------------------|-----------------------------------------------------------------------------|------------|
| Character Sheets  | `/character-sheets`| Per-character sheets for the party. The default landing page.               | DM + Player |
| Scene             | `/scene`           | The current scene the party is in — environment, present creatures, etc.    | DM + Player |
| Store             | `/store`           | Items currently for sale.                                                   | DM + Player |
| Notes             | `/notes`           | Shared and per-character game notes.                                        | DM + Player |
| Social            | `/social`          | Social-encounter information.                                               | DM + Player |
| Status            | `/status`          | DM operations surface — currently hosts the Check Resolution Stub and the Dice Resolution Roll Stub for inspection, fed with dummy data. | DM only |

A player who attempts to navigate to a DM-only URL is treated as if the page did not exist for them; the application is free to redirect them to the default landing page or render a not-available response. A DM viewing as a player is, for access purposes, a player.

## Status page layout

The Status page has its own internal left-hand navigation that switches the right-hand content pane. The left nav sits flush against the left edge of the page content (below the global top menu bar) and lists four entries, top to bottom:

1. **Status** — the default landing pane for `/status`. Shows a brief description and acts as a hub.
2. **Dice Resolution** — the right pane renders the Roll Resolution Stub (see `docs/common/ui/dice_resolution_roll_stub.md`) for each example Roll, with each Roll inside its own demo Rolls wrapper.
3. **Check Resolution** — the right pane renders the Check Resolution Stub (see `docs/common/ui/check_resolution_stub.md`) with one shared Rolls wrapper containing multiple example Rolls (Supporting and Opposing sides separated by a divider).
4. **Conditions** — the right pane renders the Conditions Downtime PC Card Stub (see `docs/common/ui/conditions_downtime_pc_card_stub.md`) for each example player Creature. The stub runs on example data; the panel emits no real state changes.

The currently-selected nav entry is visually highlighted.

Navigation between the three sub-views happens within `/status` — the global menu's `Status` link returns the viewer to the default sub-view. The sub-views may be addressed by an implementation-chosen mechanism (query string, sub-path, fragment, etc.); the rule is that the global URL remains under `/status`.

Both stubs are supplied with dummy data for now; the stubs themselves are the deliverable. Real data wiring is out of scope for this page. The Rolls wrapper's Roll All button populates the dice in every embedded Roll. Its Confirm All button is intentionally a no-op at this layer — parent stubs that embed these are responsible for capturing the confirmed output.
