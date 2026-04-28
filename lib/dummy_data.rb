require 'yaml'

# Placeholder data source for the UI rebuild. The real rule engine
# from before-refactor (character.rb, templates.rb, tools.rb, etc.)
# is not wired up yet; this class returns hard-coded values shaped
# the way the views expect so the interface can be rebuilt one
# page at a time. Each method here corresponds to a query the final
# data layer will have to answer.
#
# Production never loads this file. app.rb requires
# lib/empty_data.rb instead and binds DATA to EmptyData, so prod
# stays a clean slate sourced entirely from NotesState.

class DummyData
  # --- Campaign-level state ------------------------------------------------

  def self.campaign
    { 'gold' => 275, 'rounds_elapsed' => 4,
      'current_chapter' => 2, 'current_scene' => 1 }
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
      { label: 'Bandits',
        enemies: [
          { id: 'bandit_thug',    index: 0, name: 'Bandit Thug',    tier: 1 },
          { id: 'bandit_archer',  index: 1, name: 'Bandit Archer',  tier: 1 },
          { id: 'bandit_captain', index: 2, name: 'Bandit Captain', tier: 2 }
        ] },
      { label: 'Undead',
        enemies: [
          { id: 'skeleton',       index: 3, name: 'Skeleton',       tier: 1 },
          { id: 'wight',          index: 4, name: 'Wight',          tier: 3 }
        ] }
    ]
  end

  def self.enemy_templates
    enemy_groups.flat_map { |g| g[:enemies] }
  end

  # --- Combat --------------------------------------------------------------

  def self.combat_state
    { 'round' => 4, 'active_effects' => [], 'current_turn' => 'pc-3',
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
      ] }
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
  # All notes-page content lives here. Each kind (journal, characters,
  # images, maps) is its own array but they share the same flag set:
  #   public — false hides the entry from non-DM viewers
  #   chapter — filters with the chapter pills on /notes
  #   active — flags the entry as part of the current scene; /scene
  #     renders only entries where active is true.

  def self.notes
    [
      { 'id' => 1, 'owner_id' => 0, 'chapter' => 1, 'type' => 'chapter_title',
        'title' => 'The Road to Crimson', 'note' => '', 'public' => true, 'active' => false },
      { 'id' => 2, 'owner_id' => 0, 'chapter' => 1, 'public' => true, 'active' => false,
        'note' => "The party meets at the Weeping Stag. A courier delivers a sealed writ from Lord Halric." },
      { 'id' => 3, 'owner_id' => 0, 'chapter' => 2, 'public' => false, 'active' => true,
        'note' => "Secret: the steward is working with the bandits. He knows the party's route." },
      { 'id' => 4, 'owner_id' => 1, 'chapter' => 2, 'public' => true, 'active' => true,
        'note' => "Ash's personal log: the song keeps coming back to me in dreams." }
    ]
  end

  def self.characters_of_interest
    [
      { 'id' => 1, 'name' => 'Lord Halric',         'role' => 'Patron',
        'last_seen' => 'Crimson Hold',         'chapter' => 1, 'public' => true,  'active' => false,
        'note' => 'Sent the sealed writ that started the journey.' },
      { 'id' => 2, 'name' => 'Steward Voss',        'role' => 'Hostile (secret)',
        'last_seen' => 'Beneath the Mountain', 'chapter' => 2, 'public' => false, 'active' => true,
        'note' => 'Working with the bandits. Knows the party route.' },
      { 'id' => 3, 'name' => 'Mara the Innkeep',    'role' => 'Ally',
        'last_seen' => 'Weeping Stag',         'chapter' => 1, 'public' => true,  'active' => false,
        'note' => 'Knows local rumors. Takes coppers for hot tea.' },
      { 'id' => 4, 'name' => 'The Hooded Stranger', 'role' => 'Unknown',
        'last_seen' => 'Forest road',          'chapter' => 1, 'public' => true,  'active' => true,
        'note' => 'Watched the party leave. Did not approach.' }
    ]
  end

  def self.note_images
    [
      { 'id' => 1, 'kind' => 'document', 'chapter' => 1, 'public' => true,  'active' => false,
        'caption' => 'The sealed writ delivered to the party in the Weeping Stag.' },
      { 'id' => 2, 'kind' => 'map',      'chapter' => 2, 'public' => false, 'active' => true,
        'caption' => 'Bandit ambush map (DM only).' },
      { 'id' => 3, 'kind' => 'portrait', 'chapter' => 1, 'public' => true,  'active' => false,
        'caption' => 'Mara, the innkeep at the Weeping Stag.' },
      { 'id' => 4, 'kind' => 'location', 'chapter' => 2, 'public' => true,  'active' => true,
        'caption' => 'Cave entrance under the mountain.' }
    ]
  end

  # Each map entry can carry an `objects` array of tokens placed on
  # the map. Object coordinates use viewBox units. The arrow store
  # and other mutable map state live in NotesState (see
  # lib/notes_state.rb), not here, since they change at the table.
  # Map sizes are in *squares*; the partial scales up by
  # NotesState::SQUARE_PX (currently 50) for the SVG viewBox.
  def self.note_maps
    [
      { 'id' => 1, 'chapter' => 1, 'public' => true,  'active' => false,
        'label' => 'Crimson Hold',
        'caption' => 'Crimson Hold, ground floor.',
        'width_squares' => 8, 'height_squares' => 5,
        'objects' => [
          { 'id' => 'cb_door',     'kind' => 'door',     'x' =>  60, 'y' => 200, 'label' => 'Front door' },
          { 'id' => 'cb_throne',   'kind' => 'scenery',  'x' => 320, 'y' =>  60, 'label' => 'Throne' },
          { 'id' => 'cb_treasure', 'kind' => 'treasure', 'x' => 280, 'y' => 130, 'label' => 'Vault' }
        ] },
      { 'id' => 2, 'chapter' => 2, 'public' => true,  'active' => true,
        'label' => 'Forest road ambush',
        'caption' => 'Forest road south of the wagon. Treeline curves on the east; the wagon wreck blocks the road.',
        'width_squares' => 8, 'height_squares' => 5,
        'objects' => [
          { 'id' => 'pc_ash',  'kind' => 'pc',      'x' =>  60, 'y' =>  80, 'label' => 'Ash' },
          { 'id' => 'pc_bryn', 'kind' => 'pc',      'x' =>  80, 'y' =>  60, 'label' => 'Bryn' },
          { 'id' => 'wagon',   'kind' => 'scenery', 'x' => 200, 'y' => 112, 'label' => 'Wagon' },
          { 'id' => 'pit',     'kind' => 'trap',    'x' => 250, 'y' => 200, 'label' => 'Pit' },
          { 'id' => 'mob_1',   'kind' => 'enemy',   'x' => 320, 'y' => 180, 'label' => 'Bandit 1' },
          { 'id' => 'mob_2',   'kind' => 'enemy',   'x' => 340, 'y' => 200, 'label' => 'Bandit 2' },
          { 'id' => 'mob_3',   'kind' => 'enemy',   'x' => 350, 'y' => 170, 'label' => 'Bandit 3' }
        ] },
      { 'id' => 3, 'chapter' => 2, 'public' => false, 'active' => false,
        'label' => 'Ambush overlay',
        'caption' => 'DM-only overlay: bandit positions before the ambush is sprung.',
        'width_squares' => 8, 'height_squares' => 5,
        'objects' => [
          { 'id' => 'lookout',  'kind' => 'enemy',  'x' => 220, 'y' =>  40, 'label' => 'Lookout' },
          { 'id' => 'archer_1', 'kind' => 'enemy',  'x' => 300, 'y' =>  90, 'label' => 'Archer' },
          { 'id' => 'archer_2', 'kind' => 'enemy',  'x' => 360, 'y' => 130, 'label' => 'Archer' },
          { 'id' => 'fire',     'kind' => 'hazard', 'x' => 200, 'y' => 200, 'label' => 'Campfire' }
        ] }
    ]
  end

  def self.note_map_by_id(id)
    note_maps.find { |m| m['id'].to_i == id.to_i }
  end

  # --- Spells --------------------------------------------------------------

  def self.spell_schools
    { 'evocation'     => 'Raw magical force shaped into damage or barriers.',
      'illusion'      => 'Deceptions of the senses and the mind.',
      'transmutation' => 'Reshaping matter, form, and state.',
      'divination'    => 'Knowledge pulled from distance, memory, or fate.' }
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
    { 'equipment'  => %w[weapon armor shield],
      'item'       => %w[potion scroll misc],
      'tattoo'     => %w[shoulder arm chest],
      'ammunition' => %w[arrow bolt sling] }
  end

  # --- Attack stub ---------------------------------------------------------
  # The attack_stub is rule-ignorant: callers hand it the attacker's
  # weapons, the candidate targets, the concrete defense options for each
  # target (one per equipped weapon for parry, one per shield for block,
  # etc.), and the lists of ally / target reactions. Everything below is
  # placeholder data shaped the way the stub expects, so the UI flow can
  # be exercised end-to-end before any real rule engine is wired up.
  #
  # The defenses catalog (`data/defenses.yaml`) defines the abstract kinds
  # — `defense_options` is responsible for expanding `parry` into
  # one option per equipped weapon, `block` into one per shield, etc.

  def self.defenses_catalog
    @defenses_catalog ||= YAML.load_file(File.join(__dir__, '..', 'data', 'defenses.yaml'))['defenses']
  end

  def self.reactions_catalog
    @reactions_catalog ||= YAML.load_file(File.join(__dir__, '..', 'data', 'reactions.yaml'))['reactions']
  end

  def self.attacker_sample
    {
      'name'  => 'Bryn Ironvein',
      'skill' => { 'name' => 'Attack', 'bonus' => 2, 'dice' => 8, 'ranks' => 3 },
      'weapons' => [
        { 'key' => 'longsword',
          'name' => 'Longsword',
          'min_dice' => 2, 'max_dice' => 6,
          'attack_bonus' => 2, 'damage' => 4, 'threshold' => 8, 'bleed' => 1, 'speed' => 2,
          'afflictions' => [
            { 'key' => 'bleed', 'label' => 'Bleed', 'amount' => 1 }
          ] },
        { 'key' => 'handaxe',
          'name' => 'Handaxe',
          'min_dice' => 2, 'max_dice' => 5,
          'attack_bonus' => 1, 'damage' => 3, 'threshold' => 6, 'bleed' => 1, 'speed' => 1,
          'afflictions' => [
            { 'key' => 'bleed', 'label' => 'Bleed', 'amount' => 1 }
          ] }
      ]
    }
  end

  def self.target_samples
    [
      { 'key' => 'mob-1', 'name' => 'Bandit Thug',   'incapacitated' => false,
        'defenses'  => defense_options(:thug),
        'reactions' => reaction_options(:thug) },
      { 'key' => 'mob-2', 'name' => 'Bandit Captain','incapacitated' => false,
        'defenses'  => defense_options(:captain),
        'reactions' => reaction_options(:captain) },
      { 'key' => 'mob-3', 'name' => 'Skeleton',      'incapacitated' => true,
        'defenses'  => [defense_option('nothing')],
        'reactions' => reaction_options(:skeleton) }
    ]
  end

  # Allies who can take a reaction *during* this attack -- spend dice to
  # roll a defensive check on the target's behalf, etc. Bardic
  # Inspiration / Unsettling Words are not in here -- they are luck
  # sources, applied to other rolls, and live in luck_sources.
  def self.ally_reactions
    [
      { 'key'   => 'lira-shield-of-faith',
        'label' => 'Lira — Shield of Faith',
        'min_dice' => 2, 'max_dice' => 4,
        'skill'  => { 'name' => 'Healing', 'bonus' => 2, 'dice' => 4, 'ranks' => 2 },
        'cost'   => 'no mana (concentration)',
        'tn_label' => 'Block TN' }
    ]
  end

  # Luck pools the DM can draw on after each roll-granting choice. The
  # stub asks for points-to-spend from each pool after attack dice,
  # defense dice, and per-ally roll selections; the chosen amounts ride
  # along into the multi-roll display.
  def self.luck_sources
    [
      { 'key' => 'bardic_inspiration', 'label' => 'Bardic Inspiration',
        'kind' => 'bonus',  'remaining' => 4,
        'description' => 'Reroll N lowest dice on the chosen roll.' },
      { 'key' => 'unsettling_words',   'label' => 'Unsettling Words',
        'kind' => 'penalty', 'remaining' => 3,
        'description' => 'Reroll N highest dice on the chosen roll.' }
    ]
  end

  # Build the `defenses` array a target ships to the stub. A real data
  # layer will derive this from the target's equipped items; here we
  # synthesize representative loadouts per archetype.
  def self.defense_options(archetype)
    case archetype
    when :thug
      [
        defense_option('nothing'),
        defense_option('dodge', skill: { 'bonus' => 1, 'dice' => 5 }, min_dice: 2, max_dice: 5),
        defense_option('parry', label_suffix: 'Club',
                       implement: { 'name' => 'Club', 'attack_bonus' => 1, 'speed' => 1 },
                       skill: { 'bonus' => 1, 'dice' => 4 }, min_dice: 2, max_dice: 4)
      ]
    when :captain
      [
        defense_option('nothing'),
        defense_option('dodge', skill: { 'bonus' => 2, 'dice' => 6 }, min_dice: 2, max_dice: 6),
        defense_option('parry', label_suffix: 'Axe',
                       implement: { 'name' => 'Axe', 'attack_bonus' => 2, 'speed' => 2 },
                       skill: { 'bonus' => 2, 'dice' => 5 }, min_dice: 2, max_dice: 5),
        defense_option('parry', label_suffix: 'Dagger',
                       implement: { 'name' => 'Dagger', 'attack_bonus' => 1, 'speed' => 1 },
                       skill: { 'bonus' => 1, 'dice' => 4 }, min_dice: 2, max_dice: 4),
        defense_option('block', label_suffix: 'Buckler',
                       implement: { 'name' => 'Buckler', 'attack_bonus' => 1, 'speed' => 1 },
                       skill: { 'bonus' => 1, 'dice' => 4 }, min_dice: 2, max_dice: 4)
      ]
    else
      [defense_option('nothing')]
    end
  end

  # Build the `reactions` array a target ships to the stub. Same idea
  # as defense_options: a real data layer will derive the per-target
  # list from the target's abilities; here we synthesize per-archetype
  # samples that the test page can exercise.
  def self.reaction_options(archetype)
    case archetype
    when :captain
      [reaction_option('danger_sense'), reaction_option('primal_tenacity')]
    else
      []
    end
  end

  def self.reaction_option(kind)
    catalog = reactions_catalog.fetch(kind)
    {
      'kind'        => kind,
      'key'         => kind,
      'label'       => catalog['label'],
      'description' => catalog['description'],
      'cost'        => catalog['cost']
    }
  end

  def self.defense_option(kind, label_suffix: nil, implement: nil, skill: nil, min_dice: 0, max_dice: 0)
    catalog = defenses_catalog.fetch(kind)
    label = label_suffix ? "#{catalog['label']} with #{label_suffix}" : catalog['label']
    {
      'kind'        => kind,
      'key'         => label_suffix ? "#{kind}-#{label_suffix.downcase.tr(' ', '-')}" : kind,
      'label'       => label,
      'description' => catalog['description'],
      'uses_dice'   => catalog['uses_dice'],
      'implement'   => implement,
      'skill'       => skill,
      'min_dice'    => min_dice,
      'max_dice'    => max_dice
    }
  end

  # --- Scene ---------------------------------------------------------------
  # The scene itself is just a label + description. Everything else
  # the page renders comes from the active-flagged entries in the
  # notes arrays above.

  def self.scene
    { 'title' => 'The Bandit Ambush',
      'description' => 'Crossbows click from the treeline. Smoke rises off the wrecked wagon.',
      'show_initiative' => true }
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
