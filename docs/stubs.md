# Stub Inventory

A working list of the reusable UI stubs needed to recreate the pages from the
`before-refactor` branch. Each stub is a flexible, self-contained partial plus
an optional Ruby helper (same pattern as `stubs/roll_stub.rb` +
`views/stubs/_roll_stub.erb`). Most stubs take the data they render as
arguments so they do not depend on a specific page context.

Legend:
- **DM-only**: only rendered when `dm?` is true.
- **DM-gated content**: always rendered, but hides sensitive fields for
  non-DM viewers.
- **Player-scoped**: rendered only when the viewer is assigned to the
  character being shown (or is the DM).

## Framework-level

- `layout` stub — top-level menu, lightbox, view-mode toggle. Already
  partially present in `views/layout.erb`; needs a DM/player toggle row and
  a character-picker when unassigned.
- `menu_stub` — top nav with links. Adjusts which entries render based on
  `dm?` (Enemies, Combat, Add Item) vs. player (Character Sheet, Scene,
  Notes, Downtime, Store, Magic).
- `view_mode_toggle_stub` — DM-only. Lets the DM preview the site "as a
  player" without dropping their role.
- `character_picker_stub` — shown when the current device has no
  character assigned. Lists PCs and posts to `/user/assign_character`.
- `public_view_stub` — fallback content shown to non-DM viewers with no
  assigned character (scene + public notes only).
- `lightbox_stub` — zoomable image viewer. Already part of the current
  layout; lift into its own stub for reuse.

DM detection: any request whose IP matches the server is the DM.
There is no claim flow and no per-device DM record.

## Character sheet (`/character/:index`)

- `character_nav_stub` — prev/next arrows + "N / total" counter.
  Parameterized by route prefix so it works on enemies too.
- `character_header_stub` — name, race/class, tier line, BAB.
- `stat_grid_stub` — rows of labeled stat boxes (combat pool, perception,
  initiative, HP, mana, etc.). Accepts an array of `{label, value, css_class}`.
- `combat_table_stub` — weapons + shields + dodge row. DM-gated (hides
  some enemy fields when rendered for non-DM viewers).
- `attributes_table_stub` — attribute scores, checks, saves.
- `skills_table_stub` — skill ranks, dice, bonus.
- `items_section_stub` — tattoos, equipped, ammunition, consumable,
  other, item descriptions. Player-scoped.
- `abilities_section_stub` — ability list with descriptions.
- `spell_section_stub` — renders spell list / item spells / ritual
  spellbook given a structured input.
- `notes_section_stub` — collapsible note list + "add note" form.
  DM-gated (private notes hidden from non-owners).
- `note_item_stub` — single note with show-more/show-less toggle and
  DM-only metadata footer.

## Magic (`/spells`, `/spell/:name`)

- `spell_filter_stub` — school / tier / skill filter controls.
- `spell_table_stub` — rows of spells with link to detail.
- `spell_detail_stub` — full detail card (range, duration, casting time,
  save, description, per-tier breakdown).
- `spell_link_stub` — inline anchor rendering, used inside character
  sheet and notes.

## Store (`/store`)

- `gold_display_stub` — party gold indicator. DM can edit.
- `store_filter_sidebar_stub` — category + tier checkboxes, clear button.
- `store_grid_stub` — grid container for items.
- `store_item_stub` — single item card (name, type, tier, price).
- `store_item_variant_stub` — item card with variant selectors and
  resolved-price preview.
- `purchase_form_stub` — owner selector + buy button. DM-only.
- `store_alert_stub` — insufficient_gold / already_known / success
  flash.

## Notes (`/notes/:viewer_id`)

- `chapter_filter_stub` — chapter pills with active state.
- `notes_section_stub` (reused) — for DM notes / per-character notes.
- `note_editor_stub` — add/edit note form. DM-gated fields: chapter,
  public flag, active flag, draft flag.

## Downtime (`/downtime`)

- `downtime_card_stub` — per-PC card: header, HP/Mana/Saturation bars
  with the stat-color ramps, consumables, downtime actions.
- `stat_bar_stub` — reusable colored bar for HP/Mana/Saturation etc.
  (good-ramp and bad-ramp variants).
- `consumable_list_stub` — consumables currently available for a PC.
- `gold_display_stub` (reused).

## Scene (`/scene/:viewer_id`)

- `scene_header_stub` — title + optional image + description.
- `scene_initiative_stub` — initiative table. PC entries show HP; enemy
  entries hide HP/names behind abstracted bars for players (`scene_hp_bar_stub`).
- `scene_hp_bar_stub` — colored bar / "Down" indicator for enemy rows
  when viewed as a player.
- `scene_controls_stub` — DM-only controls to advance rounds / end combat.

## Enemies (`/enemies/*`) — DM-only

- `enemy_sidebar_stub` — grouped, collapsible enemy list with
  add/remove-from-combat buttons.
- `enemy_entry_stub` — single row in the sidebar with copy count.
- `enemy_template_stub` — template detail view (uses `character_header_stub`,
  `stat_grid_stub`, `combat_table_stub`, `abilities_section_stub`).
- `enemy_instance_stub` — combat-copy detail view with live HP editor.

## Combat tracker (`/combat`) — DM-only

- `combat_tracker_stub` — full table with initiative, HP, damage
  trackers, mana, dice, saturation, conditions.
- `combat_row_stub` — single participant row, conditional styling
  (current turn, incapacitated).
- `hp_editor_stub` — inline form to apply damage, temp HP, conditions.
- `initiative_roll_stub` — "Roll" button when initiative is blank.
- `turn_control_stub` — set-turn, start-of-turn, end-of-turn buttons.
- `active_effects_stub` — list of active effects with round countdown.

## Add Item (`/add_item`) — DM-only

- `item_form_stub` — owner picker + type/subtype cascade + name, bonus,
  quantity, equipped.
- `type_subtype_cascade_stub` — the JS-backed type→subtype dropdown (if
  we want it reusable across forms).

## Shared / primitives

- `dice_stub` — already exists (`roll_stub`). Keep as-is.
- `alert_stub` — flash message (error / warning / success).
- `collapsible_section_stub` — generic show/hide panel.
- `table_stub` — generic table wrapper so styling stays consistent.
- `form_row_stub` — labeled input wrapper to standardize forms.

## Rendering rules cheat-sheet

| Stub                      | DM sees         | Player sees                |
|---------------------------|-----------------|----------------------------|
| `menu_stub`               | full menu       | subset (no Combat/Enemies) |
| `character_sheet` stubs   | any character   | only their assigned PC     |
| `notes_section_stub`      | all notes       | public + own notes only    |
| `scene_initiative_stub`   | HP numbers      | HP bars for enemies        |
| `enemy_*`                 | visible         | not rendered               |
| `combat_tracker_stub`     | visible         | not rendered               |
| `store_stub` purchase     | can buy         | read-only                  |
