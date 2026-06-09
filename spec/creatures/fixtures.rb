require 'creatures'
require 'proficiencies'

# Test fixtures for spec/creatures and spec/proficiencies. Builds
# Creature Records in-memory so the specs don't depend on the
# docs/common/creatures/creatures_data_*.yaml files. Names mirror
# the hypothetical fixtures named in creatures_tests.md (Korth,
# Brenna, Vex, Birch, Ghoul, Brown Bear).
module CreaturesFixtures
  module_function

  # Build a Creature Record hash. Defaults supply the required
  # fields; overrides win. Symbol-keyed (the post-Record.normalize
  # shape).
  def record(**overrides)
    base = {
      # 9000-range ids keep these in-memory fixtures clear of the example
      # Equipment / Conditions datasets (whose owners use low ids), so a
      # fixture never accidentally inherits a real Creature's equipment.
      id: 9000,
      name: 'Test',
      player: nil,
      group: '',
      tags: [],
      # The generic fixture uses the `humanoid` root (no racial attribute
      # adjustments) so attribute / HP / mana mechanic tests read a clean
      # base; the named fixtures below set their own real sub-race.
      race: 'humanoid',
      attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 },
      tier: nil,
      loot_table: nil,
      metadata: {},
      classes: {},
      tier_attribute_advancement: []
    }
    base.merge!(overrides)
    base[:classes] = normalize_classes(base[:classes])
    base
  end

  def normalize_classes(classes)
    classes.each_with_object({}) do |(k, v), h|
      entry = v.is_a?(Hash) ? v.dup : { level: v }
      entry[:level]   ||= 0
      entry[:skills]  ||= []
      entry[:choices] ||= {}
      entry[:skills]  = entry[:skills].map(&:to_s)
      entry[:choices] = entry[:choices].transform_keys(&:to_s)
      h[k.to_s] = entry
    end
  end

  def accessor(**overrides)
    Creatures::Accessor.new(record(**overrides))
  end

  # ---- Named fixtures from creatures_tests.md ------------------------

  def korth  # Dwarven Cleric 4, hill_dwarf race, Tier 2 (override)
    record(
      id: 9001, name: 'Korth', race: 'hill_dwarf', tier: 2,
      tags: ['player_character'],
      attributes: { str: 12, dex: 14, con: 17, int: 14, wis: 18, cha: 11 },
      classes: { cleric: { level: 4, skills: %w[healing arcana intimidate sense_motive],
                            choices: { 'deity' => 'Karthak', 'domain' => 'War' } } },
      tier_attribute_advancement: %i[con wis]
    )
  end

  def brenna  # Human Barbarian 4, Tier 2 (override)
    record(
      id: 9002, name: 'Brenna', race: 'human', tier: 2,
      tags: ['player_character'],
      attributes: { str: 19, dex: 17, con: 17, int: 11, wis: 13, cha: 10 },
      classes: { barbarian: { level: 4, skills: %w[athletics intimidate survival sense_motive] } },
      tier_attribute_advancement: %i[str con]
    )
  end

  def vex  # High-Elf Arcane Trickster 4, Tier 2 (override)
    record(
      id: 9003, name: 'Vex', race: 'high_elf', tier: 2,
      tags: ['player_character'],
      attributes: { str: 9, dex: 19, con: 13, int: 14, wis: 15, cha: 15 },
      classes: { arcane_trickster: { level: 4,
                                       skills: %w[arcana stealth larceny sleight_of_hand
                                                  deception persuasion perception game_chess] } },
      tier_attribute_advancement: %i[dex int]
    )
  end

  def birch  # Satyr Bard 4, Tier 2 (override)
    record(
      id: 9004, name: 'Birch', race: 'satyr', tier: 2,
      tags: ['player_character'],
      attributes: { str: 9, dex: 12, con: 12, int: 10, wis: 11, cha: 18 },
      classes: { bard: { level: 4, skills: %w[perform_sing perform_dance persuasion arcana] } },
      tier_attribute_advancement: %i[dex cha]
    )
  end

  def ghoul  # Undead 2, Tier 1 (override). No class entries.
    record(
      id: 9100, name: 'Ghoul', race: 'undead', tier: 1,
      tags: ['enemy'],
      attributes: { str: 13, dex: 14, con: 12, int: 7, wis: 10, cha: 6 },
      classes: {}
    )
  end

  def brown_bear  # Animal track, Total Level 6
    record(
      id: 9101, name: 'Brown Bear', race: 'beast',
      tags: ['animal'],
      attributes: { str: 19, dex: 10, con: 16, int: 2, wis: 13, cha: 7 },
      classes: { commoner: { level: 6 } }
    )
  end
end
