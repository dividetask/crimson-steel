# Character Sheet Toggle

Per-viewer toggle between a minimal card and the full character sheet. The minimal card is forced on `/scene` regardless of the viewer's preference.

## Glossary

- **Minimal Card** — Compact layout: name + portrait, current HP/mana, conditions, Actions block, two-up Skills table under Actions.
- **Full Sheet** — Long-form layout with attributes, skills, abilities, equipment, spells, and notes.
- **View Mode** — The viewer's persisted preference (`minimal` or `full`), set via `POST /view_mode`.
- **Forced Minimal** — `/scene` ignores the preference and always renders minimal so the DM-side scene view stays compact.

## Design

The toggle is a button on `/character/<index>` that flips the persisted view mode. The chosen mode is stored per viewer (not per character) so the same player sees the same layout across all PCs they can view.

Minimal layout details:

- Skills are placed in a two-up table directly under the Actions block.
- A transparent spacer column separates the two halves of the table.
- The skill table drops all borders (not just the bottom one) so it reads as a tight grid.

The full sheet uses the existing layout. Toggling flips between `views/stubs/_character_minimal_stub.erb` and `views/stubs/_character_full_stub.erb`.

The toggle was originally broken (clicked the wrong target); the fix restructures the minimal card and forces minimal on scene as part of the same change.

## Cross-domain interactions

- See `ui/character_minimal_stub.md` and `ui/character_full_stub.md`.
- HP/mana display in the minimal card uses the current-HP and temp-HP semantics from [hp-mana-display.md](hp-mana-display.md).
