# Full character sheet stub. Renders every field the
# before-refactor sheet showed (combat pool, dice columns, ranks,
# the four secondary HP rows, etc.). Use character_minimal_stub
# for the compact monster-card layout.
#
# Fields the Character class doesn't yet own come from the
# `dummy:` hash — character_sheet_dummy_defaults supplies sane
# defaults so callers only have to pass what differs.

helpers do
  def character_full_stub(character:, dummy: {})
    erb :"stubs/_character_full_stub", layout: false, locals: {
      character: character,
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

  # Short labels for the minimal card's attribute strip.
  ATTRIBUTE_SHORT = {
    str: 'STR', dex: 'DEX', con: 'CON',
    int: 'INT', wis: 'WIS', cha: 'CHA'
  }.freeze

  def character_sheet_attribute_names;  ATTRIBUTE_NAMES;  end
  def character_sheet_attribute_short;  ATTRIBUTE_SHORT;  end

  def character_sheet_half_mod(score)
    (score.to_i / 2).to_i
  end

  def character_sheet_add_plus(value)
    n = value.to_i
    "#{'+' if n >= 0}#{n}"
  end

  # CSS class for tier-tinted text. Matches the color palette used
  # throughout the app: red / orange / gold / green / blue ramping
  # from tier 0 → 4. Anything outside that range falls back to grey.
  def character_sheet_tier_class(tier)
    n = tier.to_i
    n.between?(0, 4) ? "tier-#{n}" : 'tier-unknown'
  end

  # Pretty label for a condition key. Mirrors the initiative stub's
  # naming so the same condition reads the same wherever it appears.
  def character_sheet_condition_label(key)
    key.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')
  end

  # Default dummy block for fields the Character class doesn't yet
  # cover. Anything passed into `dummy:` overrides these.
  def character_sheet_dummy_defaults
    {
      klass:               'Bard 3',
      bab:                 4,
      combat_pool:         5,
      perception_dice:     6,
      perception_bonus:    2,
      initiative:          3,
      current_hp:          22,
      current_mana:        12,
      mana_regen:          3,
      temporary_hit_points: 0,
      moderate_damage:     0,
      major_damage:        0,
      mana_saturation:     0,
      mana_saturation_max: 0,
      conditions:          {},
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
      notes:       [{ 'note' => 'Placeholder note for the character.' }]
    }
  end
end
