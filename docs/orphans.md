# Orphan Values

Configuration keys, type lists, and concepts that don't yet have a clear domain home. Each entry should be revisited and migrated to the appropriate domain doc once a home is identified.

> **Process:** when an entry here finds a home, move both the description and any related rules into that domain's docs and delete the entry from this file. Cross-references in other docs should be updated at the same time.

## Bonus Types List

The enumerated list of valid Bonus / Penalty / Starting modifier types (e.g. Circumstance, and any future named types). Lives today in `dice_resolution_config.yaml` under the key `Bonus Types List`.

The dice resolution domain treats modifier keys as opaque integers — it neither owns the type list nor validates names against it. Whoever assembles the modifier dictionary is responsible for using only recognized type names.

**Open questions:**

- Which domain owns the canonical list?
- Where does validation of "the caller passed a recognized type name" happen — at construction of the modifier dictionary, or somewhere upstream?
- When a new modifier type is introduced (by a class, ability, item, condition, etc.), what's the workflow for registering it?
