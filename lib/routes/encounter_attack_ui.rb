# Encounter attack UI: the Attack Action-Builder blob, Luck steps, and the
# attack-payload enrichment / defender-reaction helpers. Extracted from
# routes/encounter.rb (a separate, accumulating helpers block).
helpers do
  def active_spell_strikes(combatant)
    Array(combatant[:concentration]).select { |e| e[:mode] == 'auto' && e[:reservoir].to_i.positive? }
  end

  def attack_builder_blob(attacker, active_spells: false)
    acc      = Creatures.lookup(attacker[:creature_id]) rescue nil
    die      = DiceResolution.config.die_size
    base_tn  = DiceResolution.config.base_target_number
    atk_pool = (encounter_state.combat_pool_remaining(attacker[:id]) rescue 0) || 0
    atk_tier = (acc&.tier rescue 0) || 0
    # Inherent / Ascendancy Tier modifiers on the attack check read the
    # Creatures Tier Minimum Inherent Bonus table.
    inh_table = (Creatures::Config.tier_minimum_inherent_bonus rescue [])

    # Display the character's own Bonus/Penalty list (natural signs). TNs are
    # NOT computed here — the builder hands raw Bonus lists to Check Resolution,
    # which applies cross-side propagation and computes every TN itself.
    fmt_mods = ->(list) { list.map { |type, amt| "#{amt >= 0 ? '+' : ''}#{amt} #{type}" }.join(' ') }

    weapons = active_spells ? [] : equipped_weapons(attacker[:creature_id]).map do |w|
      attr = w[:ranged] ? :dex : :str
      ri   = roll_inputs_for(acc, 'martial', attribute_override: attr)
      w.merge(dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier])
    end

    if active_spells
      active_spell_strikes(attacker).each do |sw|
        weapons << { item_type: 'spiritual_weapon', display_name: sw[:spell_name].to_s, ranged: false,
                     speed: 0, damage_types: ['force'], threshold: 0, bleed: 0, base_damage: 0,
                     dice_cap: sw[:reservoir].to_i, competency: nil }
      end
    end

    atk_tier = (acc&.tier rescue nil)

    targets = encounter_state.combatants.reject { |c| c[:id] == attacker[:id] }.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      tname = tracker_name(c)
      { id: c[:id], creature_id: c[:creature_id], name: tname,
        display_name: tname + target_status_suffix(c[:id], c[:creature_id]),
        unaware: encounter_state.unaware?(c[:id]),
        flatfooted_immune: flatfooted_immune?(tacc),
        helpless: !(encounter_state.creature_can_act?(c[:id]) rescue true),
        dying: (encounter_state.creature_dying?(c[:id]) rescue false),
        is_pc: creature_is_pc?(c[:creature_id]),
        category: (creature_is_pc?(c[:creature_id]) ? 'pc' : (((tacc&.group rescue nil) == 'npc') ? 'npc' : 'enemy')),
        tier: (tacc&.tier rescue 0) || 0,
        pool: (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0,
        martial: roll_inputs_for(tacc, 'martial',   attribute_override: :str),
        dodge:   roll_inputs_for(tacc, 'dex_save', attribute_override: :dex),
        parry_weapons: equipped_melee_weapons(c[:creature_id]),
        has_shield:    equipped_shield?(c[:creature_id]),
        ring_parry:    ring_parry_available?(c[:creature_id]),
        abilities: ((tacc&.granted_abilities rescue nil) || []).map { |g| g[:name] },
        mana_left: combatant_mana_left(c[:creature_id], tacc),
        raging:    creature_raging?(c[:creature_id]) }
    end

    rolls = [
      { id: 'attacker', side: 'supporting', creature_name: tracker_name(attacker),
        roll_name: 'Attack', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 2, speed: 0, excluded: false },
      { id: 'defender', side: 'opposing', creature_name: '—',
        roll_name: 'Defense', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true },
      { id: 'shield', side: 'opposing', creature_name: '—',
        roll_name: 'Shield of Faith', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true }
    ]

    shields = {}
    encounter_state.granted_actions.select { |g| g[:defends] }.each do |g|
      cc = encounter_state.combatant(g[:combatant_id]) or next
      source = (g[:dice_source] || 'reservoir').to_s
      available =
        if source == 'combat_pool'
          (encounter_state.combat_pool_remaining(g[:combatant_id]) rescue 0).to_i
        else
          res = Array(cc[:concentration]).find { |e| e[:mode] == 'reservoir' && e[:spell_name].to_s == g[:spell_name].to_s }
          res ? res[:reservoir].to_i : 0
        end
      next unless available >= 2
      cacc = Creatures.lookup(cc[:creature_id]) rescue nil
      shield_skill = cacc ? (cast_skill_for(cacc, nil, g[:spell_name]) rescue nil) : nil
      shield_comp  = shield_skill ? roll_inputs_for(cacc, shield_skill)[:competency_modifier] : nil
      shields[g[:defends]] = { caster_id: g[:combatant_id], caster_name: tracker_name(cc),
                               available: available, dice_source: source, dice_cap: g[:dice_cap].to_i,
                               tier: (cacc&.tier rescue nil), spell_name: g[:spell_name].to_s,
                               bonus: g[:shield_bonus].to_i, competency: shield_comp }
    end

    attacker_pc   = creature_is_pc?(attacker[:creature_id])
    enemy_targets = targets.select { |t| t[:is_pc] != attacker_pc }
    enemy_targets = enemy_targets.reject { |t| encounter_state.creature_dying?(t[:id]) rescue false }
    enemy_targets = order_targets_by_distance(attacker, enemy_targets)
    header_targets = enemy_targets.first(5)
    target_step = { key: 'target', label: 'Target',
                    header_options: header_targets.map { |t| { value: t[:id], label: t[:display_name] } },
                    options: target_options(encounter_state.combatants.reject { |c| c[:id] == attacker[:id] },
                                            roll_id: 'defender') }

    action_opts = []
    action_quick = []
    weapons.each do |w|
      cap   = w[:dice_cap]
      speed = [w[:speed].to_i, 0].max
      disp  = w[:display_name]
      grp   = w[:item_type]
      bpl   = w[:competency] ? [w[:competency]] : []
      set_atk = lambda do |dice|
        { set_dice: [{ id: 'attacker', count: dice }], set_speed: [{ id: 'attacker', speed: speed }],
          set_bpl: [{ id: 'attacker', bonus_penalty_list: bpl }] }
      end
      free = w[:item_type] == 'spiritual_weapon'
      g = dice_count_group(prefix: w[:item_type], key: w[:item_type], group: grp, min: 2, max: cap,
                           aff: ->(n) { free || speed + n <= atk_pool }, patch: set_atk,
                           summary: ->(n) { "#{disp} — #{n} dice" }, lead_label: "#{disp} (speed #{speed})",
                           header_label: disp, info: (bpl.empty? ? 'no bonuses' : fmt_mods.call(bpl)))
      action_opts.concat(g[:body])
      action_quick << g[:header]
    end
    action_step = { key: 'action', label: 'Weapon & dice', options: action_opts, header_options: action_quick }

    defense_map = {}
    defense_header_map = {}
    targets.each do |t|
      weapons.each do |w|
        comp = w[:competency] ? [w[:competency]] : []
        atk_tier_none = Encounter::Attack.attacker_tier_bonuses(
          attacker_tier: atk_tier, defender_tier: t[:tier], tier_advantage: w[:tier_advantage],
          inherent_table: inh_table, no_defense: true
        )
        def_tier = Encounter::Attack.defender_tier_bonuses(defender_tier: t[:tier], inherent_table: inh_table)
        atk_tier_def = Encounter::Attack.attacker_tier_bonuses(
          attacker_tier: atk_tier, defender_tier: t[:tier], tier_advantage: w[:tier_advantage],
          inherent_table: inh_table, no_defense: false
        )
        atk_none_bpl     = comp + atk_tier_none + Encounter::Attack.attacker_bonuses(
          flatfooted: !t[:flatfooted_immune], unaware: t[:unaware] && !t[:flatfooted_immune], helpless: t[:helpless])
        opts = [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                  patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_none_bpl }],
                           restore_dice: [{ id: 'attacker' }],
                           set_excluded: [{ id: 'defender', excluded: true }] } }]
        headers = [{ value: 'none', label: 'No defense' }]
        branches = []
        unless t[:helpless]
          branches << { key: 'dodge', group: 'dodge', name: 'Dodge', inputs: t[:dodge], speed: 0 }
          if t[:has_shield]
            branches << { key: 'block', group: 'block', name: 'Block', inputs: t[:martial], speed: 0 }
          end
          unless w[:ranged]
            t[:parry_weapons].each do |pw|
              branches << { key: "parry:#{pw[:item_type]}", group: "parry:#{pw[:item_type]}",
                            name: "Parry with #{pw[:display_name]}", inputs: t[:martial],
                            speed: [pw[:speed].to_i, 0].max }
            end
            if t[:ring_parry]
              t[:parry_weapons].each do |pw|
                branches << { key: "ringparry:#{pw[:item_type]}", group: "ringparry:#{pw[:item_type]}",
                              name: "Ring of Parry (#{pw[:display_name]})", inputs: t[:martial],
                              speed: 0, free: true }
              end
            end
          end
        end

        branches.each do |b|
          di    = b[:inputs]
          dcmp  = (di[:competency_modifier] ? [di[:competency_modifier]] : []) + def_tier
          cap   = di[:dice_cap].to_i
          dspd  = b[:speed]
          atk_branch_bpl = comp + atk_tier_def + Encounter::Attack.attacker_bonuses(
            flatfooted: (b[:key] != 'dodge') && !t[:flatfooted_immune], unaware: false, helpless: t[:helpless])
          def_no_prop = b[:key] == 'dodge' ? ['Competency'] : []
          mk = lambda do |dice, label, disabled|
            { value: "#{b[:key]}|#{dice}", group: b[:group], label: label,
              summary: "#{b[:name]} — #{dice} dice", disabled: disabled,
              patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_branch_bpl },
                                 { id: 'defender', bonus_penalty_list: dcmp }],
                       set_no_propagate: [{ id: 'defender', types: def_no_prop }],
                       restore_dice: [{ id: 'attacker' }],
                       set_dice:  [{ id: 'defender', count: dice }],
                       set_speed: [{ id: 'defender', speed: dspd }],
                       set_name:  [{ id: 'defender', roll_name: b[:name] }],
                       set_excluded: [{ id: 'defender', excluded: false }] } }
          end
          if b[:free]
            opts << mk.call(cap, "#{b[:name]} — #{cap} dice, free", cap < 1)
            headers << { value: "#{b[:key]}|#{cap}", label: b[:name], disabled: cap < 1 }
            opts << { kind: 'info', group: b[:group], value: "#{b[:group]}|info",
                      label: (dcmp.empty? ? 'no Combat Pool' : "#{fmt_mods.call(dcmp)} · no Combat Pool") }
            next
          end
          name_label = "#{b[:name]} (speed #{dspd})"
          aff_max = (2..cap).select { |n| dspd + n <= t[:pool] }.max
          opts << mk.call(aff_max || cap, name_label, aff_max.nil?)
          (2..cap).each { |n| opts << mk.call(n, n.to_s, dspd + n > t[:pool]) }
          hmin = Encounter::Config.reaction_action_minimum
          headers << { value: "#{b[:key]}|#{hmin}", label: b[:name],
                       disabled: (hmin > cap || dspd + hmin > t[:pool]) }
          opts << { kind: 'info', group: b[:group], value: "#{b[:group]}|info",
                    label: (dcmp.empty? ? 'no bonuses' : fmt_mods.call(dcmp)) }
        end
        if t[:abilities].include?('Better Lucky Than Good')
          bl_cost = reaction_mana_cost('Better Lucky Than Good')
          bl_cost = 4 if bl_cost.zero?
          bl_afford = t[:mana_left].nil? || t[:mana_left] >= bl_cost
          opts << { value: 'better_lucky', group: 'better_lucky',
                    label: "Better Lucky Than Good (#{bl_cost} mana)",
                    summary: 'Better Lucky Than Good', disabled: !bl_afford,
                    patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_none_bpl }],
                             scale_dice: [{ id: 'attacker', num: 1, den: 2, min: 3 }],
                             set_excluded: [{ id: 'defender', excluded: true }] } }
          headers << { value: 'better_lucky', label: 'Better Lucky', disabled: !bl_afford }
        end
        defense_map["#{t[:id]}|#{w[:item_type]}"] = opts
        defense_header_map["#{t[:id]}|#{w[:item_type]}"] = headers
      end
    end
    defense_step = { key: 'defense', label: 'Target&rsquo;s defense',
                     options_by: %w[target action], options_map: defense_map,
                     header_options_by: %w[target action], header_options_map: defense_header_map }

    ally_defense_map = {}
    ally_defense_header_map = {}
    shields.each do |target_id, sh|
      dcap = sh[:dice_cap].to_i.positive? ? sh[:dice_cap].to_i : sh[:available]
      cap  = [sh[:available], dcap].min
      dice_word = sh[:dice_source] == 'combat_pool' ? 'Combat Pool' : 'Reservoir'
      sh_bpl = []
      sh_bpl << sh[:competency] if sh[:competency]
      sh_bpl << ['Inherent', Encounter::Attack.inherent_amount(inh_table, sh[:tier].to_i)]
      sh_bpl << ['Guidance', sh[:bonus].to_i] if sh[:bonus].to_i.positive?
      shield_patch = lambda do |dice|
        { set_dice: [{ id: 'shield', count: dice }],
          set_bpl:  [{ id: 'shield', bonus_penalty_list: sh_bpl }],
          set_name: [{ id: 'shield', creature_name: sh[:caster_name], roll_name: sh[:spell_name] }],
          set_excluded: [{ id: 'shield', excluded: false }] }
      end
      bonus_note = sh[:bonus].to_i.positive? ? " (+#{sh[:bonus].to_i})" : ''
      g = dice_count_group(prefix: "shield:#{sh[:caster_id]}", group: 'shield', min: 2, max: cap,
                           aff: ->(_n) { true }, patch: shield_patch, header_label: sh[:spell_name],
                           summary: ->(n) { "#{sh[:spell_name]} (#{sh[:caster_name]}) — #{n} dice" },
                           info: "#{sh[:spell_name]}#{bonus_note} by #{sh[:caster_name]} — up to #{cap} #{dice_word} dice")
      ally_defense_map["#{target_id}"] =
        [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
           patch: { set_excluded: [{ id: 'shield', excluded: true }] } }] + g[:body]
      ally_defense_header_map["#{target_id}"] = [{ value: 'none', label: 'No defense' }, g[:header]]
    end
    ally_defense_step = { key: 'ally_defense', label: 'Ally Defense',
                          options_by: %w[target], options_map: ally_defense_map,
                          header_options_by: %w[target], header_options_map: ally_defense_header_map }

    steps = [target_step, action_step, defense_step, ally_defense_step]

    steps.concat(luck_steps(actor_id: attacker[:id],
                            targets: [{ roll_id: 'attacker', label: tracker_name(attacker) },
                                      { roll_id: 'defender', label: 'Defender' },
                                      { roll_id: 'shield', label: 'Ally shield' }]))

    { title: "#{tracker_name(attacker)} attacks", stub_id: "attack-#{attacker[:id]}",
      rolls: rolls, steps: steps }
  end

  def luck_steps(actor_id:, targets:)
    steps = []
    encounter_state.combatants.each do |c|
      next if c[:id] == actor_id # a Reaction can't fire on your own action
      entry = Array(c[:concentration]).find do |e|
        e[:mode] == 'reservoir' && e[:reservoir].to_i.positive? && luck_reservoir?(e)
      end
      next unless entry
      steps << luck_step("#{c[:id]}", c[:id], tracker_name(c), entry[:reservoir].to_i,
                         bard_has_unsettling_words?(c[:creature_id]), targets)
    end
    if encounter_state.dm_luck_points.to_i.positive?
      steps << luck_step('dm', nil, 'DM', encounter_state.dm_luck_points.to_i, true, targets)
    end
    steps
  end

  def luck_reservoir?(entry)
    v = resolve_named_spell(entry[:spell_name])
    v.dig('reservoir', 'discharge', 'defends').to_s.empty?
  rescue StandardError
    true
  end

  def luck_step(sid, source_id, label, amount, penalty, targets)
    { key: "luck:#{sid}", label: 'Luck', dynamic: 'luck', heading: label,
      header_options: [{ value: "#{sid}|none", label: 'No luck' }],
      luck: { source: { id: source_id, sid: sid, label: label, amount: amount, penalty: penalty },
              targets: targets } }
  end

  def creature_is_pc?(creature_id)
    acc = Creatures.lookup(creature_id) rescue nil
    !!(acc && Array(acc.tags).include?('player_character'))
  rescue StandardError
    false
  end

  def bard_has_unsettling_words?(creature_id)
    acc = Creatures.lookup(creature_id) rescue nil
    return false unless acc.respond_to?(:granted_abilities)
    acc.granted_abilities.any? { |g| g[:name].to_s == 'unsettling_words' }
  rescue StandardError
    false
  end

  def enrich_attack_payload!(payload)
    enrich_attack_reactions!(payload)

    sh = payload['shield']
    if sh.is_a?(Hash) && sh['id']
      g = encounter_state.granted_actions.find { |x| x[:combatant_id] == sh['id'] && x[:defends] }
      if g
        sh['spell_name']  = g[:spell_name].to_s
        sh['dice_source'] = (g[:dice_source] || 'reservoir').to_s
      end
    end

    wt  = payload['weapon_type']
    atk = payload['attacker'] || {}
    return unless wt && atk['id']
    if wt == 'spiritual_weapon'
      payload['attack_kind'] ||= 'ranged'
      atk['speed'] = 0
      payload['attacker'] = atk
      payload['weapon'] = { 'damage_types' => ['force'], 'threshold' => 0, 'bleed' => 0, 'base_damage' => 0 }
      payload['free_attacker_pool'] = true
      return
    end
    combatant = encounter_state.combatant(atk['id'].to_i) or return
    w = equipped_weapons(combatant[:creature_id]).find { |x| x[:item_type] == wt } or return
    acc = Creatures.lookup(combatant[:creature_id]) rescue nil
    payload['attack_kind'] ||= w[:ranged] ? 'ranged' : 'melee'
    atk['speed'] = w[:speed]
    payload['attacker'] = atk
    payload['weapon'] = { 'damage_types' => w[:damage_types], 'threshold' => w[:threshold],
                          'bleed' => w[:bleed], 'affliction' => w[:affliction],
                          'affliction_potency' => w[:affliction_potency],
                          'base_damage' => evaluate_weapon_damage(w[:damage_formula], acc),
                          'damage_riders' => w[:damage_riders], 'tier_advantage' => w[:tier_advantage] }
  end

  POST_ROLL_REACTIONS = {
    'danger_sense'    => 'Danger Sense',
    'primal_tenacity' => 'Primal Tenacity'
  }.freeze

  def attach_defender_reactions(result, payload)
    return result if result[:ok] == false
    return result unless result[:damage].to_i.positive?
    choice = (payload['defense'] || {})['choice'].to_s
    return result unless choice.empty? || choice == 'none'
    c   = encounter_state.combatant(payload['target_id'].to_i) or return result
    acc = Creatures.lookup(c[:creature_id]) rescue nil
    abilities = (acc&.granted_abilities rescue []).map { |g| g[:name] }
    mana_left = combatant_mana_left(c[:creature_id], acc)
    raging    = creature_raging?(c[:creature_id])
    avail = POST_ROLL_REACTIONS.filter_map do |key, name|
      next unless abilities.include?(name)
      next if name == 'Primal Tenacity' && !raging
      cost = reaction_mana_cost(name); cost = 4 if cost.zero?
      next unless mana_left.nil? || mana_left >= cost
      mod = Array((Abilities.catalog.ability(name) rescue nil)&.dig('modifiers')).first || {}
      { key: key, name: name, mana_cost: cost, label: "#{name} (#{cost} mana)",
        target: mod['target'].to_s, type: mod['type'].to_s, amount: mod['add'].to_i }
    end
    result.merge(defender_reactions_available: avail)
  end

  def enrich_attack_reactions!(payload)
    dfn = payload['defense']
    if dfn.is_a?(Hash) && dfn['choice'].to_s == 'better_lucky'
      cost = reaction_mana_cost('Better Lucky Than Good')
      dfn['mana_cost'] = cost.zero? ? 4 : cost
    end
    keys = Array(payload['defender_reactions'])
    return if keys.empty?
    payload['defender_reactions'] = keys.filter_map do |key|
      name = POST_ROLL_REACTIONS[key.to_s] or next
      mod  = Array((Abilities.catalog.ability(name) rescue nil)&.dig('modifiers')).first || {}
      cost = reaction_mana_cost(name)
      { 'key' => key.to_s, 'name' => name, 'mana_cost' => (cost.zero? ? 4 : cost),
        'target' => mod['target'].to_s, 'type' => mod['type'].to_s, 'amount' => mod['add'].to_i }
    end
  end

end
