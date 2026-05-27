# Creatures — Tests

Tests for the public entry points of the Creatures domain.

Unless a test specifies otherwise, all tests use the values shipped in `creatures_config.yaml`, `classes.yaml`, and `races.yaml`:

- Default Base Speed: 30
- Per-Tier Inherent Bonus: 1
- Per-Tier Inherent Chosen Bonus Count: 2 (begins at Tier 2)
- Per-Tier Inherent Chosen Bonus Amount: 2
- Tier Breakpoints: as shipped in `creatures_advancement.yaml` — `player_character`, `hero`, `boss`, `noble`, `commoner`, `animal`, each carrying its full breakpoint list including the leading 0.
- Proficiency Advancement Rates: `aligned = floor(5 × level / 3)`, `unaligned = level`, `opposed = floor(2 × level / 3)`.
- Default Save Rate: `opposed`. Default Skill Rate: `unaligned`.
- HP Formula / Mana Formula: as shipped

Test scenarios refer to named hypothetical creatures (Stumpy the dwarven cleric, Olga the human barbarian, Lysander the elven arcane trickster, Cottonballs the satyr bard, Ghoul, Brown Bear) by name and supply the data each scenario needs inline. These names do not have to match the records shipped in the example data files (`creatures_data_pcs.example.yaml`, `creatures_data_enemies.example.yaml`, `creatures_data_npcs.example.yaml`) — they are fixtures local to the test cases, chosen for narrative continuity within the suite.

When a scenario refers to one of these named fixtures, the relevant attributes, classes, levels, and tracks are described in the scenario itself. The four hypothetical PCs are on the `hero` track at Total Level 4 (Tier 2). The Ghoul is on the `hero` track at Total Level 2 (Tier 1). The Brown Bear is on the `animal` track at Total Level 6 (Tier 1 — `breakpoints[1] = 4` is the highest entry ≤ 6).

---

## Look up Creature

**Existing ID returns an Accessor.** Given `creature_id = "1"`: returns a Creature Accessor with `name = "Stumpy"`.

**Unknown ID returns null.** Given `creature_id = "999"`: returns null.

**Accessor reads fresh from the underlying record.** After *Set Tier Override* on Creature "1" to `5`, a previously-held Accessor's `tier` returns 5 on the next call. Accessors do not snapshot.

---

## List Creatures

**No filter returns every Creature in load order.** Returns six pairs: `("1", "Stumpy")`, `("2", "Olga")`, `("3", "Lysander")`, `("4", "Cottonballs")`, `("100", "Ghoul")`, `("101", "Brown Bear")`.

**Group filter narrows to matching Creatures.** With `group = "pc"`: returns the four PCs. `group = "enemy"`: returns Ghoul and Brown Bear.

**Tags filter requires every entry to be present.** With `tags = ["player_character"]`: returns the four PCs. With `tags = ["player_character", "missing"]`: returns the empty list.

---

## Find Creature by Name

**Exact match returns the Accessor.** Given `name = "Stumpy"`: returns the Accessor for Creature "1".

**Case mismatch returns null.** Given `name = "stumpy"`: returns null. Case-sensitive.

**Unknown name returns null.** Given `name = "Nobody"`: returns null.

---

## Get Tier

**Hero track, Total Level 4 → Tier 2.** Stumpy (Cleric 4, hero track): largest `i` with `breakpoints[i] ≤ 4` is index 2 (`breakpoints = [0, 1, 4, 8, 16, 30]`).

**Hero track, Total Level 2 → Tier 1.** Ghoul (Undead 2, hero track): largest `i` with `breakpoints[i] ≤ 2` is index 1.

**Animal track, Total Level 6 → Tier 1.** Brown Bear (Animal 6, animal track, `breakpoints = [0, 4, 8, 12, 16, 20]`): largest `i` with `breakpoints[i] ≤ 6` is index 1 (`breakpoints[1] = 4`) → Tier 1.

**Default track, Total Level 4 → Tier 1.** A hypothetical Creature on the `default` track (`[0, 4, 6, 12, 20, 80]`) with Total Level 4: largest `i` with `breakpoints[i] ≤ 4` is index 1 (`breakpoints[1] = 4`).

**Tier Override bypasses the computation.** After *Set Tier Override* on Stumpy to `4`: *Get Tier* returns 4, regardless of Total Level.

**Tier zero is the floor.** A Creature with Total Level 0 on any track resolves to Tier 0 (index 0 has breakpoint 0).

**Unknown Advancement Track is an error.** A Creature whose `advancement_track` does not appear in `Tier Breakpoints` raises at *Get Tier* time (and at load-time validation).

---

## Get Effective Attributes

**Tier 1 grants only the flat Per-Tier Inherent Bonus, no Chosen Bonus.** A hypothetical Cleric 1 on the `hero` track with `base_attributes = { str: 10, ... }` and no `tier_up_choices`: Tier 1. `per_tier = floor(1 × 1) = 1`. Chosen bonus is zero everywhere (the Tier 1 → Tier 2 transition is the first one that grants a Chosen Bonus). Effective `str = 10 + racial + 1`.

**Tier 2 is the first Tier with a Chosen Bonus.** Stumpy (Tier 2) picked `[con, wis]` at Tier 2 in `tier_up_choices`. `per_tier = floor(2 × 1) = 2` on every attribute. Chosen Bonus adds +2 each to `con` and `wis` because Tier 2 is at or below the Creature's current Tier.

Expected Effective Attributes:
- `str = 12 + 0 (dwarf base) + 0 (hill aspect) + 2 (per-tier) + 0 (chosen) = 14`
- `dex = 14 + 0 + 0 + 2 + 0 = 16`
- `con = 17 + 0 + 2 (hill aspect) + 2 + 2 (chosen at Tier 2) = 23`
- `int = 14 + 0 + 0 + 2 + 0 = 16`
- `wis = 18 + 0 + 2 (hill aspect) + 2 + 2 (chosen at Tier 2) = 24`
- `cha = 11 + 0 + 0 + 2 + 0 = 13`

**Human "all+1" racial adjustment applies to every attribute.** Olga (Human Barbarian 4, Tier 2, Tier-2 pick `[str, con]`):
- `str = 19 + 1 + 2 + 2 = 24`
- `dex = 17 + 1 + 2 + 0 = 20`
- `con = 17 + 1 + 2 + 2 = 22`
- `int = 11 + 1 + 2 + 0 = 14`
- `wis = 13 + 1 + 2 + 0 = 16`
- `cha = 10 + 1 + 2 + 0 = 13`

**Race with no Aspect resolves with only the Race's adjustment.** Olga's `race_aspect` is null; the lookup uses the Human base entry and adds nothing extra.

**Race with required Aspect resolves both layers.** Lysander (Elf High Arcane Trickster 4, Tier 2, Tier-2 pick `[dex, int]`):
- `str = 9 + 0 (elf base) + 0 (high aspect) + 2 + 0 = 11`
- `dex = 19 + 0 + 2 (high) + 2 + 2 (chosen) = 25`
- `con = 13 + 0 + 0 + 2 + 0 = 15`
- `int = 14 + 0 + 2 (high) + 2 + 2 (chosen) = 20`
- `wis = 15 + 0 + 0 + 2 + 0 = 17`
- `cha = 15 + 0 + 0 + 2 + 0 = 17`

**Race-level adjustment applies even without Aspects.** Cottonballs (Satyr Bard 4, Tier 2, Tier-2 pick `[dex, cha]`):
- `dex = 18 + 2 (satyr) + 2 + 2 (chosen) = 24`
- `cha = 18 + 2 (satyr) + 2 + 2 (chosen) = 24`

**Tier 0 contributes zero Per-Tier Inherent Bonus.** A hypothetical Tier 0 Creature (e.g. an unclassified NPC matching the lowest-Tier fallback) has `per_tier = floor(0.5 × 1) = 0` and `chosen = 0` (Chosen Bonus begins at Tier 2). Every Effective Attribute equals Base + any racial adjustment, with no Per-Tier contribution.

**Duplicate picks at a Tier double the chosen bonus on that attribute.** A Creature with Tier-Up Choice `[str, str]` at Tier 2 gains `2 × 2 = 4` to `str` from Tier 2's Chosen Bonus.

**Missing Tier-Up Choice entry is a forgone bonus.** A Creature at Tier 3 with `tier_up_choices = { 2: [str, con] }` (no Tier 3 entry) gets the Tier 2 Chosen Bonus but no Tier 3 Chosen Bonus.

---

## Get Speed

**Race base speed, no Aspect speed delta, no speed-targeting Modifier.** Lysander: elf base 30 + high aspect 0 (no `speed_delta`) + no `target: speed` Aggregated Modifiers = 30.

**Race base speed reduced.** Stumpy: dwarf base 20 + hill aspect 0 + no `target: speed` Aggregated Modifiers = 20.

**Race Aspect adds a speed delta.** A Wood Elf at any level adds the wood Aspect's `speed_delta: 5` on top of elf's base 30 = 35.

**Race-only Speed when no Aspect speed delta or modifier ability applies.** Olga: human base 30 + null aspect + no `target: speed` modifiers = 30. (The Barbarian's Fast Movement Ability supplies the +10 in the consuming project once Abilities ships it as a `modifiers:` entry; until then the baseline is 30.)

**Race-only Speed for a non-Aspected Race that overrides the default.** Cottonballs: satyr base 35 + no aspect + no relevant Modifier = 35.

**Speed-targeted Aggregated Modifier folds in last.** Hypothetical Creature with a Granted Ability whose `modifiers:` declares `{ target: speed, type: Enhancement, add: 10 }`: Speed = base + 10. With a second Enhancement-typed entry of `+5`, only the larger Enhancement Bonus survives per-type stacking → still +10, not +15.

**Negative Speed clamps at zero.** A Creature with a total of `−40` Speed across sources resolves to 0, not a negative number.

---

## Get Granted Abilities

**Race and Class Granted Abilities accumulate up to current Tier / Class Level.** Stumpy (Tier 2, Cleric 4, `choices: {deity: Grull, domain: War, spellcasting: [magic_vestments]}`):
- From `dwarf` Race: tier-0 `darkvision`, `dwarven_resilience`.
- From `hill` Aspect: tier-1 `healing_attunement` (Tier 2 ≥ 1).
- From `cleric` Class at level 4: level-1 `see_injury`, `improved_healing`, `combat_healing`, `domain`; level-2 `channel_divinity`, `turn_undead`, `casting_feat`. Class-level `granted_spells`: `Heal`, `Ward`, `Standard Surgery`.
- From `choices.spellcasting` under cleric: `magic_vestments`.
- From `choices.deity` + `choices.domain` via `deities.yaml` (Grull / War): `Divine Favor`, `Shield of Faith`, `Spiritual Hammer`, `Silence`.

Returned list (in encounter order, deduplicated): `darkvision`, `dwarven_resilience`, `healing_attunement`, `see_injury`, `improved_healing`, `combat_healing`, `domain`, `channel_divinity`, `turn_undead`, `casting_feat`, `Heal`, `Ward`, `Standard Surgery`, `magic_vestments`, `Divine Favor`, `Shield of Faith`, `Spiritual Hammer`, `Silence`.

**Sub-Class abilities merge with the parent's at each Level.** Lysander (Tier 2, Arcane Trickster 4, `choices.spellcasting: [elemental_dart]`): the resolved class's `ability_progression` is rogue's merged with arcane_trickster's. At level 1 the merged list is `[trapfinding, sneak_attack, thieves_cant, arcane_spellcasting]`. At level 2 the merged list is `[danger_sense, combat_trickery, mage_hand_legerdemain]`. The full Granted list across Race + Aspect + Class + choice-driven spells:

`low_light_vision`, `keen_senses`, `elven_magic`, `trapfinding`, `sneak_attack`, `thieves_cant`, `arcane_spellcasting`, `danger_sense`, `combat_trickery`, `mage_hand_legerdemain`, `elemental_dart`.

(If a Creature's `choices.spellcasting` duplicates a Race-granted name, the duplicate is dropped, preserving first encounter from Race.)

**Source filter narrows the result.** *Get Granted Abilities* on Stumpy with `source = "race"` returns just `darkvision`, `dwarven_resilience`, `healing_attunement`.

**`level_for_ability` reports the granting source's level.** For Stumpy:
- `level_for_ability("see_injury") = 4` — the Cleric Class's level.
- `level_for_ability("darkvision") = 2` — the Creature's Tier (Race source).
- `level_for_ability("magic_vestments") = 4` — the Cleric Class's level (the spell was contributed via `choices.spellcasting` under the cleric Class Entry).
- `level_for_ability("Spiritual Hammer") = 4` — the Cleric Class's level (the spell was contributed via `choices.deity` + `choices.domain` resolution against `deities.yaml`).
- `level_for_ability("nonexistent") = 0`.

**Class source attribution names the resolved Class key.** `granted_abilities()` on Lysander reports `source = "class:arcane_trickster"` for both rogue-side and arcane_trickster-side entries — the Class Entry's resolved key is what surfaces.

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

**Top-level Class resolves directly.** *Look up Class* with `class_key = "cleric"` returns the cleric entry verbatim.

**Sub-Class merges with its parent.** *Look up Class* with `class_key = "arcane_trickster"`:
- `martial_advancement` = `unaligned` (inherited from rogue; arcane_trickster does not override).
- `saves.aligned` = `[dex, int]` (inherited from rogue).
- `mana_advancement` = `2` (arcane_trickster overrides rogue's `1`).
- Effective Aligned-rate Skills = rogue's `aligned_proficiencies` list with `arcana` *added* (the Sub-Class's `aligned_proficiencies` entry is an additive adjustment, not a replacement).
- `ability_progression`: at level 1 = `[trapfinding, sneak_attack, thieves_cant]` (rogue only). At level 2 = `[danger_sense, combat_trickery, mage_hand_legerdemain]` (rogue's `[danger_sense]` then arcane_trickster's two).

**Sub-Class `unaligned_proficiencies` adjusts categorization toward Unaligned.** A hypothetical Sub-Class of Bard that declares `unaligned_proficiencies: [perception]`: the merged effective categorization is Bard's (`unaligned_proficiencies = [restricted_magic, survival]` + Sub-Class's `[perception]`). A Creature in that Sub-Class who trains `perception` advances at the `unaligned` rate, not `aligned`.

**Unknown Class key returns null.** *Look up Class* with `class_key = "homebrew_class"` returns null.

---

## Look up Race

**Race with no Aspects returns base fields only.** *Look up Race* with `race_key = "human"` returns `{ base_speed: <Default Base Speed>, racial_adjustment: { all: 1 }, granted_abilities: { 0: [versatile] }, aspects: {} }`.

**Race with Aspects returns the aspects map.** *Look up Race* with `race_key = "elf"` returns the full entry including the `high` and `wood` Aspects.

**Unknown Race returns null.** *Look up Race* with `race_key = "merfolk"` returns null.

---

## Ranks Computation (through `ranks_for`)

### Skills

**A trained Aligned Skill advances at the `aligned` rate.** Stumpy (Cleric 4) trains `healing`; cleric's `aligned_proficiencies` includes `healing`. Rate = `aligned = floor(5 × level / 3)`. Ranks = `floor(4 × 5 / 3) = 6`.

**A trained Skill not categorized falls back to the `Default Skill Rate` (`unaligned`).** Stumpy trains `intimidate`; cleric uses `aligned_proficiencies` (inclusion form) and `intimidate` is not in the list. Default for trained-but-unlisted = `unaligned = level`. Ranks = `4`.

**An untrained Skill returns zero ranks.** Stumpy does not train `stealth`. *Get ranks* returns 0, regardless of how cleric categorizes the Skill.

**The inverse `unaligned_proficiencies` form flips the default.** Cottonballs (Bard 4) trains `perform_sing`. Bard declares `unaligned_proficiencies: [restricted_magic, survival]` (inverse form). `perform_sing` (and its `perform_` prefix) is not in that list, so under the inverse default it advances at the `aligned` rate. Ranks = `floor(4 × 5 / 3) = 6`.

**A Skill in `unaligned_proficiencies` advances at the `unaligned` rate.** A hypothetical Bard who trains `survival`: Bard's `unaligned_proficiencies` includes `survival`, so the Skill advances at the `unaligned` rate. Ranks at Class Level 4 = `floor(4 × 1) = 4`.

**Set Instances inherit categorization from their Set Skill prefix.** Cottonballs's `perform_sing` resolves through the `perform_` prefix when checking the Bard's `unaligned_proficiencies` list — neither `perform_sing` nor `perform_` appears there, so the default-aligned rate of the inverse form applies. A hypothetical Cleric who trains `craft_blacksmith` resolves through `craft_` (in cleric's `aligned_proficiencies`) → `aligned` rate.

**Sub-Class extension to `aligned_proficiencies` lifts ranks.** Lysander (Arcane Trickster 4) trains `arcana`. The merged Arcane Trickster effective aligned-rate skills include `arcana` (added by the Sub-Class). Rate = `aligned`. Ranks = `floor(4 × 5 / 3) = 6`.

**`game_chess` is unaligned for Arcane Trickster.** Lysander trains `game_chess`. The merged Arcane Trickster `aligned_proficiencies` does not include `game_` or `game_chess`. Default (inclusion-form fallback) = `unaligned`. Ranks = `4`.

**An Opposed Skill the Creature trains advances at the `opposed` rate.** A hypothetical Wizard 6 with `opposed_proficiencies: [athletics]` (no such declaration in the shipped data — for illustration) who trains `athletics`: rate = `opposed = floor(2 × level / 3)`. Ranks = `floor(6 × 2 / 3) = 4`.

**Multiple Classes sum their per-Class contribution.** A hypothetical Creature with `classes = [{class: fighter, level: 3, trained_skills: [athletics]}, {class: rogue, level: 2, trained_skills: [athletics, stealth]}]`. Both classes list `athletics` in their `aligned_proficiencies`. Ranks = `floor(3 × 5 / 3) + floor(2 × 5 / 3) = 5 + 3 = 8`.

**Bare Set Skill key is invalid.** Calling `ranks_for("perform_")` is invalid input — Creatures does not store ranks under bare Set Skill keys.

**Unknown key returns zero.** Calling `ranks_for("homebrew_skill")` on Stumpy returns 0 (no Class lists it, the Creature does not train it).

### Saves

**A Class Save advances at the `aligned` rate.** Stumpy: cleric's `saves.aligned = [wis, cha]`. `ranks_for("wis_save") = floor(4 × 5 / 3) = 6`.

**A Save not in `saves.aligned` advances at the `opposed` rate (the default).** Stumpy: `str` is not in cleric's `saves.aligned`. `ranks_for("str_save") = floor(4 × 2 / 3) = 2`.

**Every Class contributes to every Save.** A hypothetical multi-classed Creature `[{fighter, 3}, {rogue, 2}]` for `ranks_for("dex_save")`: fighter has `dex` as `opposed` (`saves.aligned = [str, con]`) → `floor(3 × 2/3) = 2`. Rogue has `dex` in `saves.aligned = [dex, int]` → `floor(2 × 5/3) = 3`. Sum = `5`.

### Martial

**Martial uses `martial_advancement`.** Stumpy: cleric's `martial_advancement = unaligned`. `ranks_for("martial") = floor(4 × 1 / 1) = 4`. Olga (barbarian 4, `martial_advancement = aligned`): `floor(4 × 5 / 3) = 6`. Hypothetical wizard 6 with `martial_advancement = opposed`: `floor(6 × 2 / 3) = 4`.

**Martial does not appear in any Skill list.** A Class's `aligned_proficiencies` / `unaligned_proficiencies` / `opposed_proficiencies` never list `martial`; martial is exclusively handled via `martial_advancement`.

---

## Get Max Hit Points

**Tier 2 cleric uses the Tier-2 HP Formula and the Effective Constitution.** Stumpy's Effective Constitution is 23 and the Tier 2 formula is `"2 * con"`. `max_hit_points = floor(2 × 23) = 46`.

**Tier 1 uses the Tier-1 HP Formula.** Ghoul (Tier 1, Effective Constitution = `12 + 0 + 0 + 1 + 0 = 13`) with formula `"con"` → 13.

**Tier 0 uses the 0.5 substitution where Formulas reference `tier`.** A hypothetical Tier 0 Creature with Effective Constitution 16 evaluating an HP Formula referencing `tier` (e.g. `tier * con`) computes `0.5 * 16 = 8` after rounding.

**Aggregated `hp_bonus` adds on top, with per-Bonus-Type stacking at this consumer.** A Creature with two `target: hp_bonus`, `type: Enhancement` entries `+5` and `+8`: the +8 survives per-type stacking; max HP gains 8. A `+3 Morale` entry would survive alongside it (different Bonus Type).

**Tier beyond the configured HP Formula array is an error.** A Creature whose Tier resolves to 6 raises with the default `HP Formula` (length 6, indexes 0..5).

---

## Get Max Mana

**Tier 2 cleric: formula + per-Class contribution.** Stumpy: Effective Intelligence 16, Tier 2. Mana Formula[2] = `"int"` → 16. Plus cleric mana contribution `class.mana_advancement (4) × class.level (4) = 16`. `max_mana = 16 + 16 = 32`.

**Tier 2 barbarian: formula + low per-Class contribution.** Olga: Effective Intelligence 14, Tier 2. Formula[2] → 14. Plus barbarian `mana_advancement (1) × 4 = 4`. `max_mana = 14 + 4 = 18`.

**Class with no `mana_advancement` contributes zero.** A Class entry omitting `mana_advancement` defaults to `0`; the Class adds nothing.

**Sub-Class can override `mana_advancement`.** Lysander (Arcane Trickster 4): merged `mana_advancement = 2`. Effective Intelligence 20, Tier 2. Formula[2] → 20. Class contribution `2 × 4 = 8`. `max_mana = 28`.

---

## Update entry points

### Set Tier-Up Choices

**Valid choices land.** *Set Tier-Up Choices* on a Tier-3 hypothetical Creature with `(tier=3, [int, dex])`: subsequent *Get Effective Attributes* shows the Tier-3 Chosen Bonus on `int` and `dex` in addition to the Tier-2 picks.

**Wrong list length is rejected.** *Set Tier-Up Choices* on Stumpy with `(tier=2, [int])` (length 1, config expects 2): rejected.

**Unknown attribute key is rejected.** *Set Tier-Up Choices* on Stumpy with `(tier=2, [int, magic])`: rejected.

**Tier beyond the Creature's current Tier is rejected.** *Set Tier-Up Choices* on a Tier 1 Creature with `(tier=3, [str, con])`: rejected.

**Tier below 2 is rejected.** *Set Tier-Up Choices* with `tier = 0` or `tier = 1`: rejected. Tier 0 has no Tier-Up; Tier 1 grants only the flat Per-Tier Inherent Bonus.

**Duplicate picks at the same Tier are accepted.** *Set Tier-Up Choices* with `(tier=2, [str, str])` stores the list as-is; the Per-Tier Inherent Chosen Bonus to `str` is `2 × 2 = 4` at that Tier.

### Set Tier Override

**Override applies immediately.** *Set Tier Override* on Olga (computed Tier 2) to `4`: *Get Tier* returns 4. *Get Effective Attributes* now uses the Tier-4 Per-Tier Inherent Bonus.

**Clearing the override restores computed Tier.** *Set Tier Override* on Olga to `null`: *Get Tier* returns 2 again.

### Set Class Choices

**Setting `choices.spellcasting` adds the listed spells to Granted Abilities.** *Set Class Choices* on Lysander: `(class="arcane_trickster", {spellcasting: ["elemental_dart"]})`. *Get Granted Abilities* now includes `elemental_dart` with `source = "class:arcane_trickster"`.

**Setting `choices` wholesale replaces the previous map.** Stumpy starts with `cleric.choices = {deity: "Grull", domain: "War", spellcasting: ["magic_vestments"]}`. *Set Class Choices* on Stumpy: `(class="cleric", {deity: "Grull", domain: "War"})`: the `spellcasting` key is gone — `magic_vestments` no longer appears in *Get Granted Abilities*.

**Setting `choices` on a Class the Creature does not have rejects.** *Set Class Choices* on Olga (who has no `wizard` Class Entry): `(class="wizard", {spellcasting: ["elemental_dart"]})`: rejected. The Creature's record is unchanged.

**Choices for a Class with no Spellcasting-type ability are stored but contribute no Granted Abilities.** *Set Class Choices* on Olga (barbarian): `(class="barbarian", {spellcasting: ["fire_dart"]})`: accepted (Creatures stores opaquely), but *Get Granted Abilities* does NOT include `fire_dart` — the Barbarian Class progression never grants a Spellcasting-type ability, so the choice has no consumer.

### Set Class Level

**Increasing the Class Level shifts Tier and ranks.** *Set Class Level* on Stumpy: `(class="cleric", level=8)`: Total Level 8 → Tier 3 (hero track). `ranks_for("wis_save") = floor(8 × 5 / 3) = 13`.

**Setting Class Level to zero leaves the entry but contributes nothing.** A Class Entry with `level = 0` contributes zero ranks and zero Granted Abilities from that Class. The entry persists until *Prune Empty Classes* is invoked.

### Set Trained Skills

**Replacing the trained list changes ranks immediately.** *Set Trained Skills* on Stumpy: `(class="cleric", [arcana, healing])`. Skills no longer in the list (e.g. `sense_motive`) return zero ranks on the next call.

---

## Spawn Creature From Template

**Spawn allocates a fresh ID one past the dataset's current maximum.** Dataset contains records with IDs `{1, 2, 3, 100, 101}`. *Spawn Creature From Template* on `template_id = "100"` returns `"102"`. A second call returns `"103"`. The IDs are unique across all loaded `creatures_data_*` files — the loader globs the pattern and the allocator scans the merged set.

**Spawned record is a deep copy of the template.** Template `100` has `base_attributes = {str: 13, dex: 14, ...}`, `classes = [{class: rogue, level: 1, trained_skills: [...]}]`. After *Spawn Creature From Template* on `"100"`, the new record's `base_attributes` and `classes` are equal-by-value to the template's. Mutating the new record's `classes[0].level` to `2` does NOT change the template's `classes[0].level`.

**`name_override` replaces the template's name on the spawn only.** *Spawn Creature From Template* on `"100"` with `name_override = "Bloodfin"` produces a record with `name = "Bloodfin"`. Template `100`'s `name` remains `"Pirate"`.

**`loot_table` override replaces the template's `loot_table` on the spawn only.** Template `100` carries `loot_table = "pirates_basic"`. *Spawn Creature From Template* on `"100"` with `loot_table = "captain_loot"` produces a record with `loot_table = "captain_loot"`. Template `100` is unchanged.

**Spawn does NOT add to any Combat.** The new record is persisted in the Creatures dataset; no Combat State change occurs. The caller follows up with Combat's *Add Combatant*.

**Spawning from a non-existent template ID rejects.** *Spawn Creature From Template* on `template_id = "9999"` (no such record): rejected with a missing-template error. No new record is allocated.

**Spawning from a PC template is allowed but unusual.** *Spawn Creature From Template* on `"1"` (Ash Windmere) succeeds, producing a duplicate PC record. Validation does not gate the source's `tags` — the entry point is policy-free; consuming UIs decide which templates to surface.

---

## Delete Creature

**Delete removes the record from the dataset.** Dataset contains record `"1000"`. *Delete Creature* on `"1000"`: subsequent *Look up Creature* on `"1000"` returns null; *List Creatures* no longer reports `"1000"`.

**Delete is idempotent.** *Delete Creature* on `"1000"` after it was already deleted: no error.

**Delete does NOT cascade into other domains.** A Combat State has a Combatant whose `creature_id = "1000"`. After *Delete Creature* on `"1000"`, the Combatant entry remains in the Combat State (Combat's `creature_lookup` will now return null for it). Cleanup is the caller's responsibility — the consuming loot stub composes Combat's *Remove Combatant* + *Delete Creature* in sequence; calling *Delete Creature* in isolation is allowed.

**Conditions, Equipment, and other per-Creature state are not pruned.** After *Delete Creature* on `"1000"`, an existing entry in `conditions_data.example.json` keyed by `"1000"` and an Equipment owner `creature:1000` are both still present. The caller (typically the post-combat loot stub) cleans these as part of its flow.

---

## Roll Encounter

**Each Encounter Row resolves and produces fresh spawns.** Encounter Table `caravan_ambush` has one Guaranteed row with payload `[{template_id: "101", count: 2}]`. *Roll Encounter* on `"caravan_ambush"` returns a 2-element list of fresh Creature IDs. The Creatures dataset gains two new records, each a deep-copy of template `"101"`.

**`count` accepts dice expressions evaluated at roll time.** Encounter Row payload `[{template_id: "104", count: "1d4 + 1"}]`. Each *Roll Encounter* call rolls 1d4+1 and produces that many spawns; two successive calls may produce different counts.

**Loot Row vocabulary applies — `chance`, `when`, `as`.** Table has three rows: (1) guaranteed `[{template_id: "101", count: 2}]`, (2) Independent Chance `0.6` publishing `as: has_captain` with `[{template_id: "102", count: 1}]`, (3) Gated `when: {has_captain: true}` with `[{template_id: "105", count: 1}]`. When row 2's `chance` succeeds, row 3 fires. When row 2's `chance` fails, row 3 is skipped (no `has_captain` Variable was published).

**A skipped row does not publish.** In the table above, when row 2's `chance` fails, the Roll Variable `has_captain` is absent — row 3's `when: {has_captain: true}` evaluates false, and row 3 is skipped.

**Returned list is in roll order.** With the three-row table above and a successful captain roll: returned IDs are `[<orc1>, <orc2>, <captain>, <wardog>]` in that order.

**Spawn Refs with `loot_table` override stamp every spawn.** Encounter Row payload `[{template_id: "100", count: 2, loot_table: "captain_loot"}]`. *Roll Encounter* produces two new records, both with `loot_table = "captain_loot"` regardless of the template's own `loot_table`.

**`name_override` stamps every spawn.** Payload `[{template_id: "100", count: 3, name_override: "Skullsplitter"}]`. All three resulting records carry `name = "Skullsplitter"`.

**Roll Encounter does NOT touch Combat.** Combat State is unchanged after *Roll Encounter*. The caller adds each returned Creature ID via Combat's *Add Combatant*.

**Random Seed reproduces the result.** *Roll Encounter* on `"caravan_ambush"` with `seed = 42` twice yields the same Creature IDs and same Roll Variable outcomes both times.

**Unknown table ID rejects.** *Roll Encounter* on `"no_such_table"`: rejected with a missing-table error. No spawns are produced.

**Spawn Ref pointing at a deleted template rejects.** Encounter Table `bad_ref` has a row `[{template_id: "9999"}]` (no such record). *Roll Encounter* on `"bad_ref"`: rejected. Validation catches this at *Load Encounter Tables* time; runtime call is a fallback check.

---

## Class Resolution

**Top-level Class returns its own entry.** Resolving `"cleric"` returns the cleric entry verbatim. The resolved key is `"cleric"`.

**Sub-Class key returns the merged entry, with `class_key` reported as the Sub-Class.** Resolving `"arcane_trickster"` returns the merged entry with `class_key = "arcane_trickster"`.

**Sub-Class is detected through its parent's `sub_class` map.** Resolving `"arcane_trickster"` works even though there is no top-level `arcane_trickster:` key; the resolver scans every Class's `sub_class` map.

**Unknown key raises at load time and warns at runtime.** A Creature whose `classes[i].class = "unknown_class"` causes load-time validation to fail. (A consuming project that bypasses validation gets a warning at runtime and zero contribution.)

---

## Validation

**Required base attributes are enforced.** A Creature Record whose `base_attributes` omits `str` is rejected.

**Race Aspect required when the Race declares Aspects.** A Creature with `race = "elf"` and `race_aspect = null` is rejected.

**Race Aspect rejected when the Race declares none.** A Creature with `race = "human"` and `race_aspect = "high"` is rejected.

**`trained_skills` cannot include bare Set Skill keys.** A Class Entry with `trained_skills = ["perform_"]` is rejected. `"perform_sing"` is fine.

**Duplicate Creature IDs are rejected at load.** A dataset with two Creatures of `id = "1"` raises.

**`tier_up_choices` keys must be Tier ≥ 2.** A Creature Record with `tier_up_choices = { 1: [str, dex] }` is rejected (Tier 1 grants no Chosen Bonus). `{ 0: ... }` is likewise rejected.

**Wrong-length Tier-Up Choice entries are rejected.** A Creature Record with `tier_up_choices = { 2: [str] }` (length 1, config expects 2) is rejected.

**Unknown Advancement Track is rejected.** A Creature with `advancement_track = "epic"` (no such key in `Tier Breakpoints`) is rejected.

**A Class declaring both `aligned_proficiencies` and `unaligned_proficiencies` is rejected at config load.** The two forms are mutually exclusive at the top level. (Sub-Classes may declare any combination — each acts as an additive adjustment.)

**A Class must declare `saves.aligned`.** A Class Catalog Entry omitting `saves.aligned` is rejected at load time. (The list may be empty for a hypothetical Class with no `aligned`-rate Saves, but the key must be present.)
