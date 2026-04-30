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
               hp: 22, hp_max: 26, mana: 10, mana_max: 12, abilities: %w[wild_shape spore_cloud]),
      build_pc(id: 7, name: 'Thora Stoneveil', race: 'Hill Dwarf', klass: 'Cleric', tier: 2,
               hp: 24, hp_max: 30, mana: 8, mana_max: 14, abilities: %w[channel_divinity turn_undead]),
      build_pc(id: 8, name: 'Garroth Vask', race: 'Human', klass: 'Barbarian', tier: 2,
               hp: 28, hp_max: 32, mana: 0, mana_max: 0, abilities: %w[rage fast_movement]),
      build_pc(id: 9, name: 'Veyl Aetheris', race: 'High Elf', klass: 'Arcane Trickster', tier: 2,
               hp: 18, hp_max: 26, mana: 9, mana_max: 13, abilities: %w[sneak_attack mage_legerdemain]),
      build_pc(id: 10, name: 'Pippin Hoofstride', race: 'Satyr', klass: 'Bard', tier: 2,
               hp: 22, hp_max: 28, mana: 10, mana_max: 12, abilities: %w[bardic_inspiration magical_performance])
    ]
  end

  def self.pcs
    characters.select { |c| c['group'] == 'PC' }
  end

  def self.character_by_id(id)
    characters.find { |c| c['id'].to_i == id.to_i }
  end

  # Character class instances + per-character dummy state for the
  # /character preview page. The Character itself only stores static
  # data (id, name, player, race, base attributes); everything else
  # — current HP, mana, saturation, conditions, weapons, spells,
  # rituals, abilities, items — lives in the per-entry `:dummy`
  # hash and is merged onto character_sheet_dummy_defaults when the
  # stub renders.
  def self.pc_objects
    @pc_objects ||= [
      { character: Character.new(
          id: 1, name: 'Ash Windmere', player: 'Sam',
          race: dummy_race('human', character_level: 3),
          tier: 3,
          attributes: { str: 10, dex: 14, con: 12, int: 13, wis: 16, cha: 18 },
          advancement: dummy_advancement(tier: 3, class_levels: { 'bard' => 3 })),
        dummy: {
          klass: 'Bard 3', bab: 4,
          current_hp: 22,
          current_mana: 9,
          mana_saturation: 3, mana_saturation_max: 7,
          initiative: 4, perception_bonus: 5,
          weapons: [
            { 'name' => 'Rapier',     'speed' => 2, 'arm_speed' => '',
              'dice' => 4, 'attack_bonus' => 3, 'damage' => '+2',
              'bleed' => 1, 'threshold' => 8 },
            { 'name' => 'Hand Crossbow', 'speed' => 3, 'arm_speed' => '',
              'dice' => 3, 'attack_bonus' => 4, 'damage' => '+1',
              'bleed' => 0, 'threshold' => 7 }
          ],
          abilities: [
            { 'name' => 'Bardic Inspiration',
              'description' => 'Grant a luck bonus to an ally’s next check.' },
            { 'name' => 'Unsettling Words',
              'description' => 'Impose a luck penalty on an enemy’s next check.' }
          ],
          spell_list: [
            %w[Mending],
            ['Charm Person', 'Healing Word'],
            ['Suggestion']
          ],
          ritual_list: [
            [],
            ['Comprehend Languages', 'Detect Magic']
          ],
          equipped:  ['Rapier', 'Hand Crossbow', 'Studded Leather'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 2 }],
          other_items: [{ 'name' => 'Lute' }, { 'name' => 'Rations (5)' }, { 'name' => 'Bedroll' }],
          defined_items: [
            { 'name' => 'Cloak of Resistance +1',
              'description' => 'Adds +1 to all saves; does not stack with other resistance items.' },
            { 'name' => 'Lute of the Wandering Bard',
              'description' => 'Once per scene, grant Bardic Inspiration without spending the action.' }
          ]
        } },

      { character: Character.new(
          id: 2, name: 'Bryn Ironvein', player: 'Mira',
          race: dummy_race('dwarf', character_level: 3),
          tier: 3,
          attributes: { str: 18, dex: 10, con: 17, int: 9, wis: 12, cha: 8 },
          advancement: dummy_advancement(tier: 3, class_levels: { 'fighter' => 3 })),
        dummy: {
          klass: 'Fighter 3', bab: 6,
          current_hp: 14,
          moderate_damage: 8, major_damage: 6,
          conditions: { 'bleed' => 1 },
          current_mana: 4,
          initiative: 2, perception_bonus: 2,
          weapons: [
            { 'name' => 'Warhammer', 'speed' => 3, 'arm_speed' => '',
              'dice' => 5, 'attack_bonus' => 5, 'damage' => '+4',
              'bleed' => 0, 'threshold' => 9 },
            { 'name' => 'Tower Shield (bash)', 'speed' => 4, 'arm_speed' => '',
              'dice' => 3, 'attack_bonus' => 4, 'damage' => '+3',
              'bleed' => 0, 'threshold' => 7 }
          ],
          abilities: [
            { 'name' => 'Shield Bash',
              'description' => 'Knock a target prone on a successful shield attack.' },
            { 'name' => 'Second Wind',
              'description' => 'Once per scene, recover 1d6 + level HP as a free action.' }
          ],
          spell_list: [],
          equipped:  ['Warhammer', 'Tower Shield', 'Chain Mail'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 1 }],
          other_items: [{ 'name' => 'Whetstone' }, { 'name' => 'Rations (5)' }],
          defined_items: []
        } },

      { character: Character.new(
          id: 3, name: 'Lira Duskmoor', player: 'Jordan',
          race: dummy_race('elf', character_level: 3),
          tier: 3,
          attributes: { str: 8, dex: 14, con: 11, int: 20, wis: 16, cha: 12 },
          advancement: dummy_advancement(tier: 3, class_levels: { 'wizard' => 3 }),
          ritual_list: [
            ['Light'],
            ['Comprehend Languages', 'Detect Magic', 'Identify'],
            ['Locate Object']
          ]),
        dummy: {
          klass: 'Wizard 3', bab: 2,
          current_hp: 18,
          current_mana: 16,
          mana_saturation: 5, mana_saturation_max: 9,
          conditions: { 'poison' => 2 },
          initiative: 3, perception_bonus: 3,
          weapons: [
            { 'name' => 'Quarterstaff', 'speed' => 3, 'arm_speed' => '',
              'dice' => 2, 'attack_bonus' => 1, 'damage' => '+0',
              'bleed' => 0, 'threshold' => 7 }
          ],
          abilities: [
            { 'name' => 'Arcane Focus',
              'description' => 'Spend mana to add insight dice to a focus check.' },
            { 'name' => 'Ritual Caster',
              'description' => 'Cast spells from the ritual list without preparation.' }
          ],
          spell_list: [
            ['Mage Hand', 'Minor Illusion', 'Prestidigitation'],
            ['Magic Missile', 'Shield', 'Mage Armor'],
            ['Misty Step', 'Scorching Ray'],
            ['Counterspell']
          ],
          equipped:  ['Quarterstaff', 'Spellbook', 'Robes'],
          consumable: [{ 'name' => 'Antitoxin', 'quantity' => 1 }],
          other_items: [{ 'name' => 'Component Pouch' }, { 'name' => 'Ink and Quill' }],
          defined_items: [
            { 'name' => 'Spellbook',
              'description' => 'Holds every spell Lira has researched. Required for daily preparation.' }
          ]
        } },

      { character: Character.new(
          id: 4, name: 'Kass Thorne', player: 'Pat',
          race: dummy_race('halfling', character_level: 3),
          tier: 3,
          attributes: { str: 10, dex: 19, con: 13, int: 14, wis: 12, cha: 11 },
          advancement: dummy_advancement(tier: 3, class_levels: { 'rogue' => 3 })),
        dummy: {
          klass: 'Rogue 3', bab: 4,
          current_hp: 20,
          current_mana: 5,
          initiative: 5, perception_bonus: 4,
          weapons: [
            { 'name' => 'Shortsword', 'speed' => 1, 'arm_speed' => '',
              'dice' => 4, 'attack_bonus' => 5, 'damage' => '+2',
              'bleed' => 1, 'threshold' => 7 },
            { 'name' => 'Dagger',     'speed' => 1, 'arm_speed' => '',
              'dice' => 3, 'attack_bonus' => 5, 'damage' => '+1',
              'bleed' => 1, 'threshold' => 6 }
          ],
          abilities: [
            { 'name' => 'Sneak Attack',
              'description' => 'Add bonus damage when an attacker has advantage on the target.' },
            { 'name' => 'Evasion',
              'description' => 'On a successful Dexterity save, take no damage from area effects.' }
          ],
          spell_list: [],
          equipped:  ['Shortsword', 'Dagger', 'Leather Armor'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 3 }],
          other_items: [{ 'name' => 'Thieves’ Tools' }, { 'name' => 'Rope (50 ft)' }],
          defined_items: []
        } },

      { character: Character.new(
          id: 5, name: 'Rowan Vale', player: 'Riley',
          race: dummy_race('half_elf', character_level: 3),
          tier: 3,
          attributes: { str: 14, dex: 17, con: 13, int: 11, wis: 16, cha: 10 },
          advancement: dummy_advancement(tier: 3, class_levels: { 'ranger' => 3 })),
        dummy: {
          klass: 'Ranger 3', bab: 4,
          current_hp: 26,
          current_mana: 6,
          initiative: 4, perception_bonus: 5,
          weapons: [
            { 'name' => 'Longbow',   'speed' => 3, 'arm_speed' => '',
              'dice' => 4, 'attack_bonus' => 5, 'damage' => '+3',
              'bleed' => 0, 'threshold' => 8 },
            { 'name' => 'Hand Axe',  'speed' => 2, 'arm_speed' => '',
              'dice' => 3, 'attack_bonus' => 4, 'damage' => '+2',
              'bleed' => 0, 'threshold' => 7 }
          ],
          abilities: [
            { 'name' => "Hunter’s Mark",
              'description' => 'Mark a target; gain bonus damage and tracking against it.' },
            { 'name' => 'Quick Draw',
              'description' => 'Draw a weapon as a free action once per turn.' }
          ],
          spell_list: [[], ['Hunter’s Mark', 'Cure Wounds']],
          equipped:  ['Longbow', 'Hand Axe', 'Studded Leather'],
          consumable: [],
          other_items: [{ 'name' => 'Quiver (20 arrows)' }, { 'name' => 'Trail Rations' }],
          defined_items: []
        } },

      { character: Character.new(
          id: 6, name: 'Ember Blackoak', player: 'Casey',
          race: dummy_race('half_orc', character_level: 3),
          tier: 3,
          attributes: { str: 13, dex: 11, con: 15, int: 10, wis: 18, cha: 9 },
          advancement: dummy_advancement(tier: 3, class_levels: { 'druid' => 3 }),
          ritual_list: [['Light']]),
        dummy: {
          klass: 'Druid 3', bab: 3,
          current_hp: 22,
          current_mana: 10,
          mana_saturation: 1, mana_saturation_max: 6,
          initiative: 4, perception_bonus: 4,
          weapons: [
            { 'name' => 'Scimitar', 'speed' => 2, 'arm_speed' => '',
              'dice' => 3, 'attack_bonus' => 3, 'damage' => '+2',
              'bleed' => 1, 'threshold' => 7 }
          ],
          abilities: [
            { 'name' => 'Wild Shape',
              'description' => 'Assume the form of a beast appropriate to your tier.' },
            { 'name' => 'Spore Cloud',
              'description' => 'Release a cloud that imposes Wisdom saves on adjacent foes.' }
          ],
          spell_list: [['Druidcraft'], ['Entangle', 'Cure Wounds']],
          equipped:  ['Scimitar', 'Hide Armor'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 2 }],
          other_items: [{ 'name' => 'Druidic Focus' }, { 'name' => 'Herbalism Kit' }],
          defined_items: []
        } },

      { character: Character.new(
          id: 7, name: 'Thora Stoneveil', player: 'Avery',
          race: dummy_race('hill_dwarf', character_level: 4),
          tier: 2,
          attributes: { str: 10, dex: 10, con: 13, int: 12, wis: 12, cha: 9 },
          advancement: dummy_advancement(
            tier: 2,
            class_levels: { 'cleric' => 4 },
            picks: %i[wis dex]
          )),
        dummy: {
          klass: 'Cleric 4', bab: 3,
          current_hp: 24,
          current_mana: 8,
          initiative: 3, perception_bonus: 3,
          weapons: [
            { 'name' => 'Mace',     'speed' => 3, 'arm_speed' => '',
              'dice' => 3, 'attack_bonus' => 3, 'damage' => '+2',
              'bleed' => 0, 'threshold' => 8 }
          ],
          skills: [
            { 'name' => 'Healing',      'ranks' => 6, 'dice' => 8, 'bonus' => 2 },
            { 'name' => 'Sense Motive', 'ranks' => 6, 'dice' => 8, 'bonus' => 2 },
            { 'name' => 'Arcana',       'ranks' => 6, 'dice' => 8, 'bonus' => 2 },
            { 'name' => 'Survival',     'ranks' => 4, 'dice' => 6, 'bonus' => 2 },
            { 'name' => 'Intimidate',   'ranks' => 6, 'dice' => 8, 'bonus' => 0 },
            { 'name' => 'Perception',   'ranks' => 6, 'dice' => 8, 'bonus' => 2 }
          ],
          abilities: [
            { 'name' => 'Channel Divinity',
              'description' => 'Spend mana to invoke a domain effect.' },
            { 'name' => 'Turn Undead',
              'description' => 'Drive undead within 30 ft to flee for 1 minute.' }
          ],
          spell_list: [
            ['Stabilize', 'Sacred Flame', 'Magic Vestments'],
            ['Cure Lesser Wounds', 'Healing Word', 'Command', 'Lesser Ward', 'Divine Favor', 'Shield of Faith'],
            ['Spiritual Weapon', 'Silence', 'Cure Simple Wounds', 'Standard Ward', 'Standard Surgery']
          ],
          equipped:  ['Mace', 'Holy Symbol', 'Chain Mail'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 3 }],
          other_items: [{ 'name' => 'Prayer Book' }, { 'name' => 'Rations (5)' }],
          defined_items: []
        } },

      { character: Character.new(
          id: 8, name: 'Garroth Vask', player: 'Drew',
          race: dummy_race('human', character_level: 4),
          tier: 2,
          attributes: { str: 14, dex: 12, con: 14, int: 9, wis: 10, cha: 7 },
          advancement: dummy_advancement(
            tier: 2,
            class_levels: { 'barbarian' => 4 },
            picks: %i[str dex]
          )),
        dummy: {
          klass: 'Barbarian 4', bab: 4,
          current_hp: 28,
          current_mana: 0,
          initiative: 2, perception_bonus: 2,
          weapons: [
            { 'name' => 'Greataxe', 'speed' => 4, 'arm_speed' => '',
              'dice' => 4, 'attack_bonus' => 5, 'damage' => '+5',
              'bleed' => 1, 'threshold' => 9 }
          ],
          skills: [
            { 'name' => 'Athletics',    'ranks' => 6, 'dice' => 9, 'bonus' => 4 },
            { 'name' => 'Survival',     'ranks' => 6, 'dice' => 8, 'bonus' => 1 },
            { 'name' => 'Sense Motive', 'ranks' => 6, 'dice' => 8, 'bonus' => 1 },
            { 'name' => 'Stealth',      'ranks' => 6, 'dice' => 9, 'bonus' => 3 }
          ],
          abilities: [
            { 'name' => 'Rage',
              'description' => 'Enter rage for bonus damage and damage reduction.' },
            { 'name' => 'Fast Movement',
              'description' => '+10 ft speed when not wearing heavy armor.' }
          ],
          spell_list: [],
          equipped:  ['Greataxe', 'Hide Armor'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 2 }],
          other_items: [{ 'name' => 'Trail Rations' }, { 'name' => 'Bedroll' }],
          defined_items: []
        } },

      { character: Character.new(
          id: 9, name: 'Veyl Aetheris', player: 'Quinn',
          race: dummy_race('high_elf', character_level: 4),
          tier: 2,
          attributes: { str: 7, dex: 13, con: 11, int: 11, wis: 11, cha: 11 },
          advancement: dummy_advancement(
            tier: 2,
            class_levels: { 'arcane_trickster' => 4 },
            picks: %i[dex cha]
          ),
          ritual_list: [
            ['Guidance', 'Resistance', 'Acid Splash', 'Drench', 'Light', 'Spark', 'Mending'],
            ['Alarm', 'Endure Elements', 'Mount', 'Charm Person', 'Silent Image', 'Ant Haul', 'Disguise Self']
          ]),
        dummy: {
          klass: 'Arcane Trickster 4', bab: 3,
          current_hp: 18,
          current_mana: 9,
          initiative: 3, perception_bonus: 3,
          weapons: [
            { 'name' => 'Rapier', 'speed' => 2, 'arm_speed' => '',
              'dice' => 4, 'attack_bonus' => 4, 'damage' => '+2',
              'bleed' => 1, 'threshold' => 8 },
            { 'name' => 'Dagger', 'speed' => 1, 'arm_speed' => '',
              'dice' => 3, 'attack_bonus' => 4, 'damage' => '+1',
              'bleed' => 1, 'threshold' => 6 }
          ],
          skills: [
            { 'name' => 'Arcana',           'ranks' => 6, 'dice' => 8, 'bonus' => 1 },
            { 'name' => 'Stealth',          'ranks' => 6, 'dice' => 9, 'bonus' => 3 },
            { 'name' => 'Larceny',          'ranks' => 6, 'dice' => 9, 'bonus' => 3 },
            { 'name' => 'Sleight of Hand',  'ranks' => 6, 'dice' => 9, 'bonus' => 3 },
            { 'name' => 'Deception',        'ranks' => 6, 'dice' => 8, 'bonus' => 2 },
            { 'name' => 'Persuasion',       'ranks' => 6, 'dice' => 8, 'bonus' => 2 },
            { 'name' => 'Perception',       'ranks' => 6, 'dice' => 8, 'bonus' => 1 },
            { 'name' => 'Game (Chess)',     'ranks' => 4, 'dice' => 6, 'bonus' => 1 }
          ],
          abilities: [
            { 'name' => 'Sneak Attack',
              'description' => 'Add bonus damage when you have advantage on the target.' },
            { 'name' => 'Mage Legerdemain',
              'description' => 'Cast Mage Hand silently and at extreme range.' }
          ],
          spell_list: [
            ['Fire Dart', 'Message', 'Silent Portal', 'Ghost Sound'],
            ['Hideous Laughter', 'Illusion of Calm', 'Auditory Hallucination']
          ],
          equipped:  ['Rapier', 'Dagger', 'Studded Leather'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 2 }],
          other_items: [{ 'name' => 'Thieves’ Tools' }, { 'name' => 'Spellbook' }],
          defined_items: []
        } },

      { character: Character.new(
          id: 10, name: 'Pippin Hoofstride', player: 'Morgan',
          race: dummy_race('satyr', character_level: 4),
          tier: 2,
          attributes: { str: 9, dex: 12, con: 12, int: 10, wis: 11, cha: 12 },
          advancement: dummy_advancement(
            tier: 2,
            class_levels: { 'bard' => 4 },
            picks: %i[dex cha]
          )),
        dummy: {
          klass: 'Bard 4', bab: 3,
          current_hp: 22,
          current_mana: 10,
          initiative: 3, perception_bonus: 2,
          weapons: [
            { 'name' => 'Rapier',     'speed' => 2, 'arm_speed' => '',
              'dice' => 4, 'attack_bonus' => 4, 'damage' => '+2',
              'bleed' => 1, 'threshold' => 8 }
          ],
          skills: [
            { 'name' => 'Perform (Sing)',       'ranks' => 6, 'dice' => 9, 'bonus' => 3 },
            { 'name' => 'Perform (Percussion)', 'ranks' => 6, 'dice' => 9, 'bonus' => 3 },
            { 'name' => 'Animal Handling',      'ranks' => 6, 'dice' => 8, 'bonus' => 2 },
            { 'name' => 'Persuasion',           'ranks' => 6, 'dice' => 9, 'bonus' => 3 },
            { 'name' => 'Evocation',            'ranks' => 6, 'dice' => 8, 'bonus' => 1 },
            { 'name' => 'Perception',           'ranks' => 6, 'dice' => 8, 'bonus' => 2 },
            { 'name' => 'Nature',               'ranks' => 6, 'dice' => 8, 'bonus' => 1 }
          ],
          abilities: [
            { 'name' => 'Bardic Inspiration',
              'description' => 'Grant a luck bonus to an ally’s next check.' },
            { 'name' => 'Magical Performance',
              'description' => 'Spend mana to layer subtle compulsions over a performance.' }
          ],
          spell_list: [
            ['Heal Petty Wounds', 'Minor Detect Magic', 'Ghost Sound', 'Friends', 'Sift', 'Vacuous Vessel', 'Vicious Mockery'],
            ['Biting Words', 'Ears of the City', 'Silent Image', 'Timely Inspiration']
          ],
          equipped:  ['Rapier', 'Lyre', 'Leather Armor'],
          consumable: [{ 'name' => 'Healing Draught', 'quantity' => 2 }],
          other_items: [{ 'name' => 'Lyre' }, { 'name' => 'Wineskin' }],
          defined_items: []
        } }
    ]
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
  # Shape mirrors how this will be stored on disk: each turn carries a
  # foreign key (`char_id`) into either characters (integer id, PCs)
  # or enemy_templates (string id, mobs). Display name is resolved on
  # read via name_for; never duplicated in storage.

  def self.combat_state
    { 'round' => 4, 'active_effects' => [], 'current_turn' => 'pc-3',
      'turns' => [
        { 'combat_id' => 'pc-3',  'char_id' => 3,              'initiative' => 'X97',
          'hp' => 18, 'hp_max' => 22,
          'minor_damage' => 4, 'moderate_damage' => 0, 'major_damage' => 0,
          'combat_pool' => 5, 'combat_pool_max' => 5, 'shock' => 0, 'pain' => 0,
          'conditions' => [], 'group' => 'PC' },

        { 'combat_id' => 'pc-1',  'char_id' => 1,              'initiative' => 'X87',
          'hp' => 22, 'hp_max' => 28,
          'minor_damage' => 6, 'moderate_damage' => 0, 'major_damage' => 0,
          'combat_pool' => 4, 'combat_pool_max' => 6, 'shock' => 1, 'pain' => 0,
          'conditions' => [{ 'name' => 'bleed', 'value' => 2 }], 'group' => 'PC' },

        { 'combat_id' => 'pc-2',  'char_id' => 2,              'initiative' => '742',
          'hp' => 24, 'hp_max' => 36,
          'minor_damage' => 4, 'moderate_damage' => 8, 'major_damage' => 0,
          'combat_pool' => 3, 'combat_pool_max' => 7, 'shock' => 0, 'pain' => 2,
          'conditions' => [{ 'name' => 'poison', 'value' => 1 }], 'group' => 'PC' },

        { 'combat_id' => 'mob-1', 'char_id' => 'bandit_thug',  'initiative' => 'X4',
          'hp' => 14, 'hp_max' => 14,
          'minor_damage' => 0, 'moderate_damage' => 0, 'major_damage' => 0,
          'combat_pool' => 3, 'combat_pool_max' => 3, 'shock' => 0, 'pain' => 0,
          'conditions' => [], 'group' => 'Enemy' },

        { 'combat_id' => 'mob-2', 'char_id' => 'bandit_thug',  'initiative' => '951',
          'hp' => 5, 'hp_max' => 14,
          'minor_damage' => 2, 'moderate_damage' => 4, 'major_damage' => 3,
          'combat_pool' => 1, 'combat_pool_max' => 3, 'shock' => 2, 'pain' => 1,
          'conditions' => [{ 'name' => 'bleed', 'value' => 1 }, { 'name' => 'major_damage', 'value' => 1 }], 'group' => 'Enemy' },

        { 'combat_id' => 'mob-3', 'char_id' => 'bandit_archer','initiative' => '8',
          'hp' => 0, 'hp_max' => 10,
          'minor_damage' => 2, 'moderate_damage' => 4, 'major_damage' => 4,
          'combat_pool' => 0, 'combat_pool_max' => 3, 'shock' => 0, 'pain' => 0,
          'conditions' => [{ 'name' => 'major_damage', 'value' => 1 }], 'group' => 'Enemy' }
      ] }
  end

  # Resolve a display name for a char_id. Integer ids map to PC
  # entries; string ids map to enemy templates. Unknown ids fall back
  # to the id itself so the UI never blanks out on bad data.
  def self.name_for(char_id)
    if char_id.is_a?(Integer)
      character_by_id(char_id)&.dig('name') || char_id.to_s
    else
      enemy_templates.find { |e| e[:id].to_s == char_id.to_s }&.dig(:name) || char_id.to_s
    end
  end

  # Initiative track sorted high-to-low. Sort key is the X-bearing
  # initiative string compared as a sequence of dice values (X = 10,
  # then digits left-to-right). Returned turns are enriched with the
  # display name resolved via name_for so the view layer doesn't have
  # to know how the lookup works.
  def self.initiative_turns
    combat_state['turns']
      .sort_by { |t| initiative_sort_key(t['initiative']) }
      .map    { |t| t.merge('name' => name_for(t['char_id'])) }
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
      { 'id' => 2, 'owner_id' => 0, 'chapter' => 1, 'type' => 'note', 'public' => true, 'active' => false,
        'note' => "The party meets at the Weeping Stag. A courier delivers a sealed writ from Lord Halric." },
      { 'id' => 3, 'owner_id' => 0, 'chapter' => 2, 'type' => 'note', 'public' => false, 'active' => true,
        'note' => "Secret: the steward is working with the bandits. He knows the party's route." },
      { 'id' => 4, 'owner_id' => 1, 'chapter' => 2, 'type' => 'note', 'public' => true, 'active' => true,
        'note' => "Ash's personal log: the song keeps coming back to me in dreams." },

      # ----- Chapter 3 (Court of Ash) -----
      { 'id' => 5, 'owner_id' => 0, 'chapter' => 3, 'type' => 'chapter_title',
        'title' => 'Court of Ash', 'note' => '', 'public' => true, 'active' => false },
      { 'id' => 6, 'owner_id' => 0, 'chapter' => 3, 'type' => 'note',
        'title' => 'Arrival at the Ashen Gate', 'public' => true, 'active' => false,
        'note' => "The road opens onto a basalt plaza. Ash falls like snow even though no fire is in sight; the gates of the Court stand open and unguarded." },
      { 'id' => 7, 'owner_id' => 0, 'chapter' => 3, 'type' => 'note',
        'title' => 'The Coronation Bargain', 'public' => false, 'active' => false,
        'note' => "DM only: the Ash King will offer Ash Windmere a crown, but the price is the song from her dreams. If she gives it up, the bardic line is broken for a generation." },
      { 'id' => 8, 'owner_id' => 0, 'chapter' => 3, 'type' => 'note',
        'title' => 'Court Etiquette', 'public' => true, 'active' => false,
        'note' => "Speak only when addressed by name. Bow to the Throne, never to a courtier. Iron at the hip is permitted; iron drawn is treason." },
      { 'id' => 9, 'owner_id' => 1, 'chapter' => 3, 'type' => 'note',
        'title' => "Ash's personal log", 'public' => true, 'active' => false,
        'note' => "The song is louder here. I think the Court has been waiting for me." },

      # ----- Chapter 3 characters (typed so the combined feed shows them) -----
      { 'id' => 10, 'chapter' => 3, 'type' => 'character', 'tier' => 4,
        'title' => 'The Ash King',         'public' => false, 'active' => false,
        'note' => "Patron and threat. Wears a crown of cooled lava. Rumored to be older than the kingdom of Crimson itself." },
      { 'id' => 11, 'chapter' => 3, 'type' => 'character', 'tier' => 2,
        'title' => 'Cottonballs the Drummer', 'public' => true, 'active' => false,
        'note' => "Satyr court entertainer. His drums set the rhythm of the throne hall; the courtiers move only on his beat." },
      { 'id' => 12, 'chapter' => 3, 'type' => 'character', 'tier' => 3,
        'title' => 'Lysander of the Verge', 'public' => true, 'active' => false,
        'note' => "Half-elven envoy who claims to speak for the Old Wood. Friendly. Probably truthful. Not safe." },
      { 'id' => 13, 'chapter' => 3, 'type' => 'character', 'tier' => 3,
        'title' => 'Olga the Reaver',      'public' => true, 'active' => false,
        'note' => "Sworn champion. The Court keeps her on a leash of geas; she has not lost a duel in seven years." },
      { 'id' => 14, 'chapter' => 3, 'type' => 'character', 'tier' => 2,
        'title' => 'Stumpy of the Forge',  'public' => true, 'active' => false,
        'note' => "Dwarven smith who fled Crimson Hold years ago. Will reshoe the party's gear for the price of a story." },

      # ----- Migrated from the old characters_of_interest array. The
      # combined feed only renders typed entries (note / character),
      # so these have to live alongside the journal notes now. -----
      { 'id' => 15, 'chapter' => 1, 'type' => 'character', 'tier' => 4,
        'title' => 'Lord Halric',          'public' => true,  'active' => false,
        'note' => "Patron. Last seen at Crimson Hold. Sent the sealed writ that started the journey." },
      { 'id' => 16, 'chapter' => 1, 'type' => 'character', 'tier' => 1,
        'title' => 'Mara the Innkeep',     'public' => true,  'active' => false,
        'note' => "Ally. Runs the Weeping Stag. Knows local rumors; takes coppers for hot tea." },
      { 'id' => 17, 'chapter' => 1, 'type' => 'character', 'tier' => 2,
        'title' => 'The Hooded Stranger',  'public' => true,  'active' => true,
        'note' => "Unknown. Last seen on the forest road. Watched the party leave; did not approach." },
      { 'id' => 18, 'chapter' => 2, 'type' => 'character', 'tier' => 3,
        'title' => 'Steward Voss',         'public' => false, 'active' => true,
        'note' => "Hostile (secret). Last seen Beneath the Mountain. Working with the bandits; knows the party route." }
    ]
  end

  # Image entries with a 'path' key render as the real file under
  # public/; entries without a path fall back to the kind-specific
  # SVG placeholder. Kept side by side so the gallery shows both
  # modes for the demo.
  def self.note_images
    [
      { 'id' => 1, 'kind' => 'document', 'chapter' => 1, 'public' => true,  'active' => false,
        'caption' => 'The sealed writ delivered to the party in the Weeping Stag.' },
      { 'id' => 2, 'kind' => 'map',      'chapter' => 2, 'public' => false, 'active' => true,
        'caption' => 'Bandit ambush map (DM only).' },
      { 'id' => 3, 'kind' => 'portrait', 'chapter' => 1, 'public' => true,  'active' => false,
        'caption' => 'Mara, the innkeep at the Weeping Stag.' },
      { 'id' => 4, 'kind' => 'location', 'chapter' => 2, 'public' => true,  'active' => true,
        'caption' => 'Cave entrance under the mountain.' },

      # ----- Chapter 1 / 2 portraits with real images -----
      { 'id' => 5, 'kind' => 'portrait', 'chapter' => 1, 'public' => true,  'active' => false,
        'caption' => 'The hooded stranger on the forest road. Lysander, in better light.',
        'path' => '/images/Lysander.webp' },
      { 'id' => 6, 'kind' => 'portrait', 'chapter' => 2, 'public' => false, 'active' => true,
        'caption' => 'Captured woodcut of the Reaver, from a torn bandit pamphlet (DM only).',
        'path' => '/images/Olga.webp' },

      # ----- Chapter 3 (Court of Ash) -----
      { 'id' => 7, 'kind' => 'portrait', 'chapter' => 3, 'public' => true,  'active' => false,
        'caption' => 'Cottonballs at the throne hall feast.',
        'path' => '/images/Cottonballs.webp' },
      { 'id' => 8, 'kind' => 'portrait', 'chapter' => 3, 'public' => true,  'active' => false,
        'caption' => 'Stumpy the smith, pressing a brand into a ceremonial axe.',
        'path' => '/images/Stumpy.webp' },
      { 'id' => 9, 'kind' => 'document', 'chapter' => 3, 'public' => true,  'active' => false,
        'caption' => 'Decree of the Ash Court — invitation to the coronation.' },
      { 'id' => 10, 'kind' => 'location', 'chapter' => 3, 'public' => true,  'active' => false,
        'caption' => 'The Ashen Gate, seen from the basalt plaza.' },
      { 'id' => 11, 'kind' => 'map',      'chapter' => 3, 'public' => false, 'active' => false,
        'caption' => 'Throne hall floorplan, smuggled from the masons (DM only).' }
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
        ] },

      # ----- Chapter 3 (Court of Ash) -----
      { 'id' => 4, 'chapter' => 3, 'public' => true,  'active' => false,
        'label' => 'Throne Hall of the Court of Ash',
        'caption' => 'The basalt throne hall. Two hearth-lines flank the dais; courtiers stand along the colonnades.',
        'width_squares' => 12, 'height_squares' => 7,
        'objects' => [
          { 'id' => 'ca_throne',   'kind' => 'scenery',  'x' => 525, 'y' =>  75, 'label' => 'Throne of Ash' },
          { 'id' => 'ca_door',     'kind' => 'door',     'x' =>  25, 'y' => 175, 'label' => 'Ashen Gate' },
          { 'id' => 'ca_dais',     'kind' => 'scenery',  'x' => 475, 'y' => 175, 'label' => 'Dais step' },
          { 'id' => 'ca_hearth_1', 'kind' => 'hazard',   'x' => 325, 'y' =>  75, 'label' => 'Hearth-line (north)' },
          { 'id' => 'ca_hearth_2', 'kind' => 'hazard',   'x' => 325, 'y' => 275, 'label' => 'Hearth-line (south)' },
          { 'id' => 'ca_chest',    'kind' => 'treasure', 'x' => 575, 'y' => 275, 'label' => 'Reliquary' },
          { 'id' => 'ca_king',     'kind' => 'npc',      'x' => 525, 'y' => 125, 'label' => 'Ash King' },
          { 'id' => 'ca_champ',    'kind' => 'enemy',    'x' => 425, 'y' => 175, 'label' => 'Olga (champion)' },
          { 'id' => 'ca_drummer',  'kind' => 'npc',      'x' => 425, 'y' =>  75, 'label' => 'Cottonballs' }
        ] },
      { 'id' => 5, 'chapter' => 3, 'public' => false, 'active' => false, 'archived' => true,
        'label' => 'Outer hall (early sketch)',
        'caption' => "DM scratch sketch of the Court's outer hall — replaced by the final throne map. Kept around in case the party finds the back stairs.",
        'width_squares' => 10, 'height_squares' => 6,
        'objects' => [
          { 'id' => 'oh_door_main', 'kind' => 'door',    'x' =>  25, 'y' => 150, 'label' => 'Outer door' },
          { 'id' => 'oh_door_back', 'kind' => 'door',    'x' => 475, 'y' => 150, 'label' => 'Back stairs' },
          { 'id' => 'oh_pillar_1',  'kind' => 'scenery', 'x' => 175, 'y' => 100, 'label' => 'Pillar' },
          { 'id' => 'oh_pillar_2',  'kind' => 'scenery', 'x' => 175, 'y' => 200, 'label' => 'Pillar' },
          { 'id' => 'oh_pillar_3',  'kind' => 'scenery', 'x' => 325, 'y' => 100, 'label' => 'Pillar' },
          { 'id' => 'oh_pillar_4',  'kind' => 'scenery', 'x' => 325, 'y' => 200, 'label' => 'Pillar' },
          { 'id' => 'oh_guard_1',   'kind' => 'enemy',   'x' => 225, 'y' => 150, 'label' => 'Ashen guard' },
          { 'id' => 'oh_guard_2',   'kind' => 'enemy',   'x' => 275, 'y' => 150, 'label' => 'Ashen guard' }
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
  # The defenses catalog defines the abstract kinds —
  # `defense_options` is responsible for expanding `parry` into one
  # option per equipped weapon, `block` into one per shield, etc.
  # The shape mirrors `docs/defenses.yaml.example` and
  # `docs/reactions.yaml.example`; once the real data layer lands
  # those templates become the authoritative source.

  DEFENSES_CATALOG = {
    'nothing' => {
      'label' => 'Nothing',
      'description' => 'Take no defensive action; the attacker rolls flatfooted.',
      'uses_dice' => false,
      'uses_implement' => 'none'
    },
    'dodge' => {
      'label' => 'Dodge',
      'description' => 'Spend dice on a Dexterity-based dodge roll.',
      'uses_dice' => true,
      'uses_implement' => 'none'
    },
    'parry' => {
      'label' => 'Parry',
      'description' => 'Block the attack with a melee weapon. One option per equipped weapon.',
      'uses_dice' => true,
      'uses_implement' => 'weapon'
    },
    'block' => {
      'label' => 'Block',
      'description' => 'Block the attack with a shield. One option per equipped shield.',
      'uses_dice' => true,
      'uses_implement' => 'shield'
    }
  }.freeze

  REACTIONS_CATALOG = {
    'danger_sense' => {
      'label' => 'Danger Sense',
      'description' => 'Damage resilience +4 against this attack.',
      'cost' => '4 mana'
    },
    'primal_tenacity' => {
      'label' => 'Primal Tenacity',
      'description' => 'Damage reduction +4 against this attack.',
      'cost' => '4 mana'
    }
  }.freeze

  def self.defenses_catalog
    DEFENSES_CATALOG
  end

  def self.reactions_catalog
    REACTIONS_CATALOG
  end

  def self.attacker_sample
    {
      'name'  => 'Bryn Ironvein',
      'skill' => { 'name' => 'Attack', 'bonus' => 2, 'dice' => 8, 'ranks' => 3 },
      'combat_pool' => 15, 'combat_pool_max' => 23,
      'weapons' => [
        { 'key' => 'longsword',
          'name' => 'Longsword',
          'min_dice' => 2, 'max_dice' => 8,
          'attack_bonus' => 2, 'damage' => 4, 'threshold' => 8, 'bleed' => 1, 'speed' => 2,
          'afflictions' => [
            { 'key' => 'bleed', 'label' => 'Bleed', 'amount' => 1 }
          ] },
        { 'key' => 'hatchet',
          'name' => 'Hatchet',
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
        'combat_pool' => 9, 'combat_pool_max' => 12,
        'defenses'  => defense_options(:thug),
        'reactions' => reaction_options(:thug) },
      { 'key' => 'mob-2', 'name' => 'Bandit Captain','incapacitated' => false,
        'combat_pool' => 18, 'combat_pool_max' => 20,
        'defenses'  => defense_options(:captain),
        'reactions' => reaction_options(:captain) },
      { 'key' => 'mob-3', 'name' => 'Skeleton',      'incapacitated' => true,
        'combat_pool' => 0, 'combat_pool_max' => 6,
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
        'name'  => 'Lira',
        'label' => 'Shield of Faith',
        'combat_pool' => 5, 'combat_pool_max' => 12,
        'min_dice' => 2, 'max_dice' => 6,
        'skill'  => { 'name' => 'Healing', 'bonus' => 2, 'dice' => 6, 'ranks' => 2 },
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

  # Race + advancement definitions used by the dummy roster.
  # Pulled from docs/*.yaml.example so the dev data exercises the
  # same rules the real configs would. Half-Elf and Half-Orc
  # aren't in the example races file yet; defined inline so
  # existing dummy characters keep their bonuses.
  RACE_DEFINITIONS_PATH         = File.expand_path('../docs/race/race_config.yaml.example',                __dir__)
  ADVANCEMENT_DEFINITIONS_PATH  = File.expand_path('../docs/advancement/advancement_config.yaml.example',  __dir__)

  def self.race_definitions
    @race_definitions ||= Race.load_yaml(RACE_DEFINITIONS_PATH).merge(
      'half_elf' => {
        'name' => 'Half-Elf',
        'speed' => 30,
        'ability_score_adjustments' => { 'cha' => 2 }
      },
      'half_orc' => {
        'name' => 'Half-Orc',
        'speed' => 30,
        'ability_score_adjustments' => { 'str' => 2, 'con' => 1 }
      }
    )
  end

  def self.advancement_config
    @advancement_config ||= Advancement.load_config(ADVANCEMENT_DEFINITIONS_PATH)
  end

  # Race instance keyed against the loaded race_definitions, so
  # name, speed, ability_score_adjustments, and racial abilities
  # are all populated. character_level lets racial abilities with
  # min_level thresholds appear once the character qualifies.
  def self.dummy_race(key, character_level: 0)
    Race.new(
      key:              key,
      race_definitions: race_definitions,
      character_level:  character_level
    )
  end

  # Advancement built with the rule values from
  # docs/advancement.yaml.example, so attribute_bonus,
  # max_hit_points, max_mana, and abilities all reflect what a
  # character loaded from the real config would compute.
  def self.dummy_advancement(tier:, class_levels:, picks: [])
    rules = advancement_config['rules']
    Advancement.new(
      tier:                             tier,
      class_levels:                     class_levels,
      tier_attribute_advancement:       picks.map(&:to_s),
      attribute_bonus_per_tier:         rules.fetch('attribute_bonus_per_tier',         [1, 1, 1, 1, 1]),
      focused_attribute_bonus_per_tier: rules.fetch('focused_attribute_bonus_per_tier', [0, 2, 2, 2, 2]),
      focused_attribute_count:          rules.fetch('focused_attribute_count',          2),
      tier_advancement:                 rules.fetch('tier_advancement',                 {}),
      class_definitions:                advancement_config['classes']
    )
  end

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
