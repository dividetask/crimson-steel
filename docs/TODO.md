# TODO — Restoring Functionality Lost to the Refactor

Functionality `before-refactor` had that the current branch doesn't yet match, plus a sequenced rebuild plan. `before-refactor` was a monolith (~3000-line `app.rb`, 60 HTTP routes); the new architecture splits the same surface into nine specialized domains but currently exposes only `/` and `/view-mode`.

## Inventory of feature areas

| Feature area | `before-refactor` | New arch — docs | New arch — lib | Gap |
|---|---|---|---|---|
| Dice resolution | inlined | ✅ | ✅ `dice_system.rb` | done |
| Character (identity + delegation) | `CharacterSheet` | ✅ | ✅ `character.rb` | done |
| Race | inside character.rb | ✅ | ✅ `race.rb` | done |
| Advancement (tier, classes, skills, saves) | `SingleKlassProgress` | ✅ | ✅ `advancement.rb` | done |
| Always-On Modifiers | inlined | ✅ | ✅ `modifiers.rb` | done |
| Combat tracker (initiative, Combat Pool) | `Combat` class | ✅ | ✅ `combat.rb` | partial — no attack resolution |
| Conditions (HP, Temp HP, magic toxicity, shock, acid, afflictions, effects) | inlined per-CombatTurn | ✅ | ❌ | **lib missing** |
| Damage Types catalog | hardcoded in rules.json | ✅ | ❌ | **lib missing** |
| Abilities / Spells reference | `Compendium` class | ✅ | ❌ | **lib missing** |
| Equipment / Inventory | inlined into character.rb | ✅ | ❌ | **lib missing** |
| Skills config | inlined in rules.json | ✅ (catalog only) | ❌ helper | **lib helper missing** |
| Attack resolution (calculate_damage) | `Combat.calculate_damage` | partial (severity routing in combat_design) | ❌ | **schema + lib missing** |
| Procedural Class/Race Abilities catalog | `rules.json reference.abilities` | ✅ | ❌ | **catalog content + lib missing** |
| Bardic Inspiration / Luck points | `Combat#bardic_inspiration` | ✅ (in Conditions design) | ❌ | **lib missing** |
| Spell casting flow | inlined in routes | ✅ | ✅ `lib/casting.rb` | mana_cost field on schema is a follow-up |
| Rituals | inlined | partial | ❌ | **lib missing** |
| Store / purchasing | inlined | partial (Equipment shops in docs) | ❌ | **lib missing** |
| Downtime (cast, rest, services, urgent, quick) | 7 routes + helpers | ❌ | ❌ | **design + lib missing** |
| Notes system | inlined | partial (`notes_state.rb`) | partial | needs review |
| Scene view (DM tool) | 14 routes | ❌ | ❌ | **design + lib missing** |
| Enemy instances | `enemy_instance.erb` + routes | ❌ | ❌ | **design + lib missing** |
| Templates (enemy archetypes + gear tables) | `templates.rb` | partial (loot tables in equipment) | ❌ | **design merge + lib missing** |
| Per-player view mode | `view_mode` cookie + `viewer_id` | partial | partial | needs review |
| All-characters view | `/all_characters/:index` | ❌ | ❌ | **UI missing** |

## Sequenced rebuild plan

### Phase 1 — Module libraries the rest of the system depends on

Pure data/state libraries with no UI. Block every later phase.

- [ ] **Conditions library** (`lib/conditions.rb`).
  Per-creature damage counters, temp HP single-grant rule, magic toxicity, Shock with overflow, Acid Counter, afflictions with severity evolution, Effects list with source-id replacement and lookup-time stacking, `APPLY_NAMED_EFFECT`, `REMOVE_EFFECTS_BY_PREFIX`, atomic serialization. Loads `conditions_config.yaml`.

- [ ] **Damage Types library** (`lib/damage_types.rb`).
  Reference module: load `damage_types_config.yaml`, expose Severity, Mechanics, runtime-bucketing flag. Closed validator for `damage_per_dice`, `apply_acid_counter`, `damage_multiplier`, `inflict`, `critical_value`.

- [ ] **Abilities library** (`lib/abilities.rb`).
  Reference module: load `compendium.json`, validate every entry, resolve Variants (tier or aspects axis), evaluate Effect Hashes, expose `RESOLVE_ENTRY`, `GET_PROCEDURAL_TRIGGERS`, `GET_ABILITY_MODIFIERS`.

- [ ] **Equipment library** (`lib/equipment.rb`).
  The largest of the four. Per-Owner inventories, four Owner kinds, Stack Identity / Merge / Cleanup, item add/remove/adjust/transfer, per-category Unit Price, Total Wealth, Debit Wealth, loot-table rolling (four row shapes + Roll Variables), magical-item generation, specific/generic shop refresh, atomic Restock, Loot Archive open/claim/close, three detail-fetchers, equip-time wiring to Conditions via the `equipment:*` namespace.

### Phase 2 — Combat-side wiring needing Phase 1's modules

- [ ] **Attack resolution** in `lib/combat.rb`.
  Implement the Severity Calculation pipeline from `combat_design.md`: damage type lookup → pre-bucketing mechanics → severity decision → `APPLY_HIT_POINT_DAMAGE` → post-damage side-effects. Includes rolling the attack itself through DiceSystem and consuming weapon/armor/threshold/resilience inputs.

- [ ] **Bardic Inspiration / Luck point spend.**
  Combat route that spends a luck point against a target check, decrementing the Conditions counter. Reset at start of turn.

- [ ] **Cure cascade and Ability cure cascade.**
  `APPLY_HIT_POINT_HEAL_CASCADE` and `APPLY_ABILITY_HEAL_CASCADE`. Hookup point lives wherever healing spells are cast.

### Phase 3 — Spell casting and rituals

- [x] **Cast spell** flow. ✅ `lib/casting.rb`. Mana cost is a caller parameter today; adding a `mana_cost` field to the abilities schema is a follow-up.

- [x] **Cast ritual** flow. ✅ `Casting#cast_ritual`. Reads per-tier material gold from `Ritual Cost.gold_per_tier`, debits via Equipment. Returns total casting time. `error: 'insufficient_gold'` when the owner can't pay — no mana spent, no effects.

- [x] **Use item / consume.** ✅ `lib/item_use.rb`. Per-form Magic Toxicity, saturation gate, conventional Effect Hash keys, improved_healing scroll discount, quantity decrement. Wand mana flow deferred.

### Phase 4 — Store and Downtime

Depend on Equipment + Spells.

- [ ] **Store routes** (`/store`, `/purchase/:item_index`, `/purchase_ritual`). Read shop inventory through Equipment, debit Character wealth, transfer Stack. Ritual purchase uses the same pattern but stores the result in `ritual_list`.

- [ ] **Ammunition / Spell / Ritual store generation.** `Compendium#ammunition_store_items`, `spell_store_items`, `ritual_store_items` from before-refactor.

- [ ] **Downtime routes** (`/downtime`, `/downtime/cast`, `/downtime/cast_ritual`, `/downtime/use_item`, `/downtime/service`, `/downtime/rest`, `/downtime/urgent_actions`, `/downtime/quick_resolve`).
  Needs a Downtime domain doc first — the only major feature area without a `docs/downtime/` folder.

### Phase 5 — UI and DM tools

- [ ] **Character sheet** view (full + minimal). Partially stubs today.
- [ ] **Combat tracker** view. Initiative order, current turn highlight, Combat Pool remaining, conditions, luck-points. Needs every Phase 1-2 module.
- [ ] **Spells browser** (`/spells`, `/spell/:name`). Reference UI; no mutation.
- [ ] **Add item** (`/add_item` GET + POST). DM injection tool.
- [ ] **Notes system.** Compare today's `notes_state.rb` against `before-refactor` notes routes; fill gaps.
- [ ] **Enemy instances** (`/enemies/:index`, `/enemies/instance/:id`, rename, reroll). Per-instance monster state. Likely a new `instances/` or `combatants/` domain.
- [ ] **Templates** (enemy archetypes + gear tables). Equipment loot-tables covers half; creature-template variant rolls need a parallel home (likely `templates/`).
- [ ] **Scene view** (DM tool — 14 routes). Initiative toggle, draft names/notes, panels, image sharing, promote-to-formal. Needs `docs/scene/` before any rebuild.
- [ ] **Per-player view mode**. `/view-mode` exists as a stub; restore full per-viewer filtering.
- [ ] **All-characters view** (`/all_characters/:index`). DM oversight UI.

## Cross-cutting prerequisites

Catalogs need content before any spell/ability features actually do anything:

- [ ] **Populate Effect Names** in `conditions_config.yaml` (`paralyzed`, `prone`, `flustered`, `dazzled`, `blind`, etc. — most sketched in the example).
- [ ] **Populate Procedural Abilities** in `abilities_config.yaml` (`sneak_attack`, `channel_divinity`, `improved_healing`, `sense_injury`). Each entry needs a Trigger Spec.
- [ ] **Populate Always-On Modifiers** on each ability entry's `modifiers:` field. Schema and a few examples on TentativeAdditions; fill out the rest.
- [ ] **Author the actual rules** for class contributions to `damage_resilience` / `damage_reduction` (placeholders return 0); per-day usage trackers (Channel Divinity, no home decided).

## Validation gaps to consider while rebuilding

A single startup-time linter (or CI script) loading every config and walking cross-references would knock out the whole cluster:

- Roster `race:` / class keys → real race / class.
- `parent_class`, `parent_race` → real chain target.
- Skill list entries → real Skills.
- `tier_attribute_advancement` picks → real attribute keys.
- `attribute:` in `skills_config.yaml` → real attribute.
- Loot table `item:` / property references → real catalog entries.
- Material names on Armor → defined Materials.
- Damage Types `condition` / `condition_name` strings → consumer-known.
- Effect strings declared by abilities → real Effect Names (raised today only at apply-time).
