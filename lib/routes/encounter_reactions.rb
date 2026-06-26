# Encounter roll-table reaction helpers: which Combatants can answer an attack
# with an equipped/class Roll-Table ability, and the builder blob for channeling
# one. Extracted from routes/encounter.rb; a separate `helpers do` block.
helpers do
  def equipped_granted_abilities(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.select(&:equipped).flat_map do |s|
      it = cat.item_type(s.item_type)
      Array(it && it[:definition] && it[:definition]['grants']).map do |g|
        (g.is_a?(Hash) ? g['ability'] : g).to_s
      end
    end.reject(&:empty?).uniq
  rescue StandardError
    []
  end

  def roll_table_reaction_for(acc, creature_id)
    equipped_granted_abilities(creature_id).each do |name|
      table = Abilities.roll_table_for(name) or next
      return { ability: name, table: table, source: 'item', skill: 'evocation' }
    end
    (acc&.granted_abilities rescue []).each do |g|
      table = Abilities.roll_table_for(g[:name]) or next
      skill = g[:source].to_s.start_with?('class:') ? 'invocation' : 'evocation'
      return { ability: g[:name], table: table, source: 'class', skill: skill }
    end
    nil
  end

  def roll_table_reaction_channelers(attacker_id)
    rmin = Encounter::Config.reaction_action_minimum
    encounter_state.combatants.filter_map do |c|
      next if c[:id] == attacker_id
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next unless acc
      found = roll_table_reaction_for(acc, c[:creature_id]) or next
      pool  = (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0
      ri    = roll_inputs_for(acc, found[:skill])
      cost  = reaction_mana_cost(found[:ability])
      mana_left = combatant_mana_left(c[:creature_id], acc)
      afford_pool = pool >= rmin
      afford_mana = mana_left.nil? || mana_left >= cost
      { combatant_id: c[:id], name: tracker_name(c), ability: found[:ability],
        table: found[:table], source: found[:source], skill: found[:skill],
        skill_label: Encounter::Special.pretty_skill(found[:skill]), dice_cap: ri[:dice_cap].to_i,
        mana_cost: cost, pool: pool,
        disabled: !(afford_pool && afford_mana),
        disabled_reason: (!afford_pool ? 'not enough Combat Pool' : (!afford_mana ? 'not enough Mana' : nil)) }
    end
  end

  def roll_table_channel_info(acc, creature_id)
    found = roll_table_reaction_for(acc, creature_id) || { skill: 'evocation' }
    ri    = roll_inputs_for(acc, found[:skill])
    bpl   = []
    bpl << ri[:competency_modifier] if ri[:competency_modifier]
    tier  = (acc&.tier rescue nil)
    bpl << ['Inherent', tier.to_i] if tier.to_i.positive?
    { skill: found[:skill], dice_cap: ri[:dice_cap].to_i, tier: tier, bpl: bpl }
  end

  def roll_table_check_info(combatant)
    acc  = Creatures.lookup(combatant[:creature_id]) rescue nil
    info = roll_table_channel_info(acc, combatant[:creature_id])
    { skill_label: Encounter::Special.pretty_skill(info[:skill]),
      modifiers: info[:bpl].map { |type, amt| { type: type.to_s, amount: amt.to_i } } }
  end

  def roll_table_builder_blob(combatant, ability_name)
    acc     = Creatures.lookup(combatant[:creature_id]) rescue nil
    die     = DiceResolution.config.die_size
    base_tn = DiceResolution.config.base_target_number
    pool    = (encounter_state.combat_pool_remaining(combatant[:id]) rescue 0) || 0
    rmin    = Encounter::Config.reaction_action_minimum
    info    = roll_table_channel_info(acc, combatant[:creature_id])
    skill   = info[:skill]
    bpl     = info[:bpl]
    tier    = info[:tier]

    rolls = [{ id: 'channel', side: 'supporting', creature_name: tracker_name(combatant),
               roll_name: ability_name, die_size: die, tn: base_tn, starting_value: 0,
               base_tn: base_tn, bonus_penalty_list: bpl, dice_count: rmin, speed: 0, excluded: false,
               tier: tier }]

    upper = info[:dice_cap].positive? ? [info[:dice_cap], pool].min : pool
    upper = [upper, rmin].max
    set   = ->(n) { { set_dice: [{ id: 'channel', count: n }] } }
    label = Encounter::Special.pretty_skill(skill)
    opts  = [{ value: upper, key: 'dice', group: 'dice', label: label,
               summary: "#{label} — #{upper} dice", patch: set.call(upper) }]
    (rmin..upper).each { |n| opts << { value: n, key: 'dice', group: 'dice', label: n.to_s,
                                       summary: "#{n} dice", patch: set.call(n) } }
    steps = [{ key: 'dice', label: 'Channel dice', options: opts,
               header_options: [{ value: upper, label: label }] }]

    { title: "#{tracker_name(combatant)} — #{ability_name}",
      stub_id: "roll-table-#{combatant[:id]}", rolls: rolls, steps: steps }
  end
end
