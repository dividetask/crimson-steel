# Chronicle — Design

Owns the Campaign's mutable state: the Campaign Name, the current Timestamp, the Current Chapter, the Chapter list, and the Entry collection. State is loaded from `data/chronicle_data.json` (or the example file in development mode) at startup and persisted on every mutation.

Chronicle delegates calendar arithmetic to the Timekeeping domain and creature data to the Creatures domain. It does not perform calculations itself beyond the bookkeeping needed to manage its own state.

## Common types

### Entry

A single record in the Chronicle. Polymorphic — most fields are shared, with type-specific fields applying when the Entry Type matches.

Shared fields (all Entries):

| Field | Type | Description |
|---|---|---|
| `id` | integer | Unique within the Campaign. Assigned by Chronicle when the Entry is added. |
| `entry_type` | `note` or `creature` | Discriminator for type-specific fields. |
| `chapter` | integer | The Chapter this Entry belongs to. |
| `notes_position` | integer | Order on the notes page within the Chapter. Always set. |
| `scene_position` | integer | Order on the scene page among Active Entries. Always set. |
| `title` | string | The Entry's heading. For Notes, this is the note title. For Creature References, this is an optional suffix appended to the creature's name (typically blank). |
| `public_description` | string | Body text shown to players. May be empty. |
| `dm_description` | string | Body text shown only to the Game Master. May be empty. |
| `image` | string or null | An image identifier (path, URL, or other reference) the consuming project resolves. Chronicle stores the string opaquely; image storage and retrieval are out of scope here — each consuming project defines its own rules for where images live and how the identifier resolves. |
| `shared` | boolean | When true, all players see the Entry. When false, only the `owner_id` Creature's controller (plus the Game Master) sees it; a DM-created Entry with `owner_id = null` is GM-only when unshared. |
| `hidden_from` | list of Creature IDs | Players controlling any Creature in this list cannot see the Entry even when `shared` is true. |
| `owner_id` | Creature ID or null | The player Creature that created the Entry. Null when the Game Master created it. |
| `active` | boolean | When true, the Entry belongs to the current Scene. When false, the Entry is archived. |

Creature-Reference-specific fields (when `entry_type = creature`):

| Field | Type | Description |
|---|---|---|
| `creature_id` | Creature ID | Reference to the Creatures domain. Required. |
| `creature_token` | string or null | Path or URL of a smaller token-style image. |
| `tier` | integer or null | Override for the referenced Creature's tier. When null, the tier is read from the Creatures domain. |

### Chapter

| Field | Type | Description |
|---|---|---|
| `number` | integer | Chapter number. Determines display order. |
| `name` | string | Human-readable Chapter name. |

### Chronicle State

| Field | Type | Description |
|---|---|---|
| `campaign_name` | string | The Campaign Name. |
| `timestamp` | Timestamp (per Timekeeping domain) | The current in-game time. |
| `current_chapter` | integer | The Current Chapter number. Defaults to 1 on a new Chronicle. |
| `chapters` | list of Chapter | All Chapters that exist. |
| `entries` | list of Entry | All Entries. |
| `next_id` | integer | Next ID to assign when creating an Entry. |

## Public entry points

### Read campaign metadata

- **Get Campaign Name** — returns the current Campaign Name.
- **Get current Timestamp** — returns the Timestamp.
- **Set Campaign Name** — replaces the Campaign Name.

### Advance time

Adds rounds and/or days to the current Timestamp. Delegates the arithmetic to Timekeeping's Advance a Timestamp entry point and stores the result.

Inputs: `rounds` (signed integer, default 0), `days` (signed integer, default 0).

Returns: the new Timestamp.

### Manage Chapters

- **List Chapters** — returns all Chapters in number order.
- **Add Chapter** — creates a new Chapter with a given number and name.
- **Rename Chapter** — changes a Chapter's name.
- **Remove Chapter** — deletes a Chapter. Entries belonging to the removed Chapter are not deleted; they retain their `chapter` field, which now references a non-existent Chapter. Callers may reassign or delete those Entries separately.
- **Get Current Chapter** — returns the Current Chapter number.
- **Advance Chapter** — increments the Current Chapter by one. Intended for normal story progression. Does not move existing Entries; new Entries created without an explicit `chapter` land in the new Current Chapter.
- **Set Current Chapter** — sets the Current Chapter to a given number. Intended for correcting user error; the GM normally only moves Current Chapter forward via *Advance Chapter*.

### Manage Entries

- **Add Entry** — creates a new Entry with all fields supplied. Chronicle assigns the ID. Returns the assigned ID.
- **Edit Entry** — updates one or more fields of an existing Entry by ID.
- **Delete Entry** — removes an Entry by ID.
- **Get Entry** — returns a single Entry by ID.
- **List Entries** — returns Entries filtered by the parameters below. All filters are optional and combine conjunctively.
  - `chapter` — restrict to Entries in this Chapter.
  - `entry_type` — restrict to Notes or Creature References.
  - `active_only` — when true, return only Entries with `active = true`.
  - `visible_to` — a Creature ID. Returns Entries the player controlling that Creature would see; that means: not hidden from them, not owned by another player, and either Public or owned by them. The Game Master sees everything regardless and does not need this filter.

### Reorder Entries

- **Set Notes Position** — sets an Entry's `notes_position`. Other Entries in the same Chapter with `notes_position >= the new value` shift up by one.
- **Set Scene Position** — same semantics for `scene_position`. Other Active Entries with `scene_position >= the new value` shift up by one.

## Operations

### Visibility resolution

When a viewer asks "is this Entry visible to me?", the rules are:

1. The Game Master sees every Entry.
2. If the viewer is a player controlling Creature C:
   - If C is in `hidden_from`, the Entry is invisible (the exclusion overrides everything else).
   - If `shared` is true, the Entry is visible.
   - If `owner_id` is C, the Entry is visible.
   - Otherwise, the Entry is invisible.

### Position management

`notes_position` and `scene_position` are always set. When inserting an Entry at a given position, existing Entries at or beyond that position shift up by one. Tie-breakers (when two Entries have the same position) are resolved by storage order — the first one encountered wins.

If an Entry is loaded with a missing or null position field, Chronicle assigns a position automatically — appended to the end of its Chapter (for `notes_position`) or to the end of the Active Entry list (for `scene_position`).

Positions are not required to be densely packed; gaps are permitted but the shift behavior eliminates them when entries are inserted between existing ones.

## Cross-domain interactions

- **Timekeeping** — Chronicle calls Timekeeping's Advance a Timestamp entry point. Timekeeping does not know about Chronicle; the Timestamp passed in is just two integers.
- **Creatures** — Chronicle stores `creature_id` references and calls into Creatures when it needs creature data (name, tier). The Creatures domain owns those values; Chronicle never duplicates them. The `tier` field on a Creature Reference Entry is an optional override; when null, the value is read from the Creatures domain.
- Configuration: Chronicle has no static config. Tunables live on individual Entries and Chapters.
- Persistence: state is loaded from `data/chronicle_data.json` at startup (or the example file in development mode) and written back on every mutation. Persistence mechanics are the consuming project's responsibility; Chronicle provides the in-memory shape.
