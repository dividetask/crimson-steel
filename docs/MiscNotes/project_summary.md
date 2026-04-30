# Project Design Summary

Living document summarizing decisions made during the design of this tabletop RPG's dice resolution, attack roll, and equipment/loot systems. Intended to preserve context so future work (by you, by Claude, or by anyone joining the project) doesn't retread settled ground.

---

## Project context

You are designing a tabletop RPG with three companion implementations:

- A tabletop rules document (human-facing).
- A first-person shooter written in C#.
- A DM aid written in Ruby (the `crimson-steel` repository).

Design files are language-agnostic. Each module is expressed as a glossary of defined terms, one or more YAML config files, and a pseudocode specification. Implementers translate the pseudocode to the target language using their own naming conventions.

The current `crimson-steel` repo is serving as a reference for existing logic, but the glossary and pseudocode are **canonical** — when they disagree with the repo, the repo is considered outdated.

---

## File and naming conventions

- **Pseudocode**: class names in `PascalCase`, method names in `ALL_CAPS_WITH_UNDERSCORES` to signal pseudocode (rename on translation).
- **YAML keys**: top-level section headings are human-readable (capitalized, spaces allowed). Inner field names use `snake_case`.
- **Field naming in text**: when referring to YAML config keys from English prose, the human-readable form is used.
- **Consistent use of underscores throughout code identifiers and file names.** Hyphens reserved for file-glob patterns (e.g., `loot-*.yaml`).
- **Defined terms** in glossaries are capitalized to distinguish them from surrounding prose.
- **Abbreviations** declared in glossary entries (e.g., Target Number → TN).

---

## Files produced so far

| File | Purpose |
|---|---|
| `dice_resolution_glossary.md` | Glossary for the dice resolution module. |
| `dice_resolution_config.yaml` | Configurable values for dice resolution. |
| `dice_resolution_pseudocode.md` | Pseudocode for the `DiceSystem` class. |
| `unassigned_glossary.md` | Terms removed from dice resolution that belong to other modules. Includes Luck, Insight, Training Ranks, Physical Modifier, Total Prowess, Prowess Bonus, Attack Check, Spell Check, Variable Target Number, Half Modifier, and the named bonus types (Competency, Circumstance, etc.). |
| `unassigned_config.yaml` | Values removed from dice resolution that belong elsewhere: Base Prowess Offset, Half Modifier Divisor. |
| `equipment_config.yaml` | Weapons, armor, ammunition, currencies, magical properties, pricing, and naming rules. |
| `loot.yaml` | Sample inventory tracking. |
| `loot_routing.yaml` | Rules for which file a given owner's inventory is written to. |

Not yet produced: Attack Roll glossary/pseudocode/config, Equipment class glossary/pseudocode, Loot class glossary/pseudocode, character module, combat module.

---

## Dice resolution module

### Terms and concepts

- **Tier**: density of magical energy in a creature, item, spell, or ability.
- **Die Size**: number of sides on each die. Configurable.
- **Check**: a resolution for any action with a chance of failure. Composed of one or more Rolls.
- **Roll**: a single creature's contribution to a Check.
- **Primary Roll**: a Roll by the creature attempting the Check. (Retained for forward use; not mechanically distinguished from Supporting Roll in this module.)
- **Supporting Roll**: a Roll that contributes positively to Degree of Success. Includes Primary Roll and allies assisting.
- **Opposed Roll**: a Roll that contributes negatively to Degree of Success.
- **Initial Roll** / **Final Roll**: the results before and after any rerolls or value adjustments.
- **Dice Count**: dice rolled on a specific Roll. Bounded by Minimum Dice Count and Maximum Dice Count (which is `Minimum Dice Count + Dice Count Range - 1`).
- **Success**, **Failure**, **Critical Success**: die outcomes. Each has a configurable modifier (`-1`, `2`, `1` by default). Failures can be disabled by passing `failure_modifier = 0`.
- **Critical Count**: number of dice showing Die Size in a Roll.
- **Target Number** (**TN**): threshold each die is compared against. Derived from Base TN plus modifier math, clamped between Min TN and Max TN.
- **Starting Value**: signed integer Starting contribution from modifiers and overflow. Positive = Starting Successes, negative = Starting Failures.
- **Degree of Individual Success** / **Degree of Success**: net numeric result of a Roll / Check.

### Configuration (`dice_resolution_config.yaml`)

```
Die Size: 10
Base Target Number: 6
Minimum Target Number: 3
Maximum Target Number: 9
Minimum Dice Count: 6
Dice Count Range: 5
Default Success Threshold: 2
Default Fumble Threshold: 2
Bonus Types List:
  Competency, Circumstance, Morale, Guidance, Inherent, Ascendancy
```

### Modifier system

- **Target Number Modifiers** (affect TN): Bonus and Penalty per type. Bonus/Penalty of the same type do not stack — only the highest of each applies, and their signed sum is the net effect.
- **Roll Modifiers** (affect dice, not TN): Luck (rerolls) and Insight (value adjustment). Defined in `unassigned_glossary.md` because the named effects belong to the magic/character module; the mechanical operations (`APPLY_NUDGE`, `RAND_REROLL_SOME_DICE`) live in dice resolution.
- **Bonus/Penalty/Starting by type**: any type in Bonus Types List may produce a `<Type> Bonus`, `<Type> Penalty`, and `<Type> Starting` modifier. Unrecognized keys throw an exception.
- **Overflow**: TN modifiers exceeding Min/Max TN convert 1:1 to Starting Successes / Starting Failures.
- **Signed values**: `starting_value`, `reroll_count`, `nudge_amount`, `luck_value`, `insight_value` are all signed — positive for bonuses/improvements, negative for penalties/worsenings, zero for no effect. Bonus and Penalty are never both present for Luck/Insight on a single Roll.

### `DiceSystem` methods

- `CONSTRUCTOR(config_path, random_source)` — loads YAML, initializes random source.
- `RAND_ROLL_DIE()` — rolls one die.
- `RAND_ROLL_DICE(dice_count)` — rolls multiple.
- `COMPUTE_ROLL_PARAMETERS(modifiers)` — returns `tn` and `starting_value`. Validates keys.
- `COMPUTE_RESULTS(dice, tn, starting_value, failure_modifier=-1, critical_modifier=2)` — returns DoIS and Critical Count.
- `APPLY_NUDGE(dice, nudge_amount, tn, failure_modifier=-1, critical_modifier=2)` — chooses the die whose DoIS contribution changes most; applies nudge, clamps to `[1, die_size]`.
- `RAND_REROLL_SOME_DICE(dice, reroll_count, tn)` — positive rerolls failures (low-to-high), negative rerolls successes (high-to-low); no die rerolled more than once.
- Helpers: `COMPUTE_NUDGE_EFFECT`, `COMPUTE_ASCENDING_INDICES`.

### Named Roll Modifier effects (in `unassigned_glossary.md`)

- **Luck Bonus/Penalty**: invokes the Reroll Operation.
- **Insight Bonus/Penalty**: invokes the Value Adjustment (nudge) operation. Insight is applied before Luck.

### Key design decisions

- DiceSystem is deliberately ignorant of modifier semantics — all it sees are signed integers keyed by type.
- Stateless CheckResolver was designed but not built yet; decided a caller can assemble checks directly using DiceSystem methods.
- Modifier validation is strict: unknown keys throw. Silent acceptance was rejected for defensive reasons.
- Tie-break convention: first occurrence (lowest index) wins in all lookups.

---

## Equipment system

### Scope

Defines what items CAN exist: weapons, armor, ammunition, currency, magical properties, tier surcharges, naming rules. Does not define individual magical item variants (those are constructed at runtime from the combination of a mundane item + tier + properties).

### Pricing

- All prices in gold pieces (gp) as decimal numbers.
- Currency exchange: 1 gp = 10 sp = 100 cp. So 1 sp = 10 cp.
- Prices may be fractional (e.g., a magical arrow at 7.75 gp).
- Decimal floating-point accepted throughout; code that compares prices should use tolerance-based equality rather than strict equality.

### Tier surcharges (shared, immutable across weapon/armor/ammo)

| Tier | Surcharge |
|---|---|
| 0 | 0 gp (non-magical) |
| 1 | 250 gp |
| 2 | 1000 gp |
| 3 | 4000 gp |
| 4 | 16000 gp |
| 5 | 80000 gp |

### Weapons

Categories: Ranged (projectile and thrown collapsed), One Handed, Two Handed.

Damage formulas by category:
- Ranged: `str / 4`
- One Handed: `str / 4 - 2`
- Two Handed: `str / 2 + 2`
- Thrown weapons (Ranged with no `ammo_type`): overridden to `str / 4 - 2` individually on each weapon.

Damage types: Slashing, Bludgeoning, Piercing. Each provides default bleed and threshold (Slashing: 7/5, Bludgeoning: 5/3, Piercing: 3/4). Multi-type weapons use best-of (highest bleed, lowest threshold).

A ranged weapon with an `ammo_type` field uses projectile ammunition; a ranged weapon without one is thrown.

Weapon properties field (free-form list). Currently one property defined: `double_weapon` (Quarterstaff, Twinblade).

### Weapon magical properties

- **Tier 1 (melee, ranged, ammo)**: Elemental (subtype Fire/Acid/Electricity/Cold, 500 gp), Subdual (250 gp), Emotional (500 gp), Radiant (500 gp).
- **Tier 2 (melee, ranged, ammo)**: Necrotic (2000 gp).
- **Tier 2 (melee only)**: Vicious (2000 gp). Ranged and ammo cannot be Vicious.
- Multiple properties per item are not enforced as illegal, but typically only one per item.

### Ammunition

- Sold in bundles of 20.
- Types: Arrow, Bolt, Blowgun dart, Stone.
- Magical ammunition unit cost = (mundane bundle price / 20) + (equivalent magical weapon surcharge / 100).
- Ammunition cannot be Vicious.
- One arrow fired is destroyed (recovery mechanics may be added later).

### Armor

Categories and their defaults:

| Category | DR | Resilience Increment | Category Level |
|---|---|---|---|
| Light | 1 | 1 | 1 |
| Medium | 3 | 2 | 2 |
| Heavy | 6 | 3 | 3 |
| Shield | null | null | 1 |

Materials and their defaults:

| Material | Hardness | HP Formula |
|---|---|---|
| Leather | 2 | 5 × category_level |
| Metal | 10 | 30 × category_level |
| Wood | 5 | 10 × category_level |

Resilience: non-magical armor has none. Magical armor has `tier × resilience_increment` resilience.

Specific armors defined: Leather armor, Chain shirt, Hide armor, Chain mail, Plate mail, Light wooden shield, Light shield, Tower shield.

### Armor magical properties

- **Tier 1**: Fortification (500, not shields), Spell Storing 1 (500), Spell Crystal 0 (1000), Elemental Affinity (500, has subtype).
- **Tier 2**: Spell Storing 2 (2000), Spell Crystal 1 (4000), Elemental Resistance (2000, has subtype).
- **Spell Storing N**: can store one spell at tier ≤ N. Expends the spell on use.
- **Spell Crystal N**: holds one spell at tier ≤ N; allows the bearer to cast it by paying mana rather than consuming the stored spell. (Further details TBD.)

Higher tier properties will be added later.

### Naming convention

Generated name format:
```
+N <property_prefixes...> <item_name> <property_suffixes...>
```

- Tier prefix `+N` shown for magical (tier ≥ 1) weapons and armor. Omitted for tier 0 and for any category listed in `tier_hidden_for` (currently just Potion).
- Each magical property specifies a `display` block: a `word` and optional `position` (default `prefix`, alternative `suffix`).
- For properties with subtypes, the `display` block is keyed by subtype.
- Multiple properties apply in the order listed on the item. Prefixes accumulate in order; suffixes accumulate in order.
- An item entry may specify a `name` override that fully replaces the generated name.

Placeholder words I chose (change freely):

| Property | Word |
|---|---|
| Elemental Fire | Flaming |
| Elemental Acid | Corrosive |
| Elemental Electricity | Shocking |
| Elemental Cold | Freezing |
| Subdual | Merciful |
| Emotional | Laughing |
| Radiant | Radiant |
| Necrotic | Withering |
| Vicious | Vicious |
| Fortification | Fortified |
| Spell Storing 1 | Warded |
| Spell Storing 2 | Greater Warded |
| Spell Crystal 0 | Crystalline |
| Spell Crystal 1 | Prismatic |
| Elemental Affinity Fire / Acid / Electricity / Cold | Smoldering / Caustic / Storm-kissed / Frostbound |
| Elemental Resistance Fire / Acid / Electricity / Cold | Fireproof / Acidproof / Grounded / Coldproof |

---

## Loot and inventory system

### Model

- **Model A** stacked inventory: each entry is `(item_type, properties, quantity)`. Identical items merge into the same stack.
- **Stack identity**: two entries are identical only if all identity fields match — item name, tier, properties (in order), stored spell, durability damage, and name override.
- **No persistent item IDs**. Items are referenced by index within the owner's list at use time. No cross-file pointers, no references surviving server restarts.
- **Zero-quantity stacks are not auto-removed**. A cleanup pass (typically at server restart) removes them. Code reading inventory must filter `quantity > 0`.
- **Duplicates across files concatenate**. If the same character appears in multiple loaded files, their inventory entries are merged.

### Item entry fields

All optional except `item`:

- `item` (required): matches a name in equipment_config.
- `quantity`: defaults to 1.
- `tier`: defaults to 0.
- `properties`: list of applied magical properties.
- `stored_spell`: name of stored spell; absent or blank means expended.
- `durability_damage`: damage taken, defaults to 0.
- `name`: overrides generated name.
- `restock_target`: desired quantity. Defaults to 0.

### Currency

Treated as items. An inventory entry `{item: Gold, quantity: 147.5}` is valid. Currency value conversion lives in the Equipment class (1 gp = 10 sp = 100 cp).

### File layout

- **`loot.yaml`**: base file, sample inventory data.
- **`loot-*.yaml`**: additional files discovered by glob. Loader concatenates everything.
- **`loot_routing.yaml`**: where new items get written per owner.

### Routing precedence (highest first)

1. `character_overrides` (by character ID).
2. `group_overrides` (by group ID — groups defined in the character module).
3. `party_file` for the party pool.
4. `ground_file` for ground piles.
5. `default_file` fallback.

When both a character override and a group override could apply, the character override wins.

### Ground piles

Items at a named location. Location is a free-form string (e.g., `"Goblin cave — entrance"`). Persists until picked up or cleared.

### Restock

- `restock_target` lives on any item entry (not just consumables) but typically only meaningful on consumables.
- Restock action computes `(restock_target - quantity) × unit_price` for every understocked item, subtracts total from currency, increments quantities.
- Default `restock_target` is 0 (no restocking).

---

## Attack Roll module (scope outlined, not yet written)

### Scope

- Two attack types: **melee** and **ranged**. Melee allows parry; ranged does not. One class likely handles both with a range-type parameter.
- Participants: **attacker**, **defender**, **attacking weapon**, plus reactions from any non-attacker creatures present.
- Each non-attacker creature gets one reaction per attack (not per turn). Reactions include dodge, parry (melee only), block, use a special ability, use a spell, or do nothing.
- Flat-footed and unaware conditions adjust TN, not starting failures.
- Item enhancement bonuses (the +N from magical weapons) feed into Competency Bonus for the attack (assumed, not yet confirmed).
- Attack Roll is ignorant of spell and ability details. Reactions that invoke abilities or spells are resolved upstream into generic effects (e.g., "apply +1 Luck", "apply a Circumstance Bonus"), and Attack Roll receives those effects already resolved.

### Expected interface (provisional)

- Attack Roll calls into Equipment to resolve damage, bleed, threshold from the attacker's weapon, attacker's strength, attacker's tier, and defender's tier.
- Attack Roll calls into DiceSystem for the actual roll resolution.
- Attack Roll returns the hit outcome and damage.

### Open design questions

- Does Attack Roll compute damage, or does the combat module do it after Attack Roll returns a Degree of Success?
- Exact shape of the reaction system. The assumption so far: caller collects and resolves reactions before invoking Attack Roll, passing in generic effects. Not yet confirmed.
- Whether Attack Roll returns a hit/miss/crit classification or just Degree of Success + dice.

### Open rules questions

- **Defender tier's role in threshold calculation.** You mentioned it's relevant but the mechanism is not yet specified. This is a blocker for writing the damage calculation in the Equipment class.

---

## Character module (scope, not yet written)

Outside the scope of the current work, but already referenced by dice resolution. Expected to own:

- **Training Ranks**, **Physical Modifier**, **Total Prowess**, **Prowess Bonus**, **Skill Dice Maximum** (in `unassigned_glossary.md`). *(The Skill Roll slice — Skill Prowess and the Dice Count / Competency Bonus / Starting Value partition — is now owned: Skills computes Prowess and DiceSystem partitions it via `compute_check_details`.)*
- **Half Modifier** calculation (divisor stored in character config). *(Now lives on Skills as `skill_prowess.attribute_contribution_divisor` for Skill Rolls.)*
- **Base Prowess Offset** (currently in `unassigned_config.yaml`).
- Named bonus types (Competency, Circumstance, Morale, Guidance, Inherent, Ascendancy) — definitions live in `unassigned_glossary.md` until the character/magic/combat modules claim them.
- Character IDs and Group IDs referenced by `loot_routing.yaml`.
- Character Competency Bonus vs. Effective Competency Bonus distinction (the distinction between a character's innate Competency and what they project on a specific Roll).
- Converting a creature's attributes into the modifier dict that DiceSystem accepts.

---

## Combat module (scope, not yet written)

Expected to own:

- Attack Check (currently in `unassigned_glossary.md`), including the "meets Default Success Threshold → damage + Degree of Success" rule.
- Circumstance Bonus/Penalty and Ascendancy Bonus/Penalty application.
- Reaction collection and resolution (feeding into Attack Roll).
- Turn order / initiative (initiative rolls now go through DiceSystem, per the pseudocode workflow — not the inline dice-rolling in the reference repo).
- Fumble consequences (DM-determined).

---

## Magic / spells module (scope, not yet written)

Expected to own:

- Spell Check (currently in `unassigned_glossary.md`).
- Variable Target Number mechanic for a caster rolling against multiple targets with different TN modifiers.
- Luck and Insight as spell/divination effects (which invoke the generic DiceSystem Roll Modifier operations).
- Guidance Bonus/Penalty, Inherent Bonus.
- Spell Storing and Spell Crystal semantics (what spell tiers can be stored, how casting from a crystal interacts with mana).
- Potion, scroll, wand, and ritual item types and their effects.

---

## Open questions still pending

These are carried over from in-progress conversations and not yet resolved:

1. **Defender tier's role in threshold calculation.** Blocks the Equipment class's threshold computation and likely part of the Attack Roll damage flow. You said you'd explain later.

2. **Attack Roll interface final shape.** Whether the class drives reaction collection itself or consumes already-resolved reactions (leaning on the latter).

3. **Attack Roll return value.** Whether it includes hit/miss interpretation or only the numeric Degree of Success.

4. **Insight Penalty for initiative.** Initiative-specific Insight semantics were outlined for the Bonus case but not the Penalty case. May no longer matter if initiative uses the generic `APPLY_NUDGE` (per the current pseudocode), but worth confirming.

5. **Item durability mechanics.** The `durability_damage` field exists but durability's actual game effect (penalties? breakage?) isn't specified.

6. **Spell Crystal mana cost.** Spell Crystal lets the bearer cast a stored spell by paying mana instead of consuming the spell. How much mana, what stat determines it, whether the crystal has a usage cap per period — all unspecified.

7. **Multiple properties on the same item.** Mechanically supported, but the default rule is one property per item. Which specific properties allow stacking (and with what rules) is not yet defined.

8. **Higher-tier (3+) magical properties.** None yet defined. Tier 3+ items currently benefit only from the tier surcharge with no additional property choices.

9. **Thrown weapon damage balance.** When Thrown and Ranged categories collapsed into Ranged, thrown weapons got an individual damage override to keep `str / 4 - 2`. Worth a balance review at some point.

10. **Whip bleed value.** The Whip has `damage: 0` and `threshold: null` overrides but keeps the default Slashing bleed (7). May want to be explicit about whether this is intentional.

11. **Shield damage reduction.** Tower Shield currently has `null` damage reduction (inherited from the Shield category default). No specific shield overrides this. Intuitively, different shield sizes probably should provide different DR, but no model has been proposed yet.

---

## Process conventions

These have emerged through the work and should be kept in mind:

- **Questions belong in conversation, not in the files.** Claude should ask questions directly rather than embedding them in generated documents.
- **Claude is expected to flag unintended balance changes.** When a refactor has game-mechanic side effects (e.g., thrown weapons getting a +2 damage buff), those should be called out.
- **Changes to configurable values are rare and between executions.** Config is hand-edited during rule tuning, then stabilizes. No runtime config reloads planned.
- **Canonical source is the glossary and pseudocode.** The reference repo has outdated logic; diverge from it when necessary.
- **Keep modules ignorant of concerns outside their scope.** DiceSystem doesn't know about creatures. Equipment doesn't know about character sheets. Attack Roll doesn't know about spell internals. Cross-module concepts live in their least-surprising home and get referenced (not duplicated) elsewhere.
