require_relative '../proficiencies'
require 'dice_resolution'

module Status
  # Sample Creatures for the Status > Creatures sub-view. Per the
  # project's per-page-data rule, this is hand-curated dummy data for
  # the Status page only — not a window into the live Creatures
  # roster. Used by /character-sheets too while live data wiring is
  # still pending the rest of the Creatures domain.
  #
  # What is hand-stored vs computed:
  #   - Stored: header / class entries (class key, level, trained
  #     skill keys, choices), Effective Attributes, vitals, actions,
  #     items, abilities, spells, rituals, notes.
  #   - Computed via the live class functions: Skill ranks
  #     (Proficiencies::Ranks.ranks_for_skill, which applies Skill
  #     Rate Resolution and the Proficiency Advancement Rates) and
  #     the resulting dice / bonus (Proficiencies skill prowess plus
  #     DiceResolution.translate_prowess).
  #
  # When the Creatures domain's vitals (HP / Mana / Effective
  # Attributes / etc.) come online they'll replace the stored values
  # in the same way the Skills section already does.
  module SampleCreatures
    module_function

    # The full list of sheet-renderable demos, in display order.
    # /character-sheets pages between these via ?i=<index>; the
    # Roster Sidebar groups them by `roster_group` (and, for
    # templates, by `category`).
    def demos
      [
        ash_windmere, bryn_ironvein, veyl_aetheris,
        daven_korr_npc,
        *general_red_tier_demos,
        *rise_of_the_slavelords_demos,
        *fey_favors_demos
      ]
    end

    def by_index(i)
      demos[i]
    end

    # Categories the Roster Sidebar renders below Players and NPCs.
    # The display order is the order in this list.
    CATEGORIES = [
      { key: 'general_red_tier',         name: 'General Red Tier' },
      { key: 'rise_of_the_slavelords',   name: 'Rise of the Slavelords' },
      { key: 'fey_favors',               name: 'Fey Favors' }
    ].freeze

    # Grouped roster for the Roster Sidebar
    # (docs/common/ui/creatures_roster_sidebar_stub.md). New shape:
    # players + npcs are top-level lists; each themed category mixes
    # creature templates and random encounter tables under one heading.
    # Per-row state (Player Active/Absent, NPC Active/Absent,
    # template copy_count) is pulled from the live Encounter roster.
    def roster
      players = []
      npcs    = []
      by_category = Hash.new { |h, k| h[k] = { templates: [], random_encounter_tables: [] } }
      enc_state = Encounter.state
      spawned   = spawned_by_template(enc_state)

      demos.each_with_index do |demo, idx|
        group = demo[:roster_group] || :players
        row = { id: demo[:id], name: demo[:header][:name],
                copy_count: enc_state.copy_count(demo[:id]), sheet_index: idx }
        case group
        when :players
          row[:active] = !enc_state.pc_excluded?(demo[:id])
          players << row
        when :npcs
          row[:active] = enc_state.includes_creature?(demo[:id])
          npcs << row
        when :template
          cat = demo[:category]
          # Spawned instances cloned from this template, in roster order.
          children = spawned[demo[:id].to_s] || []
          row[:spawned]    = children
          row[:copy_count] = children.length
          by_category[cat][:templates] << row if cat
        end
      end

      Status::SampleCreatures.sample_encounter_tables.each do |t|
        by_category[t[:category]][:random_encounter_tables] << t
      end

      categories = CATEGORIES.map do |c|
        bucket = by_category[c[:key]]
        c.merge(templates: bucket[:templates], random_encounter_tables: bucket[:random_encounter_tables])
      end

      { players: players, npcs: npcs, categories: categories }
    end

    # Map of template id (string) => list of spawned-instance rows
    # currently in the Encounter roster, in roster order. A spawned
    # Creature records the template it was cloned from in its
    # `spawned_from` field (see Creatures::RandomEncounter.spawn_from_template).
    def spawned_by_template(enc_state)
      out = Hash.new { |h, k| h[k] = [] }
      enc_state.combatants.each do |c|
        rec = (Creatures::Dataset.get(c[:creature_id]) rescue nil)
        next unless rec && rec[:spawned_from]
        name = c[:name].to_s.empty? ? rec[:name] : c[:name]
        out[rec[:spawned_from].to_s] << {
          creature_id:  c[:creature_id],
          combatant_id: c[:id],
          name:         name
        }
      end
      out
    end

    # Random Encounter Tables surfaced to the Roster Sidebar. Each entry is
    # filed under one of the CATEGORIES above via its `category` key.
    def sample_encounter_tables
      [
        { table_id: 'slave_lords_caravan', name: 'Caravan ambush',           category: 'rise_of_the_slavelords' },
        { table_id: 'stockade_patrol',     name: 'Stockade patrol',          category: 'rise_of_the_slavelords' },
        { table_id: 'general_pirate_raid', name: 'Generic pirate raid',      category: 'general_red_tier' },
        { table_id: 'general_wolf_pack',   name: 'Wolf pack',                category: 'general_red_tier' },
        { table_id: 'general_goblin_ambush', name: 'Goblin ambush',          category: 'general_red_tier' },
        { table_id: 'fey_pixie_mischief',  name: 'Pixie mischief',           category: 'fey_favors' },
        { table_id: 'fey_dryad_grove',     name: "Dryad's grove",            category: 'fey_favors' }
      ]
    end

    # Sample roll-result fixtures keyed by encounter table id. Used
    # by /random_encounters/roll/<table_id> on the Character Sheets page —
    # the Combat / enemy-data-file side effects of a roll aren't
    # wired yet, so the panel pulls from this curated set instead of
    # calling Creatures.roll_random_encounter. The shape matches the
    # creatures_random_encounter_roll_result_stub.md `result` parameter.
    def sample_roll_results
      {
        'slave_lords_caravan' => [
          {
            table_name: 'Slave Lords — caravan ambush',
            subtitle: 'Slaver merchant escort',
            rolls: [
              { count: 1, name: 'Slaver Merchant', gold: 369,
                items: [{ name: 'falcion', count: 1 }, { name: 'chain shirt', count: 1 }] },
              { count: 5, name: 'Half-Orc Soldier', gold: 73,
                items: [{ name: 'falcion', count: 5 }, { name: 'longbow', count: 5 },
                        { name: 'chain shirt +1', count: 2 },
                        { name: 'Potion of Sanctuary', count: 1 },
                        { name: 'Potion of Stabilize', count: 1 },
                        { name: 'chain shirt', count: 3 },
                        { name: 'Potion of Cure Lesser Wounds', count: 1 }] },
              { count: 1, name: 'Orc Interpreter', gold: 13,
                items: [{ name: 'falcion', count: 1 }, { name: 'longbow', count: 1 }, { name: 'chain shirt', count: 1 }] }
            ]
          },
          {
            table_name: 'Slave Lords — caravan ambush',
            subtitle: 'Lone slaver patrol',
            rolls: [
              { count: 2, name: 'Orc Patrol', gold: 22,
                items: [{ name: 'falcion', count: 2 }, { name: 'leather armor', count: 2 }] },
              { count: 1, name: 'Slaver Lieutenant', gold: 84,
                items: [{ name: 'longsword', count: 1 }, { name: 'chain shirt', count: 1 },
                        { name: 'Potion of Cure Lesser Wounds', count: 1 }] }
            ]
          }
        ],
        'general_pirate_raid' => [
          {
            table_name: 'Generic pirate raid',
            subtitle: 'Boarding party',
            rolls: [
              { count: 6, name: 'Pirate', gold: 41,
                items: [{ name: 'cutlass', count: 6 }, { name: 'buckler', count: 4 },
                        { name: 'Potion of Cure Lesser Wounds', count: 2 }] }
            ]
          },
          {
            table_name: 'Generic pirate raid',
            subtitle: 'Skeleton crew',
            rolls: [
              { count: 3, name: 'Pirate', gold: 18,
                items: [{ name: 'cutlass', count: 3 }, { name: 'shortbow', count: 1 }] }
            ]
          }
        ],
        'stockade_patrol' => [
          {
            table_name: 'Slave Lords — stockade patrol',
            subtitle: 'Standard patrol',
            rolls: [
              { count: 3, name: 'Stockade Guard', gold: 28,
                items: [{ name: 'longsword', count: 3 }, { name: 'chain shirt', count: 3 },
                        { name: 'lantern', count: 1 }] }
            ]
          }
        ]
      }
    end

    # Pick a sample roll result for the given table. Returns a
    # different variant each call (so successive clicks of the Roll
    # button visibly reroll). Falls back to a generic placeholder
    # for tables not in the sample map.
    def random_roll_result(table_id, rng = Random.new)
      variants = sample_roll_results[table_id.to_s]
      if variants.nil? || variants.empty?
        return {
          table_id: table_id.to_s,
          table_name: table_id.to_s,
          subtitle: 'No sample loot data for this table yet.',
          rolls: []
        }
      end
      pick = variants[rng.rand(variants.length)]
      pick.merge(table_id: table_id.to_s)
    end

    # ---- 1. Ash Windmere ------------------------------------------------

    def ash_windmere
      attrs = { str: 14, dex: 18, con: 16, int: 17, wis: 20, cha: 22 }
      classes = [{ key: 'bard', level: 3,
                   trained_skills: %w[perform_dance persuasion perception arcana] }]
      base_data(
        id: 1,
        label: 'Ash Windmere — Tier 3 Bard with full kit',
        header: { name: 'Ash Windmere', player: 'Sam',
                  summary: 'Human Bard 3', tier: 3, bab: 4 },
        attributes: attrs,
        classes: classes,
        vitals: {
          hp:   { current: 22, max: 48 },
          mana: { current: 9,  max: 31, regen: 3 },
          toxicity: { current: 0, threshold: 11 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 5, damage_reduction: 0, damage_resilience: 3
        },
        initiative: { dice_count: 4 },
        perception: { dice: 6, bonus: 5 },
        speed: 30,
        actions: [
          { name: 'Rapier',        speed: 2, roll: '4d', attack_bonus: 3, dmg_bonus: 2, bleed: 1, mt: 8, notes: '' },
          { name: 'Hand Crossbow', speed: 3, roll: '3d', attack_bonus: 4, dmg_bonus: 1, bleed: 0, mt: 7, notes: '' },
          { name: 'Dodge',         speed: 0, roll: '3d', attack_bonus: 2, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],
        attributes_table: [
          { attr: 'Strength',     score: 14, half: 7,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Dexterity',    score: 18, half: 9,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Constitution', score: 16, half: 8,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Intelligence', score: 17, half: 8,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Wisdom',       score: 20, half: 10, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Charisma',     score: 22, half: 11, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } }
        ],
        items: {
          equipped: [{ name: 'Rapier' }, { name: 'Hand Crossbow' }, { name: 'Studded Leather' }],
          consumable: [{ quantity: 2, name: 'Healing Draught' }],
          ammunition: [{ quantity: 20, name: 'Bolt' }],
          other: [{ quantity: 1, name: 'Lute' }, { quantity: 5, name: 'Rations' }, { quantity: 1, name: 'Bedroll' }]
        },
        item_descriptions: [
          { name: 'Cloak of Resistance +1', description: 'Adds +1 to all saves; does not stack with other resistance items.' },
          { name: 'Lute of the Wandering Bard', description: 'Once per scene, grant Bardic Inspiration without spending the action.' }
        ],
        abilities: [
          { name: 'Bonus Feat',              description: 'Choose any 1st-level feat.' },
          { name: 'Magical Performance (3)', description: 'Learn a magical variant of any Performance skill, used both for mundane checks and to create a magical performance. Maintaining a performance takes a main action each turn; bardic spells can be cast as part of that action. Only advances on bard levels.' },
          { name: 'Bardic Spellcasting',     description: 'Cast a number of bardic spells as a main action while performing. Spells need not be prepared each day. Casting outside a performance takes twice as long.' },
          { name: 'Bardic Inspiration',      description: 'While performing, spend 1 mana (once per turn) to grant a pool of luck. Each point lets you or an ally reroll a single die before the initial check. Successes grant 1 luck (must be used before your next turn); a fumble awards luck to the DM instead.' },
          { name: 'Jack Of All Trades',      description: 'Treat all skills (except restricted skills) as trained, with effective ranks equal to half your level on checks where you have no ranks.' },
          { name: 'Better Lucky Than Good',  description: 'Spend 3 mana during a round you cannot act (e.g. surprise round). Attacks against you (including spells) are made with half as many dice (min 3). Enemies are unconsciously aware of the penalty.' },
          { name: 'Performance Feat',        description: 'Gain Familiar, Social Spell, Spell Focus (Enchantment), or Spell Focus (Illusion) as a bonus feat.' },
          { name: 'Silver Tongue',           description: '+1 inherent bonus to Persuasion and Deception checks; applies when using versatile performance.' },
          { name: 'Unsettling Words',        description: 'Spend a luck point from your performance before an enemy rolls; pick one of their dice to reroll.' },
          { name: 'Versatile Performance',   description: 'No description yet.' }
        ],
        spells: [
          { tier: 0, names: ['Repair'] },
          { tier: 1, names: ['Charm Person', 'Healing Word'] },
          { tier: 2, names: ['Suggestion'] }
        ],
        rituals: [{ tier: 1, names: ['Comprehend Languages', 'Detect Magic'] }],
        item_spells: [],
        active_effects: [],
        usable_spells: [],
        notes: [{ body: 'Placeholder note for the character.' }]
      )
    end

    # ---- 2. Bryn Ironvein -----------------------------------------------

    def bryn_ironvein
      attrs = { str: 19, dex: 11, con: 20, int: 10, wis: 13, cha: 7 }
      classes = [{ key: 'fighter', level: 3,
                   trained_skills: %w[athletics intimidate perception] }]
      base_data(
        id: 2,
        label: 'Bryn Ironvein — Tier 1 Fighter, pure martial',
        header: { name: 'Bryn Ironvein', player: 'Mira',
                  summary: 'Dwarf Fighter 3', tier: 1, bab: 5 },
        attributes: attrs,
        classes: classes,
        vitals: {
          hp:   { current: 0,  max: 20 },
          mana: { current: 8,  max: 8,  regen: 1 },
          toxicity: { current: 0, threshold: 7 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 8, damage_reduction: 2, damage_resilience: 5
        },
        initiative: { dice_count: 6 },
        perception: { dice: 4, bonus: 2 },
        speed: 25,
        actions: [
          { name: 'Warhammer', speed: 3, roll: '6d', attack_bonus: 2, dmg_bonus: 1, bleed: 0, mt: 7, notes: '' },
          { name: 'Dodge',     speed: 0, roll: '3d', attack_bonus: 0, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],
        attributes_table: [
          { attr: 'Strength',     score: 19, half: 9,  check: { dice: 4, bonus: 0 }, save: { dice: 4, bonus: 0 } },
          { attr: 'Dexterity',    score: 11, half: 5,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Constitution', score: 20, half: 10, check: { dice: 4, bonus: 0 }, save: { dice: 4, bonus: 0 } },
          { attr: 'Intelligence', score: 10, half: 5,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Wisdom',       score: 13, half: 6,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Charisma',     score: 7,  half: 3,  check: { dice: 3, bonus: 0 }, save: { dice: 3, bonus: 0 } }
        ],
        items: {
          equipped: [{ name: 'Warhammer' }, { name: 'Tower shield' }, { name: 'Chain mail' }],
          consumable: [{ quantity: 1, name: 'Healing Draught' }],
          ammunition: [],
          other: [{ quantity: 3, name: 'Javelin' }, { quantity: 1, name: 'Whetstone' },
                  { quantity: 5, name: 'Rations' }, { quantity: 28, name: 'Gold' }]
        },
        item_descriptions: [],
        abilities: [
          { name: 'Darkvision',         description: 'No description yet.' },
          { name: 'Dwarven Resilience', description: 'No description yet.' },
          { name: 'Stonecunning',       description: 'No description yet.' },
          { name: 'Weapon Training',    description: 'No description yet.' },
          { name: 'Armor Training',     description: 'No description yet.' }
        ],
        spells: [], rituals: [], item_spells: [],
        active_effects: [], usable_spells: [], notes: []
      )
    end

    # ---- 3. Veyl Aetheris -----------------------------------------------

    def veyl_aetheris
      attrs = { str: 7, dex: 17, con: 11, int: 17, wis: 11, cha: 13 }
      classes = [{ key: 'arcane_trickster', level: 4,
                   trained_skills: %w[arcana stealth larceny sleight_of_hand deception persuasion perception game_chess] }]
      base_data(
        id: 9,
        label: 'Veyl Aetheris — Tier 2 Arcane Trickster (Archetype demo)',
        header: { name: 'Veyl Aetheris', player: nil,
                  summary: 'High Elf Arcane Trickster 4', tier: 2, bab: 4 },
        attributes: attrs,
        classes: classes,
        vitals: {
          hp:   { current: 18, max: 22 },
          mana: { current: 12, max: 16, regen: 2 },
          toxicity: { current: 0, threshold: 7 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 6, damage_reduction: 1, damage_resilience: 3
        },
        initiative: { dice_count: 5 },
        perception: { dice: 4, bonus: 0 },
        speed: 30,
        actions: [
          { name: 'Shortbow', speed: 2, roll: '4d', attack_bonus: 3, dmg_bonus: 0, bleed: 0, mt: 7, notes: '' },
          { name: 'Dagger',   speed: 1, roll: '3d', attack_bonus: 2, dmg_bonus: 0, bleed: 0, mt: 6, notes: '' },
          { name: 'Dodge',    speed: 0, roll: '3d', attack_bonus: 1, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],
        attributes_table: [
          { attr: 'Strength',     score: 7,  half: 3, check: { dice: 3, bonus: 0 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Dexterity',    score: 17, half: 8, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Constitution', score: 11, half: 5, check: { dice: 3, bonus: 1 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Intelligence', score: 17, half: 8, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Wisdom',       score: 11, half: 5, check: { dice: 3, bonus: 1 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Charisma',     score: 13, half: 6, check: { dice: 3, bonus: 1 }, save: { dice: 3, bonus: 0 } }
        ],
        items: {
          equipped: [{ name: 'Shortbow' }, { name: 'Dagger' }, { name: 'Studded Leather' }],
          consumable: [],
          ammunition: [{ quantity: 18, name: 'Arrow' }],
          other: [{ quantity: 1, name: 'Thieves Tools' }, { quantity: 1, name: 'Component Pouch' }]
        },
        item_descriptions: [],
        abilities: [
          { name: 'Low-Light Vision',     description: 'No description yet.' },
          { name: 'Keen Senses',          description: 'No description yet.' },
          { name: 'Elven Magic',          description: 'No description yet.' },
          { name: 'Trapfinding',          description: 'No description yet.' },
          { name: 'Sneak Attack',         description: 'No description yet.' },
          { name: "Thieves' Cant",        description: 'No description yet.' },
          { name: 'Arcane Spellcasting',  description: 'No description yet.' },
          { name: 'Danger Sense',         description: 'No description yet.' },
          { name: 'Combat Trickery',      description: 'No description yet.' },
          { name: 'Mage Hand Legerdemain', description: 'No description yet.' },
          { name: 'Elemental Dart',       description: 'No description yet.' }
        ],
        spells: [
          { tier: 0, names: ['Light', 'Message'] },
          { tier: 1, names: ['Fire Dart', 'Silent Portal'] },
          { tier: 2, names: ['Hideous Laughter'] }
        ],
        rituals: [], item_spells: [],
        active_effects: [
          { caster: 'Ash Windmere', source: 'Bardic Inspiration', rounds_left: 3 }
        ],
        usable_spells: [
          { name: 'Fire Dart',         casting_time: '1 action', mana_cost: 1, save_tn: nil },
          { name: 'Silent Portal',     casting_time: '1 action', mana_cost: 2, save_tn: 7 },
          { name: 'Hideous Laughter',  casting_time: '1 action', mana_cost: 3, save_tn: 7 }
        ],
        notes: []
      )
    end

    # ---- 4. Daven Korr — NPC quest-giver --------------------------------

    def daven_korr_npc
      attrs = { str: 10, dex: 10, con: 11, int: 12, wis: 13, cha: 14 }
      classes = [{ key: 'commoner', level: 1, trained_skills: %w[perception persuasion] }]
      simple_demo(
        id: 2001, label: 'Daven Korr — NPC quest-giver',
        roster_group: :npcs,
        header: { name: 'Daven Korr', player: nil, summary: 'Human Commoner 1', tier: 1, bab: 0 },
        attributes: attrs, classes: classes,
        speed: 30,
        items: { equipped: [{ name: 'Robes' }], consumable: [], ammunition: [], other: [] }
      )
    end

    # ---- Themed Creature Template demos ---------------------------------
    #
    # One simple_demo per template declared in the
    # creatures_data_<theme>.example.yaml files. Each carries the
    # `category` field used by SampleCreatures.roster to group rows
    # in the Roster Sidebar.

    def general_red_tier_demos
      [
        template_demo(id: 300, name: 'Medium Spider', race: 'beast', tier: 1,
                       attrs: { str: 9, dex: 14, con: 11, int: 1, wis: 10, cha: 2 },
                       classes: [{ key: 'commoner', level: 1, trained_skills: [] }],
                       category: 'general_red_tier'),
        template_demo(id: 301, name: 'Wolf', race: 'beast', tier: 1,
                       attrs: { str: 12, dex: 15, con: 13, int: 3, wis: 12, cha: 6 },
                       classes: [{ key: 'commoner', level: 1, trained_skills: [] }],
                       category: 'general_red_tier'),
        template_demo(id: 302, name: 'Goblin', race: 'goblin', tier: 1,
                       attrs: { str: 8, dex: 14, con: 10, int: 9, wis: 8, cha: 8 },
                       classes: [{ key: 'rogue', level: 1, trained_skills: %w[stealth larceny] }],
                       category: 'general_red_tier'),
        template_demo(id: 303, name: 'Goblin Archer', race: 'goblin', tier: 1,
                       attrs: { str: 8, dex: 16, con: 10, int: 9, wis: 10, cha: 8 },
                       classes: [{ key: 'rogue', level: 1, trained_skills: %w[stealth perception] }],
                       category: 'general_red_tier'),
        template_demo(id: 304, name: 'Cultist', race: 'human', tier: 1,
                       attrs: { str: 10, dex: 11, con: 12, int: 11, wis: 13, cha: 12 },
                       classes: [{ key: 'cleric', level: 1, trained_skills: %w[religion intimidate] }],
                       category: 'general_red_tier'),
        template_demo(id: 305, name: 'Cult Fanatic', race: 'human', tier: 1,
                       attrs: { str: 10, dex: 12, con: 13, int: 12, wis: 14, cha: 14 },
                       classes: [{ key: 'cleric', level: 2, trained_skills: %w[religion intimidate persuasion] }],
                       category: 'general_red_tier')
      ]
    end

    def rise_of_the_slavelords_demos
      [
        template_demo(id: 350, name: 'Slaver Merchant', race: 'human', tier: 1,
                       attrs: { str: 12, dex: 12, con: 12, int: 13, wis: 11, cha: 14 },
                       classes: [{ key: 'rogue', level: 2, trained_skills: %w[appraisal persuasion deception] }],
                       category: 'rise_of_the_slavelords'),
        template_demo(id: 351, name: 'Slaver Lieutenant', race: 'human', tier: 1,
                       attrs: { str: 15, dex: 13, con: 14, int: 11, wis: 11, cha: 12 },
                       classes: [{ key: 'fighter', level: 3, trained_skills: %w[athletics intimidate perception] }],
                       category: 'rise_of_the_slavelords'),
        template_demo(id: 352, name: 'Half-Orc Soldier', race: 'half_orc', tier: 1,
                       attrs: { str: 15, dex: 12, con: 14, int: 9, wis: 10, cha: 8 },
                       classes: [{ key: 'fighter', level: 1, trained_skills: %w[athletics intimidate] }],
                       category: 'rise_of_the_slavelords'),
        template_demo(id: 353, name: 'Orc Interpreter', race: 'half_orc', tier: 1,
                       attrs: { str: 12, dex: 12, con: 12, int: 12, wis: 10, cha: 10 },
                       classes: [{ key: 'rogue', level: 1, trained_skills: %w[linguistics persuasion] }],
                       category: 'rise_of_the_slavelords'),
        template_demo(id: 354, name: 'Stockade Guard', race: 'human', tier: 1,
                       attrs: { str: 14, dex: 12, con: 14, int: 10, wis: 12, cha: 10 },
                       classes: [{ key: 'fighter', level: 2, trained_skills: %w[perception intimidate] }],
                       category: 'rise_of_the_slavelords')
      ]
    end

    def fey_favors_demos
      [
        template_demo(id: 400, name: 'Sprite', race: 'sprite', tier: 1,
                       attrs: { str: 3, dex: 18, con: 10, int: 14, wis: 13, cha: 11 },
                       classes: [{ key: 'rogue', level: 1, trained_skills: %w[stealth perception] }],
                       category: 'fey_favors'),
        template_demo(id: 401, name: 'Pixie', race: 'pixie', tier: 1,
                       attrs: { str: 2, dex: 20, con: 8, int: 10, wis: 14, cha: 15 },
                       classes: [{ key: 'bard', level: 1, trained_skills: %w[perform_dance deception] }],
                       category: 'fey_favors'),
        template_demo(id: 402, name: 'Dryad', race: 'dryad', tier: 1,
                       attrs: { str: 10, dex: 12, con: 11, int: 14, wis: 15, cha: 18 },
                       classes: [{ key: 'druid', level: 2, trained_skills: %w[nature persuasion] }],
                       category: 'fey_favors'),
        template_demo(id: 403, name: 'Brownie', race: 'brownie', tier: 1,
                       attrs: { str: 6, dex: 14, con: 10, int: 12, wis: 13, cha: 11 },
                       classes: [{ key: 'rogue', level: 1, trained_skills: %w[stealth sleight_of_hand] }],
                       category: 'fey_favors'),
        template_demo(id: 404, name: "Will-o'-Wisp Spark", race: 'fey', tier: 1,
                       attrs: { str: 1, dex: 17, con: 10, int: 13, wis: 14, cha: 11 },
                       classes: [{ key: 'commoner', level: 2, trained_skills: [] }],
                       category: 'fey_favors')
      ]
    end

    # Bridge a live Creatures::Accessor to the demo Hash the sheet
    # partials consume. Used to render spawned Creatures (instances
    # cloned from a template) that aren't in the hand-curated `demos`.
    # Vitals (HP / Mana / Speed), attributes, and skills are computed
    # from the Accessor; abilities come from granted_abilities. Items
    # stay empty until the Equipment domain lands.
    def live_demo(accessor)
      rec = accessor.record
      attrs = Creatures::Config.attribute_keys.each_with_object({}) do |k, h|
        h[k] = accessor.base_attribute_value(k)
      end
      classes = rec[:classes].map do |key, entry|
        { key: key, level: entry[:level], trained_skills: Array(entry[:skills]) }
      end

      race_label  = (rec[:race] || '').to_s.split('_').map(&:capitalize).join(' ')
      class_label = classes.map { |c| "#{c[:key].split('_').map(&:capitalize).join(' ')} #{c[:level]}" }.join(' / ')
      summary     = [race_label, class_label].reject(&:empty?).join(' ')

      tier    = (accessor.tier rescue 0)
      max_hp  = (accessor.max_hit_points rescue 0)
      max_mana = (accessor.max_mana rescue 0)
      bab     = (accessor.ranks_for('martial') rescue 0)
      init    = (accessor.attribute_value(:wis) rescue 0) / 2

      abilities = (accessor.granted_abilities rescue []).map do |g|
        { name: g[:name], description: 'No description yet.' }
      end

      base_data(
        id: accessor.id,
        label: accessor.name,
        roster_group: :template,
        header: { name: accessor.name, player: accessor.player, summary: summary, tier: tier, bab: bab },
        attributes: attrs,
        classes: classes,
        vitals: {
          hp:   { current: max_hp, max: max_hp },
          mana: { current: max_mana, max: max_mana, regen: 0 },
          toxicity: { current: 0, threshold: 0 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 0, damage_reduction: 0, damage_resilience: 0
        },
        initiative: { dice_count: init },
        perception: { dice: 3, bonus: 0 },
        speed: (accessor.speed rescue 30),
        actions: [
          { name: 'Dodge', speed: 0, roll: '3d', attack_bonus: 0, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],
        attributes_table: live_attributes_table(attrs),
        items: { equipped: [], consumable: [], ammunition: [], other: [] },
        item_descriptions: [],
        abilities: abilities,
        spells: [], rituals: [], item_spells: [],
        active_effects: [], usable_spells: [], notes: []
      )
    end

    def live_attributes_table(attrs)
      %i[Strength Dexterity Constitution Intelligence Wisdom Charisma]
        .zip(%i[str dex con int wis cha]).map do |label_name, k|
        { attr: label_name.to_s, score: attrs[k], half: attrs[k] / 2,
          check: { dice: 3, bonus: 0 }, save: { dice: 3, bonus: 0 } }
      end
    end

    # Build a simple_demo for one themed template entry.
    def template_demo(id:, name:, race:, tier:, attrs:, classes:, category:)
      summary_parts = []
      summary_parts << race.split('_').map(&:capitalize).join(' ')
      classes.each { |c| summary_parts << "#{c[:key].split('_').map(&:capitalize).join(' ')} #{c[:level]}" }
      simple_demo(
        id: id, label: "#{name} — template (#{category})",
        roster_group: :template,
        category: category,
        header: { name: name, player: nil, summary: summary_parts.join(' '),
                  tier: tier, bab: 0 },
        attributes: attrs, classes: classes,
        speed: 30,
        items: { equipped: [], consumable: [], ammunition: [], other: [] }
      )
    end

    # Convenience builder for the lightweight non-PC demos. Fills in
    # sensible empty defaults for all sections so the partial doesn't
    # have to guard each one.
    def simple_demo(id:, label:, roster_group:, header:, attributes:, classes:,
                    speed:, items:, actions: nil, category: nil)
      half = ->(a) { a / 2 }
      attrs_table = %i[Strength Dexterity Constitution Intelligence Wisdom Charisma]
                    .zip(%i[str dex con int wis cha]).map do |label_name, k|
        { attr: label_name.to_s, score: attributes[k], half: half.call(attributes[k]),
          check: { dice: 4, bonus: 0 }, save: { dice: 3, bonus: 0 } }
      end
      base_data(
        id: id, label: label,
        roster_group: roster_group,
        category: category,
        header: header,
        attributes: attributes,
        classes: classes,
        vitals: {
          hp: { current: 0, max: 0 }, mana: { current: 0, max: 0, regen: 0 },
          toxicity: { current: 0, threshold: 0 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 0, damage_reduction: 0, damage_resilience: 0
        },
        initiative: { dice_count: 3 },
        perception: { dice: 3, bonus: 0 },
        speed: speed,
        actions: actions || [
          { name: 'Dodge', speed: 0, roll: '3d', attack_bonus: 0, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],
        attributes_table: attrs_table,
        items: items,
        item_descriptions: [],
        abilities: [],
        spells: [], rituals: [], item_spells: [],
        active_effects: [], usable_spells: [], notes: []
      )
    end

    # --------------------------------------------------------------------

    # Build the demo Hash. Adds `skills` derived from `classes` +
    # `attributes` via Proficiencies + DiceResolution, so ranks /
    # dice / bonus are never hand-set.
    def base_data(classes:, attributes:, **rest)
      rest[:attributes]    = attributes
      rest[:classes]       = classes
      rest[:skills]        = compute_skills(classes, attributes)
      rest[:roster_group] ||= :players
      rest
    end

    # For each trained skill across the Creature's classes, request
    # the Roll inputs (Dice Cap + Competency Modifier) from
    # Proficiencies' *Compute Roll inputs* entry point rather than
    # recomputing Prowess here. Ranks are summed across classes by the
    # same Proficiencies entry point via the shim's `ranks_for`.
    def compute_skills(classes, attributes)
      shim = SkillShim.new(classes, attributes)
      trained = classes.flat_map { |e| Array(e[:trained_skills]) }.uniq
      trained.filter_map do |skill_key|
        next unless Proficiencies.attribute_for(skill_key) # skip unknown keys
        inputs = Proficiencies::Compute.roll_inputs(key: skill_key, creature: shim)
        bonus  = inputs[:competency_modifier] ? inputs[:competency_modifier][1] : 0
        {
          name:  pretty_skill_name(skill_key),
          ranks: shim.ranks_for(skill_key),
          dice:  inputs[:dice_cap],
          bonus: bonus
        }
      end
    end

    # Minimal Creature-like adapter over sample (classes, attributes)
    # data so Proficiencies::Compute can resolve Roll inputs. Mirrors
    # the subset of the Creatures Accessor that Compute touches. Floor
    # / Substitution abilities aren't modeled for sample data, so the
    # ability predicates return their empty answers.
    class SkillShim
      def initialize(classes, attributes)
        @classes    = classes
        @attributes = attributes
      end

      def ranks_for(key)
        key = key.to_s
        @classes.sum do |entry|
          trained = Array(entry[:trained_skills]).include?(key)
          Proficiencies::Ranks.ranks_for_skill(entry[:key], entry[:level], key, trained: trained)
        end
      end

      def attribute_value(attr)
        @attributes[attr.to_sym] || 0
      end

      def has_ability(_name) = false
      def level_for_ability(_name) = 0
    end

    # Render `perform_dance` as `Perform (Dance)`, `sleight_of_hand`
    # as `Sleight Of Hand`, `game_chess` as `Game (Chess)`, etc.
    def pretty_skill_name(key)
      if key.include?('_') && Proficiencies.skills.key?("#{key.split('_').first}_")
        family, *rest = key.split('_')
        return "#{family.capitalize} (#{rest.map(&:capitalize).join(' ')})"
      end
      key.split('_').map(&:capitalize).join(' ')
    end
  end
end
