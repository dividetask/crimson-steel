# Branch — implement-roll-class-gbLWb

Snapshot of work done on `claude/implement-roll-class-gbLWb`. The branch absorbed work from several deleted feature branches; the inventory below covers the union of all functionality.

The branch lifecycle: 191 commits of feature work were merged, then a follow-up cleanup branch (`CLEANUP-V0`) reorganized docs and reverted some scaffolding. The original feature work is preserved at `claude/implement-roll-class-gbLWb-pre-revert`. This document describes what was built across that whole arc.

## Feature index

Each entry links to a short feature file under `features/`. UI specs live in `ui/`. Shared rule data (races, classes, conditions, spells, loot tables) lives in `../common/data/` rather than this branch's folder.

- [features/scene-maps.md](features/scene-maps.md) — DM scene-map editor with grid, image tokens per cell, pan/zoom viewport, image library walker, dedicated `/maps` workshop page, and player view with arrow overlay.
- [features/random-encounters.md](features/random-encounters.md) — `/combat/roll_encounter` rolls a wandering encounter table, drops the resulting creatures into combat, and posts a structured banner (per-creature gold + items as bullets).
- [features/encounter-banner.md](features/encounter-banner.md) — Cross-page banner that surfaces encounter results to the DM and stays hidden from players on `/character`.
- [features/dm-skill-check.md](features/dm-skill-check.md) — DM-only skill-check screen with TN math + dice-breakdown tooltip on hover.
- [features/character-sheet-toggle.md](features/character-sheet-toggle.md) — Per-viewer minimal/full character card toggle. `/scene` always renders minimal. Skills appear in a two-up table under Actions in the minimal layout, with a transparent spacer column.
- [features/combat-tracker.md](features/combat-tracker.md) — Set-Turn button per row, per-combatant initiative reroll, end-combat, bardic-inspiration and luck-spend actions, condition tracking (bleed including ranged attacks, ghoul paralysis), temporary hit points.
- [features/hp-mana-display.md](features/hp-mana-display.md) — Current HP/mana columns plus moderate/major damage breakdown shown on character sheets and the combat tracker.
- [features/shield-block.md](features/shield-block.md) — Shield block defense action that mirrors parry but uses shield stats.
- [features/spells.md](features/spells.md) — Spell list page, spell detail page, add-spell flow, casting-time human-readable labels, single/multi/no-target classification driving checkbox selection in cast UI. New spells: Cure (with target select + ability-damage cure cascade), Ward (grants temporary HP), Obscuring Mist.
- [features/scrolls-and-potions.md](features/scrolls-and-potions.md) — Scrolls cast with full spell semantics (no skill check, ephemeral item id). Potions are consumable on use; potions and oils skip the skill check at the store. Spells/scrolls/potions tagged `single`/`multi`/`no` target drive checkbox vs auto-cast UI.
- [features/store.md](features/store.md) — Multi-PC purchase rows (one row per PC), ritual purchase flow, scroll/potion price corrections, ephemeral item ids that don't persist between server restarts.
- [features/templates-and-enemies.md](features/templates-and-enemies.md) — Templates for commoner and aberration classes; wardog with a declared natural bite weapon. The enemies sidebar collapses each category by default and remembers collapse state across reloads. GearTable hardened against non-Hash references.
- [features/scene-page.md](features/scene-page.md) — `/scene` view: per-PC visibility on grid cells, drag-reorder of panels, Hidden/Visible UX with the status above the note text, collapsible Reminder banner above the date when initiative is hidden, CoI image controls folded into the visibility-collapse details, notes longer than 200 chars collapsed by default, draft-name promotion flow.
- [features/notes-and-images.md](features/notes-and-images.md) — Image storage attached to character notes and campaign portraits, `/notes` viewer, `_notes_images_stub` panel.
- [features/downtime.md](features/downtime.md) — `/downtime` page with cast, cast-ritual, use-item, service, rest, urgent-actions, and quick-resolve actions.
- [features/races.md](features/races.md) — Race-driven attribute adjustments, speed modifiers, and tier-progression abilities (e.g. orc ferocity, ghoul fever/paralysis). Race data definitions live in `../common/data/races.yaml.example`.

## Cross-cutting notes

- All formulas in this branch use `floor()` for division and treat Tier 0 as 0.5, per project convention.
- Saves are referred to as "Wisdom save" / "Dexterity save"; never "will" or "reflex".
- Ability/condition damage uses "magic toxicity"; never "mana saturation".
- Data this branch added or shaped (race tier_progression, condition definitions, new spells, loot tables, class templates) is captured under `../common/data/` because every other branch is likely to reference it.
