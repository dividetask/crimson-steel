# Branches — Common

Shared content used by multiple branch snapshots under `docs/Branches/`. When documenting a new branch, put genuinely cross-branch content (race definitions, condition definitions, shared spell lists, loot tables, class templates) here rather than duplicating it in the branch's own folder.

## Structure

- `data/` — `*.yaml.example` rule data definitions (races, classes, conditions, spells, loot tables, etc.). Mirrors the canonical `docs/orphan_data/` style.

## Convention

Before writing a file in a per-branch folder, check whether the same content already lives in `docs/Branches/common/` or in another branch's folder. If it does, do not re-write it. If it's generic enough to be shared and isn't already in `common/`, add it here instead of in the branch folder.
