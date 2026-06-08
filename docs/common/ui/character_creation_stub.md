# Character Creation Stub

The DM's "New Character" wizard. Walks the DM through building a level-1
(Tier 0) Player Character and, on the final Confirm, creates and saves a
Creature through the Creatures domain. Reached from the **New Character**
button at the bottom of the Character Sheets roster sidebar (DM only).

DM-only: a player (any non-loopback viewer) who navigates to
`/character-creation` is redirected to the default landing page, and the
create `POST` is refused.

The page is a thin shell. The server emits one JSON blob (every catalog
the flow needs) into the page; the client controller
(`public/js/ui/characterCreation.js`) renders each step from it without
further round-trips. Only the final create touches the server.

See `ui_conventions.md` for shared rules.

## Steps

A step indicator runs across the top; a single **Back** / **Next**
(**Create Character** on the last step) pair drives navigation. **Next**
is disabled until the current step is valid.

1. **Attribute Allocation (Point Buy).** The six attributes, each
   starting at the configured `starting_value` (10). A `−` / value / `+`
   control per attribute, with a box showing the cost of the next point.
   Costs come from `creatures/character_creation.yaml`'s cumulative cost
   table; the marginal cost of raising an attribute from V to V+1 is
   `cost[V+1] - cost[V]`. A badge shows Remaining Point Buy
   (`point_buy` minus the sum of every attribute's cumulative cost);
   raising past the pool or outside `[minimum, maximum]` is blocked.
2. **Race Selection.** A card per playable Race (the `Playable Races`
   whitelist in `character_creation.yaml` — abstract parent/root races
   are never offered). Each card shows chain, size, speed, stat
   adjustments, and abilities. A bar shows the chosen attributes adjusted by
   the selected Race's `attribute_adjustments`, updating live on
   selection. Back returns to Attribute Allocation.
3. **Class Selection.** A card per Class (bonus skills, mana/level,
   martial rate, strong saves, level-1 abilities, and a one-line summary
   of its spell-selection rule).
4. **Skill Selection.** Skills grouped into **Aligned**, **Unaligned**,
   and **Opposed** for the chosen Class (Proficiencies' Skill Rate
   Resolution). The Skill Pick budget is `floor(int / 4) + bonus_skills`
   (`creatures_config.yaml`'s Skill Pick Formula), evaluated on the
   Effective Intelligence (point-buy + racial + the Tier inherent bonus).
   A Set Skill (key ending `_`) carries an instance text box; its concrete
   key is the family prefix plus the slugified instance.
5. **Spell Selection.** Present only when the chosen Class declares a
   `spell_selection` block with a pickable mode. Driven by that block
   (see *Spell Selection* in `creatures_advancement.yaml`):
   - **count** — pick up to `budget` spells from the (skill-filtered)
     catalog, grouped by Tier.
   - **points** — spend a `budget` point pool; each spell costs `cost`
     (a formula in `tier`, floored — a Tier 0 spell costs 1).
     Unaffordable spells disable.
   - **domain** (Cleric) — pick a deity, then choose `CLERIC_DOMAIN_PICKS`
     (3) domains instead of individual spells. Any domain may be chosen
     except the deity's anathema; every chosen domain grants its spells,
     and a favored domain additionally grants its Channel Divinity ability.
   Classes with `mode: auto` (Druid) or no block (non-casters) skip this
   step entirely.
6. **Confirmation.** A character-name field (required) and an optional
   player-name field, plus a summary of every choice. **Create Character**
   `POST`s the assembled character; the server builds, validates, and
   persists the Creature, then returns the new sheet URL the client
   navigates to.

## Server contract

- `GET /character-creation` — renders the shell + blob (DM only).
- `POST /character-creation` — JSON body
  `{ name, player, race, class, attributes, skills, spells, deity, domain }`.
  Builds a level-1 PC via `CharacterCreation.create!` and persists it to
  the Player Character data file. Returns `{ ok, id, redirect }` on
  success, `422` with `{ ok: false, error }` on validation failure, `403`
  for non-DM callers.

Spell picks are stored as Catalog spell display names under the Class
Entry's `choices.spellcasting`; the Cleric's pick is stored as
`choices.deity` / `choices.domain`. Base attributes are stored as chosen
(racial and inherent bonuses are applied at read time by the Accessor).

## Configuration

| File | Provides |
|------|----------|
| `creatures/character_creation.yaml` | Attribute Allocation (Point Buy) rules. |
| `creatures/creatures_advancement.yaml` | Per-Class `spell_selection` rules; Class catalogs. |
| `creatures/creatures_config.yaml` | Skill Pick Formula, Tier inherent bonus. |
| `proficiencies/skills.yaml` | Skill catalog and per-Class categorization. |
| `abilities/spells.yaml` | The spell pool (filtered per Class). |
| `creatures/deities.yaml` | Deities, domains, and domain spell lists. |
