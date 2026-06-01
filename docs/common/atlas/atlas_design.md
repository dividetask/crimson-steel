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
| `image` | string or null | Token Image override. Null defers to the Creature Reference Entry's `creature_token`, then the Tier-colored default. |
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

### Atlas State

| Field | Type | Description |
|---|---|---|
| `maps` | list of Map | All Maps that exist, archived or not. |
| `tokens` | list of Token | All Tokens that exist. |
| `zones` | list of Zone | All Zones currently placed. |
| `active_map_id` | Map ID or null | The Active Map, or null when no Map is active. |
| `next_map_id` | integer | Next ID to assign when creating a Map. |
| `next_token_id` | integer | Next ID to assign when creating a Token. |
| `next_zone_id` | integer | Next ID to assign when creating a Zone. |

## Public entry points

### Manage Maps

- **Add Map** — creates a new Map with the supplied fields. Atlas assigns the Map ID. `archived` defaults to false. Returns the assigned ID.
- **Edit Map** — updates one or more fields of an existing Map by ID. Width and height may be changed at any time; existing Token positions are not adjusted (positions outside the new extent remain valid, per the *Map Width* glossary entry).
- **Archive Map** — sets `archived = true` on the Map. If the Map was the Active Map, `active_map_id` is set to null. Tokens belonging to the Map are retained.
- **Unarchive Map** — sets `archived = false` on the Map.
- **Delete Map** — removes the Map by ID and removes every Token whose `map_id` matches. If the Map was the Active Map, `active_map_id` is set to null. Distinct from Archive — destructive and not reversible.
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

*Delete Map* is the destructive counterpart. Cascading Token deletion is part of the contract — Atlas does not leave orphan Tokens pointing at non-existent Maps. Callers wanting a recoverable variant should use Archive instead.

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
