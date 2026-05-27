module Status
  # Sample Rolls for the Dice Resolution sub-view of the Status page.
  # Each entry exercises a distinct variant of the Roll Resolution Stub
  # (no reroll, reroll, nudge, mass-reroll positive, mass-reroll negative).
  module SampleRolls
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
          dice_count: 8, tn: 3, starting_value: 2,
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
  end
end
