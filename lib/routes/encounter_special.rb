# Encounter special-performance helpers: the Action Builder blob for channeling
# a Special (Bardic Inspiration etc.) and the channel Dice-Cap guard. Extracted
# from routes/encounter.rb; a separate `helpers do` block.
helpers do
  def special_builder_blob(combatant, ability_name)
    acc     = Creatures.lookup(combatant[:creature_id]) rescue nil
    die     = DiceResolution.config.die_size
    base_tn = DiceResolution.config.base_target_number
    pool    = (encounter_state.combat_pool_remaining(combatant[:id]) rescue 0) || 0
    min     = Encounter::Config.main_action_minimum

    raw   = Abilities.catalog.ability(ability_name)
    ratio = (raw && raw.dig('reservoir', 'fill', 'ratio')) || 1
    # A check-based channel (fill source check_successes, e.g. Bardic
    # Inspiration) rolls a real skill Check, so it obeys the skill's Dice Cap.
    check_channel = Encounter::Special.check_channel?(raw)
    skills = Encounter::Special.check_skills(acc, raw)

    rolls = [{ id: 'performance', side: 'supporting', creature_name: tracker_name(combatant),
               roll_name: ability_name, die_size: die, tn: base_tn, starting_value: 0,
               base_tn: base_tn, bonus_penalty_list: [], dice_count: min, speed: 0, excluded: false }]

    dice_for = lambda do |skill_label, dice_cap|
      upper = (check_channel && dice_cap.to_i.positive?) ? [dice_cap.to_i, pool].min : pool
      upper = [upper, min].max
      set   = ->(n) { { set_dice: [{ id: 'performance', count: n }] } }
      opts  = [{ value: upper, key: 'dice', group: 'dice', label: skill_label,
                 summary: "#{skill_label} — #{upper} dice", patch: set.call(upper) }]
      (min..upper).each { |n| opts << { value: n, key: 'dice', group: 'dice', label: n.to_s,
                                        summary: "#{n} dice", patch: set.call(n) } }
      { options: opts, header: { value: upper, label: skill_label } }
    end

    steps = []
    perform_skill = nil
    if check_channel && skills.length > 1
      # Several trained Performance skills — ask which (its Competency rides the
      # Roll; its Dice Cap bounds the choice-dependent Dice step).
      perf_opts = skills.map do |s|
        { value: s[:key], key: s[:key], label: s[:label], summary: s[:label],
          patch: { set_bpl: [{ id: 'performance',
                               bonus_penalty_list: ([s[:competency]] + Array(s[:modifiers])).compact }] } }
      end
      steps << { key: 'performance', label: 'Performance', options: perf_opts }
      dice_map = {}
      header_map = {}
      skills.each do |s|
        d = dice_for.call(s[:label], s[:dice_cap])
        dice_map[s[:key]]   = d[:options]
        header_map[s[:key]] = [d[:header]]
      end
      steps << { key: 'dice', label: 'Channel dice', options_by: %w[performance], options_map: dice_map,
                 header_options_by: %w[performance], header_options_map: header_map }
    else
      skill = skills.first
      perform_skill = skill && skill[:key]
      rolls[0][:bonus_penalty_list] = skill ? ([skill[:competency]] + Array(skill[:modifiers])).compact : []
      d = dice_for.call((skill ? skill[:label] : ability_name), skill ? skill[:dice_cap] : 0)
      steps << { key: 'dice', label: 'Channel dice', options: d[:options], header_options: [d[:header]] }
    end

    steps.concat(luck_steps(actor_id: combatant[:id],
                            targets: [{ roll_id: 'performance', label: tracker_name(combatant) }]))

    { title: "#{tracker_name(combatant)} — #{ability_name}", stub_id: "special-#{combatant[:id]}",
      reservoir_ratio: ratio, perform_skill: perform_skill, rolls: rolls, steps: steps }
  end

  def channel_dice_cap_error(payload)
    raw = Abilities.catalog.ability(payload['ability'].to_s) or return nil
    return nil unless Encounter::Special.check_channel?(raw)
    dice = payload['dice'].to_i
    return nil unless dice.positive?
    combatant = encounter_state.combatant(payload['combatant_id'].to_i) or return nil
    acc = (Creatures.lookup(combatant[:creature_id]) rescue nil)
    cap = Encounter::Special.check_skills(acc, raw).map { |s| s[:dice_cap] }.max.to_i
    return nil unless cap.positive?
    dice > cap ? "Performance check cannot roll more than the Dice Cap (#{cap})" : nil
  end
end
