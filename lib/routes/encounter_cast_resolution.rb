# Encounter cast resolution: applying a resolved Cast — routing effects,
# placing area zones, registering sustains, consuming cast items. Extracted
# from routes/encounter.rb (a separate, accumulating helpers block).
helpers do
  def spell_base_axis(name)
    info = (CreatureSheet.spell_info(name) rescue nil)
    return [info[:base], info[:axis].to_i] if info && info[:base]
    [name.to_s, 0]
  end

  def resolve_named_spell(name)
    base, axis = spell_base_axis(name)
    (Abilities.lookup(base, axis_index: axis) rescue nil) || {}
  rescue StandardError
    {}
  end

  def dice_count_group(prefix:, group:, min:, max:, aff:, patch:, summary:,
                       header_label:, info: nil, key: nil, lead_label: nil, header_min: false)
    aff_max = (min..max).select { |n| aff.call(n) }.max
    opt = lambda do |dice, label, disabled|
      o = { value: "#{prefix}|#{dice}", group: group, label: label,
            summary: summary.call(dice), disabled: disabled, patch: patch.call(dice) }
      o[:key] = key unless key.nil?
      o
    end
    body = []
    body << opt.call(aff_max || max, lead_label, aff_max.nil?) if lead_label
    (min..max).each { |n| body << opt.call(n, n.to_s, !aff.call(n)) }
    # Optional trailing note (e.g. an Attack's weapon bonuses). Omitted when empty.
    body << { kind: 'info', group: group, value: "#{group}|info", label: info } if info && !info.to_s.empty?
    hdice = header_min ? min : (aff_max || max)
    { body: body, header: { value: "#{prefix}|#{hdice}", label: header_label,
                            disabled: (header_min ? !aff.call(min) : aff_max.nil?) } }
  end

  def spell_defends_spec(v)
    return { block_dice: 'reservoir' } if v.dig('reservoir', 'discharge', 'defends').to_s == 'target'
    d = v['defends']
    return { block_dice: (d['block_dice'] || 'combat_pool').to_s } if d.is_a?(Hash)
    { block_dice: 'combat_pool' } if d.to_s == 'target'
  end

  # The per-Tier Mana Cost (abilities_config.yaml → Mana Cost Per Tier).
  def mana_cost_for_tier(tier)
    tbl = (Abilities.catalog.config.mana_cost_per_tier rescue {})
    (tbl[tier] || tbl[tier.to_s] || tbl[tier.to_i] || 0).to_i
  end

  def enrich_cast_payload!(payload)
    spell  = (payload['spell'] ||= {})
    spell['name'] ||= payload['spell_name']
    caster = payload['caster'] || {}
    # A constructed per-Tier name ("Standard Shield") resolves to its base
    # catalog key + Tier axis so every Abilities lookup below succeeds.
    base_name, = spell_base_axis(spell['name']) if spell['name']

    if (item = payload['item']) && spell['name']
      spell['mana_cost'] = 0
      spell['cast_skill'] ||= item_cast_skill(resolve_named_spell(spell['name']))
      if item['form'].to_s == 'potion'
        ccomb = (encounter_state.combatant(caster['id'].to_i) rescue nil)
        cacc  = ccomb && (Creatures.lookup(ccomb[:creature_id]) rescue nil)
        spell['toxicity'] = (Equipment.instance.item_form_toxicity(
          item_tier: item['tier'].to_i, target_tier: (cacc&.tier rescue nil)) rescue 0)
      end
    end

    # Resolve the caster's own Casting Skill (a Cleric's Invocation) so the
    # casting check rolls that Skill, not the Spell's generic `arcana` default.
    if spell['cast_skill'].nil? && caster['id'] && spell['name']
      ccomb = (encounter_state.combatant(caster['id'].to_i) rescue nil)
      cacc  = ccomb && (Creatures.lookup(ccomb[:creature_id]) rescue nil)
      variant = resolve_named_spell(spell['name'])
      spell['cast_skill'] = cast_skill_for(cacc, variant, spell['name']) if cacc
    end

    if spell['tier'].nil? && spell['name']
      info = (CreatureSheet.spell_info(spell['name']) rescue nil)
      spell['tier'] = info[:tier] if info
    end
    spell['mana_cost'] ||= mana_cost_for_tier(spell['tier']) unless spell['tier'].nil?

    if spell['bleed_reduction'].nil? && base_name
      raw_v   = (Abilities.catalog.ability(base_name) rescue nil) || {}
      formula = raw_v.dig('channel', 'effect_hash', 'bleed_reduction')
      if formula
        tier       = spell['tier'].to_i
        tier_value = tier.zero? ? 0.5 : tier
        succ       = (caster['successes'] || 0).to_i
        amt        = (Abilities::Formula.evaluate(formula.to_s, 'tier' => tier_value, 'success' => succ) rescue 0)
        spell['bleed_reduction'] = [amt.floor, 0].max
      end
    end

    if Abilities.respond_to?(:resolve_spell) && spell['name']
      resolved = (Abilities.resolve_spell(base_name, tier: spell['tier']) rescue nil)
      apply_resolved_spell!(payload, resolved) if resolved
    end
    spell['cast_skill'] ||= Encounter::Cast::DEFAULT_CAST_SKILL

    # Casting-skill Competency also feeds the default Spell-damage formula
    # (floor(stat/4) + Tier + Competency + Successes): Competency applies to
    # both the casting Roll and the damage. Resolve it from the caster + skill.
    if spell['cast_competency'].nil? && caster['id']
      ccomb = (encounter_state.combatant(caster['id'].to_i) rescue nil)
      cacc  = ccomb && (Creatures.lookup(ccomb[:creature_id]) rescue nil)
      comp  = cacc ? roll_inputs_for(cacc, spell['cast_skill'])[:competency_modifier] : nil
      spell['cast_competency'] = comp ? comp[1].to_i : 0
    end
  end

  def apply_resolved_spell!(payload, resolved)
    r = (resolved.transform_keys(&:to_s) rescue {})
    spell = (payload['spell'] ||= {})
    spell['polarity'] = r['polarity'] unless r['polarity'].nil?

    variant = resolve_named_spell(spell['name'])
    spell['cast_skill'] ||= (Array(variant && variant['skills']).first || Encounter::Cast::DEFAULT_CAST_SKILL)

    effects = cast_effects_from_consumption(r['effects'])
    spell['duration'] ||= variant['duration'] if variant && variant['duration']
    spell['temp_hp_condition'] = 'ward' if (spell_base_axis(spell['name']).first rescue nil) == 'Ward'
    if variant && variant['duration']
      effects = effects.map { |e| e['kind'] == 'temp_hp' ? e.merge('duration' => variant['duration']) : e }
    end
    if variant && Array(variant['modifiers']).any?
      effects += [{ 'kind' => 'modifiers', 'modifiers' => variant['modifiers'],
                    'duration' => variant['duration'] }]
    end

    base_name, = spell_base_axis(spell['name']) if spell['name']
    raw_entry = (Abilities.catalog.ability(base_name) rescue nil) || variant || {}
    raw_area  = raw_entry['area']
    area_hash = raw_area.is_a?(Array) ? raw_area.find { |x| x.is_a?(Hash) } : raw_area
    if area_hash.is_a?(Hash) && (oe = Array(area_hash['on_enter']).first)
      fx = oe['fail'].to_s
      effects += [{ 'kind' => 'effect', 'name' => fx }] unless fx.empty? || fx == '0'
    end
    Array(payload['targets']).each { |t| t['effects'] = effects }

    if area_hash.is_a?(Hash)
      spell['area'] = area_hash
      spell['duration'] = variant['duration'] || raw_entry['duration']
    end

    reservoir_channel = %w[reservoir auto].include?((variant && variant.dig('channel', 'mode')).to_s) &&
                        (variant && variant.dig('reservoir', 'fill', 'source')).to_s == 'channel_dice'

    if variant && variant['attack_roll'] && !reservoir_channel
      spell['attack_roll'] = true
      spell['damage_type'] ||= Array(variant['damage_type']).compact.first
      spell['casting_attribute'] ||= (Proficiencies.attribute_for(spell['cast_skill']) || :cha).to_s
    elsif variant && !reservoir_channel && Array(variant['damage_type']).compact.any? && effects.none? { |e| e['kind'] == 'damage' }
      spell['default_damage'] = true
      spell['damage_type'] ||= Array(variant['damage_type']).compact.first
      spell['casting_attribute'] ||= (Proficiencies.attribute_for(spell['cast_skill']) || :cha).to_s
    end

    save_meta = variant && Array(variant['save']).first
    if save_meta
      on_success = spell['default_damage'] ? 'halved' : (save_meta['success'].to_s == 'halved' ? 'halved' : 'none')
      Array(payload['targets']).each do |t|
        next unless t['save']
        t['save']['on_success'] ||= on_success
      end
    end

    if payload['sustain'].nil? && variant && variant['channel']
      sustain = Encounter::Cast.sustain_spec(channel: variant['channel'], reservoir: variant['reservoir'])
      payload['sustain'] = sustain if sustain
    end
  end

  def place_spell_area_zone!(payload)
    spell = payload['spell'] || {}
    area  = spell['area']
    return nil unless area.is_a?(Hash)
    map_id = Atlas.state.active_map_id
    return nil unless map_id
    caster = payload['caster'] || {}
    source_id = "encounter:zone:#{spell['name']}:#{caster['id']}"
    placement = payload['placement']
    anchor =
      if placement && placement['x'] && placement['y']
        { 'type' => 'point', 'x' => placement['x'].to_i, 'y' => placement['y'].to_i }
      else
        target = Array(payload['targets']).first or return nil
        combatant = encounter_state.combatant(target['id'].to_i) or return nil
        { 'type' => 'target', 'creature_id' => combatant[:creature_id] }
      end
    cacc  = (Creatures.lookup(combatant_for_id_creature(caster['id'])) rescue nil)
    rank  = (cacc&.ranks_for(spell['cast_skill']) rescue 0) || 0
    # Resolve a per-rank Area `size` Formula to a concrete square count
    # before the footprint reaches Atlas (which requires an integer size).
    size  = (Abilities.resolver.resolve_area_size(area['size'], rank: rank) rescue nil) || area['size']
    zone_id = Atlas.state.place_zone(map_id: map_id, source_id: source_id,
                                     shape: area['shape'], size: size,
                                     anchor: anchor, texture: area['texture'])
    return nil unless zone_id.is_a?(Integer)
    rounds = duration_in_rounds(spell['duration'], rank)
    ends   = rounds && encounter_state.current_round ? encounter_state.current_round + rounds : nil
    Conditions.store.create_zone_effect(
      source_id: source_id, atlas_zone_id: zone_id, ends_on_round: ends,
      triggers: { on_create: area['on_create'], on_enter: area['on_enter'],
                  on_end_of_turn: area['on_end_of_turn'] },
      metadata: { 'caster_id' => caster['id'] }
    )
    { source_id: source_id, atlas_zone_id: zone_id, map_id: map_id,
      shape: area['shape'], size: size, ends_on_round: ends }
  end

  # The Creature ID behind a Combatant ID (for caster lookups).
  def combatant_for_id_creature(combatant_id)
    c = encounter_state.combatant(combatant_id.to_i)
    c && c[:creature_id]
  end

  def duration_in_rounds(duration, rank)
    return nil if duration.nil?
    s = duration.to_s.strip
    binds = { 'rank' => rank.to_i }
    rl = (Timekeeping.config.round_length.to_f rescue 6.0)
    rl = 6.0 if rl <= 0
    if (m = s.match(/\A(.+?)\s+turns?\z/))
      (Abilities::Formula.evaluate(m[1], binds).to_i rescue nil)
    elsif (m = s.match(/\A(.+?)\s+minutes?\z/))
      n = (Abilities::Formula.evaluate(m[1], binds).to_f rescue nil)
      n && (n * 60 / rl).ceil
    elsif (m = s.match(/\A(.+?)\s+hours?\z/))
      n = (Abilities::Formula.evaluate(m[1], binds).to_f rescue nil)
      n && (n * 3600 / rl).ceil
    end
  end

  def expire_caster_zones!(combatant_id)
    round = encounter_state.current_round or return []
    removed = Conditions.store.expire_zone_effects_for(combatant_id, round)
    removed.each { |z| Atlas.state.remove_zone(z[:atlas_zone_id]) if z[:atlas_zone_id] }
    removed.map { |z| z[:source_id] }
  end

  def begin_turn_side_effects!(combatant_id)
    expire_caster_zones!(combatant_id)
    Conditions.store.persist!
  end

  def grant_defend_reaction!(payload)
    spell = payload['spell'] || {}
    v = resolve_named_spell(spell['name'])
    spec = spell_defends_spec(v) or return
    caster = payload['caster'] || {}
    ally = Array(payload['targets']).first or return
    # The block rolls up to the caster's Dice Cap in the casting skill; each die
    # spends one Reservoir die (Shield of Faith) or one Combat Pool die (Shield).
    skill = (spell['cast_skill'] || Encounter::Cast::DEFAULT_CAST_SKILL).to_s
    cacc  = (Creatures.lookup(combatant_for_id_creature(caster['id'])) rescue nil)
    cap   = (roll_inputs_for(cacc, skill)[:dice_cap].to_i rescue 0)
    # Replace any prior shield from the same caster+spell on a new cast.
    encounter_state.revoke_action { |g| g[:source] == spell['name'].to_s && g[:combatant_id] == caster['id'] }
    encounter_state.grant_action({ combatant_id: caster['id'], name: spell['name'], source: spell['name'],
                                   spell_name: spell['name'], defends: ally['id'],
                                   cast_skill: skill, dice_cap: cap,
                                   dice_source: spec[:block_dice],
                                   shield_bonus: v['shield_bonus'].to_i })
    # Show the protected ally a visible "shielded" condition (the caster still
    # controls the block). Refreshed each cast.
    apply_shielded_condition(ally['id'], spell['name'].to_s)
  end

  def consume_cast_item!(payload)
    item  = payload['item'] or return nil
    owner = item['owner_id']
    ref   = item['ref']
    return nil if owner.nil? || ref.nil?
    inst = Equipment.instance
    inst.remove_item(owner, ref.to_i, quantity: 1)
    inst.cleanup(owner)
    item['display'] || item['item_type']
  end

  # Mark the shielded Combatant with the `shielded` named effect for display.
  def apply_shielded_condition(combatant_id, source_name)
    c = encounter_state.combatant(combatant_id.to_i) or return
    inst = Conditions.store.instance_for(c[:creature_id])
    inst.apply_named_effect('shielded', source_id: "shield:#{source_name}") if inst.respond_to?(:apply_named_effect)
  rescue StandardError
    nil
  end

  # Drop the `shielded` marker from whichever Combatant a protective Spell
  # currently guards (its granted defend-action's ally).
  def clear_shielded_condition!(caster_id, spell_name)
    prior = encounter_state.granted_actions.find { |g| g[:source].to_s == spell_name.to_s && g[:combatant_id] == caster_id }
    return unless prior && (old_ally = encounter_state.combatant(prior[:defends]))
    inst = (Conditions.store.instance_for(old_ally[:creature_id]) rescue nil)
    inst.remove_effects_by_prefix("shield:#{spell_name}") if inst.respond_to?(:remove_effects_by_prefix)
  end

  # Retarget a protective Spell (Shield of Faith): move the `shielded` marker to
  # the new ally and rebuild the caster's granted defend-action so the block now
  # guards them. The block's Dice Cap tracks the caster's casting Skill, as at
  # cast time (grant_defend_reaction!).
  def retarget_defend_action!(caster_id, spell_name, ally_id)
    v = resolve_named_spell(spell_name)
    spec = spell_defends_spec(v) or return
    caster = encounter_state.combatant(caster_id) or return
    # Preserve the block's parameters as first cast. Read them from the existing
    # grant (a Standard Shield conjures no concentration entry, so the grant is
    # the only record); fall back to the concentration entry / recomputing them.
    prior  = encounter_state.granted_actions.find { |g| g[:source].to_s == spell_name.to_s && g[:combatant_id] == caster_id }
    entry  = Array(caster[:concentration]).find { |e| e[:spell_name].to_s == spell_name.to_s }
    skill  = ((prior && prior[:cast_skill]) || (entry && entry[:cast_skill]) || Encounter::Cast::DEFAULT_CAST_SKILL).to_s
    cacc   = (Creatures.lookup(caster[:creature_id]) rescue nil)
    cap    = (prior && prior[:dice_cap]) || (roll_inputs_for(cacc, skill)[:dice_cap].to_i rescue 0)
    bonus  = (prior && prior[:shield_bonus]) || v['shield_bonus'].to_i
    clear_shielded_condition!(caster_id, spell_name)
    encounter_state.revoke_action { |g| g[:source].to_s == spell_name.to_s && g[:combatant_id] == caster_id }
    encounter_state.grant_action({ combatant_id: caster_id, name: spell_name, source: spell_name,
                                   spell_name: spell_name, defends: ally_id, cast_skill: skill,
                                   dice_cap: cap.to_i, dice_source: spec[:block_dice],
                                   shield_bonus: bonus.to_i })
    apply_shielded_condition(ally_id, spell_name)
    Conditions.store.persist!
  end

  # Tear down a protective Spell's defend-action + shielded marker when the
  # Spell is ended.
  def retarget_end_defend_action!(caster_id, spell_name)
    clear_shielded_condition!(caster_id, spell_name)
    encounter_state.revoke_action { |g| g[:source].to_s == spell_name.to_s && g[:combatant_id] == caster_id }
    Conditions.store.persist!
  rescue StandardError
    nil
  end

  def cast_effects_from_consumption(effects)
    Array(effects).flat_map do |raw|
      e = (raw.transform_keys(&:to_s) rescue raw)
      if e.key?('damage')
        d = (e['damage'] || {}).transform_keys(&:to_s)
        [{ 'kind' => 'damage', 'amount' => d['amount'].to_i,
           'damage_type' => (d['type'] || 'physical'), 'threshold' => 0 }]
      elsif e.key?('temp_hp')
        [{ 'kind' => 'temp_hp', 'amount' => e['temp_hp'].to_i }]
      elsif e.key?('mana')
        [{ 'kind' => 'mana', 'amount' => e['mana'].to_i }]
      elsif %w[minor_damage moderate_damage major_damage].any? { |k| e.key?(k) }
        sev = { 'minor' => e['minor_damage'].to_i, 'moderate' => e['moderate_damage'].to_i,
                'major' => e['major_damage'].to_i }
        if sev.values.all? { |v| v <= 0 }
          heal = sev.each_with_object({}) { |(k, v), h| h[k] = -v if v.negative? }
          [{ 'kind' => 'heal', 'severity_map' => heal }]
        else
          [{ 'kind' => 'damage', 'amount' => sev.values.select(&:positive?).sum,
             'damage_type' => 'physical', 'threshold' => 0 }]
        end
      else
        []
      end
    end
  end

end
