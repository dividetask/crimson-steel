# Encounter affliction helpers: the out-of-combat Affliction relief stub
# (per-creature cards + Heal-channeler aiders) and the server-side save roller.
# Extracted from routes/encounter.rb; a separate `helpers do` block on the
# same app.
helpers do
  def urgent_action_groups
    encounter_state.combatants.filter_map do |c|
      saves = start_of_turn_saves(c)
      next nil if saves.empty?
      { combatant_id: c[:id], creature_id: c[:creature_id],
        name: tracker_name(c), is_pc: creature_is_pc?(c[:creature_id]),
        saves: saves }
    end
  end

  def affliction_relief_groups
    aiders = heal_aider_candidates
    encounter_state.combatants.filter_map do |c|
      acc  = (Creatures.lookup(c[:creature_id]) rescue nil)
      inst = Conditions.store.instance_for(c[:creature_id])
      afflictions = inst.state.afflictions.filter_map do |name, entry|
        rule = (inst.catalog.affliction(name) rescue nil)
        next nil unless rule && rule['effect']
        next nil unless (rule['save_frequency'] || 'round').to_s == 'round'
        relief_affliction_blob(acc, inst, name, rule, entry)
      end
      next nil if afflictions.empty?
      { combatant_id: c[:id], creature_id: c[:creature_id],
        name: tracker_name(c), is_pc: creature_is_pc?(c[:creature_id]),
        afflictions: afflictions, aiders: aiders }
    end
  end

  def relief_affliction_blob(acc, inst, name, rule, entry)
    attr = (rule['save'] || 'con').to_s
    ri   = roll_inputs_for(acc, "#{attr}_save", attribute_override: attr.to_sym)
    save_mods = []
    save_mods << ri[:competency_modifier] if ri[:competency_modifier]
    if acc
      category = (rule['category'] || 'other').to_s
      CreatureModifiers.save_modifiers(acc, attr, descriptors: [category]).each { |p| save_mods << p }
    end
    { name: name, category: (rule['category'] || 'other').to_s,
      potency: entry[:potency].to_i, save_attr: attr,
      save: { save_dice: ri[:dice_cap].to_i, die_size: DiceResolution.config.die_size,
              save_modifiers: save_mods, potency_divisor: inst.catalog.potency_divisor,
              creature_tier: (acc&.tier rescue 0) || 0,
              inflicter_tier: entry[:inflicting_tier].to_i } }
  end

  def heal_aider_candidates
    encounter_state.combatants.filter_map do |c|
      acc   = (Creatures.lookup(c[:creature_id]) rescue nil) or next nil
      tiers = heal_caster_tiers(acc)
      next nil if tiers.empty?
      ri = roll_inputs_for(acc, 'healing')
      { creature_id: c[:creature_id], name: tracker_name(c), tiers: tiers,
        heal_dice: ri[:dice_cap].to_i, channeling: aider_channeling_heal?(c) }
    end
  end

  def heal_caster_tiers(acc)
    return [] unless acc
    cap  = (acc.tier rescue 0).to_i
    keys = (acc.granted_abilities rescue []).map { |g| g[:name] }
    keys.filter_map do |k|
      info = CreatureSheet.spell_info(k)
      info[:tier] if info && info[:base].to_s.casecmp?('Heal') && info[:tier].to_i <= cap
    end.uniq.sort
  end

  def aider_channeling_heal?(combatant)
    Array(combatant[:concentration]).any? do |e|
      ((e[:spell_name] || e['spell_name']).to_s.casecmp?('Heal'))
    end
  rescue StandardError
    false
  end

  ROLL_CRITICAL_MODIFIER = 2
  ROLL_FAILURE_MODIFIER  = -1
  def roll_affliction_save_dois(save)
    potency        = save[:affliction][:potency].to_i
    divisor        = save[:potency_divisor].to_i
    creature_tier  = save[:creature][:tier].to_i
    inflicter_tier = save[:affliction][:inflicter_tier].to_i
    potency_penalty = divisor.positive? ? potency / divisor : 0

    list = Array(save[:save_modifiers]).map do |m|
      m.is_a?(Array) ? m : [m[:type] || m['type'], m[:amount] || m['amount']]
    end
    list << ['Inherent', creature_tier] if creature_tier.positive?
    list << ['Competency', -potency_penalty] if potency_penalty.positive?
    list << ['Inherent', -inflicter_tier]

    calc = DiceResolution.compute_target_number(list)
    tn   = calc[:tn]
    die  = save[:die_size].to_i
    dice = Array.new(save[:save_dice].to_i) { rand(1..die) }
    calc[:starting_value] + dice.sum do |v|
      if    v == die then ROLL_CRITICAL_MODIFIER
      elsif v == 1   then ROLL_FAILURE_MODIFIER
      elsif v >= tn  then 1
      else 0
      end
    end
  end
end
