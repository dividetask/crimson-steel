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
        dois: 4, critical_count: 0, die_size: 10
      },
      {
        creature_name: 'Cleric of Ruin',
        roll_name: 'Smite (Curse of Doubt)',
        dice_count: 6, tn: 4, starting_value: 0,
        reroll: nil,
        mass_reroll: { sign: :neg, label: 'Curse of Doubt' },
        nudge:  nil,
        initial_dice: [5, 8, 2, 6, 9, 3],
        post_reroll_dice: nil,
        post_mass_reroll_dice: [3, 7, nil, 2, 4, nil],
        post_nudge_dice: nil,
        dois: 1, critical_count: 0, die_size: 10
      },
      {
        creature_name: 'Frenzied Berserker',
        roll_name: 'Attack (Reckless)',
        dice_count: 10, tn: 5, starting_value: -1,
        reroll: nil,
        mass_reroll: { sign: :pos, label: 'Reckless' },
        nudge:  nil,
        initial_dice: [1, 2, 4, 5, 7, 3, 6, 1, 8, 4],
        post_reroll_dice: nil,
        post_mass_reroll_dice: [nil, nil, nil, 5, 7, nil, 6, nil, 8, nil],
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

  # Four example Conditions Save Resolution scenarios. The first
  # three live on the Conditions sub-view; the fourth (with both a
  # Reroll source and a Blessing Nudge source) is shared between the
  # Conditions and Check Resolution sub-views as a demo of the
  # multi-step Save Resolution Stub.
  def save_resolution_examples(catalog)
    ash_luck = {
      creature_ref: nil, creature_name: 'Ash Windmere',
      source_name: 'Bardic Inspiration', direction: 'pos', pool: 5
    }
    selka_blessing = {
      creature_ref: nil, creature_name: 'Selka Embermane',
      source_name: 'Blessing', direction: 'pos', pool: 4
    }

    [
      {
        creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
        affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                      potency: 25, inflicter_tier: 3 },
        save_dice: 7, save_tn: 8, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: [ash_luck], reroll_label: 'Luck',
        mass_reroll_sources: nil, nudge_sources: nil,
        stub_id: 'save-bleed-t3'
      },
      {
        creature:   { id: '3', name: 'Tana Quickfoot', tier: 2 },
        affliction: { name: 'common_venom', rule: catalog.affliction('common_venom'),
                      potency: 12, inflicter_tier: 1 },
        save_dice: 5, save_tn: 6, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: [ash_luck], reroll_label: 'Luck',
        mass_reroll_sources: nil, nudge_sources: nil,
        stub_id: 'save-poison-t1'
      },
      {
        creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
        affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                      potency: 8, inflicter_tier: 2 },
        save_dice: 7, save_tn: 7, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: nil,
        mass_reroll_sources: nil, nudge_sources: nil,
        stub_id: 'save-bleed-t2-noluck'
      },
      {
        creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
        affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                      potency: 15, inflicter_tier: 2 },
        save_dice: 7, save_tn: 7, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: [ash_luck], reroll_label: 'Luck',
        mass_reroll_sources: nil,
        nudge_sources: [selka_blessing], nudge_label: 'Blessing',
        stub_id: 'save-bleed-t2-blessing'
      }
    ]
  end
end
