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
| 3 | Encounter         | `/encounter`       | DM + Player |
| 4 | Store             | `/store`           | DM + Player |
| 5 | Notes             | `/notes`           | DM + Player |
| 6 | Social            | `/social`          | DM + Player |
| 7 | Compendium        | `/compendium`      | DM + Player |
| 8 | Status            | `/status`          | DM only    |

`Home` always points at the website root (`/`). The root is not a page in its own right — it immediately redirects to `/character-sheets`, which is the default landing page. Clicking `Home` therefore lands the viewer on Character Sheets.

## Pages

Each page is listed with a short description and its access rule. Detailed page content is defined elsewhere; this section only fixes which viewers may reach each page.

| Page              | URL                | Description                                                                 | Access     |
|-------------------|--------------------|-----------------------------------------------------------------------------|------------|
| Character Sheets  | `/character-sheets`| Per-character sheets for the party. The default landing page.               | DM + Player |
| Encounter         | `/encounter`       | What is happening right now — timekeeping, the Combat Tracker (initiative), and the active scene's notes. The Combat Tracker is hidden from players until Combat starts; the notes are hidden from players once Combat starts. | DM + Player |
| Store             | `/store`           | Provision Creatures with gear — the Equipment Provision Stub (Weapons, Armor, Alchemy). A recipient that is a Player Character is charged (its own wealth first, then the Party); non-PCs are provisioned free. Enemies are hidden from players. | DM + Player |
| Notes             | `/notes`           | Shared and per-character game notes.                                        | DM + Player |
| Social            | `/social`          | Social-encounter information.                                               | DM + Player |
| Compendium        | `/compendium`      | Reference material drawn from the rules documents — currently the Glossary. | DM + Player |
| Status            | `/status`          | DM operations surface — currently hosts the Check Resolution Stub and the Dice Resolution Roll Stub for inspection, fed with dummy data. | DM only |

A player who attempts to navigate to a DM-only URL is treated as if the page did not exist for them; the application is free to redirect them to the default landing page or render a not-available response. A DM viewing as a player is, for access purposes, a player.

## Compendium page layout

The Compendium page has its own internal left-hand navigation that switches the right-hand content pane. The left nav sits flush against the left edge of the page content (below the global top menu bar) and currently lists:

1. **Glossary** — the default landing pane for `/compendium`. The right pane renders the union of every glossary in `docs/common/` (`common_glossary.md`, `dice_resolution/dice_resolution_glossary.md`, `check_resolution/check_resolution_glossary.md`, `conditions/conditions_glossary.md`). Each source becomes its own group with the common glossary listed first; within a group, the source's `##` headings become subsections and each `**Term**: definition` paragraph becomes a definition-list entry.
2. **Dice Resolution** — a player-facing chapter explaining how a single Roll works (Dice Count, TN, Bonuses/Penalties, Reroll/Nudge, DoIS, Roll Outcome). Sourced from `docs/common/dice_resolution/dice_resolution_explainer.md` and rendered through kramdown. Embedded Mermaid (```` ```mermaid ```` fenced blocks) and inline `.die` spans render the resolution-pipeline diagram and dice examples respectively.

Additional chapters (Check Resolution, Conditions, etc.) follow the same explainer pattern: a `*_explainer.md` next to the existing design/test docs, registered in `lib/explainer_docs.rb`, automatically appearing in the Compendium left-nav.

The layout follows the same convention as the Status page (highlighted active entry, sub-views addressed by an implementation-chosen mechanism, global URL stays under `/compendium`). The Mermaid client-side renderer is loaded only on pages that contain a Mermaid block.

The Compendium is visible to both DMs and players.

## Status page layout

The Status page has its own internal left-hand navigation that switches the right-hand content pane. The left nav sits flush against the left edge of the page content (below the global top menu bar) and lists six entries, top to bottom:

1. **Status** — the default landing pane for `/status`. Shows a brief description and acts as a hub.
2. **Dice Resolution** — the right pane renders the Roll Resolution Stub (see `docs/common/ui/dice_resolution_roll_stub.md`) for each example Roll, with each Roll inside its own demo Rolls wrapper.
3. **Check Resolution** — the right pane renders the Check Resolution Stub (see `docs/common/ui/check_resolution_stub.md`) with one shared Rolls wrapper containing multiple example Rolls (Supporting and Opposing sides separated by a divider), followed by three example Conditions Save Resolution Stubs (see `docs/common/ui/conditions_save_resolution_stub.md`) — each wrapping the Check Resolution Builder Stub (see `docs/common/ui/check_resolution_builder_stub.md`) over a sample Affliction save (Bleed vs Tier 3 with Bardic Inspiration, Poison vs Tier 1 with Bardic Inspiration, Bleed vs Tier 2 with no Reroll).
4. **Conditions** — the right pane renders the Conditions Downtime PC Card Stub (see `docs/common/ui/conditions_downtime_pc_card_stub.md`) for each example player Creature. The stub runs on example data; the panel emits no real state changes.
5. **Timekeeping** — the right pane renders the Timekeeping Stub (see `docs/common/ui/timekeeping_stub.md`) once per example Timestamp, stacked vertically. The examples vary the Time of Day across early morning, dawn, midday, dusk, midnight, and a Leap Day to show the sky's day/night transitions and the sun/moon's arc across the full width of the stub.
6. **Chronicle** — the right pane renders the Chronicle Entry Stub (see `docs/common/ui/chronicle_entry_stub.md`). Five example Entries are rendered twice: first under a **DM View** heading, then again under a **Player View** heading using a player viewer (Bryn, Creature id 1). The five Entries cover a shared Note with a long public description, a private GM Note with a long DM-only description, a shared Note with long content in both descriptions, a Creature Reference with an image, and a player-owned shared Note (whose owner can edit it under both views). Each example is labeled above the card so reviewers can compare what does and does not render for each viewer role.
7. **Equipment** — the right pane renders the Equipment Store Stub (see `docs/common/ui/equipment_store_stub.md`) on hand-curated sample stock. The selectors and Buy buttons are inert here (`purchasable: false`); the live, purchasable version of the same stub is the `/store` page.

The currently-selected nav entry is visually highlighted.

Navigation between the three sub-views happens within `/status` — the global menu's `Status` link returns the viewer to the default sub-view. The sub-views may be addressed by an implementation-chosen mechanism (query string, sub-path, fragment, etc.); the rule is that the global URL remains under `/status`.

Both stubs are supplied with dummy data for now; the stubs themselves are the deliverable. Real data wiring is out of scope for this page. The Rolls wrapper's Roll All button populates the dice in every embedded Roll. Its Confirm All button is intentionally a no-op at this layer — parent stubs that embed these are responsible for capturing the confirmed output.
