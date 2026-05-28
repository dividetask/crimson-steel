# Creatures — Tests

Tests for the public entry points of the Creatures domain.

Unless a test specifies otherwise, all tests use the values shipped in `creatures_config.yaml`, `creatures_advancement.yaml`, and `creatures_race.yaml`:

- Default Base Speed: 30
- Tier Minimum Inherent Bonus: `[0, 1, 2, 3, 4, 5]`
- Tier Inherent Chosen Bonus Count: `[0, 0, 2, 2, 2, 2]`
- Per-Tier Inherent Chosen Bonus Amount: 2
- Tier Breakpoints: as shipped in `creatures_advancement.yaml` — `player_character`, `hero`, `boss`, `noble`, `commoner`, `animal`, each carrying its full breakpoint list including the leading 0.
- Proficiency Advancement Rates: `aligned = floor(5 × level / 3)`, `unaligned = level`, `opposed = floor(2 × level / 3)`.
- Default Save Rate: `opposed`. Default Skill Rate: `unaligned`.
- HP Formula / Mana Base Formula: as shipped

Test scenarios refer to named hypothetical creatures (Korth the dwarven cleric, Brenna the human barbarian, Vex the elven arcane trickster, Birch the satyr bard, Ghoul, Brown Bear) by name and supply the data each scenario needs inline. These names do not have to match the records shipped in the example data files (`creatures_data_pcs.example.yaml`, `creatures_data_enemies.example.yaml`, `creatures_data_npcs.example.yaml`) — they are fixtures local to the test cases, chosen for narrative continuity within the suite.

When a scenario refers to one of these named fixtures, the relevant attributes, classes, levels, and tags are described in the scenario itself. The four hypothetical PCs are tagged `player_character` and at Total Class Level 4 (Tier 2). The Ghoul is tagged `hero` at Total Level 2 (Tier 1). The Brown Bear is tagged `animal` at Total Level 6 (Tier 1 — `breakpoints[1] = 4` is the highest entry ≤ 6).

---

## Look up Creature

**Existing ID returns an Accessor.** Given `creature_id = 1`: returns a Creature Accessor with `name = "Korth"`.

**Unknown ID returns null.** Given `creature_id = 999`: returns null.

**Accessor reads fresh from the underlying record.** After *Set Tier Override* on Creature 1 to `5`, a previously-held Accessor's `tier` returns 5 on the next call. Accessors do not snapshot.

---

## List Creatures

**No filter returns every Creature in load order.** Returns six pairs: `(1, "Korth")`, `(2, "Brenna")`, `(3, "Vex")`, `(4, "Birch")`, `(100, "Ghoul")`, `(101, "Brown Bear")`.

**Group filter narrows to matching Creatures.** With `group = "pc"`: returns the four PCs. `group = "enemy"`: returns Ghoul and Brown Bear.

**Tags filter requires every entry to be present.** With `tags = ["player_character"]`: returns the four PCs. With `tags = ["player_character", "missing"]`: returns the empty list.

---

## Find Creature by Name

**Exact match returns the Accessor.** Given `name = "Korth"`: returns the Accessor for Creature 1.

**Case mismatch returns null.** Given `name = "stumpy"`: returns null. Case-sensitive.

**Unknown name returns null.** Given `name = "Nobody"`: returns null.

---

## Get Tier

**`player_character` tag, Total Level 4 → Tier 2.** Korth (Cleric 4, tagged `player_character`): the `player_character` breakpoints `[0, 1, 4, 8, 16, 30]` give largest `i` with `breakpoints[i] ≤ 4` of index 2.

**`hero` tag, Total Level 2 → Tier 1.** Ghoul (tagged `hero`): the `hero` breakpoints `[0, 1, 4, 8, 16, 30]` give largest `i` with `breakpoints[i] ≤ 2` of index 1.

**`animal` tag, Total Level 6 → Tier 1.** Brown Bear (tagged `animal`, `breakpoints = [0, 4, 8, 12, 16, 20]`): largest `i` with `breakpoints[i] ≤ 6` is index 1 (`breakpoints[1] = 4`) → Tier 1.

**Multiple matching tags take the maximum.** A Creature tagged `[player_character, noble]` at Total Level 5: `player_character` produces Tier 2 (`breakpoints[2] = 4 ≤ 5`); `noble` produces Tier 2 (`breakpoints[2] = 5 ≤ 5`). Tier = max = 2.

**No matching tag takes the minimum across every list.** A Creature with tags that match none of `Tier Breakpoints`' keys at Total Level 12: every per-list Tier is computed and the minimum is returned. With the shipped lists, `animal: breakpoints[2] = 8 ≤ 12` → Tier 2; `commoner: breakpoints[1] = 4 ≤ 12, breakpoints[2] = 12 ≤ 12` → Tier 2; `noble: breakpoints[3] = 9 ≤ 12` → Tier 3; `player_character: breakpoints[3] = 8 ≤ 12` → Tier 3. The minimum is 2.

**Tier Override bypasses the computation.** After *Set Tier Override* on Korth to `4`: *Get Tier* returns 4, regardless of Total Level or tags.

**Tier zero is the floor.** A Creature with Total Level 0 on any matching tag resolves to Tier 0 (index 0 has breakpoint 0).

---

## Get Effective Attributes

**Tier 1 grants only the flat Per-Tier Inherent Bonus, no Chosen Bonus.** A hypothetical Cleric 1 tagged `player_character` with `attributes = { str: 10, ... }` and empty `tier_attribute_advancement`: Tier 1. `per_tier = Tier Minimum Inherent Bonus[1] = 1`. Chosen bonus is zero everywhere (`Tier Inherent Chosen Bonus Count[1] = 0`). Effective `str = 10 + racial + 1`.

**Tier 2 is the first Tier with a Chosen Bonus.** Korth (Tier 2) has `tier_attribute_advancement = [con, wis]`. The Tier 2 chunk consumes the first `Tier Inherent Chosen Bonus Count[2] = 2` entries → Tier 2 picks are `[con, wis]`. `per_tier = Tier Minimum Inherent Bonus[2] = 2` on every attribute. Chosen Bonus adds +2 each to `con` and `wis`.

Expected Effective Attributes (Korth is `race: hill_dwarf`, whose chain is `humanoid → dwarf → hill_dwarf`):
- `str = 12 + 0 (chain) + 2 (per-tier) + 0 (chosen) = 14`
- `dex = 14 + 0 + 2 + 0 = 16`
- `con = 17 + 2 (hill_dwarf) + 2 + 2 (chosen at Tier 2) = 23`
- `int = 14 + 0 + 2 + 0 = 16`
- `wis = 18 + 2 (hill_dwarf) + 2 + 2 (chosen at Tier 2) = 24`
- `cha = 11 + 0 + 2 + 0 = 13`

**Human "all+1" racial adjustment applies to every attribute.** Brenna (Human Barbarian 4, Tier 2, `tier_attribute_advancement = [str, con]`):
- `str = 19 + 1 + 2 + 2 = 24`
- `dex = 17 + 1 + 2 + 0 = 20`
- `con = 17 + 1 + 2 + 2 = 22`
- `int = 11 + 1 + 2 + 0 = 14`
- `wis = 13 + 1 + 2 + 0 = 16`
- `cha = 10 + 1 + 2 + 0 = 13`

**Race with no chain ancestors past humanoid resolves with just the leaf adjustment.** Brenna's `race: human` chain is `humanoid → human`; the `human` entry's `attribute_adjustments: { all: 1 }` is the only contribution beyond the base.

**Race chain accumulates adjustments down the chain.** Vex (race `high_elf`, chain `humanoid → elf → high_elf`, Arcane Trickster 4, Tier 2, `tier_attribute_advancement = [dex, int]`):
- `str = 9 + 0 (elf) + 0 (high_elf) + 2 + 0 = 11`
- `dex = 19 + 0 + 2 (high_elf) + 2 + 2 (chosen) = 25`
- `con = 13 + 0 + 0 + 2 + 0 = 15`
- `int = 14 + 0 + 2 (high_elf) + 2 + 2 (chosen) = 20`
- `wis = 15 + 0 + 0 + 2 + 0 = 17`
- `cha = 15 + 0 + 0 + 2 + 0 = 17`

**A single-link Race chain resolves with just that entry's adjustment.** Birch (race `satyr`, chain `humanoid → satyr`, Bard 4, Tier 2, `tier_attribute_advancement = [dex, cha]`):
- `dex = 18 + 2 (satyr) + 2 + 2 (chosen) = 24`
- `cha = 18 + 2 (satyr) + 2 + 2 (chosen) = 24`

**Tier 0 contributes zero Per-Tier Inherent Bonus.** A hypothetical Tier 0 Creature (e.g. an unclassified NPC matching the lowest-Tier fallback) has `per_tier = Tier Minimum Inherent Bonus[0] = 0` and `chosen = 0` (`Tier Inherent Chosen Bonus Count[0] = 0`). Every Effective Attribute equals Base + chain racial adjustment, with no Per-Tier contribution.

**Duplicate picks within the same Tier-Up double the chosen bonus on that attribute.** A Creature with `tier_attribute_advancement = [str, str]` at Tier 2 gains `2 × 2 = 4` to `str` from Tier 2's Chosen Bonus.

**A short `tier_attribute_advancement` list forgoes trailing picks.** A Creature at Tier 3 with `tier_attribute_advancement = [str, con]` (length 2) only has Tier 2's picks filled — the Tier 3 chunk would need 2 more entries and they aren't there, so Tier 3 grants no Chosen Bonus.

---

## Get Speed

**Race chain leaf-wins for Speed.** Vex (`high_elf` chain `humanoid → elf → high_elf`): `high_elf` declares no `speed`, `elf` declares `speed: 30`, `humanoid` declares `speed: 30`. The first non-null encountered walking root-leaf is `elf`'s 30. No `target: speed` Aggregated Modifiers → Speed = 30.

**Race chain leaf wins when it overrides the parent.** Korth (`hill_dwarf` chain `humanoid → dwarf → hill_dwarf`): `dwarf` declares `speed: 20`; `hill_dwarf` does not override. Speed = 20.

**A child Race overrides the parent's Speed.** A Wood Elf (chain `humanoid → elf → wood_elf`, where `wood_elf` declares `speed: 35`): Speed = 35, not 30.

**Race-only Speed when no Granted Ability targets `speed`.** Brenna (race `human`): human's `speed: 30` is the only contributor → Speed = 30. (The Barbarian's Fast Movement Ability supplies the +10 in the consuming project once Abilities ships it as a `modifiers:` entry; until then the baseline is 30.)

**Direct-leaf Race Speed.** Birch (race `satyr`, chain `humanoid → satyr` with `satyr.speed = 35`): Speed = 35.

**Speed-targeted Aggregated Modifier folds in last.** Hypothetical Creature with a Granted Ability whose `modifiers:` declares `{ target: speed, type: Enhancement, add: 10 }`: Speed = base + 10. With a second Enhancement-typed entry of `+5`, only the larger Enhancement Bonus survives per-type stacking → still +10, not +15.

**Negative Speed clamps at zero.** A Creature with a total of `−40` Speed across sources resolves to 0, not a negative number.

---

## Get Granted Abilities

**Race and Class Granted Abilities accumulate up to current Tier / Class Level.** Korth (Tier 2, Cleric 4, race `hill_dwarf`, `choices: {deity: Grull, domain: War, spellcasting: [magic_vestments]}`):
- From the Race chain `humanoid → dwarf → hill_dwarf`: `dwarf`'s `darkvision`, `dwarven_resilience` (each with `min_level: 0`) and `hill_dwarf`'s `healing_attunement` (`min_level: 1`, qualifies because Tier 2 ≥ 1).
- From `cleric` Class at level 4: level-1 `see_injury`, `improved_healing`, `combat_healing`, `domain`; level-2 `channel_divinity`, `turn_undead`, `casting_feat`. Class-level `granted_spells`: `Heal`, `Ward`, `Standard Surgery`.
- From `choices.spellcasting` under cleric: `magic_vestments`.
- From `choices.deity` + `choices.domain` via `deities.yaml` (Grull / War): `Divine Favor`, `Shield of Faith`, `Spiritual Hammer`, `Silence`.

Returned list (in encounter order, deduplicated): `darkvision`, `dwarven_resilience`, `healing_attunement`, `see_injury`, `improved_healing`, `combat_healing`, `domain`, `channel_divinity`, `turn_undead`, `casting_feat`, `Heal`, `Ward`, `Standard Surgery`, `magic_vestments`, `Divine Favor`, `Shield of Faith`, `Spiritual Hammer`, `Silence`.

**Archetype abilities extend the parent's at each Class Level.** Vex (Tier 2, Arcane Trickster 4, race `high_elf`, `choices.spellcasting: [elemental_dart]`): the resolved class's `ability_progression` is rogue's extended by arcane_trickster's. At level 1 the merged list is `[trapfinding, sneak_attack, thieves_cant, arcane_spellcasting]`. At level 2 the merged list is `[danger_sense, combat_trickery, mage_hand_legerdemain]`. The full Granted list across Race + Class + choice-driven spells (Race chain `humanoid → elf → high_elf`):

`low_light_vision`, `keen_senses`, `elven_magic`, `trapfinding`, `sneak_attack`, `thieves_cant`, `arcane_spellcasting`, `danger_sense`, `combat_trickery`, `mage_hand_legerdemain`, `elemental_dart`.

(If a Creature's `choices.spellcasting` duplicates a Race-granted name, the duplicate is dropped, preserving first encounter from Race.)

**Source filter narrows the result.** *Get Granted Abilities* on Korth with `source = "race"` returns just `darkvision`, `dwarven_resilience`, `healing_attunement`.

**`level_for_ability` reports the granting source's level.** For Korth:
- `level_for_ability("see_injury") = 4` — the Cleric Class's level.
- `level_for_ability("darkvision") = 2` — the Creature's Tier (Race source).
- `level_for_ability("magic_vestments") = 4` — the Cleric Class's level (the spell was contributed via `choices.spellcasting` under the cleric Class Entry).
- `level_for_ability("Spiritual Hammer") = 4` — the Cleric Class's level (the spell was contributed via `choices.deity` + `choices.domain` resolution against `deities.yaml`).
- `level_for_ability("nonexistent") = 0`.

**Class source attribution names the Archetype key.** `granted_abilities()` on Vex reports `source = "class:arcane_trickster"` for both rogue-side and arcane_trickster-side entries — the Class Entry's key is what surfaces, not the Archetype's parent.

---

## Get Aggregated Modifiers

**Modifier `add` Formulas evaluate against `level` and `tier`.** A Creature with a Granted Ability whose `modifiers:` entry is `{ target: weapon_attack, type: Untyped, add: "1 + (level / 4)" }`, at Total Level 8: the entry resolves to `amount = 1 + floor(8 / 4) = 3`.

**Tier 0 → 0.5 substitution applies.** A Creature at Tier 0 with a Modifier `add: "tier * 2"` evaluates to `floor(0.5 × 2) = 1`.

**Zero amounts are dropped.** A Modifier whose `add` evaluates to 0 does not appear in the returned list.

**Target filter narrows the list.** *Get Aggregated Modifiers* with `target = "speed"` returns only entries whose Modifier Entry target was `"speed"`.

**Per-Bonus-Type stacking is not applied here.** Two `target: speed`, `type: Enhancement` entries of `+5` and `+10` both appear in the returned list. The consumer (Combat's Speed integration, or Conditions' Bonus Type rollup) collapses them.

**Source name is the Ability name verbatim.** Each Aggregated Modifier Entry's `source` matches the Granted Ability that contributed it.

---

## Look up Class

**Top-level Class resolves directly.** *Look up Class* with `class_key = "cleric"` returns the cleric entry verbatim. `parent_class` is null.

**Archetype merges with its parent.** *Look up Class* with `class_key = "arcane_trickster"`:
- `parent_class` = `rogue` (the Archetype declaration).
- `martial_advancement` = `unaligned` (inherited from rogue; arcane_trickster does not override).
- `saves.aligned` = `[dex, int]` (inherited from rogue).
- `mana_per_level` = `2` (arcane_trickster overrides rogue's `1`).
- Effective Aligned-rate Skills = rogue's `aligned_proficiencies` list with `arcana` *added* (the Archetype's `aligned_proficiencies` entry is an additive adjustment, not a replacement).
- `ability_progression`: at level 1 = `[trapfinding, sneak_attack, thieves_cant, arcane_spellcasting]` (rogue's then arcane_trickster's appended). At level 2 = `[danger_sense, combat_trickery, mage_hand_legerdemain]` (rogue's `[danger_sense]` then arcane_trickster's two).

**Archetype `unaligned_proficiencies` adjusts categorization toward Unaligned.** A hypothetical Archetype of Bard that declares `unaligned_proficiencies: [perception]`: the merged effective categorization is Bard's (`unaligned_proficiencies = [restricted_magic, survival]` + Archetype's `[perception]`). A Creature in that Archetype who trains `perception` advances at the `unaligned` rate, not `aligned`.

**Unknown Class key returns null.** *Look up Class* with `class_key = "homebrew_class"` returns null.

---

## Look up Race

**Leaf Race with no parent chain past the root returns just its own fields.** *Look up Race* with `race_key = "human"` (chain `humanoid → human`) returns `{ size: medium, speed: 30, attribute_adjustments: { all: 1 }, abilities: [{ name: versatile, min_level: 0 }] }`. `humanoid`'s `size` and `speed` are inherited because `human` doesn't override them.

**Race with chain ancestors merges the chain.** *Look up Race* with `race_key = "hill_dwarf"` (chain `humanoid → dwarf → hill_dwarf`) returns size and speed from the first non-null in the chain (`dwarf` declares `speed: 20`), accumulated attribute adjustments across the chain (`dwarf` + `hill_dwarf`), and the concatenated abilities list (root → leaf) with child-wins dedup on `name`.

**Unknown Race returns null.** *Look up Race* with `race_key = "merfolk"` returns null.

---

## Ranks Computation (through `ranks_for`)

### Skills

**A trained Aligned Skill advances at the `aligned` rate.** Korth (Cleric 4) trains `healing`; cleric's `aligned_proficiencies` includes `healing`. Rate = `aligned = floor(5 × level / 3)`. Ranks = `floor(4 × 5 / 3) = 6`.

**A trained Skill not categorized falls back to the `Default Skill Rate` (`unaligned`).** Korth trains `intimidate`; cleric uses `aligned_proficiencies` (inclusion form) and `intimidate` is not in the list. Default for trained-but-unlisted = `unaligned = level`. Ranks = `4`.

**An untrained Skill returns zero ranks.** Korth does not train `stealth`. *Get ranks* returns 0, regardless of how cleric categorizes the Skill.

**The inverse `unaligned_proficiencies` form flips the default.** Birch (Bard 4) trains `perform_sing`. Bard declares `unaligned_proficiencies: [restricted_magic, survival]` (inverse form). `perform_sing` (and its `perform_` prefix) is not in that list, so under the inverse default it advances at the `aligned` rate. Ranks = `floor(4 × 5 / 3) = 6`.

**A Skill in `unaligned_proficiencies` advances at the `unaligned` rate.** A hypothetical Bard who trains `survival`: Bard's `unaligned_proficiencies` includes `survival`, so the Skill advances at the `unaligned` rate. Ranks at Class Level 4 = `floor(4 × 1) = 4`.

**Set Instances inherit categorization from their Set Skill prefix.** Birch's `perform_sing` resolves through the `perform_` prefix when checking the Bard's `unaligned_proficiencies` list — neither `perform_sing` nor `perform_` appears there, so the default-aligned rate of the inverse form applies. A hypothetical Cleric who trains `craft_blacksmith` resolves through `craft_` (in cleric's `aligned_proficiencies`) → `aligned` rate.

**Archetype extension to `aligned_proficiencies` lifts ranks.** Vex (Arcane Trickster 4) trains `arcana`. The merged Arcane Trickster effective aligned-rate skills include `arcana` (added by the Archetype). Rate = `aligned`. Ranks = `floor(4 × 5 / 3) = 6`.

**`game_chess` is unaligned for Arcane Trickster.** Vex trains `game_chess`. The merged Arcane Trickster `aligned_proficiencies` does not include `game_` or `game_chess`. Default (inclusion-form fallback) = `unaligned`. Ranks = `4`.

**An Opposed Skill the Creature trains advances at the `opposed` rate.** A hypothetical Wizard 6 with `opposed_proficiencies: [athletics]` (no such declaration in the shipped data — for illustration) who trains `athletics`: rate = `opposed = floor(2 × level / 3)`. Ranks = `floor(6 × 2 / 3) = 4`.

**Multiple Classes sum their per-Class contribution.** A hypothetical Creature with `advancement.classes = { fighter: { level: 3, skills: [athletics] }, rogue: { level: 2, skills: [athletics, stealth] } }`. Both classes list `athletics` in their `aligned_proficiencies`. Ranks = `floor(3 × 5 / 3) + floor(2 × 5 / 3) = 5 + 3 = 8`.

**Bare Set Skill key is invalid.** Calling `ranks_for("perform_")` is invalid input — Creatures does not store ranks under bare Set Skill keys.

**Unknown key returns zero.** Calling `ranks_for("homebrew_skill")` on Korth returns 0 (no Class lists it, the Creature does not train it).

### Saves

**A Class Save advances at the `aligned` rate.** Korth: cleric's `saves.aligned = [wis, cha]`. `ranks_for("wis_save") = floor(4 × 5 / 3) = 6`.

**A Save not in `saves.aligned` advances at the `opposed` rate (the default).** Korth: `str` is not in cleric's `saves.aligned`. `ranks_for("str_save") = floor(4 × 2 / 3) = 2`.

**Every Class contributes to every Save.** A hypothetical multi-classed Creature `{ fighter: 3, rogue: 2 }` for `ranks_for("dex_save")`: fighter has `dex` as `opposed` (`saves.aligned = [str, con]`) → `floor(3 × 2/3) = 2`. Rogue has `dex` in `saves.aligned = [dex, int]` → `floor(2 × 5/3) = 3`. Sum = `5`.

### Martial

**Martial uses `martial_advancement`.** Korth: cleric's `martial_advancement = unaligned`. `ranks_for("martial") = floor(4 × 1 / 1) = 4`. Brenna (barbarian 4, `martial_advancement = aligned`): `floor(4 × 5 / 3) = 6`. Hypothetical wizard 6 with `martial_advancement = opposed`: `floor(6 × 2 / 3) = 4`.

**Martial does not appear in any Skill list.** A Class's `aligned_proficiencies` / `unaligned_proficiencies` / `opposed_proficiencies` never list `martial`; martial is exclusively handled via `martial_advancement`.

---

## Get Max Hit Points

**Tier 2 cleric uses the Tier-2 HP Formula and the Effective Constitution.** Korth's Effective Constitution is 23 and the Tier 2 formula is `"2 * con"`. `max_hit_points = floor(2 × 23) = 46`.

**Tier 1 uses the Tier-1 HP Formula.** Ghoul (Tier 1, Effective Constitution = `12 + 0 + 1 + 0 = 13`) with formula `"con"` → 13.

**Tier 0 uses the Tier-0 HP Formula.** A hypothetical Tier 0 Creature with Effective Constitution 16 evaluating the shipped Tier-0 HP Formula `"con / 2"` computes `floor(16 / 2) = 8`.

**Aggregated `hp_bonus` adds on top, with per-Bonus-Type stacking at this consumer.** A Creature with two `target: hp_bonus`, `type: Enhancement` entries `+5` and `+8`: the +8 survives per-type stacking; max HP gains 8. A `+3 Morale` entry would survive alongside it (different Bonus Type).

**Tier beyond the configured HP Formula array is an error.** A Creature whose Tier resolves to 6 raises with the default `HP Formula` (length 6, indexes 0..5).

---

## Get Max Mana

**Tier 2 cleric: formula + per-Class contribution.** Korth: Effective Intelligence 16, Tier 2. `Mana Base Formula[2] = "int"` → 16. Plus cleric mana contribution `resolved_class.mana_per_level (4) × class.level (4) = 16`. `max_mana = 16 + 16 = 32`.

**Tier 2 barbarian: formula + low per-Class contribution.** Brenna: Effective Intelligence 14, Tier 2. `Mana Base Formula[2]` → 14. Plus barbarian `mana_per_level (1) × 4 = 4`. `max_mana = 14 + 4 = 18`.

**Class with no `mana_per_level` contributes zero.** A Class entry omitting `mana_per_level` defaults to `0`; the Class adds nothing.

**Archetype can override `mana_per_level`.** Vex (Arcane Trickster 4): merged `mana_per_level = 2` (Archetype overrides rogue's `1`). Effective Intelligence 20, Tier 2. `Mana Base Formula[2]` → 20. Class contribution `2 × 4 = 8`. `max_mana = 28`.

---

## Update entry points

### Set Tier Attribute Advancement

**Valid list lands.** *Set Tier Attribute Advancement* on a Tier-3 hypothetical Creature with `[con, wis, int, dex]`: the first two entries become Tier 2's picks (Chosen Bonus on `con` and `wis`); the next two become Tier 3's (Chosen Bonus on `int` and `dex`). *Get Effective Attributes* reflects both Tier chunks.

**Unknown attribute key is rejected.** *Set Tier Attribute Advancement* on Korth with `[int, magic]`: rejected with a descriptive error naming `magic`.

**Short list forgoes trailing Tiers.** *Set Tier Attribute Advancement* on a Tier-3 Creature with `[str, con]` (length 2): Tier 2's two-entry chunk is consumed; Tier 3 has no entries to consume and grants no Chosen Bonus.

**Long list stores future picks.** *Set Tier Attribute Advancement* on a Tier-2 Creature with `[str, con, wis, dex]` (length 4): Tier 2's chunk consumes `[str, con]`. Tier 3's chunk `[wis, dex]` is stored but inactive at Tier 2; once the Creature reaches Tier 3 the picks apply automatically.

**Duplicate picks within the same Tier's chunk are accepted.** *Set Tier Attribute Advancement* with `[str, str]` on a Tier 2 Creature stores the list as-is; the Per-Tier Inherent Chosen Bonus to `str` is `2 × 2 = 4` at Tier 2.

**Empty list clears all chosen bonuses.** *Set Tier Attribute Advancement* on Korth with `[]`: subsequent *Get Effective Attributes* shows no Chosen Bonus contributions.

### Set Tier Override

**Override applies immediately.** *Set Tier Override* on Brenna (computed Tier 2) to `4`: *Get Tier* returns 4. *Get Effective Attributes* now uses the Tier-4 Per-Tier Inherent Bonus.

**Clearing the override restores computed Tier.** *Set Tier Override* on Brenna to `null`: *Get Tier* returns 2 again.

### Set Class Choices

**Setting `choices.spellcasting` adds the listed spells to Granted Abilities.** *Set Class Choices* on Vex: `(class="arcane_trickster", {spellcasting: ["elemental_dart"]})`. *Get Granted Abilities* now includes `elemental_dart` with `source = "class:arcane_trickster"`.

**Setting `choices` wholesale replaces the previous map.** Korth starts with `cleric.choices = {deity: "Grull", domain: "War", spellcasting: ["magic_vestments"]}`. *Set Class Choices* on Korth: `(class="cleric", {deity: "Grull", domain: "War"})`: the `spellcasting` key is gone — `magic_vestments` no longer appears in *Get Granted Abilities*.

**Setting `choices` on a Class the Creature does not have rejects.** *Set Class Choices* on Brenna (who has no `wizard` Class Entry): `(class="wizard", {spellcasting: ["elemental_dart"]})`: rejected. The Creature's record is unchanged.

**Choices for a Class with no Spellcasting-type ability are stored but contribute no Granted Abilities.** *Set Class Choices* on Brenna (barbarian): `(class="barbarian", {spellcasting: ["fire_dart"]})`: accepted (Creatures stores opaquely), but *Get Granted Abilities* does NOT include `fire_dart` — the Barbarian Class progression never grants a Spellcasting-type ability, so the choice has no consumer.

### Set Class Level

**Increasing the Class Level shifts Tier and ranks.** *Set Class Level* on Korth: `(class="cleric", level=8)`: Total Level 8 → Tier 3 (the `player_character` breakpoint list has `breakpoints[3] = 8`). `ranks_for("wis_save") = floor(8 × 5 / 3) = 13`.

**Adding an Archetype when the Creature has the parent is rejected.** A Creature with `advancement.classes = { rogue: 3 }`: *Set Class Level* with `(class="arcane_trickster", level=3)` is rejected with an Archetype Exclusivity error naming `rogue` and `arcane_trickster`. The Creature's record is unchanged.

**Adding the parent Class when the Creature already has an Archetype is rejected.** A Creature with `advancement.classes = { arcane_trickster: 4 }`: *Set Class Level* with `(class="rogue", level=1)` is rejected with the same Archetype Exclusivity error.

**Multi-classing across unrelated Classes is accepted.** A Creature with `advancement.classes = { rogue: 3 }`: *Set Class Level* with `(class="fighter", level=2)` succeeds; the record now has both Class Entries.

**Setting Class Level to zero leaves the entry but contributes nothing.** A Class Entry with `level = 0` contributes zero ranks and zero Granted Abilities from that Class. The entry persists until *Prune Empty Classes* is invoked.

### Set Trained Skills

**Replacing the trained list changes ranks immediately.** *Set Trained Skills* on Korth: `(class="cleric", [arcana, healing])`. Skills no longer in the list (e.g. `sense_motive`) return zero ranks on the next call.

---

## Spawn Creature From Template

**Spawn allocates a fresh ID one past the dataset's current maximum.** Dataset contains records with IDs `{1, 2, 3, 100, 101}`. *Spawn Creature From Template* on `template_id = 100` returns `102`. A second call returns `103`. The IDs are unique across all loaded `creatures_data_*` files — the loader globs the pattern and the allocator scans the merged set.

**Spawned record is a deep copy of the template.** Template `100` has `attributes = {str: 13, dex: 14, ...}`, `advancement.classes = { rogue: { level: 1, skills: [...] } }`. After *Spawn Creature From Template* on `100`, the new record's `attributes` and `advancement.classes` are equal-by-value to the template's. Mutating the new record's `advancement.classes.rogue.level` to `2` does NOT change the template's level.

**`name_override` replaces the template's name on the spawn only.** *Spawn Creature From Template* on `100` with `name_override = "Bloodfin"` produces a record with `name = "Bloodfin"`. Template `100`'s `name` remains `"Pirate"`.

**`loot_table` override replaces the template's `loot_table` on the spawn only.** Template `100` carries `loot_table = "pirates_basic"`. *Spawn Creature From Template* on `100` with `loot_table = "captain_loot"` produces a record with `loot_table = "captain_loot"`. Template `100` is unchanged.

**Spawn does NOT add to any Combat.** The new record is persisted in the Creatures dataset; no Combat State change occurs. The caller follows up with Combat's *Add Combatant*.

**Spawning from a non-existent template ID rejects.** *Spawn Creature From Template* on `template_id = 9999` (no such record): rejected with a missing-template error. No new record is allocated.

**Spawning from a PC template is allowed but unusual.** *Spawn Creature From Template* on `1` (the first PC) succeeds, producing a duplicate PC record. Validation does not gate the source's `tags` — the entry point is policy-free; consuming UIs decide which templates to surface.

---

## Delete Creature

**Delete removes the record from the dataset.** Dataset contains record `1000`. *Delete Creature* on `1000`: subsequent *Look up Creature* on `1000` returns null; *List Creatures* no longer reports `1000`.

**Delete is idempotent.** *Delete Creature* on `1000` after it was already deleted: no error.

**Delete does NOT cascade into other domains.** A Combat State has a Combatant whose `creature_id = 1000`. After *Delete Creature* on `1000`, the Combatant entry remains in the Combat State (Combat's `creature_lookup` will now return null for it). Cleanup is the caller's responsibility — the consuming loot stub composes Combat's *Remove Combatant* + *Delete Creature* in sequence; calling *Delete Creature* in isolation is allowed.

**Conditions, Equipment, and other per-Creature state are not pruned.** After *Delete Creature* on `1000`, an existing entry in `conditions_data.example.json` keyed by `1000` and an Equipment owner `creature:1000` are both still present. The caller (typically the post-combat loot stub) cleans these as part of its flow.

---

## Roll Encounter

**Each Encounter Row resolves and produces fresh spawns.** Encounter Table `caravan_ambush` has one Guaranteed row with payload `[{template_id: 101, count: 2}]`. *Roll Encounter* on `"caravan_ambush"` returns a 2-element list of fresh Creature IDs. The Creatures dataset gains two new records, each a deep-copy of template `101`.

**`count` accepts dice expressions evaluated at roll time.** Encounter Row payload `[{template_id: 104, count: "1d4 + 1"}]`. Each *Roll Encounter* call rolls 1d4+1 and produces that many spawns; two successive calls may produce different counts.

**Loot Row vocabulary applies — `chance`, `when`, `as`.** Table has three rows: (1) guaranteed `[{template_id: 101, count: 2}]`, (2) Independent Chance `0.6` publishing `as: has_captain` with `[{template_id: 102, count: 1}]`, (3) Gated `when: {has_captain: true}` with `[{template_id: 105, count: 1}]`. When row 2's `chance` succeeds, row 3 fires. When row 2's `chance` fails, row 3 is skipped (no `has_captain` Variable was published).

**A skipped row does not publish.** In the table above, when row 2's `chance` fails, the Roll Variable `has_captain` is absent — row 3's `when: {has_captain: true}` evaluates false, and row 3 is skipped.

**Returned list is in roll order.** With the three-row table above and a successful captain roll: returned IDs are `[<orc1>, <orc2>, <captain>, <wardog>]` in that order.

**Spawn Refs with `loot_table` override stamp every spawn.** Encounter Row payload `[{template_id: 100, count: 2, loot_table: "captain_loot"}]`. *Roll Encounter* produces two new records, both with `loot_table = "captain_loot"` regardless of the template's own `loot_table`.

**`name_override` stamps every spawn.** Payload `[{template_id: 100, count: 3, name_override: "Skullsplitter"}]`. All three resulting records carry `name = "Skullsplitter"`.

**Roll Encounter does NOT touch Combat.** Combat State is unchanged after *Roll Encounter*. The caller adds each returned Creature ID via Combat's *Add Combatant*.

**Random Seed reproduces the result.** *Roll Encounter* on `"caravan_ambush"` with `seed = 42` twice yields the same Creature IDs and same Roll Variable outcomes both times.

**Unknown table ID rejects.** *Roll Encounter* on `"no_such_table"`: rejected with a missing-table error. No spawns are produced.

**Spawn Ref pointing at a deleted template rejects.** Encounter Table `bad_ref` has a row `[{template_id: 9999}]` (no such record). *Roll Encounter* on `"bad_ref"`: rejected. Validation catches this at *Load Encounter Tables* time; runtime call is a fallback check.

---

## Archetype Resolution

**Top-level Class returns its own entry.** Resolving `"cleric"` returns the cleric entry verbatim. The resolved key is `"cleric"`, `parent_class` is null.

**Archetype key returns the merged entry, with the Archetype key reported.** Resolving `"arcane_trickster"` returns the rogue-extended entry with `class_key = "arcane_trickster"`.

**Archetype is detected through its own `parent_class:` field.** The resolver finds `arcane_trickster` as a top-level entry in `Classes:`, sees its `parent_class: rogue`, and applies the Archetype merge against rogue.

**Unknown key raises at load time and warns at runtime.** A Creature with an `advancement.classes` key that resolves to nothing in `Classes:` causes load-time validation to fail. (A consuming project that bypasses validation gets a warning at runtime and zero contribution.)

---

## Archetype Exclusivity

**A Creature cannot hold both a Class and its Archetype.** A record with `advancement.classes = { rogue: 3, arcane_trickster: 1 }` is rejected at load with an Archetype Exclusivity error naming `rogue` and `arcane_trickster`.

**A Creature cannot hold two Archetypes of the same parent.** A record with `advancement.classes = { arcane_trickster: 4, hypothetical_rogue_archetype: 1 }` (both having `parent_class: rogue`) is rejected.

**A Creature CAN multi-class an Archetype with an unrelated Class.** A record with `advancement.classes = { arcane_trickster: 4, fighter: 2 }` is accepted — fighter is not the parent of arcane_trickster, nor a sibling Archetype.

---

## Validation

**Required attributes are enforced.** A Creature Record whose `attributes` omits `str` is rejected.

**Unknown Race is rejected.** A Creature with `race: "merfolk"` (no such entry in `creatures_race.yaml`) is rejected.

**Race chain must terminate.** A `creatures_race.yaml` with a `parent:` cycle is rejected at config load.

**`skills` cannot include bare Set Skill keys.** A Class Entry with `skills: ["perform_"]` is rejected. `"perform_sing"` is fine.

**Duplicate Creature IDs are rejected at load.** A dataset with two Creatures of `id = 1` raises with an Id Collision error naming both source files.

**`tier_attribute_advancement` entries must be recognized attribute keys.** A Creature Record with `tier_attribute_advancement: [str, magic]` is rejected with a descriptive error naming `magic`.

**Non-integer `tier` is rejected.** A Creature with `tier: "two"` is rejected; `tier:` must be either null or a non-negative integer.

**A non-Archetype Class declaring both `aligned_proficiencies` and `unaligned_proficiencies` is rejected at config load.** The two forms are mutually exclusive on a top-level Class. (Archetypes may declare any combination — each acts as an additive adjustment.)

**A Class must declare `saves.aligned`.** A non-Archetype Class Catalog Entry omitting `saves.aligned` is rejected at load time. (The list may be empty for a hypothetical Class with no `aligned`-rate Saves, but the key must be present.) An Archetype that omits `saves` inherits the parent's; an Archetype that declares `saves` must declare `saves.aligned`.
