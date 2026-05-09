# Scrolls and Potions

Scrolls cast their stored spell with full spell semantics. Potions are consumable on use. Both bypass the skill check at the store and use ephemeral item ids that don't persist between server restarts.

## Glossary

- **Scroll** — Single-use item that casts a stored spell when consumed. Uses spell-cast semantics (target, ability damage, cure cascade — everything a normal cast does).
- **Potion** — Single-use consumable. May grant temp HP, cure damage, or apply other effects on use.
- **Oil** — A potion-like item applied to weapons or armor.
- **Item ID** — A short identifier used to reference an item in URLs and forms. Ephemeral: regenerated on server start, not persisted.
- **Target Classification** — Inherited from the underlying spell (single / multi / no). Drives the cast UI.

## Design

### Scroll cast semantics

Casting a scroll runs the same code path as casting the spell directly: target picker matches the spell's `target` classification, ability-damage cure cascade applies if the spell heals, temp HP is granted if the spell wards. The skill check normally required for raw spellcasting is skipped — scrolls are pre-prepared.

### Potion consumption

Potions are consumed on use. Effects include: heal HP (via cure cascade), cure ability damage (via ability-cure cascade), grant temp HP, or apply named conditions. Potion sickness from `rules.json` `potion_sickness` accrues per use.

### Store skill skip

The store's purchase flow normally requires a skill check (Appraisal). Potions and oils skip this check — they're commodity items.

### Item id collisions

Item ids are now ephemeral (`make_item_ids_ephemeral`): regenerated each boot, not stored to disk. This avoids collisions where two purchased items would share an id and block scroll/potion access. Purchase flow generates a new id on the fly.

### Target classification

Spells, scrolls, and potions all carry `target: single | multi | no`. The cast UI renders:

- `single` — target dropdown.
- `multi` — checkbox list (this is what the multi-roll example PR tested).
- `no` — no picker; immediate resolve.

## Cross-domain interactions

- See [spells.md](spells.md) for spell semantics scrolls reuse.
- See [store.md](store.md) for purchase flow.
- Item data lives in `data/items.json`; new spell items reference `../../common/data/spells.yaml.example`.
