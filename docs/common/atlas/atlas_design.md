# Atlas — Design

Atlas owns the Campaign's spatial state: a catalog of Maps and the Tokens placed on them. State is loaded from `data/atlas_data.json` (or the example file in development mode) at startup and persisted on every mutation.

Atlas is a record-keeping domain. It does not interpret Map Units, snap Tokens to grids, or evaluate visibility — those are UI concerns. It also does not own the rules of Combat or the identity of Creatures; Tokens cross-reference the Creatures domain by Creature ID and Combat by the same Creature ID.

Sibling domains:
- **Creatures** owns Creature identity, Tier, and the data behind a Token's hover content. Atlas stores `creature_id` and looks up display data through a `creature_lookup` callback.
- **Combat** owns the active fight. Atlas does not subscribe to Combat events; the consuming application is expected to call *Place Token* / *Remove Token* in response to *Start Combat* / *End Combat* if it wants Combatant tokens placed automatically.
- **Chronicle** owns the narrative scene; Atlas owns the spatial scene. The two are independent — switching the Active Map does not change the Active Chronicle Entries and vice versa.

## Common types

### Map

| Field | Type | Description |
|---|---|---|
| `id` | integer | Map ID. Assigned by Atlas. Stable for the Map's lifetime. |
| `name` | string | Display name. |
| `image` | string or null | Path or URL of the Map Image. Null for a blank canvas. |
| `width` | number or null | Map Width in Map Units. Null when unbounded. No enforced upper bound. |
| `height` | number or null | Map Height in Map Units. Null when unbounded. No enforced upper bound. |
| `grid` | Grid or null | Grid overlay metadata. Null when the Map has no grid. |
| `archived` | boolean | When true, the Map is hidden from default listings. Reversible. |
| `notes` | string | Free-text GM notes about the Map. May be empty. |

### Grid

| Field | Type | Description |
|---|---|---|
| `type` | `none` \| `square` \| `hex` | Grid Type. |
| `origin` | `(number, number)` | Grid Origin in Map Units. Defaults to `(0, 0)`. |

One Map Unit is one Grid cell — there is no separate cell-size field.

### Token

| Field | Type | Description |
|---|---|---|
| `id` | integer | Token ID. Assigned by Atlas. |
| `map_id` | Map ID | The Map the Token lives on. |
| `creature_id` | Creature ID | Reference to the Creatures domain. Required. |
| `x` | number | Token Position X in Map Units. |
| `y` | number | Token Position Y in Map Units. |
| `size` | number | Token Size (side length, square) in Map Units. Defaults to `Default Token Size`. |
| `label` | string or null | Token Label override. Null defers to the Creature's name. |
| `image` | string or null | Token Image override. Null defers to the Creature's token image (`metadata.creature_token`), then a `?` marker. |
| `owner_id` | Creature ID or null | Token Owner ID. Atlas stores it; enforcement is the consumer's concern. |
| `hidden` | boolean | When true, players should not see the Token. Atlas stores the flag; filtering is the consumer's concern. |

### Zone

| Field | Type | Description |
|---|---|---|
| `id` | integer | Zone ID. Assigned by Atlas. |
| `map_id` | Map ID | The Map the Zone sits on. |
| `source_id` | string | Opaque identifier paired with the Conditions-side Zone Effect that owns this Zone's lifecycle and triggers. |
| `shape` | `square` \| `circle` \| `cone` \| `line` | Geometry. *(catalog configurable)* |
| `size` | integer | Extent in Map Units. Side length for `square`, radius for `circle`, etc. |
| `anchor` | Anchor | How the Zone's center is fixed. See below. |

**Anchor**:

| Field | Type | Description |
|---|---|---|
| `type` | `point` \| `target` \| `caster` | Anchor kind. |
| `x`, `y` | number | Stored center, in Map Units. Always present; for `target` / `caster` anchors Atlas updates these whenever the anchor Creature's Token moves. |
| `creature_id` | Creature ID or null | Required for `target` / `caster`. Null for `point`. |

### Annotation

A free-form drawing placed on a Map by a viewer — distinct from a Zone (which is the spatial half of a rules-driven Zone Effect). Annotations carry no mechanical meaning; they are visual aids the table draws to communicate (movement arrows, area markers, labels).

| Field | Type | Description |
|---|---|---|
| `id` | integer | Annotation ID. Assigned by Atlas. |
| `map_id` | Map ID | The Map the Annotation is drawn on. |
| `type` | `arrow` \| `shape` \| `text` | Annotation Kind. |
| `points` | list of `(number, number)` | Geometry in Map Units. Two points for an `arrow` (tail → head) or a `shape` (opposite corners of its bounding box); one point for `text` (its anchor). |
| `shape_kind` | `rect` \| `ellipse` or null | For `shape` Annotations only. Null otherwise. *(catalog configurable)* |
| `text` | string or null | For `text` Annotations only. The string to render. Null otherwise. |
| `color` | string or null | Stroke / fill color hint. Null defers to a viewer-default. |
| `author` | `dm` \| `player` | Who drew the Annotation. Atlas stores it; permission enforcement is the consumer's concern. |
| `dm_only` | boolean | When true, only the DM should see the Annotation (e.g. a secret text note). Atlas stores the flag; filtering it out of a player's view is the consumer's concern, exactly as with a hidden Token. Defaults to false. |

Atlas treats `points` as opaque Map Units (no clamping or snapping), exactly as it does Token positions.

### Terrain

Painted map structure: a rectangle (or ellipse) filled with a **repeating** texture — the walls, dirt, and stone floor a DM lays down to build a scene. Terrain is distinct from an Annotation: it is permanent furniture, not a transient marking. It is *not* swept by *Clear Annotations* and persists until the DM clears it (or the Map is deleted). It is also distinct from a Zone (which carries rules-driven Zone Effect lifecycle); Terrain carries no mechanical meaning.

| Field | Type | Description |
|---|---|---|
| `id` | integer | Terrain ID. Assigned by Atlas. |
| `map_id` | Map ID | The Map the Terrain is painted on. |
| `shape_kind` | `rect` \| `ellipse` | Footprint shape. *(catalog configurable)* |
| `points` | list of `(number, number)` | Opposite corners of the footprint's bounding box, in Map Units. Opaque (no clamping / snapping), like Token positions. |
| `texture` | string | Fill image's filename, resolved by the UI against its terrain texture folder. The image repeats (one tile per Grid cell). |

### Fog

Hidden map structure: a rectangle (or ellipse) region the DM paints to conceal part of a Map from players — the spatial half of **fog of war**. Fog is distinct from an Annotation (it is permanent furniture, not a transient marking) and from Terrain (it carries no texture and no visual structure — it is a visibility mask). Like Terrain it is *not* swept by *Clear Annotations* and persists until the DM clears it (or the Map is deleted).

Fog of war is **disabled by default**: a Map with no Fog regions restricts nothing and every viewer sees the whole Map. Restriction begins only where the DM paints Fog. Atlas is a record-keeping domain — it stores the regions but does not itself decide what a given viewer sees; the consumer applies the visibility policy (see *Fog of war and visibility* below), exactly as it does for a hidden Token or a `dm_only` Annotation.

| Field | Type | Description |
|---|---|---|
| `id` | integer | Fog ID. Assigned by Atlas. |
| `map_id` | Map ID | The Map the Fog is painted on. |
| `shape_kind` | `rect` \| `ellipse` | Footprint shape. *(catalog configurable)* |
| `points` | list of `(number, number)` | Opposite corners of the footprint's bounding box, in Map Units. Opaque (no clamping / snapping), like Token positions. |

### Atlas State

| Field | Type | Description |
|---|---|---|
| `maps` | list of Map | All Maps that exist, archived or not. |
| `tokens` | list of Token | All Tokens that exist. |
| `zones` | list of Zone | All Zones currently placed. |
| `annotations` | list of Annotation | All Annotations currently drawn. |
| `terrain` | list of Terrain | All Terrain fills currently painted. |
| `fog` | list of Fog | All Fog regions currently painted. |
| `active_map_id` | Map ID or null | The Active Map, or null when no Map is active. |
| `next_map_id` | integer | Next ID to assign when creating a Map. |
| `next_token_id` | integer | Next ID to assign when creating a Token. |
| `next_zone_id` | integer | Next ID to assign when creating a Zone. |
| `next_annotation_id` | integer | Next ID to assign when creating an Annotation. |
| `next_terrain_id` | integer | Next ID to assign when creating a Terrain fill. |
| `next_fog_id` | integer | Next ID to assign when creating a Fog region. |

## Public entry points

### Manage Maps

- **Add Map** — creates a new Map with the supplied fields. Atlas assigns the Map ID. `archived` defaults to false. Returns the assigned ID.
- **Edit Map** — updates one or more fields of an existing Map by ID. Width and height may be changed at any time; existing Token positions are not adjusted (positions outside the new extent remain valid, per the *Map Width* glossary entry).
- **Archive Map** — sets `archived = true` on the Map. If the Map was the Active Map, `active_map_id` is set to null. Tokens belonging to the Map are retained.
- **Unarchive Map** — sets `archived = false` on the Map.
- **Delete Map** — removes the Map by ID and removes every Token and Terrain fill whose `map_id` matches. If the Map was the Active Map, `active_map_id` is set to null. Distinct from Archive — destructive and not reversible.
- **Get Map** — returns a single Map by ID, regardless of archive state. Returns nothing for an unknown ID.
- **List Maps** — returns Maps filtered by the parameters below. Filters combine conjunctively.
  - `include_archived` — boolean, default false. When false, archived Maps are excluded.
  - `archived_only` — boolean, default false. When true, only archived Maps are returned. Overrides `include_archived`.

### Active Map

- **Get Active Map** — returns the Active Map's record, or null when no Map is active. Returns the Map even if it is archived (which can happen only via direct mutation of stored data; *Archive Map* clears the Active Map).
- **Set Active Map** — sets `active_map_id` to the supplied Map ID. The Map must exist and must not be archived. Passing null clears the Active Map.

### Manage Tokens

- **Place Token** — creates a Token on a Map. Inputs: `map_id`, `creature_id`, `x`, `y`, and any optional overrides (`size`, `label`, `image`, `owner_id`, `hidden`). The Map must exist. Atlas assigns the Token ID. Returns the assigned ID.
- **Move Token** — updates `x` and `y` for an existing Token. Idempotent.
- **Edit Token** — updates one or more fields of an existing Token by ID. Cannot change `id` or `map_id`; relocating a Token to another Map is *Remove Token* + *Place Token*.
- **Remove Token** — deletes a Token by ID.
- **Get Token** — returns a single Token by ID.
- **List Tokens** — returns Tokens filtered by the parameters below. Filters combine conjunctively.
  - `map_id` — restrict to Tokens on the given Map. Default: every Map.
  - `creature_id` — restrict to Tokens for the given Creature.
  - `include_hidden` — boolean, default true. When false, Tokens with `hidden = true` are excluded.

### Manage Zones

- **Place Zone** — creates a Zone on a Map. Inputs: `map_id`, `source_id`, `shape`, `size`, and an Anchor specification. The Map must exist; if the Anchor type is `target` or `caster`, the referenced Creature must have a Token on this Map (Atlas seeds the stored `x, y` from that Token). Atlas assigns the Zone ID. Returns the assigned ID.
- **Remove Zone** — deletes a Zone by ID. Quiet no-op when the Zone is already gone.
- **Get Zone** — returns a single Zone by ID.
- **List Zones** — returns Zones filtered by `map_id` (optional) and `source_id` (optional). Filters combine conjunctively.
- **Zones In Position** — given `(map_id, x, y, size)`, returns the IDs of every Zone on that Map whose footprint overlaps the supplied footprint. Used by Movement Notification (below) and by callers that want to know what a creature is currently standing in.

### Manage Annotations

- **Add Annotation** — creates an Annotation on a Map. Inputs: `map_id`, `type`, `points`, and the optional `shape_kind`, `text`, `color`, `author`, `dm_only`. The Map must exist. Atlas assigns the Annotation ID. Returns the assigned ID. Atlas does not validate that `author` is permitted to draw `type` — that gate is the consumer's (e.g. the UI restricts players to `arrow`).
- **Edit Annotation** — updates one or more fields of an Annotation by ID (e.g. retext or reposition a note). `id` and `map_id` are immutable; changing either returns the error sentinel. Unknown ID returns the sentinel.
- **Remove Annotation** — deletes an Annotation by ID. Quiet no-op when already gone.
- **Get Annotation** — returns a single Annotation by ID.
- **List Annotations** — returns Annotations filtered by `map_id`, `type`, and `author` (all optional). Filters combine conjunctively.
- **Clear Annotations On Map** — removes Annotations on a Map. With an optional `author` filter, removes only that author's Annotations (e.g. a player clearing only their own arrows); without it, clears every Annotation on the Map.

Annotations are independent of Tokens and Zones: *Delete Map* cascades to Tokens and Terrain only, so a consumer that wants a Map's Annotations gone calls *Clear Annotations On Map* (mirroring *Clear Zones On Map*).

### Manage Terrain

- **Add Terrain** — paints a Terrain fill on a Map. Inputs: `map_id`, `points`, `texture`, and the optional `shape_kind` (defaults to `rect`). The Map must exist. Atlas assigns the Terrain ID. Returns the assigned ID. Coordinates are opaque (no clamping / snapping).
- **Edit Terrain** — updates one or more fields of a Terrain fill by ID (`points`, `shape_kind`, `texture`) — e.g. the DM retyping a wall's corners. `id` and `map_id` are immutable; changing either returns the error sentinel. Unknown ID returns the sentinel.
- **Remove Terrain** — deletes a Terrain fill by ID. Quiet no-op when already gone.
- **Get Terrain** — returns a single Terrain fill by ID.
- **List Terrain** — returns Terrain fills filtered by `map_id` (optional).
- **Erase Terrain Box** — subtracts a rectangular region `(x0, y0)-(x1, y1)` (Map Units) from a Map's Terrain (the eraser box tool). A `rect` fill overlapping the box is replaced by the up-to-four rectangles that remain after removing the box; a fully covered fill is deleted. An `ellipse` fill that overlaps is removed wholesale. Returns the number of fills the box touched.
- **Clear Terrain On Map** — removes every Terrain fill whose `map_id` matches. Returns the count removed.

Terrain is permanent map structure: unlike Annotations it is *not* removed by *Clear Annotations On Map*. It *is* cascaded by *Delete Map* (it dies with the Map it is painted on, like Tokens).

### Manage Fog

Fog mirrors Terrain — it is painted map structure with the same lifecycle — but carries no texture and represents concealment rather than visible structure.

- **Add Fog** — paints a Fog region on a Map. Inputs: `map_id`, `points`, and the optional `shape_kind` (defaults to `rect`). The Map must exist. Atlas assigns the Fog ID. Returns the assigned ID. Coordinates are opaque (no clamping / snapping).
- **Edit Fog** — updates one or more fields of a Fog region by ID (`points`, `shape_kind`). `id` and `map_id` are immutable; changing either returns the error sentinel. Unknown ID returns the sentinel.
- **Remove Fog** — deletes a Fog region by ID. Quiet no-op when already gone.
- **Get Fog** — returns a single Fog region by ID.
- **List Fog** — returns Fog regions filtered by `map_id` (optional).
- **Erase Fog Box** — the *Reveal* tool: subtracts a rectangular region `(x0, y0)-(x1, y1)` (Map Units) from a Map's Fog. A `rect` region overlapping the box is replaced by the up-to-four rectangles that remain after removing the box; a fully covered region is deleted; an `ellipse` region that overlaps is removed wholesale. Returns the number of regions the box touched. (Mechanically identical to *Erase Terrain Box*.)
- **Clear Fog On Map** — removes every Fog region whose `map_id` matches. Returns the count removed.

Like Terrain, Fog is permanent map structure: it is *not* removed by *Clear Annotations On Map* and *is* cascaded by *Delete Map*.

### Fog of war and visibility

Fog restricts what a **player** viewer sees; the **DM** always sees through it. As a record-keeping domain Atlas stores Fog regions but does not filter anyone's view — the consumer applies the policy when it builds a viewer's snapshot, the same way it strips hidden Tokens and `dm_only` Annotations. The reference host applies it as:

- A player's snapshot omits any Token whose center lies inside a Fog region (so a concealed creature's position never reaches the player's browser), and carries the Fog regions so the UI can paint them as an opaque grey cross-hatch over the map.
- The DM's snapshot is unfiltered; the UI paints Fog as the same grey cross-hatch but translucent, so the DM can see the concealed area and knows what the players cannot. (The DM may also toggle the overlay off in their own view — a UI convenience that does not affect the player view.)
- The *Reveal* tool erases Fog by box (*Erase Fog Box*), but on a Map that has **no Fog yet** the host first seeds a full-Map Fog region, so revealing on a clear Map conceals everything but the dragged box (the "hide everything, reveal here" workflow). This is a host convenience built on the plain *Add Fog* / *Erase Fog Box* entry points; Atlas itself has no full-Map notion.

With no Fog on a Map, nothing is filtered — fog of war is off by default.

### Bulk operations

- **Place Tokens For Combat** — convenience entry point: given a Map ID and a list of `(creature_id, x, y)` triples, calls *Place Token* once per triple. Returns the list of assigned Token IDs in input order. No special tie to the Combat domain — the consuming application supplies the Combatant roster.
- **Clear Tokens On Map** — removes every Token whose `map_id` matches. Used by the consumer at *End Combat* or whenever a scene resets. Does **not** remove Zones; Zones persist independently of Tokens.
- **Clear Zones On Map** — removes every Zone whose `map_id` matches. Used by scene resets that want to wipe spatial state entirely.

## Operations

### Map ID and Token ID allocation

Both ID sequences are independent. Atlas assigns the next available value from `next_map_id` / `next_token_id`, then increments. Deleted IDs are not reused; subsequent allocations always advance.

### Archive semantics

Archive is a soft delete. An archived Map keeps its image, dimensions, Grid metadata, and every Token whose `map_id` matches. *List Maps* excludes archived Maps by default; *Get Map* and *Get Token* still return them. *Set Active Map* refuses an archived target.

Unarchiving restores the Map to default listings without further side effects. The Active Map pointer is not restored automatically.

### Delete semantics

*Delete Map* is the destructive counterpart. Cascading Token, Terrain, and Fog deletion is part of the contract — Atlas does not leave orphan Tokens, Terrain fills, or Fog regions pointing at non-existent Maps. Callers wanting a recoverable variant should use Archive instead.

### Position handling

Atlas treats `x` and `y` as opaque numbers in Map Units. It does not clamp positions to the Map's `width` / `height`, snap to grid cells, or reject negative values. Callers that want clamping or snapping perform it before calling *Place Token* / *Move Token*.

The lack of clamping is intentional: Maps may be expanded after Tokens are placed, and a Token momentarily off the edge during drag-and-drop on the UI should still round-trip through Atlas.

### Movement Notification

When *Move Token* changes a Token's position, Atlas computes the diff in Zone Membership for that Token's footprint:

1. Compute the set of Zones the Token overlapped before the move (using the pre-move position).
2. Compute the set of Zones it overlaps after the move.
3. Compute `entered = after − before` and `exited = before − after`.
4. If either set is non-empty, emit a Movement Notification to the consuming application carrying the Creature ID, Map ID, entered Zone IDs, and exited Zone IDs.

Atlas does not call into Combat or Conditions directly. The notification is a callback the consuming application registers; Combat is the typical recipient. Combat then decides whether to surface the entered / exited Zones as event options for the GM (per Combat's design).

### Anchor-following Zones

When *Move Token* moves a Token whose Creature ID is referenced by one or more Zones (via Anchor type `target` or `caster`), Atlas updates each such Zone's stored `(x, y)` to match the Token's new position before computing Movement Notifications. The notification then reflects the moved Zones' new footprints.

When a Token referenced as a Zone Anchor is removed (via *Remove Token*), Atlas does **not** automatically remove the Zone — the Zone retains its last known position, and the consuming domain decides whether to remove it via *Remove Zone*.

### Display data resolution

For a Token's display data, Atlas exposes only the stored fields. UI surfaces look up the referenced Creature through `creature_lookup` to obtain the Creature's name, Tier, and (if the Token's `image` is null) any token-style image associated with the Creature.

When a referenced Creature does not exist (deleted from the Creatures domain after the Token was placed), Atlas still returns the Token. The UI presents a placeholder per `atlas_stub.md`.

## Cross-domain interactions

- **Creatures** — Tokens reference `creature_id`. Atlas never stores Creature data directly; the consuming UI calls Creatures for name and Tier.
- **Combat** — Atlas does not subscribe to Combat. The consuming application is the integration point: it may call *Place Tokens For Combat* at *Start Combat* and *Clear Tokens On Map* at *End Combat*, or place Tokens manually as Combatants arrive. Atlas works fine outside Combat (exploration scenes, downtime maps). Combat is the typical recipient of Atlas's Movement Notifications and surfaces Zone Events to the GM (see `combat/combat_design.md`).
- **Conditions** — Conditions owns the lifecycle and triggers of Zone Effects. Atlas pairs each Zone Effect with a spatial Zone record by shared `source_id`. *Place Zone* and *Remove Zone* are called by Conditions during *Create Zone Effect* and *Remove Zone Effect*.
- **Chronicle** — independent. A scene can have an Active Map and Active Chronicle Entries with no required correlation.

## Persistence

State is loaded from `data/atlas_data.json` at startup (or the example file in development mode) and written back on every mutation. Persistence mechanics are the consuming project's responsibility; Atlas provides the in-memory shape.
