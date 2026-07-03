# Atlas — Glossary

Defines the vocabulary used by `atlas_design.md` and `atlas_tests.md`. Atlas owns the Campaign's spatial state — Maps and the Tokens placed on them. *(configurable)* values come from `atlas_config.yaml`.

## Atlas

**Atlas**: The Campaign's spatial state — Maps, Tokens, Zones, and the pointer naming the Active Map.

## Map

**Map**: A named spatial backdrop a scene plays out on. Has an image, dimensions, an optional Grid, and an Archived marker.

**Map Image**: The picture the Map renders with.

**Map Units**: A Map's coordinate space. One Map Unit is one Grid cell. The unit's real-world meaning (feet, meters, etc.) is a Campaign-level convention.

**Map Width**, **Map Height**: A Map's extent in Map Units.

**Active Map**: The Map currently presented to viewers. At most one is active at a time.

**Archived**: A marker on a Map that hides it from default listings while preserving its data. Reversible.

## Grid

**Grid**: Optional overlay describing how a Map is subdivided.

**Grid Type**: A Grid's overall shape — none, square, or hex. *(configurable default)*

**Grid Origin**: The corner of the Grid relative to the Map Image.

## Token

**Token**: A renderable marker for a Creature on a Map. Each Token references a Creature; the Creature supplies the display name and Tier.

**Token Position**: A Token's location on its Map.

**Token Size**: The side length of a Token. Tokens are square. *(configurable default)*

**Token Label**: An optional display string that overrides the referenced Creature's name on the Token.

**Token Image**: An optional override for a Token's icon. When absent, the UI falls back to the Creature's portrait, then to a Tier-colored default.

**Token Owner**: The player Creature whose controller may move a Token. Absent means GM-only control.

## Zone

**Zone**: A spatially-anchored area on a Map that lasts beyond a single action — the spatial half of a Zone Effect (the Conditions side carries the lifecycle and triggers; see `conditions/conditions_glossary.md`). A Zone has a shape, a size, and an Anchor.

**Zone Shape**: A Zone's overall geometry — square, circle, cone, or line. *(catalog configurable)*

**Zone Size**: A Zone's extent — side length for square, radius for circle, and so on.

**Zone Anchor**: How a Zone's center is fixed on the Map — to a stationary point, to a target Creature's Token (the Zone tracks the target), or to the caster's Token.

**Zone Membership**: Whether a Token overlaps a Zone's footprint. Tokens whose footprint touches the Zone at all count as inside.

**Movement Notification**: A message Atlas emits when a Token's movement changes its set of Zones — listing the Zones entered and the Zones exited. The consuming domain (typically Combat) decides what to do.

## Annotation

**Annotation**: A free-form drawing placed on a Map — an Arrow, a Shape, or Text. Carries no mechanical meaning (unlike a Zone); it is a visual aid the table draws to communicate.

**Annotation Kind**: An Annotation's form — `arrow` (a tail-to-head line), `shape` (a rectangle or ellipse), or `text` (a placed label).

**Annotation Author**: Who drew an Annotation — the DM or a player. The DM may draw any Kind; players may draw Arrows only. Atlas records the Author; enforcing who may draw what is the consumer's concern.

## Terrain

**Terrain**: Painted map structure — a rectangle (or ellipse) filled with a repeating texture (wall, dirt, stone floor) the DM lays down to build a scene. Permanent furniture: not swept by Clear Annotations, cascaded by Delete Map.

## Fog

**Fog**: A rectangle (or ellipse) region the DM paints to conceal part of a Map from players — the spatial half of Fog of War. Carries no texture and no mechanical meaning; it is a visibility mask. Permanent map structure like Terrain: not swept by Clear Annotations, cascaded by Delete Map.

**Fog of War**: The concealment of a Map from players wherever Fog is painted. **Disabled by default** — a Map with no Fog restricts nothing. Atlas records Fog regions; deciding what a given viewer sees (a player's view is restricted, the DM's is not) is the consumer's concern, exactly as with a hidden Token.

**Reveal**: The tool that erases Fog by region — the mirror of the Terrain eraser. Uncovering a fogged area returns it to the players' sight.

## Viewport (UI-side)

**Viewport**: The visible portion of a Map presented to a viewer. The Viewport's pan and zoom are UI state — Atlas does not store them.
