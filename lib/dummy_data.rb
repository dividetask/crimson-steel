require 'json'

# Dummy data for the Status page sub-views. The page is fed example
# Rolls / Checks / Creatures so the stubs can render without a real
# Combat or Creatures domain wired in.
module DummyData
  module_function

  def rolls
    [
      {
        creature_name: 'Orc Patrol',
        roll_name: 'Attack (Greataxe)',
        dice_count: 3, tn: 5, starting_value: 0,
        reroll: nil,
        nudge:  nil,
        initial_dice: [2, 5, 6],
        post_reroll_dice: nil,
        post_nudge_dice: nil,
        dois: 2, critical_count: 1, die_size: 10
      },
      {
        creature_name: 'Bryn Ironvein',
        roll_name: 'Attack (Longsword)',
        dice_count: 8, tn: 1, starting_value: 0,
        reroll: { amount: 2, max: false, sign: :neg, label: 'Unsettling Words' },
        nudge:  nil,
        initial_dice: [8, 6, 10, 1, 10, 4, 8, 10],
        post_reroll_dice: [nil, nil, nil, nil, 9, nil, nil, 1],
        post_nudge_dice: nil,
        dois: 9, critical_count: 1, die_size: 10
      },
      {
        creature_name: 'Wisp Familiar',
        roll_name: 'Aid (Guidance)',
        dice_count: 4, tn: 5, starting_value: 1,
        reroll: { amount: 1, max: false, sign: :pos, label: 'Bardic Inspiration' },
        nudge:  { amount: 1, max: false, sign: :pos, label: 'Guidance' },
        initial_dice: [1, 3, 5, 8],
        post_reroll_dice: [1, 5, 5, 8],
        post_nudge_dice: [1, 5, 6, 9],
        dois: 4, critical_count: 0, die_size: 8
      },
      {
        creature_name: 'Cleric of Ruin',
        roll_name: 'Smite (Curse of Doubt)',
        dice_count: 6, tn: 4, starting_value: 0,
        reroll: { amount: 0, max: true, sign: :neg, label: 'Curse of Doubt' },
        nudge:  nil,
        initial_dice: [5, 8, 2, 6, 9, 3],
        post_reroll_dice: [3, 7, nil, 2, 4, nil],
        post_nudge_dice: nil,
        dois: 1, critical_count: 0, die_size: 10
      },
      {
        creature_name: 'Frenzied Berserker',
        roll_name: 'Attack (Reckless)',
        dice_count: 10, tn: 5, starting_value: -1,
        reroll: { amount: 0, max: true, sign: :pos, label: 'Reckless' },
        nudge:  nil,
        initial_dice: [1, 2, 4, 5, 7, 3, 6, 1, 8, 4],
        post_reroll_dice: [nil, nil, nil, 5, 7, nil, 6, nil, 8, nil],
        post_nudge_dice: nil,
        dois: 4, critical_count: 0, die_size: 10
      }
    ]
  end

  def check
    {
      supporting: [
        {
          creature_name: 'Bryn Ironvein',
          roll_name: 'Attack (Longsword)',
          dice_count: 8, tn: 2, starting_value: 0,
          reroll: { amount: 2, max: false, sign: :neg, label: 'Unsettling Words' },
          nudge: nil,
          initial_dice: [10, 8, 7, 4, 8, 4, 6, 9],
          post_reroll_dice: [7, nil, nil, nil, nil, nil, nil, 10],
          post_nudge_dice: nil,
          dois: 9, critical_count: 1, die_size: 10
        },
        {
          creature_name: 'Shield of Faith',
          roll_name: 'Aid',
          dice_count: 5, tn: 6, starting_value: 0,
          reroll: { amount: 1, max: false, sign: :neg, label: 'Unsettling Words' },
          nudge: nil,
          initial_dice: [4, 5, 3, 8, 1],
          post_reroll_dice: [nil, nil, nil, 3, nil],
          post_nudge_dice: nil,
          dois: -1, critical_count: 0, die_size: 10
        }
      ],
      opposing: [
        {
          creature_name: 'Bandit Captain',
          roll_name: 'Dodge',
          dice_count: 6, tn: 6, starting_value: 0,
          reroll: { amount: 3, max: false, sign: :pos, label: 'Bardic Inspiration' },
          nudge: nil,
          initial_dice: [5, 9, 8, 1, 10, 6],
          post_reroll_dice: [nil, nil, nil, 9, nil, nil],
          post_nudge_dice: nil,
          dois: 6, critical_count: 1, die_size: 10
        }
      ]
    }
  end

  # Sample player Creatures. The Conditions State is drawn from
  # docs/common/conditions/conditions_data.example.json by Creature ID.
  def creatures
    raw = File.read(File.expand_path('../docs/common/conditions/conditions_data.example.json', __dir__))
    states = JSON.parse(raw)['creatures'] || {}
    [
      { id: '1',  name: 'Bryn Ironvein',  race: 'Dwarf',  klass: 'Fighter',  tier: 3, max_hp: 24, mana_max: 8,  charisma: 8,  attributes: { str: 14, dex: 10, con: 14, int: 9,  wis: 11, cha: 8  },
        consumables: [
          { name: 'Cure Simple Wounds Potion', tier: 1, quantity: 2 },
          { name: 'Minor Recharge Potion',     tier: 0, quantity: 1 }
        ] },
      { id: '2',  name: 'Wisp Trueheart', race: 'Human',  klass: 'Cleric',   tier: 2, max_hp: 30, mana_max: 12, charisma: 14, attributes: { str: 10, dex: 11, con: 12, int: 11, wis: 16, cha: 14 },
        consumables: [
          { name: 'Cure Lesser Wounds Scroll', tier: 2, quantity: 8 },
          { name: 'Cure Simple Wounds Scroll', tier: 1, quantity: 1 }
        ] },
      { id: '3',  name: 'Tana Quickfoot', race: 'Halfling', klass: 'Rogue',  tier: 2, max_hp: 18, mana_max: 6,  charisma: 12, attributes: { str: 9,  dex: 16, con: 11, int: 13, wis: 12, cha: 12 },
        consumables: [
          { name: 'Cure Simple Wounds Potion', tier: 1, quantity: 1 },
          { name: 'Cure Lesser Wounds Potion', tier: 2, quantity: 4 }
        ] },
      { id: '4',  name: 'Selka Embermane', race: 'Tiefling', klass: 'Sorcerer', tier: 1, max_hp: 14, mana_max: 14, charisma: 16, attributes: { str: 8, dex: 12, con: 11, int: 12, wis: 11, cha: 16 },
        consumables: [] }
    ].map { |c| c.merge(state: Conditions::State.load(states[c[:id]])) }
  end
end
