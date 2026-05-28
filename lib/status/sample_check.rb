module Status
  # Sample Check (one Rolls wrapper with multiple Rolls, separated into
  # Supporting and Opposing groups) for the Check Resolution sub-view of
  # the Status page.
  module SampleCheck
    module_function

    def check
      {
        supporting: [
          {
            creature_name: 'Bryn Ironvein',
            roll_name: 'Attack (Longsword)',
            dice_count: 8, tn: 3, starting_value: 1,
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
  end
end
