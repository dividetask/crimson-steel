# Scene Page

The `/scene` view aggregates everything the table sees during play: PCs, NPCs, panels, images, the date/time, and the active map. The branch reworked layout, visibility, and interactions extensively.

## Glossary

- **Panel** — A scene element (note, image, NPC card) the DM can show or hide.
- **Visibility** — Per-panel and per-character: which viewers can see this element. Toggleable as `Hidden` / `Visible`, or per-PC via `visible_to` lists.
- **Reminder Banner** — Collapsible banner above the date that surfaces important reminders when initiative is hidden (out of combat).
- **Draft Name** — A pending NPC name the DM has staged but not yet promoted into a full character record.
- **CoI** (Character of Interest) — A panel-style entry highlighting a single character with portrait and notes.
- **Per-PC Visibility on Cells** — Each grid cell can mark itself visible to only specific PCs.

## Design

### Visibility

- `POST /scene/panel/toggle_visible_to` toggles a panel's visibility for a specific viewer.
- `POST /scene/character/toggle_scene_visible_to` toggles per-PC for a character panel.
- Bulk: `/scene/character/scene_visible_all`, `/scene/character/scene_visible_none`, `/scene/panel/visible_to_all`, `/scene/panel/visible_to_none`.
- The Hidden/Visible status now appears **above** the note text (not below) so the DM sees state at a glance.
- CoI image controls fold into the same details element as the visibility toggle, reducing clutter.

### Layout

- Panels can be drag-reordered (`POST /scene/reorder`).
- Portraits no longer crop — they letterbox to fit.
- Notes longer than 200 characters collapse by default, expandable on click.
- The active map renders inside its own editor model on `/scene` (read-only when not on `/maps`).
- Grid cells are bound to track width so cells stay square as the page resizes.

### Reminder Banner

When initiative is hidden (combat not active), a Reminder banner is available above the date. The DM can write a short reminder string. The banner is collapsible and saves its expanded/collapsed state.

### Draft Names

`POST /scene/draft_names_bulk` accepts a list of names; subsequent endpoints update, delete, or promote a draft into a full character. Promotion reuses the standard add-character flow.

### Date/time advance

`POST /scene/datetime/advance` advances the game-time clock. `POST /scene/toggle_initiative` switches between out-of-combat (Reminder banner area) and in-combat (initiative tracker) modes.

## Cross-domain interactions

- Maps render via [scene-maps.md](scene-maps.md).
- Notes live in [notes-and-images.md](notes-and-images.md).
- Per-PC visibility on grid cells is part of the map cell schema in [scene-maps.md](scene-maps.md).
