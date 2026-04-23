# Placeholder data source for the UI rebuild. The real rule engine from
# before-refactor (character.rb, templates.rb, tools.rb, etc.) is not
# wired up yet; this class returns hard-coded values shaped the way the
# views expect so the interface can be rebuilt one page at a time. Each
# method here corresponds to a query the final data layer will have to
# answer.
class DummyData
  # --- Campaign-level state ------------------------------------------------

  def self.campaign
    {
      'gold' => 275,
      'rounds_elapsed' => 4,
      'current_chapter' => 2,
      'current_scene' => 1
    }
  end

  def self.chapters
    [
      { 'number' => 1, 'title' => 'The Road to Crimson' },
      { 'number' => 2, 'title' => 'Beneath the Mountain' },
      { 'number' => 3, 'title' => 'Court of Ash' }
    ]
  end

  # --- Characters ----------------------------------------------------------

  def self.characters
    @characters ||= [
      build_pc(id: 1, name: 'Ash Windmere',   race: 'Human',    klass: 'Bard',    tier: 3,
               hp: 24, hp_max: 28, mana: 12, mana_max: 14, abilities: %w[bardic_inspiration unsettling_words]),
      build_pc(id: 2, name: 'Bryn Ironvein',  race: 'Dwarf',    klass: 'Fighter', tier: 3,
               hp: 32, hp_max: 36, mana: 0,  mana_max: 0,  abilities: %w[shield_bash second_wind]),
      build_pc(id: 3, name: 'Lira Duskmoor',  race: 'Elf',      klass: 'Wizard',  tier: 3,
               hp: 18, hp_max: 22, mana: 16, mana_max: 18, abilities: %w[arcane_focus ritual_caster]),
      build_pc(id: 4, name: 'Kass Thorne',    race: 'Halfling', klass: 'Rogue',   tier: 3,
               hp: 20, hp_max: 24, mana: 0,  mana_max: 0,  abilities: %w[sneak_attack evasion]),
      build_pc(id: 5, name: 'Rowan Vale',     race: 'Half-Elf', klass: 'Ranger',  tier: 3,
               hp: 26, hp_max: 30, mana: 6,  mana_max: 8,  abilities: %w[hunters_mark quick_draw]),
      build_pc(id: 6, name: 'Ember Blackoak', race: 'Half-Orc', klass: 'Druid',   tier: 3,
               hp: 22, hp_max: 26, mana: 10, mana_max: 12, abilities: %w[wild_shape spore_cloud])
    ]
  end

  def self.pcs
    characters.select { |c| c['group'] == 'PC' }
  end

  def self.character_by_id(id)
    characters.find { |c| c['id'].to_i == id.to_i }
  end

  # --- Enemies -------------------------------------------------------------

  def self.enemy_groups
    [
      {
        label: 'Bandits',
        enemies: [
          { id: 'bandit_thug',    index: 0, name: 'Bandit Thug',    tier: 1 },
          { id: 'bandit_archer',  index: 1, name: 'Bandit Archer',  tier: 1 },
          { id: 'bandit_captain', index: 2, name: 'Bandit Captain', tier: 2 }
        ]
      },
      {
        label: 'Undead',
        enemies: [
          { id: 'skeleton',       index: 3, name: 'Skeleton',       tier: 1 },
          { id: 'wight',          index: 4, name: 'Wight',          tier: 3 }
        ]
      }
    ]
  end

  def self.enemy_templates
    enemy_groups.flat_map { |g| g[:enemies] }
  end

  # --- Combat --------------------------------------------------------------

  def self.combat_state
    {
      'round' => 4,
      'active_effects' => [],
      'current_turn' => 'pc-3',
      'turns' => [
        { 'combat_id' => 'pc-3',  'char_id' => 3,              'name' => 'Lira Duskmoor',  'initiative' => 'X97',
          'hp' => 18, 'hp_max' => 22,
          'minor_damage' => 4, 'moderate_damage' => 0, 'major_damage' => 0,
          'combat_pool' => 5, 'combat_pool_max' => 5, 'shock' => 0, 'pain' => 0,
          'conditions' => [], 'group' => 'PC' },

        { 'combat_id' => 'pc-1',  'char_id' => 1,              'name' => 'Ash Windmere',   'initiative' => 'X87',
          'hp' => 22, 'hp_max' => 28,
          'minor_damage' => 6, 'moderate_damage' => 0, 'major_damage' => 0,
          'combat_pool' => 4, 'combat_pool_max' => 6, 'shock' => 1, 'pain' => 0,
          'conditions' => [{ 'name' => 'bleed', 'value' => 2 }], 'group' => 'PC' },

        { 'combat_id' => 'pc-2',  'char_id' => 2,              'name' => 'Bryn Ironvein',  'initiative' => '742',
          'hp' => 24, 'hp_max' => 36,
          'minor_damage' => 4, 'moderate_damage' => 8, 'major_damage' => 0,
          'combat_pool' => 3, 'combat_pool_max' => 7, 'shock' => 0, 'pain' => 2,
          'conditions' => [{ 'name' => 'poison', 'value' => 1 }], 'group' => 'PC' },

        { 'combat_id' => 'mob-1', 'char_id' => 'bandit_thug',  'name' => 'Bandit Thug',    'initiative' => 'X4',
          'hp' => 14, 'hp_max' => 14,
          'minor_damage' => 0, 'moderate_damage' => 0, 'major_damage' => 0,
          'combat_pool' => 3, 'combat_pool_max' => 3, 'shock' => 0, 'pain' => 0,
          'conditions' => [], 'group' => 'Enemy' },

        { 'combat_id' => 'mob-2', 'char_id' => 'bandit_thug',  'name' => 'Bandit Thug',    'initiative' => '951',
          'hp' => 5, 'hp_max' => 14,
          'minor_damage' => 2, 'moderate_damage' => 4, 'major_damage' => 3,
          'combat_pool' => 1, 'combat_pool_max' => 3, 'shock' => 2, 'pain' => 1,
          'conditions' => [{ 'name' => 'bleed', 'value' => 1 }, { 'name' => 'major_damage', 'value' => 1 }], 'group' => 'Enemy' },

        { 'combat_id' => 'mob-3', 'char_id' => 'bandit_archer','name' => 'Bandit Archer',  'initiative' => '8',
          'hp' => 0, 'hp_max' => 10,
          'minor_damage' => 2, 'moderate_damage' => 4, 'major_damage' => 4,
          'combat_pool' => 0, 'combat_pool_max' => 3, 'shock' => 0, 'pain' => 0,
          'conditions' => [{ 'name' => 'major_damage', 'value' => 1 }], 'group' => 'Enemy' }
      ]
    }
  end

  # Initiative track sorted high-to-low. Sort key is the X-bearing
  # initiative string compared as a sequence of dice values (X = 10,
  # then digits left-to-right).
  def self.initiative_turns
    combat_state['turns'].sort_by { |t| initiative_sort_key(t['initiative']) }
  end

  def self.initiative_sort_key(str)
    str.to_s.chars.map { |c| c == 'X' ? -10 : -c.to_i }
  end

  # --- Notes ---------------------------------------------------------------

  def self.notes
    [
      { 'id' => 1, 'owner_id' => 0, 'chapter' => 1, 'type' => 'chapter_title',
        'title' => 'The Road to Crimson', 'note' => '', 'public' => true },
      { 'id' => 2, 'owner_id' => 0, 'chapter' => 1, 'public' => true,
        'note' => "The party meets at the Weeping Stag. A courier delivers a sealed writ from Lord Halric." },
      { 'id' => 3, 'owner_id' => 0, 'chapter' => 2, 'public' => false,
        'note' => "Secret: the steward is working with the bandits. He knows the party's route." },
      { 'id' => 4, 'owner_id' => 1, 'chapter' => 2, 'public' => true,
        'note' => "Ash's personal log: the song keeps coming back to me in dreams." }
    ]
  end

  # --- Spells --------------------------------------------------------------

  def self.spell_schools
    {
      'evocation'     => 'Raw magical force shaped into damage or barriers.',
      'illusion'      => 'Deceptions of the senses and the mind.',
      'transmutation' => 'Reshaping matter, form, and state.',
      'divination'    => 'Knowledge pulled from distance, memory, or fate.'
    }
  end

  def self.spell_list
    [
      { 'name' => 'Firebolt',        'school' => 'evocation',     'tier' => 1, 'skill' => ['focus'],    'save' => 0,      'range' => 'medium', 'duration' => 'instant' },
      { 'name' => 'Minor Illusion',  'school' => 'illusion',      'tier' => 0, 'skill' => ['guile'],    'save' => 'wis',  'range' => 'short',  'duration' => '1 min' },
      { 'name' => 'Mend',            'school' => 'transmutation', 'tier' => 1, 'skill' => ['craft'],    'save' => 0,      'range' => 'touch',  'duration' => 'instant' },
      { 'name' => 'Scrying',         'school' => 'divination',    'tier' => 3, 'skill' => ['insight'],  'save' => 'wis',  'range' => 'far',    'duration' => '10 min' }
    ]
  end

  def self.spell_by_name(name)
    spell = spell_list.find { |s| s['name'].casecmp(name.to_s).zero? }
    return nil unless spell
    spell.merge('description' => "Placeholder description for #{spell['name']}.")
  end

  def self.all_skills
    %w[perception focus craft guile insight athletics stealth persuasion arcana lore]
  end

  # --- Store ---------------------------------------------------------------

  def self.store_items
    [
      { 'name' => 'Longsword',       'type' => 'equipment',   'subtype' => 'weapon',   'tier' => 1, 'price' => 15 },
      { 'name' => 'Leather Armor',   'type' => 'equipment',   'subtype' => 'armor',    'tier' => 1, 'price' => 10 },
      { 'name' => 'Healing Draught', 'type' => 'item',        'subtype' => 'potion',   'tier' => 1, 'price' => 25 },
      { 'name' => 'Ember Tattoo',    'type' => 'tattoo',      'subtype' => 'shoulder', 'tier' => 2, 'price' => 80 },
      { 'name' => 'Iron Arrows',     'type' => 'ammunition',  'subtype' => 'arrow',    'tier' => 1, 'price' => 1  }
    ]
  end

  def self.item_tree
    {
      'equipment'  => %w[weapon armor shield],
      'item'       => %w[potion scroll misc],
      'tattoo'     => %w[shoulder arm chest],
      'ammunition' => %w[arrow bolt sling]
    }
  end

  # --- Scene ---------------------------------------------------------------

  def self.scene
    {
      'title' => 'The Bandit Ambush',
      'image' => nil,
      'show_initiative' => true,
      'description' => 'Crossbows click from the treeline. Smoke rises off the wrecked wagon.'
    }
  end

  # --- Builders ------------------------------------------------------------

  def self.build_pc(id:, name:, race:, klass:, tier:, hp:, hp_max:, mana:, mana_max:, abilities:)
    {
      'id' => id,
      'name' => name,
      'race' => race,
      'klass' => klass,
      'full_klass' => klass,
      'group' => 'PC',
      'tier' => tier,
      'bab' => tier * 2,
      'hp_max' => hp_max,
      'current_hp' => hp,
      'mana_max' => mana_max,
      'current_mana' => mana,
      'mana_regen' => (mana_max / 4.0).floor,
      'combat_pool' => tier + 2,
      'initiative' => tier + 3,
      'speed' => 6,
      'damage_reduction' => tier,
      'damage_resilience' => tier,
      'temporary_hit_points' => 0,
      'moderate_damage' => 0,
      'major_damage' => 0,
      'saturation' => 0,
      'attributes' => { 'str' => 4, 'dex' => 3, 'con' => 3, 'int' => 3, 'wis' => 3, 'cha' => 3 },
      'skills' => [
        { 'name' => 'perception', 'ranks' => 2, 'dice' => tier + 2 },
        { 'name' => 'focus',      'ranks' => tier, 'dice' => tier + 3 }
      ],
      'weapons' => [
        { 'name' => 'Longsword', 'speed' => 2, 'dice' => tier + 1, 'attack_bonus' => tier, 'damage_bonus' => 2, 'bleed' => 0, 'threshold' => 8 }
      ],
      'shields' => [],
      'items' => [
        { 'name' => 'Rations (5)', 'equipped' => false },
        { 'name' => 'Bedroll', 'equipped' => false }
      ],
      'abilities' => abilities,
      'spell_list' => klass == 'Wizard' ? [%w[Firebolt Mend], %w[Minor\ Illusion]] : nil,
      'notes' => [{ 'note' => "Placeholder note for #{name}." }]
    }
  end
end
