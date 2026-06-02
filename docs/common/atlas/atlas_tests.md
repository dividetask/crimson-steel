# Atlas — Tests

Externally-observable behavior of Atlas's public entry points. Each section is a public entry point or a closely related cluster.

## Test config

Tests use the defaults from `atlas_config.yaml` unless noted:

- Default Token Size = 1.
- Default Grid Type = `square`.

The baseline state for each test (unless overridden) is: no Maps, no Tokens, `active_map_id = null`, `next_map_id = 1`, `next_token_id = 1`. Tests assume Atlas can resolve `creature_lookup` for any Creature ID referenced; Creature data shape is exercised in the Creatures tests, not here.

---

## Manage Maps

**Add Map assigns a unique ID.** Calling Add Map with `name = "Forest Clearing"`, `image = "/maps/forest.png"`, `width = 50`, `height = 50`: returns the assigned ID (1 on a fresh Atlas). A subsequent Add Map returns a higher integer.

**Add Map defaults `archived` to false.** A new Map's `archived` field is false even when not supplied in the call.

**Add Map accepts null dimensions.** With `width = null` and `height = null`: the Map is created and stored. The Map is treated as having no declared extent; later Token placements at any coordinate succeed.

**Add Map accepts arbitrarily large dimensions.** With `width = 100000` and `height = 100000`: the Map is created without modification. Atlas does not enforce an upper bound.

**Edit Map updates only the supplied fields.** With an existing Map having `name = "Old"` and `width = 50`: Edit Map with only `name = "New"` leaves `width = 50`.

**Edit Map can grow the Map.** With Map `width = 50`: Edit Map with `width = 200` stores 200. Existing Tokens are not moved.

**Edit Map can shrink the Map without dropping out-of-bounds Tokens.** With Map `width = 50` and a Token at `x = 40`: Edit Map to `width = 30` leaves the Token's `x = 40` unchanged. Atlas does not clamp.

**Get Map returns the full record.** Get Map on a stored Map returns every field including `grid` and `archived`.

**Get Map on an unknown ID returns nothing.** No error is raised.

---

## Archive / Unarchive / Delete Maps

**Archive Map sets the flag.** With a stored Map having `archived = false`: Archive Map flips it to true. The Map is still retrievable via Get Map.

**Archive Map preserves Tokens.** A Map with three Tokens: after Archive Map, List Tokens with `map_id` matching still returns all three.

**Archive Map clears the Active Map when it matches.** With `active_map_id = 5` and Map 5 archived: after Archive Map, `active_map_id = null`. With `active_map_id = 6` and Map 5 archived: `active_map_id` remains 6.

**Unarchive Map flips the flag back.** Unarchive Map on a Map with `archived = true` sets it to false. The Active Map pointer is not restored.

**Delete Map removes the Map and its Tokens.** Map 7 has two Tokens with `map_id = 7`. Delete Map on Map 7 removes the Map (Get Map returns nothing) and both Tokens (Get Token returns nothing for either ID).

**Delete Map clears the Active Map when it matches.** Same rule as Archive Map.

**List Maps default excludes archived.** Maps 1 (archived), 2, and 3 stored. List Maps with no parameters returns Maps 2 and 3.

**List Maps with `include_archived = true` returns everything.** Returns Maps 1, 2, and 3.

**List Maps with `archived_only = true` returns only archived.** Returns Map 1 only. `include_archived` is ignored when `archived_only` is set.

---

## Active Map

**Get Active Map returns null on a fresh Atlas.** No Maps present, `active_map_id = null`: Get Active Map returns null.

**Set Active Map points at an existing Map.** With Map 4 stored and not archived: Set Active Map to 4 sets `active_map_id = 4`. Get Active Map returns Map 4's record.

**Set Active Map to null clears the pointer.** With `active_map_id = 4`: Set Active Map with null sets it to null.

**Set Active Map refuses an archived Map.** With Map 4 archived: Set Active Map to 4 returns an error sentinel; `active_map_id` is unchanged.

**Set Active Map refuses an unknown Map.** With no Map 99 stored: Set Active Map to 99 returns an error sentinel.

---

## Manage Tokens

**Place Token assigns a unique ID.** Place Token on Map 1 at `(10, 12)` for `creature_id = 1001`: returns the assigned Token ID (1 on a fresh Atlas). A subsequent Place Token returns a higher integer.

**Place Token applies default size.** Place Token with no `size` parameter: the stored Token's `size` is Default Token Size (1).

**Place Token preserves the supplied position verbatim.** Place Token at `(10.5, -3)`: the stored Token has `x = 10.5` and `y = -3`. Negative coordinates and non-integer values round-trip unchanged.

**Place Token outside the Map's declared extent succeeds.** With Map 1 having `width = 50`, `height = 50`: Place Token at `(100, 100)` succeeds; the Token is stored at those coordinates.

**Place Token on an unknown Map returns an error sentinel.** With no Map 99: Place Token with `map_id = 99` returns the sentinel; no Token is created.

**Move Token updates position.** Token 5 at `(10, 12)`. Move Token 5 to `(20, 25)`: stored position is `(20, 25)`. `creature_id`, `size`, and `map_id` are unchanged.

**Move Token is idempotent.** Calling Move Token twice with the same target position leaves the Token at that position.

**Edit Token updates supplied fields only.** Token 5 with `label = null`, `size = 1`. Edit Token 5 with `label = "Goblin Boss"`: stored `label = "Goblin Boss"`, `size = 1` unchanged.

**Edit Token cannot change `id` or `map_id`.** Attempting either via Edit Token returns an error sentinel; the Token is unchanged.

**Remove Token deletes by ID.** Remove Token on a known Token ID: subsequent Get Token returns nothing.

**Get Token on a deleted ID returns nothing.** No error.

---

## List Tokens

**List Tokens with no filters returns everything.** With Tokens on Maps 1, 2, and 3: returns all of them.

**Filter by `map_id` returns only that Map's Tokens.** Two Tokens on Map 1, one on Map 2. List Tokens with `map_id = 1` returns two Tokens.

**Filter by `creature_id` returns only Tokens for that Creature.** Two Tokens for `creature_id = 1001` (the same Creature placed on two Maps), one for `creature_id = 1002`. List Tokens with `creature_id = 1001` returns two Tokens.

**Filter by `include_hidden = false` excludes hidden Tokens.** Three Tokens; one has `hidden = true`. List Tokens with `include_hidden = false` returns two; with `include_hidden = true` (the default) returns three.

**Combined filters are conjunctive.** With Tokens on Map 1 for Creatures 1001 and 1002, and on Map 2 for Creature 1001: List Tokens with `map_id = 1, creature_id = 1001` returns one Token.

---

## Bulk operations

**Place Tokens For Combat creates one Token per triple.** Inputs: `map_id = 1`, triples `[(1001, 0, 0), (1002, 5, 0), (1003, 10, 0)]`. Returns three Token IDs in input order. List Tokens with `map_id = 1` returns three Tokens with those Creature IDs and positions.

**Place Tokens For Combat with an empty list is a no-op.** Returns the empty list; no Tokens created.

**Clear Tokens On Map removes every Token on that Map.** Map 1 has four Tokens; Map 2 has two. Clear Tokens On Map 1: List Tokens with `map_id = 1` returns nothing; Tokens on Map 2 are unchanged.

---

## Annotations

**Add Annotation stores geometry and assigns an ID.** Add Annotation with `type = arrow`, `points = [(1, 2), (8, 9)]`, `author = player`: returns an integer ID; Get Annotation returns the record with those points and `author = player`.

**Add Annotation carries shape and text payloads.** A `shape` Annotation with `shape_kind = rect` stores the kind; a `text` Annotation with `text = "Ambush!"` stores the string.

**Add Annotation on an unknown Map returns the sentinel.** With no Map 99: Add Annotation with `map_id = 99` returns the error sentinel; nothing is created.

**List Annotations filters conjunctively.** Filters by `map_id`, `type`, and `author` combine — e.g. `map_id = 1, author = dm` returns only that Map's DM-drawn Annotations.

**Remove Annotation deletes by ID.** Get Annotation then returns nothing.

**Clear Annotations On Map can scope to an author.** A Map with one `player` arrow and one `dm` shape: Clear Annotations On Map with `author = player` removes one and leaves the DM shape; calling it again with no author clears the rest.

**Annotations persist across reload.** An Annotation written and reloaded from disk round-trips its points and author.

**Annotations are independent of Delete Map's Token cascade.** Deleting a *different* Map does not touch Annotations on the surviving Map; clearing a Map's Annotations is done via *Clear Annotations On Map*, not *Delete Map*.

## Edge cases

**Token referencing a deleted Creature is still returned.** The Creatures domain removes Creature 1001 after a Token was placed for it. Get Token on that Token still returns the Token record with `creature_id = 1001` intact. The UI is responsible for rendering a placeholder; Atlas does not validate.

**Deleted IDs are not reused.** After Delete Map on Map 3 (the highest assigned), the next Add Map assigns Map 4, not Map 3. Same rule for Tokens.

**Loaded state with `active_map_id` referencing an archived Map.** Loaded from disk with `active_map_id = 5` and Map 5 having `archived = true`: Get Active Map returns Map 5's record. (Atlas's invariant is established by *Archive Map*; pre-existing data is honored as stored. *Set Active Map* still refuses to set it back if cleared.)

**Loaded state with a Token referencing an unknown Map.** A Token with `map_id = 99` when no Map 99 exists: Atlas returns the Token from Get Token / List Tokens. Cleanup is the consumer's choice — call *Remove Token* if undesired.
