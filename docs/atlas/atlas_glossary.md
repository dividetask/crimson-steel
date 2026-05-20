# Atlas — Glossary

Defines the vocabulary used by `atlas_design.md` and `atlas_tests.md`. Atlas owns the campaign's spatial state: the catalog of Maps and the Tokens placed on them. *(configurable)* values come from `atlas_config.yaml`.

## Atlas

**Atlas**: The Campaign's spatial state — the Map catalog, the Token collection, and the pointer identifying the Active Map. Loaded from a data file at startup and persisted on every mutation.

## Map

**Map**: A named spatial backdrop a scene plays out on. Has an image, dimensions in Map Units, optional Grid metadata, and an Archived flag. Maps are referenced by Map ID.

**Map ID**: Integer identifier for a Map. Unique within the Campaign and stable for the Map's lifetime.

**Map Image**: A path or URL of the picture the Map renders with. May be null when the Map is a blank canvas.

**Map Units**: The Map's own coordinate space. One Map Unit is one Grid cell. Width, height, and Token positions are all expressed in these units. The unit's real-world meaning (feet, meters, etc.) is a Campaign-level convention; Atlas does not interpret it.

**Map Width**, **Map Height**: The Map's extent in Map Units. Stored as numbers with no enforced upper bound. May be null when the extent is unbounded — Atlas does not clamp Token positions to these values either way.

**Active Map**: The Map currently presented to viewers. At most one Active Map at a time, identified by `active_map_id` in Atlas State. May be null when no Map is active.

**Archived**: A boolean flag on a Map. Archived Maps are excluded from default Map listings but retain all data (image, dimensions, Tokens). Archive is reversible. Removing a Map is a separate, destructive operation (*Delete Map*).

## Grid

**Grid**: Optional overlay metadata describing how the Map is subdivided. Atlas stores the metadata; rendering and snapping behavior are a UI concern.

**Grid Type**: One of `none`, `square`, or `hex`. *(configurable default)*

**Grid Origin**: The Map Unit coordinates of the cell `(0, 0)` corner. Allows offsetting the grid relative to the Map Image. Defaults to `(0, 0)`.

## Token

**Token**: A renderable marker placed on a Map at a specific position. Each Token references a Creature by Creature ID; the referenced Creature supplies the display name and Tier the UI uses for the Token's appearance and hover content.

**Token ID**: Integer identifier for a Token. Unique within the Campaign and stable for the Token's lifetime.

**Token Position**: A `(x, y)` pair in Map Units giving the Token's location on its Map. Numbers, not required to be integers. Atlas accepts positions outside the Map's declared extent without complaint.

**Token Size**: The side length of the Token in Map Units. Tokens are square. *(configurable default)*

**Token Label**: Optional display string. When set, the UI uses this instead of the referenced Creature's name. Useful for unnamed minions and disguised identities.

**Token Image**: Optional path or URL overriding the Token's icon. When null, the UI falls back to the Creature Reference Entry's `creature_token`, then to the Tier-colored default.

**Token Owner ID**: Creature ID of the player creature whose controller may move this Token, or null. Null means GM-only control. Atlas stores the value; enforcement is the consuming application's concern.

## Viewport (UI-side)

**Viewport**: The visible portion of a Map presented to a viewer. The Viewport's pan offset and zoom factor are UI state — Atlas does not store them. Defined here so the design and stub can refer to a single term.
