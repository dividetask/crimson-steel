module Status
  # Sample Creatures for the Creatures sub-view of the Status page.
  # Hand-built (not loaded through the live Creatures domain) so the
  # sub-view stays scoped to Status's own dummy data per the project's
  # per-page-data rule. Each entry has the full set of derived values
  # the Creature Card Stub displays — base attributes, racial chain
  # adjustments, per-tier inherent bonus, chosen bonus, effective
  # attributes, speed, max HP, max mana, granted abilities, trained
  # skills with rate badges, and saves.
  #
  # The roster is curated to exercise every variant of the stub:
  #
  #   1. Single-class PC, no race chain ancestors past humanoid (Olga,
  #      Human Barbarian 4) — exercises the `all: +1` racial.
  #   2. Single-class PC with multi-link race chain (Stumpy, Hill Dwarf
  #      Cleric 4) — exercises chain walk + deity/domain spells.
  #   3. Archetype PC (Lysander, High Elf Arcane Trickster 4) —
  #      exercises Archetype merge.
  #   4. Multi-class PC (Rook, Half-Orc Fighter 3 / Rogue 2) —
  #      exercises per-Class rank summation.
  #   5. Tier 0 untrained NPC (Pidge, Halfling Commoner 1) — exercises
  #      the bottom of the Tier table.
  #   6. Tier-override creature (Pale Lantern, undead, Tier 4 with
  #      no classes) — exercises the override path.
  module SampleCreatures
    module_function

    def creatures
      [stumpy, olga, lysander, rook, pidge, pale_lantern]
    end

    # ---- 1. Single-class with race chain --------------------------------

    def stumpy
      base = { str: 12, dex: 14, con: 17, int: 14, wis: 18, cha: 11 }
      racial = { con: 2, wis: 2 } # hill_dwarf adjustments (illustrative)
      per_tier = 2                # Tier Minimum Inherent Bonus[2]
      chosen = { con: 2, wis: 2 } # tier_attribute_advancement[0..1] = [con, wis]
      effective = combine(base, racial, per_tier, chosen)
      {
        id: 1001, label: 'Single-class + multi-link Race chain',
        name: 'Stumpy', player: 'Mira',
        race_chain: %w[humanoid dwarf hill_dwarf],
        tags: %w[player_character],
        tier: 2, tier_source: 'computed (player_character breakpoints)',
        classes: [{ key: 'cleric', label: 'Cleric 4',
                    level: 4, choices: { deity: 'Grull', domain: 'War',
                                         spellcasting: %w[magic_vestments] } }],
        total_level: 4,
        attributes_table: attribute_rows(base, racial, per_tier, chosen, effective),
        speed: { value: 20, source: 'dwarf.speed = 20 (chain leaf wins)' },
        max_hp: { value: 46, formula: '2 * con', con: effective[:con] },
        max_mana: { value: 32,
                    base_formula: 'int', base_value: effective[:int],
                    class_contributions: [{ class: 'cleric', amount: 16, breakdown: '4 mana_per_level × 4 level' }] },
        granted_abilities: [
          { source: 'race', name: 'darkvision' },
          { source: 'race', name: 'dwarven_resilience' },
          { source: 'race', name: 'healing_attunement' },
          { source: 'class:cleric', name: 'see_injury' },
          { source: 'class:cleric', name: 'improved_healing' },
          { source: 'class:cleric', name: 'combat_healing' },
          { source: 'class:cleric', name: 'domain' },
          { source: 'class:cleric', name: 'channel_divinity' },
          { source: 'class:cleric', name: 'turn_undead' },
          { source: 'class:cleric', name: 'casting_feat' },
          { source: 'class:cleric', name: 'Heal' },
          { source: 'class:cleric', name: 'Ward' },
          { source: 'class:cleric', name: 'Standard Surgery' },
          { source: 'class:cleric', name: 'magic_vestments' },
          { source: 'class:cleric', name: 'Divine Favor' },
          { source: 'class:cleric', name: 'Shield of Faith' },
          { source: 'class:cleric', name: 'Spiritual Hammer' },
          { source: 'class:cleric', name: 'Silence' }
        ],
        trained_skills: [
          { key: 'healing',    rate: 'aligned',   ranks: 6, class: 'cleric' },
          { key: 'arcana',     rate: 'aligned',   ranks: 6, class: 'cleric' },
          { key: 'intimidate', rate: 'unaligned', ranks: 4, class: 'cleric' },
          { key: 'sense_motive', rate: 'aligned', ranks: 6, class: 'cleric' }
        ],
        saves: [
          { attr: 'str', rate: 'opposed', ranks: 2 },
          { attr: 'dex', rate: 'opposed', ranks: 2 },
          { attr: 'con', rate: 'opposed', ranks: 2 },
          { attr: 'int', rate: 'opposed', ranks: 2 },
          { attr: 'wis', rate: 'aligned', ranks: 6 },
          { attr: 'cha', rate: 'aligned', ranks: 6 }
        ],
        martial: { rate: 'unaligned', ranks: 4 }
      }
    end

    # ---- 2. Single-class, no race chain past humanoid -------------------

    def olga
      base = { str: 19, dex: 17, con: 17, int: 11, wis: 13, cha: 10 }
      racial = Hash.new(1).tap { |h| %i[str dex con int wis cha].each { |k| h[k] = 1 } } # human all: +1
      per_tier = 2
      chosen = { str: 2, con: 2 } # tier_attribute_advancement = [str, con]
      effective = combine(base, racial, per_tier, chosen)
      {
        id: 1002, label: 'Single-class, `all: +1` racial',
        name: 'Olga', player: 'Drew',
        race_chain: %w[humanoid human],
        tags: %w[player_character],
        tier: 2, tier_source: 'computed (player_character breakpoints)',
        classes: [{ key: 'barbarian', label: 'Barbarian 4', level: 4, choices: {} }],
        total_level: 4,
        attributes_table: attribute_rows(base, racial, per_tier, chosen, effective),
        speed: { value: 30, source: 'humanoid.speed = 30 (no chain override)' },
        max_hp: { value: 44, formula: '2 * con', con: effective[:con] },
        max_mana: { value: 18,
                    base_formula: 'int', base_value: effective[:int],
                    class_contributions: [{ class: 'barbarian', amount: 4, breakdown: '1 mana_per_level × 4 level' }] },
        granted_abilities: [
          { source: 'race', name: 'versatile' },
          { source: 'class:barbarian', name: 'rage' },
          { source: 'class:barbarian', name: 'fast_movement' },
          { source: 'class:barbarian', name: 'reckless_attacks' },
          { source: 'class:barbarian', name: 'uncanny_dodge' },
          { source: 'class:barbarian', name: 'primal_tenacity' },
          { source: 'class:barbarian', name: 'combat_feat' }
        ],
        trained_skills: [
          { key: 'athletics',    rate: 'aligned',   ranks: 6, class: 'barbarian' },
          { key: 'intimidate',   rate: 'aligned',   ranks: 6, class: 'barbarian' },
          { key: 'survival',     rate: 'unaligned', ranks: 4, class: 'barbarian' },
          { key: 'sense_motive', rate: 'unaligned', ranks: 4, class: 'barbarian' }
        ],
        saves: [
          { attr: 'str', rate: 'aligned', ranks: 6 },
          { attr: 'dex', rate: 'opposed', ranks: 2 },
          { attr: 'con', rate: 'aligned', ranks: 6 },
          { attr: 'int', rate: 'opposed', ranks: 2 },
          { attr: 'wis', rate: 'opposed', ranks: 2 },
          { attr: 'cha', rate: 'opposed', ranks: 2 }
        ],
        martial: { rate: 'aligned', ranks: 6 }
      }
    end

    # ---- 3. Archetype with race chain -----------------------------------

    def lysander
      base = { str: 9, dex: 19, con: 13, int: 14, wis: 15, cha: 15 }
      racial = { dex: 2, int: 2 } # high_elf adjustments (illustrative)
      per_tier = 2
      chosen = { dex: 2, int: 2 } # tier_attribute_advancement = [dex, int]
      effective = combine(base, racial, per_tier, chosen)
      {
        id: 1003, label: 'Archetype (Arcane Trickster, parent: rogue)',
        name: 'Lysander', player: 'Quinn',
        race_chain: %w[humanoid elf high_elf],
        tags: %w[player_character],
        tier: 2, tier_source: 'computed (player_character breakpoints)',
        classes: [{ key: 'arcane_trickster', label: 'Arcane Trickster 4 (replaced Rogue)',
                    level: 4, choices: { spellcasting: %w[elemental_dart] } }],
        total_level: 4,
        attributes_table: attribute_rows(base, racial, per_tier, chosen, effective),
        speed: { value: 30, source: 'elf.speed = 30 (chain ancestor wins)' },
        max_hp: { value: 30, formula: '2 * con', con: effective[:con] },
        max_mana: { value: 28,
                    base_formula: 'int', base_value: effective[:int],
                    class_contributions: [{ class: 'arcane_trickster', amount: 8, breakdown: '2 mana_per_level (archetype override) × 4 level' }] },
        granted_abilities: [
          { source: 'race', name: 'low_light_vision' },
          { source: 'race', name: 'keen_senses' },
          { source: 'race', name: 'elven_magic' },
          { source: 'class:arcane_trickster', name: 'trapfinding' },
          { source: 'class:arcane_trickster', name: 'sneak_attack' },
          { source: 'class:arcane_trickster', name: 'thieves_cant' },
          { source: 'class:arcane_trickster', name: 'arcane_spellcasting' },
          { source: 'class:arcane_trickster', name: 'danger_sense' },
          { source: 'class:arcane_trickster', name: 'combat_trickery' },
          { source: 'class:arcane_trickster', name: 'mage_hand_legerdemain' },
          { source: 'class:arcane_trickster', name: 'elemental_dart' }
        ],
        trained_skills: [
          { key: 'arcana',          rate: 'aligned',   ranks: 6, class: 'arcane_trickster', note: 'added by archetype' },
          { key: 'stealth',         rate: 'unaligned', ranks: 4, class: 'arcane_trickster' },
          { key: 'sleight_of_hand', rate: 'unaligned', ranks: 4, class: 'arcane_trickster' },
          { key: 'larceny',         rate: 'unaligned', ranks: 4, class: 'arcane_trickster' },
          { key: 'deception',       rate: 'unaligned', ranks: 4, class: 'arcane_trickster' },
          { key: 'game_chess',      rate: 'unaligned', ranks: 4, class: 'arcane_trickster' }
        ],
        saves: [
          { attr: 'str', rate: 'opposed', ranks: 2 },
          { attr: 'dex', rate: 'aligned', ranks: 6 },
          { attr: 'con', rate: 'opposed', ranks: 2 },
          { attr: 'int', rate: 'aligned', ranks: 6 },
          { attr: 'wis', rate: 'opposed', ranks: 2 },
          { attr: 'cha', rate: 'opposed', ranks: 2 }
        ],
        martial: { rate: 'unaligned', ranks: 4 }
      }
    end

    # ---- 4. Multi-class -------------------------------------------------

    def rook
      base = { str: 16, dex: 13, con: 14, int: 10, wis: 11, cha: 9 }
      racial = {} # half_orc placeholder (config has no adjustments yet)
      per_tier = 2
      chosen = { str: 2, con: 2 }
      effective = combine(base, racial, per_tier, chosen)
      {
        id: 1004, label: 'Multi-class (Fighter 3 / Rogue 2)',
        name: 'Rook', player: 'Avery',
        race_chain: %w[humanoid half_orc],
        tags: %w[player_character],
        tier: 2, tier_source: 'computed (Total Level 5 ≥ breakpoint 4)',
        classes: [
          { key: 'fighter', label: 'Fighter 3', level: 3, choices: {} },
          { key: 'rogue',   label: 'Rogue 2',   level: 2, choices: {} }
        ],
        total_level: 5,
        attributes_table: attribute_rows(base, racial, per_tier, chosen, effective),
        speed: { value: 30, source: 'humanoid.speed = 30' },
        max_hp: { value: 32, formula: '2 * con', con: effective[:con] },
        max_mana: { value: 15,
                    base_formula: 'int', base_value: effective[:int],
                    class_contributions: [
                      { class: 'fighter', amount: 3, breakdown: '1 × 3' },
                      { class: 'rogue',   amount: 2, breakdown: '1 × 2' }
                    ] },
        granted_abilities: [
          { source: 'class:fighter', name: 'weapon_training' },
          { source: 'class:fighter', name: 'armor_training' },
          { source: 'class:rogue',   name: 'trapfinding' },
          { source: 'class:rogue',   name: 'sneak_attack' },
          { source: 'class:rogue',   name: 'thieves_cant' },
          { source: 'class:rogue',   name: 'danger_sense' }
        ],
        trained_skills: [
          { key: 'athletics',  rate: 'aligned',   ranks: 5, class: 'fighter' },
          { key: 'athletics',  rate: 'unaligned', ranks: 2, class: 'rogue',  note: 'rogue: athletics is not in its aligned list' },
          { key: 'intimidate', rate: 'aligned',   ranks: 5, class: 'fighter' },
          { key: 'stealth',    rate: 'unaligned', ranks: 2, class: 'rogue' },
          { key: 'larceny',    rate: 'unaligned', ranks: 2, class: 'rogue' }
        ],
        saves: [
          { attr: 'str', rate: 'aligned',  ranks: 8, breakdown: 'fighter 5 + rogue 3 (rogue str is opposed: 1)... — illustrative' },
          { attr: 'dex', rate: 'mixed',    ranks: 5, breakdown: 'fighter 2 (opposed) + rogue 3 (aligned)' },
          { attr: 'con', rate: 'mixed',    ranks: 6, breakdown: 'fighter 5 (aligned) + rogue 1 (opposed)' },
          { attr: 'int', rate: 'mixed',    ranks: 5, breakdown: 'fighter 2 (opposed) + rogue 3 (aligned)' },
          { attr: 'wis', rate: 'opposed',  ranks: 3, breakdown: 'fighter 2 + rogue 1' },
          { attr: 'cha', rate: 'opposed',  ranks: 3, breakdown: 'fighter 2 + rogue 1' }
        ],
        martial: { rate: 'mixed', ranks: 7, breakdown: 'fighter 5 (aligned) + rogue 2 (unaligned)' }
      }
    end

    # ---- 5. Tier 0 untrained NPC ----------------------------------------

    def pidge
      base = { str: 9, dex: 12, con: 10, int: 10, wis: 10, cha: 11 }
      racial = {}
      per_tier = 0 # Tier Minimum Inherent Bonus[0]
      chosen = {}
      effective = combine(base, racial, per_tier, chosen)
      {
        id: 1005, label: 'Tier 0 NPC (bottom of the Tier table)',
        name: 'Pidge', player: nil,
        race_chain: %w[humanoid halfling],
        tags: %w[commoner],
        tier: 0, tier_source: 'computed (commoner breakpoints; level 1 < 4)',
        classes: [{ key: 'commoner', label: 'Commoner 1', level: 1, choices: {} }],
        total_level: 1,
        attributes_table: attribute_rows(base, racial, per_tier, chosen, effective),
        speed: { value: 25, source: 'halfling.speed = 25' },
        max_hp: { value: 5, formula: 'con / 2', con: effective[:con] },
        max_mana: { value: 2,
                    base_formula: 'int / 4', base_value: effective[:int],
                    class_contributions: [{ class: 'commoner', amount: 0, breakdown: '0 mana_per_level × 1 level' }] },
        granted_abilities: [],
        trained_skills: [
          { key: 'profession_innkeeper', rate: 'aligned',   ranks: 1, class: 'commoner' },
          { key: 'perception',           rate: 'aligned',   ranks: 1, class: 'commoner' }
        ],
        saves: [
          { attr: 'str', rate: 'aligned', ranks: 1 },
          { attr: 'dex', rate: 'opposed', ranks: 0 },
          { attr: 'con', rate: 'aligned', ranks: 1 },
          { attr: 'int', rate: 'opposed', ranks: 0 },
          { attr: 'wis', rate: 'opposed', ranks: 0 },
          { attr: 'cha', rate: 'opposed', ranks: 0 }
        ],
        martial: { rate: 'opposed', ranks: 0 }
      }
    end

    # ---- 6. Tier-override creature, no classes --------------------------

    def pale_lantern
      base = { str: 10, dex: 14, con: 10, int: 12, wis: 14, cha: 16 }
      racial = {}
      per_tier = 4 # Tier Minimum Inherent Bonus[4]
      chosen = {}
      effective = combine(base, racial, per_tier, chosen)
      {
        id: 2002, label: 'Tier Override, no classes',
        name: 'The Pale Lantern', player: nil,
        race_chain: %w[undead],
        tags: [],
        tier: 4, tier_source: 'override (tier: 4 on the record)',
        classes: [],
        total_level: 0,
        attributes_table: attribute_rows(base, racial, per_tier, chosen, effective),
        speed: { value: 30, source: 'undead.speed = 30' },
        max_hp: { value: 56, formula: '4 * con', con: effective[:con] },
        max_mana: { value: 48,
                    base_formula: '3 * int', base_value: effective[:int],
                    class_contributions: [] },
        granted_abilities: [
          { source: 'race', name: 'undead_traits' }
        ],
        trained_skills: [],
        saves: [
          { attr: 'str', rate: '—', ranks: 0 },
          { attr: 'dex', rate: '—', ranks: 0 },
          { attr: 'con', rate: '—', ranks: 0 },
          { attr: 'int', rate: '—', ranks: 0 },
          { attr: 'wis', rate: '—', ranks: 0 },
          { attr: 'cha', rate: '—', ranks: 0 }
        ],
        martial: { rate: '—', ranks: 0 }
      }
    end

    # ---- helpers --------------------------------------------------------

    def combine(base, racial, per_tier, chosen)
      %i[str dex con int wis cha].each_with_object({}) do |a, h|
        h[a] = base[a] + (racial[a] || 0) + per_tier + (chosen[a] || 0)
      end
    end

    def attribute_rows(base, racial, per_tier, chosen, effective)
      %i[str dex con int wis cha].map do |a|
        {
          attr: a,
          base: base[a],
          racial: racial[a] || 0,
          per_tier: per_tier,
          chosen: chosen[a] || 0,
          effective: effective[a]
        }
      end
    end
  end
end
