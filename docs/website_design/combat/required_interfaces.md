# Combat — Required Interfaces

The combat encounter stub does almost no rules math itself; it gathers the GM's
choices and calls out to the other domains. This document is the **contract**:
one section per domain, listing exactly the entry points and data the combat
stub needs. Each section is the **partial stub** that domain's branch must
provide for combat to work — when a domain is built on its own branch, it must
satisfy at least the surface listed here.

Notation: **Name** — `inputs` → result / behavior. Names mirror the current
combined implementation where one exists; the shapes are the part that matters.

---

## Check Resolution

Combat composes Check Resolution's roll surface and defers all per-Roll and
per-Check math to it. Player-facing definitions live in
[`../../game_rules/check_resolution`](../../game_rules/check_resolution/check_resolution_overview.md).

- **Roll table (composable UI)** — the embedded roll stub the Action Builder
  mounts as its terminal step: `Roll All` + `Confirm` + the dice table; rolls
  each seed Roll client-side and allows a manual Result override before Confirm.
- **Compute Target Number & Starting Value** — `Roll.bonus_penalty_list` (+
  Base/Min/Max Target Number) → per-type stacking → **Dice Modifier** → clamped
  **Roll Target Number** + **Starting Value** (the clamp overflow).
- **Resolve a Roll** — `dice_count, target_number, starting_value, die_size,
  failure_modifier?, critical_modifier?, preroll?, reroll/nudge slots` →
  `{ successes, crits, degree_of_individual_success }`.
- **Net & classify a Check** — supporting Successes − opposing Successes →
  net **Degree of Success**; classify against the Default Success / Fumble
  Thresholds into success / failure / fumble (a check can always fumble).
- **Cross-side propagation** — invert each side's bonus/penalty entries onto the
  other (keeping type), honoring a Roll's `no_propagate` list (Dodge keeps its
  Competency local; its Inherent still crosses).
- **Ascendancy** — derived per Roll during TN computation from the Inherent
  imbalance (`floor(2 × gap)`, gated on a present Inherent Penalty). Combat only
  supplies an `Inherent` entry on each combat Roll (emitted even at Tier 0).
- **Reroll / Mass Reroll / Nudge / Luck** — reroll slots `positive_reroll` /
  `negative_reroll` (max per sign, no stacking, each die rerolled once); Combat
  only sets the data.
- **Preroll (Set-Value Spend)** — fold `N` prerolled dice in at Die Size (each a
  Crit); when `dice_count = 0`, score the prerolled dice alone.
- **Critical Modifier override** — accept a per-Roll `critical_modifier` (Combat
  supplies it per Damage Type via *Critical Modifier For*).
- **Additional Damage** — the elemental-weapon extra-dice roll (`Successes +
  Crits`), used by the Attack rider phase. See game_rules → *Additional Damage*.
- **Die Size** — the shared config value, queried at point of use.

## Damage

Combat hands raw damage to the Damage domain and gets back a per-Severity map to
write through Conditions. Player-facing rules:
[`../../game_rules/damage`](../../game_rules/damage/damage_overview.md). (In the
combined implementation this pipeline lived in Encounter; the split moves it to
Damage.)

- **Apply Damage** — `defender_ref, raw_damage, damage_type, threshold?,
  attacker_tier, defender_tier` → `{ minor, moderate, major }` plus mechanic
  outputs. Internally: subtract **Damage Reduction** and **Ascendancy Damage
  Reduction** (`floor(Per-Tier × Δ)`, Δ = defender − attacker effective Tier,
  Tier 0 = 0.5, zero-clamped); **runtime-bucket** physical damage by `Threshold
  + Damage Resilience` (Minor, then Moderate, then Major); fire **Damage Type
  Mechanics**.
- **Damage Type catalog** — per type: default Severity or `runtime_bucketed`,
  `parent` inheritance, and mechanics (`damage_per_hit`, `damage_multiplier`,
  `upgrade_severity` + condition tags, `apply_acid_counter`, `inflict` e.g.
  cold → Shock, `critical_value`).
- **Damage Resilience** — the defender's resilience value used during bucketing.
- **Glory (effective-Tier override)** — a weapon-only bump that shrinks Δ before
  Ascendancy Damage Reduction; never applies to spells/abilities.
- **Bleed / falling-damage conventions** — `Bleed Constant + raw_damage`, the
  Falling Damage Threshold, etc. (combat passes the raw figures in).

Conditions side-effects (Acid Counter, Shock) are *applied by* Conditions; the
Damage domain only tells Combat which fired.

## Conditions

Conditions owns all per-Creature mutable state; Combat invokes it to read and
mutate. Combat never stores HP, mana, toxicity, afflictions, or effects.

- **Apply Hit Point Damage** — `{ minor, moderate, major }` → Temporary HP
  absorbs worst-first, the rest lands as damage.
- **Apply Acid Damage** / **Apply Shock** — route Damage Type side-effects.
- **Apply Mana Cost** — `amount` → debit `mana_spent`.
- **Apply Magic Toxicity** — `amount, source_kind` → gated by the Toxicity
  Threshold (`floor(Charisma × Tier)`, Tier 0 = 0.5) for positive sources.
- **Apply Named Effect / Apply Effect** — grant a Condition + its Modifiers, or a
  timed modifier Active Effect with a turns-based `duration`.
- **Resolve Affliction** — `affliction, potency, net_dois` → consequence +
  decay / reschedule. **Reduce Affliction Potency** — `affliction, amount`.
  **Inflict Affliction** — bleed / poison channel, scheduled to the victim's
  next turn.
- **Clear Expired Effects** — for the current Round. **Expire Zone Effects For** —
  drop a Combatant's elapsed spell Zones at its turn start.
- **Creature Can Act?**, **Creature Is Dying?**, **Dead?** — booleans.
- **Removal** — *Remove Active Effect* / *Remove Active Affliction* / clear a
  counter (for the tracker badge `×`).
- **Reads** — `acid_counter`, `shock`, `ability_damage` map, `magic_toxicity`,
  `mana_spent`, Temporary HP, active afflictions (with Potency), active effects,
  per-Severity HP damage.

## Creatures

Read through a `creature_lookup`; Combat reads, never writes, the Creature.

- **Look up Creature** — `creature_ref` → name, `tags` (incl. `player_character`).
- **Vitals** — Max HP, Max Mana, **Tier**, the per-Tier **Inherent Bonus**
  (`+Tier`), **Damage Resilience**.
- **Effective attributes** — used for default spell damage's casting stat and
  the Toxicity Threshold's Charisma.
- **Sheet contents** — known spells and granted abilities (or via Abilities).

## Proficiencies

- **Compute Roll inputs for a Proficiency** — `key, attribute_override?` →
  `{ dice_cap, competency_modifier }`. Drives attack rolls, the `dex_save`
  Dodge, every Saving Throw (`<attr>_save`, full Dice Cap), casting-skill rolls,
  and Performance checks.

## Equipment

- **Get Weapon Details** — `base_damage`/`damage_formula`, `damage_types`,
  `bleed`, `threshold` (+ Property deltas), `affliction`, `damage_riders`,
  `tier_advantage` (Glory), `tags`, `ammo_type`.
- **Get Armor Details** — `damage_reduction`, `resilience`, metal-armor flag.
- **Consumable spell items** — the actor's Potions / Scrolls, each with its
  `item_cast_skill` (Evocation default) and resolved spell-at-Tier name;
  **Item-Form Magic Toxicity** for a Potion.
- **Granted spells** — spells an equipped Wand / Ring lends to the Cast list.
- **Remove Item / Cleanup** — decrement a consumed charge on commit.

## Abilities

Abilities owns how a spell or talent works; Combat routes the resolved Effects
without interpreting them.

- **Resolve Spell** — `spell, caster, dice/successes, targets` → Effects:
  `{ damage: {amount, type} }`, per-Severity heal, mana, Temporary HP / ward,
  named Active Effect, timed `modifiers:`, `bleed_reduction`.
- **Spell metadata** — Tier, per-Tier Mana Cost, `save:` block (Save Attribute,
  `on_success: halved|none`), `target` / `area` / `range` / shape, casting
  `skills`, `attack_roll`, `duration`, an explicit damage formula (else the
  default `floor(casting stat / 4) + Tier + Successes`).
- **Talents / Special Abilities** — `activation_time`
  (`free`/`bonus`/`main`/`reaction`/`trigger`), `mana_cost`, named effects +
  Modifiers + `duration`, Reservoir `fill` (Bardic Inspiration), `roll_table`
  (Reaction tables).
- **Bonus Types List** — the canonical set (Circumstance, Guidance, Inherent,
  Morale, Ascendancy); Combat owns per-Type stacking.
- **Modifier system** — surfaces situational modifiers (Weapon Training, defense
  bonuses) Combat layers onto a Roll.

## Other domains (brief)

- **Atlas** — place / remove a Zone for a committed area spell, anchored at the
  target's Token.
- **Chronicle** — *Advance current Timestamp* on a Round wrap; staleness check.
- **Timekeeping** — Round Length, to convert a spell's minute/hour `duration`
  into Rounds for Zone / effect expiry.
