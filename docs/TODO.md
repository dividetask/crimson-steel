# TODO — Restoring Functionality Lost to the Refactor

This document catalogs the functionality `before-refactor` had that the
current branch (post-refactor) does not yet match, and proposes an order
for rebuilding it on top of the new domain architecture.

`before-refactor` is the pre-refactor monolith: ~3000-line `app.rb`,
~1400-line `character.rb` with `CombatTurn` / `Combat` / `Compendium` /
`SingleKlassProgress` / `CharacterSheet` classes, and 60 HTTP routes
covering combat, scene view, enemies, notes, items, spells, store, and
downtime. The new architecture splits the same surface into nine
specialized domains with cleaner ownership but currently exposes only a
handful of routes (`/`, `/view-mode`).

## Inventory of feature areas

| Feature area | `before-refactor` | New arch — docs | New arch — lib | Gap |
|---|---|---|---|---|
| Dice resolution | inlined | ✅ | ✅ `dice_system.rb` | done |
| Character (identity + delegation) | `CharacterSheet` | ✅ | ✅ `character.rb` (refactored) | done |
| Race | inside character.rb | ✅ | ✅ `race.rb` | done |
| Advancement (tier, classes, skills, saves) | `SingleKlassProgress` | ✅ | ✅ `advancement.rb` | done |
| Always-On Modifiers | inlined | ✅ | ✅ `modifiers.rb` | done |
| Combat tracker (initiative, Combat Pool) | `Combat` class | ✅ | ✅ `combat.rb` | partial — no attack resolution |
| Conditions (HP, Temp HP, magic toxicity, shock, acid, afflictions, effects) | inlined per-CombatTurn | ✅ | ❌ | **lib missing** |
| Damage Types catalog | hardcoded in rules.json | ✅ | ❌ | **lib missing** |
| Abilities / Spells reference (compendium) | `Compendium` class | ✅ | ❌ | **lib missing** |
| Equipment / Inventory (items, weapons, armor, ammo, gems, currency) | inlined into character.rb | ✅ | ❌ | **lib missing** |
| Skills config | inlined in rules.json | ✅ (catalog only) | ❌ helper | **lib helper missing** |
| Attack resolution (calculate_damage) | `Combat.calculate_damage` | partial (severity routing in combat_design) | ❌ | **schema + lib missing** |
| Procedural Class/Race Abilities catalog | `rules.json reference.abilities` | ✅ (term defined) | ❌ | **catalog content + lib missing** |
| Bardic Inspiration / Luck points | `Combat#bardic_inspiration` | ✅ (in Conditions design) | ❌ | **lib missing** |
| Spell casting flow (mana spend, effects apply) | inlined in routes | ✅ | ✅ `lib/casting.rb` | mana_cost field on abilities schema is a follow-up |
| Rituals | inlined | partial | ❌ | **lib missing** |
| Store / purchasing | inlined | partial (Equipment shops in docs) | ❌ | **lib missing** |
| Downtime (cast, rest, services, urgent, quick) | 7 routes + helpers | ❌ | ❌ | **design + lib missing** |
| Notes system | inlined | partial (`notes_state.rb` exists) | partial | needs review |
| Scene view (DM tool) | 14 routes | ❌ | ❌ | **design + lib missing** |
| Enemy instances (per-instance state) | `enemy_instance.erb` + routes | ❌ | ❌ | **design + lib missing** |
| Templates (enemy archetypes + gear tables) | `templates.rb` | partial (loot tables in equipment) | ❌ | **design merge + lib missing** |
| Per-player view mode | `view_mode` cookie + `viewer_id` | partial (`/view-mode` route exists) | partial | needs review |
| All-characters view | `/all_characters/:index` | ❌ | ❌ | **UI missing** |

## Sequenced rebuild plan

The order below respects dependencies — each step's prerequisites have
been completed (or already exist in the new architecture) before the step
itself.

### Phase 1 — Module libraries the rest of the system depends on

These four are pure data/state libraries with no UI. Without them, every
later phase is blocked.

- [ ] **Conditions library** (`lib/conditions.rb`).
  Implement the design in `docs/conditions/conditions_design.md`:
  per-creature damage counters, temp HP single-grant rule, magic
  toxicity, Shock with overflow, Acid Counter (`APPLY_ACID_DAMAGE` /
  `RESOLVE_ACID_TURN_START`), afflictions with severity evolution, the
  Effects list with source-id replacement and lookup-time stacking,
  `APPLY_NAMED_EFFECT`, `REMOVE_EFFECTS_BY_PREFIX`, atomic
  serialization. Loads `conditions_config.yaml` (Effect Names + Afflictions).

- [ ] **Damage Types library** (`lib/damage_types.rb`).
  Reference module: load `damage_types_config.yaml`, expose Severity,
  Mechanics, and the runtime-bucketing flag for physical. Closed
  validator that recognizes the mechanic kinds (`damage_per_dice`,
  `apply_acid_counter`, `damage_multiplier`, `inflict`,
  `critical_value`).

- [ ] **Abilities library** (`lib/abilities.rb`).
  Reference module: load `compendium.json`, validate every entry,
  resolve Variants (tier or aspects axis), evaluate Effect Hashes, do
  the deferred-damage classification, expose `RESOLVE_ENTRY` and the
  procedural-ability lookups (`GET_PROCEDURAL_TRIGGERS`,
  `GET_ABILITY_MODIFIERS`).

- [ ] **Equipment library** (`lib/equipment.rb`).
  The largest of the four. Per-Owner inventories, the four Owner kinds,
  Stack Identity / Merge / Cleanup, item add / remove / adjust /
  transfer, the per-category Unit Price formulas, Total Wealth and
  Debit Wealth, loot-table rolling with the four row shapes and Roll
  Variables, magical-item generation, specific-and-generic shop
  refresh, atomic Restock, the Loot Archive open / claim / close, the
  three detail-fetchers (`GET_ITEM_DETAILS`, `GET_WEAPON_DETAILS`,
  `GET_ARMOR_DETAILS`), the equip-time wiring to Conditions via the
  `equipment:*` source-id namespace.

### Phase 2 — Combat-side wiring that needs Phase 1's modules

- [ ] **Attack resolution** in `lib/combat.rb`.
  The big missing piece. Implement the Severity Calculation pipeline
  documented in `docs/combat/combat_design.md`: damage type lookup →
  pre-bucketing mechanics (`damage_per_dice`, `damage_multiplier`) →
  severity decision (declared or runtime-bucketed) →
  `APPLY_HIT_POINT_DAMAGE` on the target's Conditions instance →
  post-damage side-effects (`APPLY_ACID_DAMAGE`, `APPLY_SHOCK`).
  Includes rolling the attack itself through DiceSystem and consuming
  weapon/armor/threshold/resilience inputs.

- [ ] **Bardic Inspiration / Luck point spend.**
  Today's design has Bardic Inspiration as a Conditions counter. Wire
  it: a Combat route that spends a luck point against a target check,
  decrementing the counter via Conditions. Reset at start of turn.

- [ ] **Cure cascade and Ability cure cascade.**
  The `APPLY_HIT_POINT_HEAL_CASCADE` and `APPLY_ABILITY_HEAL_CASCADE`
  operations from the conditions design. Hookup point lives wherever
  healing spells are cast.

### Phase 3 — Spell casting and rituals

- [x] **Cast spell** flow. ✅
  Implemented in `lib/casting.rb`. Resolves the entry, runs the
  mana check + saturation gate, spends mana, applies cure /
  ward / mana effects to the target's Conditions, imposes magic
  toxicity on the caster, returns deferred damage effects + save
  specs + concentration block for the caller to handle. Mana
  cost is currently a caller parameter — adding a `mana_cost`
  field to the abilities schema is a follow-up.

- [x] **Cast ritual** flow. ✅
  `Casting#cast_ritual` is a thin extension of `cast`. Reads the
  per-tier material gold cost from `Ritual Cost.gold_per_tier` and
  debits it from the supplied gold_owner_id (typically 'party')
  via Equipment. Reads the per-tier extra rounds from
  `Ritual Cost.casting_time_per_tier` and returns the total
  casting time. Mana cost, magic toxicity, and effects are
  inherited from `cast` unchanged. When the gold owner can't pay,
  returns `error: 'insufficient_gold'` — no mana spent, no
  effects.

- [x] **Use item / consume.** ✅
  Implemented in `lib/item_use.rb` (Phase 3, prior commit). Per-form
  Magic Toxicity formulas, saturation gate, conventional Effect
  Hash keys (cure / mana / temp_hp), the improved_healing scroll
  discount, and item quantity decrement. Wand mana flow is still
  deferred.

### Phase 4 — Store and Downtime

These depend on Equipment + Spells.

- [ ] **Store routes** (`/store`, `/purchase/:item_index`,
  `/purchase_ritual`). Read shop inventory through Equipment, debit
  Character wealth, transfer the Stack to the Character. Ritual
  purchase is the same pattern but the result lives in the
  Character's `ritual_list`.

- [ ] **Ammunition / Spell / Ritual store generation.**
  `Compendium#ammunition_store_items`, `spell_store_items`,
  `ritual_store_items` from before-refactor. Produces store stock
  from the spell catalog plus the available item forms.

- [ ] **Downtime routes** (`/downtime`, `/downtime/cast`,
  `/downtime/cast_ritual`, `/downtime/use_item`, `/downtime/service`,
  `/downtime/rest`, `/downtime/urgent_actions`,
  `/downtime/quick_resolve`).
  Need a small Downtime domain doc first — the per-route semantics
  weren't documented anywhere, and this is the only major feature
  area without a `docs/downtime/` folder. Sketch the flow, then
  implement.

### Phase 5 — UI and DM tools

- [ ] **Character sheet** view (full + minimal).
  Partially exists today as stubs. Wire to the full Character API.

- [ ] **Combat tracker** view.
  Initiative order, current turn highlight, Combat Pool remaining,
  conditions display, luck-points indicator for bards. Needs every
  Phase 1-2 module in place.

- [ ] **Spells browser** (`/spells`, `/spell/:name`).
  List the compendium and show full entry details. Reference UI;
  no mutation.

- [ ] **Add item** (`/add_item` GET + POST).
  DM tool to inject items into a Character or shop.

- [ ] **Notes system.**
  Today there's a `notes_state.rb`. Compare against the
  `before-refactor` notes routes (`/add_note`, `/add_note_entry`,
  `/notes/:viewer_id`) and fill in any gaps.

- [ ] **Enemy instances** (`/enemies/:index`,
  `/enemies/instance/:id`, rename, reroll). Per-instance state for
  monsters in combat. Probably belongs in a new `instances/` or
  `combatants/` domain — the Equipment-style "templates produce
  instances" pattern fits.

- [ ] **Templates** (enemy archetypes with gear tables and
  variants). The Equipment loot-tables work covers part of this; the
  creature-template part with variant rolls (`templates.rb` from
  before-refactor) needs a parallel home — likely a new
  `templates/` domain that consumes Equipment loot tables for the
  gear half.

- [ ] **Scene view** (DM tool — 14 routes).
  Initiative toggle, draft names, draft notes, panels, image
  sharing, promote-to-formal. This is a complex DM-facing UI with
  no current docs. Needs its own `docs/scene/` folder before any
  rebuild.

- [ ] **Per-player view mode** (`view_mode` cookie + `viewer_id`).
  `/view-mode` exists today as a stub. Restore the full per-viewer
  filtering.

- [ ] **All-characters view** (`/all_characters/:index`).
  DM oversight UI.

## Cross-cutting prerequisites

Independent of the phase order above, several catalogs need content
before any of the spell/ability features actually do anything:

- [ ] **Populate Effect Names** in `conditions_config.yaml` with every
  status referenced from the compendium (`paralyzed`, `prone`,
  `flustered`, `dazzled`, `blind`, etc. — most are sketched in the
  example config).
- [ ] **Populate Procedural Abilities** in
  `abilities_config.yaml` for every class/race ability that's
  stateless (`sneak_attack`, `channel_divinity`, `improved_healing`,
  `sense_injury`, etc.). Each entry needs a Trigger Spec
  (`on` / `condition` / `effect`). The full schema is still
  attack-resolution-dependent, so first iterations may use placeholder
  effect kinds.
- [ ] **Populate Always-On Modifiers** on each ability entry's
  `modifiers:` field. TentativeAdditions has the schema and a few
  examples (`fast_movement: speed +10`); fill out the rest.
- [ ] **Author the actual rules** for:
  - Class contributions to `damage_resilience` / `damage_reduction`
    (today's placeholders return 0).
  - Per-day usage trackers for abilities like Channel Divinity (no
    home decided yet).

## Validation gaps to consider while rebuilding

The refactor exposed several "silent typo" gaps documented across the
Unassigned sections of every domain design doc. Worth tackling as a
single linter pass once the libs are back:

- Roster `race:` / class keys → real race / class.
- `parent_class`, `parent_race` → real chain target.
- Skill list entries (`class_skills`, `non_class_skills`,
  `opposed_skills`) → real Skills.
- `tier_attribute_advancement` picks → real attribute keys.
- `attribute:` in `skills_config.yaml` → one of six real attributes.
- Loot table `item:` / property references → real catalog entries.
- Material names on Armor → defined Materials.
- Damage Types `condition` / `condition_name` strings → consumer-known.
- Effect strings declared by abilities → real Effect Names (raised
  today only at apply-time).

A single startup-time linter (or a CI script) that loads every config
and walks the cross-references would knock out the whole cluster.
