# Character sheet stub. Renders a character's static data (from the
# Character class) using the layout from origin/before-refactor's
# views/character_sheet.erb. Every field the Character class doesn't
# yet own — combat pool, hp, skills, weapons, abilities, etc. — is
# pulled from the dummy hash passed in so the page still looks like
# the old sheet while the per-feature classes are rebuilt.

helpers do
  # detail: :minimal (default) trims the sheet to what a player needs
  # at a glance — dropping dice columns, weapon threshold/bleed, skill
  # ranks, and the secondary HP rows. :full renders everything the
  # before-refactor sheet showed.
  def character_sheet_stub(character:, detail: :minimal, dummy: {})
    erb :"stubs/_character_sheet_stub", layout: false, locals: {
      character: character,
      detail:    detail == :full ? :full : :minimal,
      dummy:     character_sheet_dummy_defaults.merge(dummy || {})
    }
  end

  ATTRIBUTE_NAMES = {
    'Strength'     => :str,
    'Dexterity'    => :dex,
    'Constitution' => :con,
    'Intelligence' => :int,
    'Wisdom'       => :wis,
    'Charisma'     => :cha
  }.freeze

  def character_sheet_attribute_names
    ATTRIBUTE_NAMES
  end

  def character_sheet_half_mod(score)
    (score.to_i / 2).to_i
  end

  def character_sheet_add_plus(value)
    n = value.to_i
    "#{'+' if n >= 0}#{n}"
  end

  # Default dummy block for fields the Character class doesn't yet
  # cover. Anything passed into `dummy:` overrides these.
  def character_sheet_dummy_defaults
    {
      klass:               'Bard 3',
      tier:                3,
      bab:                 4,
      combat_pool:         5,
      perception_dice:     6,
      perception_bonus:    2,
      initiative:          3,
      damage_reduction:    2,
      damage_resilience:   2,
      speed:               30,
      current_hp:          22,
      hp_max:              28,
      current_mana:        12,
      mana_max:            14,
      mana_regen:          3,
      temporary_hit_points: 0,
      moderate_damage:     0,
      major_damage:        0,
      bab_dice:            3,
      bab_bonus:           2,
      save_enhancement:    0,
      attribute_damage:    Hash.new(0),
      attribute_enhancement: Hash.new(0),
      save_dice:           Hash.new(3),
      save_bonus:          Hash.new(2),
      attr_dice:           Hash.new(3),
      attr_bonus:          Hash.new(2),
      shields:             [],
      weapons:             [
        { 'name' => 'Longsword', 'speed' => 2, 'arm_speed' => '',
          'dice' => 4, 'attack_bonus' => 3, 'damage' => '+2',
          'bleed' => 0, 'threshold' => 8 }
      ],
      skills: [
        { 'name' => 'Perception', 'ranks' => 2, 'dice' => 5, 'bonus' => 2 },
        { 'name' => 'Focus',      'ranks' => 3, 'dice' => 6, 'bonus' => 3 }
      ],
      tattoos:     [],
      equipped:    ['Longsword', 'Leather Armor'],
      ammunition:  [],
      consumable:  [{ 'name' => 'Healing Draught', 'quantity' => 2 }],
      other_items: [{ 'name' => 'Rations (5)' }, { 'name' => 'Bedroll' }],
      defined_items: [],
      abilities:   [
        { 'name' => 'Bardic Inspiration',
          'description' => 'Grant a luck bonus to an ally’s next check.' },
        { 'name' => 'Unsettling Words',
          'description' => 'Impose a luck penalty on an enemy’s next check.' }
      ],
      spell_list:  [],
      item_spell_list: nil,
      ritual_list: [],
      notes:       [{ 'note' => 'Placeholder note for the character.' }]
    }
  end
end
