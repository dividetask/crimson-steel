# Notes and Images

Image storage attached to character notes and campaign portraits. `/notes/<viewer_id>` viewer renders public notes. New stub: `_notes_images_stub.erb` for image-only panels.

## Glossary

- **Note** — A free-text entry attached to a character or to the campaign.
- **Note Image** — An image attached to a note. Stored under `public/images/notes/`.
- **Public Note** — A note visible to non-DM viewers.
- **Notes Viewer** (`/notes/<viewer_id>`) — Read-only page showing the notes available to that viewer.
- **Campaign Portraits** — Character/NPC portraits added to campaign data.

## Design

Notes can be marked `public` (visible to players) or kept DM-only. Toggling: `POST /notes/character/toggle_public`. Deletion: `POST /notes/character/delete`. Image attachment: `POST /notes/character/image` and `/notes/character/image/clear`.

Note types:

- **Journal** — Long-form entries.
- **Map** — Map-flavored notes attached to a region.
- **Characters** — Character-bio notes.
- **Combined** — Multi-section panel.
- **Images** — Image-only panel (`_notes_images_stub.erb`).

The notes view (`/notes/:viewer_id`) renders only the notes the viewer is permitted to see. The same visibility logic is shared with `/scene` (a note hidden in scene is also hidden in notes view for that viewer).

### Toggle in scene

`POST /notes/character/toggle_in_scene` and `/notes/character/toggle_scene_visible` control whether a character's notes show on `/scene`.

### Image storage

Images uploaded for notes go under `public/images/notes/<character>/`. The `_notes_images_stub` panel renders a thumbnail strip; clicking opens the full image. Map images uploaded for the scene go under `public/images/maps/` and are subject to the `map_images.yaml` whitelist (see [scene-maps.md](scene-maps.md)).

## Cross-domain interactions

- Note format conversion (`Convert notes images format`) was an earlier migration on this branch.
- Visibility intersects with scene visibility — see [scene-page.md](scene-page.md).
