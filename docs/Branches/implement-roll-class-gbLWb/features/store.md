# Store

Purchase flow with one row per PC, ritual purchase, scroll/potion price corrections, and ephemeral item ids.

## Glossary

- **Multi-PC Purchase Row** — The store renders one row per PC for each item, so the DM can route purchases to specific characters in a single submit.
- **Ritual Purchase** — Buying a ritual scroll. Goes through `POST /purchase_ritual` rather than the standard purchase route.
- **Ephemeral Item ID** — Regenerated on server boot; not persisted. Prevents id collisions across saves.

## Design

`/store` lists items grouped by category. Each item gets one row per PC; the buyer picks a row, sets quantity, and submits. The route `POST /purchase/<item_index>` deducts gold from the chosen PC and adds the item to their inventory.

Rituals follow the same flow but go through `POST /purchase_ritual` because they create a scroll item rather than a physical item.

Skill check skip: Appraisal is normally rolled before purchase to set haggle bounds. Potions and oils skip this — see [scrolls-and-potions.md](scrolls-and-potions.md).

Scroll prices: corrected from earlier values that didn't match the price formula. Prices now follow `tier × base × spell_rank` consistently.

Item id collisions: previously, persisted ids could collide between a stored scroll and a freshly purchased one, blocking the new item from being usable. Item ids are now generated at boot and live only in memory.

## Cross-domain interactions

- Store inventory reads from `data/store.json`.
- Purchase routes mutate `data/characters.json` (gold, inventory).
- Scroll-cast semantics are in [scrolls-and-potions.md](scrolls-and-potions.md).
