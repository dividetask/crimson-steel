# Encounter cast UI: the Cast / Item Action-Builder blobs, castable spell and
# item lists, the Ring-of-Parry defense, and casting-skill helpers. Extracted
# from routes/encounter.rb (a separate, accumulating helpers block).
helpers do
  def cast_builder_blob(caster)
    acc        = Creatures.lookup(caster[:creature_id]) rescue nil
    pool       = (encounter_state.combat_pool_remaining(caster[:id]) rescue 0) || 0
    mana_max   = (acc&.max_mana rescue nil)
    mana_spent = (Conditions.store.instance_for(caster[:creature_id]).state.mana_spent rescue 0)
    mana_left  = mana_max ? [mana_max - mana_spent, 0].max : nil

    spells = (known_spell_castables(acc, pool, mana_left) +
              granted_item_castables(caster, acc, pool, mana_left))
             .reject { |sp| sp[:long_cast] }

    build_cast_blob(caster: caster, acc: acc, spells: spells, pool: pool,
                    title: "#{tracker_name(caster)} casts", stub_id: "cast-#{caster[:id]}")
  end

  def item_builder_blob(actor)
    acc        = Creatures.lookup(actor[:creature_id]) rescue nil
    pool       = (encounter_state.combat_pool_remaining(actor[:id]) rescue 0) || 0
    mana_max   = (acc&.max_mana rescue nil)
    mana_spent = (Conditions.store.instance_for(actor[:creature_id]).state.mana_spent rescue 0)
    mana_left  = mana_max ? [mana_max - mana_spent, 0].max : nil
    spells = (consumable_castables(actor, acc, pool) +
              granted_item_castables(actor, acc, pool, mana_left))
             .reject { |sp| sp[:long_cast] }
    build_cast_blob(caster: actor, acc: acc, spells: spells, pool: pool,
                    title: "#{tracker_name(actor)} uses an item", stub_id: "item-#{actor[:id]}",
                    spell_label: 'Item', cast_verb: 'Use')
  end

  # The Combatant's known Spells as castable descriptors (the Cast list).
  def known_spell_castables(acc, pool, mana_left)
    (CreatureSheet.spells(acc) rescue []).flat_map do |g|
      cost = mana_cost_for_tier(g[:tier])
      Array(g[:names]).map do |name|
        v     = (Abilities.lookup(name) rescue nil) || {}
        skill = cast_skill_for(acc, v, name)
        castable_descriptor(acc, name, g[:tier], pool, mana_left, skill: skill, mana_cost: cost)
      end
    end
  end

  def granted_item_castables(caster, acc, pool, mana_left)
    known = (CreatureSheet.spells(acc) rescue []).flat_map { |g| Array(g[:names]).map(&:to_s) }
    granted_spell_items(caster[:creature_id]).filter_map do |it|
      vname = spell_variant_name(it[:spell], it[:tier])
      next if known.include?(vname)
      v    = spell_variant_definition(vname)
      cost = mana_cost_for_tier(it[:tier])
      castable_descriptor(acc, vname, it[:tier], pool, mana_left,
                          skill_options: item_skill_options(v, acc), mana_cost: cost)
    end
  end

  def spell_variant_name(spell, tier)
    CreatureSheet.spell_variant_name(spell, tier)
  end

  # The catalog definition behind a Spell name, falling back to the base Spell
  # when the name is a Variant. A Variant name (e.g. "Shooting Stars", a Variant
  # of "Spark Shower") is not itself a catalog key, so a bare Abilities.lookup
  # returns nil — dropping the base Spell's casting Skills (nature / arcana) and
  # leaving only the default `evocation` for a granted Item like the Ring of
  # Shooting Stars.
  def spell_variant_definition(name)
    v = (Abilities.lookup(name) rescue nil)
    return v if v && !v.empty?
    base, = spell_base_axis(name)
    (base && (Abilities.lookup(base) rescue nil)) || {}
  end

  def item_display_with_variant(stack, cat, _spell, _tier)
    CreatureSheet.item_display_name(stack, cat)
  end

  def consumable_castables(actor, acc, pool)
    consumable_spell_items(actor[:creature_id]).map do |it|
      v = spell_variant_definition(it[:spell])
      castable_descriptor(acc, it[:spell], it[:tier], pool, nil,
                          mana_cost: 0, key: "item:#{it[:ref]}", display: it[:display],
                          item: it, self_only: it[:form] == 'potion',
                          quantity: it[:quantity], skill_options: item_skill_options(v, acc))
    end
  end

  def item_cast_skill(variant)
    (Array(variant && variant['skills']).first || 'evocation').to_s
  end

  def item_skill_options(variant, acc = nil)
    listed = Array(variant && variant['skills']).map(&:to_s).flat_map do |s|
      next [s] unless s.end_with?('_')
      resolved = acc ? resolve_skill_family(acc, s) : s
      resolved.to_s.end_with?('_') ? [] : [resolved.to_s]
    end
    (listed + ['evocation']).uniq
  end

  def castable_descriptor(acc, name, tier, pool, mana_left, skill: nil, mana_cost:,
                          key: nil, display: nil, item: nil, self_only: false,
                          skill_options: nil, quantity: nil)
    v   = (Abilities.lookup(name) rescue nil) || {}
    bname = (spell_base_axis(name).first rescue nil) if name
    v = ((Abilities.lookup(bname) rescue nil) || {}) if v.empty? && bname
    raw  = (Abilities.catalog.ability(name) rescue nil) || (bname && Abilities.catalog.ability(bname) rescue nil) || {}
    ra   = raw['area']
    area = ra.is_a?(Array) ? ra.find { |x| x.is_a?(Hash) } : ra
    act  = (Abilities.resolve_activation(v) rescue nil)
    channel_mode = v.dig('channel', 'mode').to_s
    fills_reservoir = %w[reservoir auto].include?(channel_mode) &&
                      v.dig('reservoir', 'fill', 'source').to_s == 'channel_dice'
    # A channel that scales an effect with casting successes (e.g. Heal's
    # bleed_reduction = spell_tier*2*success) needs a real casting check rolled.
    channel_check = !!(v.dig('channel', 'effect_hash', 'bleed_reduction') ||
                       raw.dig('channel', 'effect_hash', 'bleed_reduction'))
    requires_roll = !fills_reservoir &&
                    !!(v['attack_roll'] || Array(v['save']).first || Array(v['damage_type']).compact.first || channel_check)

    candidate_skills = (skill_options || [skill]).compact
    candidate_skills = ['evocation'] if candidate_skills.empty?
    skopts = candidate_skills.uniq.map do |sk|
      r = roll_inputs_for(acc, sk)
      comp = r[:competency_modifier]
      { skill: sk, label: Encounter::Special.pretty_skill(sk),
        dice_cap: r[:dice_cap].to_i, competency: comp, bonus: (comp ? comp[1].to_i : 0) }
    end
    skopts.sort_by! { |o| [-o[:dice_cap], -o[:bonus]] }
    skopts = [skopts.first] if !requires_roll && skopts.any?
    primary = skopts.first || { skill: 'evocation', dice_cap: 0, competency: nil }

    action_min = Encounter::Special.action_cost(act && act[:alias])
    target_rank = (acc&.ranks_for(primary[:skill]) rescue 0).to_i
    # A per-rank Area `size` (e.g. "rank", "8*rank") resolves to a concrete
    # 5-foot-square count against the caster's rank before the footprint
    # reaches the placement UI / Atlas.
    if area.is_a?(Hash) && area['size'].is_a?(String)
      rsize = (Abilities.resolver.resolve_area_size(area['size'], rank: target_rank) rescue nil)
      area = area.merge('size' => rsize) if rsize
    end
    multi_max   = if Array(v['save']).first || v['attack_roll']
                    multi_target_max(v['target'], target_rank)
                  end
    { name: name, key: (key || name), display: (display || name),
      tier: tier, mana_cost: mana_cost, skill: primary[:skill], skill_options: skopts,
      dice_cap: primary[:dice_cap], competency: primary[:competency],
      damage_type: Array(v['damage_type']).compact.first, school: v['school'],
      attack_roll: (fills_reservoir ? false : !!v['attack_roll']), save: (fills_reservoir ? nil : Array(v['save']).first),
      area: (area.is_a?(Hash) ? area : nil),
      multi_max: multi_max,
      requires_roll: requires_roll,
      reservoir: fills_reservoir,
      action_min: action_min,
      long_cast: !!(act && act[:kind].to_s == 'real_time' && act[:minutes].to_i >= 1),
      affordable: mana_left.nil? || mana_cost <= mana_left,
      item: item, self_only: self_only || v['target'].to_s == 'self',
      # An object-targeted Spell (Silent Portal targets a door/window, not a
      # Creature) has no Creature to pick — the Target step auto-resolves with
      # no defender rather than prompting for one.
      object_target: v['target'].to_s == 'object', quantity: quantity }
  end

  def multi_target_max(target, rank)
    return nil if target.nil?
    s = target.to_s
    return nil if %w[self object 1].include?(s)
    n = (Abilities.resolver.resolve_target({ 'target' => target }, rank: rank) rescue nil)
    n = n.to_i if n.is_a?(Numeric)
    (n.is_a?(Integer) && n > 1) ? n : nil
  end

  def granted_spell_items(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.each_with_index.flat_map do |s, i|
      next [] unless s.equipped
      defn = cat.definition_of(s.item_type) || {}
      next [] unless defn['grants_spell']
      form = item_form_of(s.item_type, defn)
      display = CreatureSheet.item_display_name(s, cat)
      granted_spell_names(s, defn).map do |spell|
        { ref: i, item_type: s.item_type, display: display,
          spell: spell, tier: granted_spell_tier(spell, s.tier), form: form }
      end
    end
  end

  def ring_parry_item(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.each_with_index do |s, i|
      next unless s.equipped
      defn = cat.definition_of(s.item_type) || {}
      return { ref: i, stack: s } if defn['grants_parry']
    end
    nil
  end

  # Per-day Parry cap from the ring's catalog definition (default 1/day).
  def ring_parry_uses_per_day(item_type)
    ((Equipment.catalog.definition_of(item_type) || {})['uses_per_day'] || 1).to_i
  end

  def ring_parry_available?(creature_id)
    it = ring_parry_item(creature_id) or return false
    cap = ring_parry_uses_per_day(it[:stack].item_type)
    Equipment.instance.daily_charge_remaining(it[:stack], 'parry', cap,
                                              encounter_state.current_day_index).positive?
  end

  def consume_ring_parry!(creature_id)
    it = ring_parry_item(creature_id) or return
    Equipment.instance.spend_daily_charge!(equipment_owner(creature_id), it[:ref], 'parry',
                                           encounter_state.current_day_index)
  end

  def granted_spell_names(stack, defn)
    names = defn['spells'].is_a?(Array) ? defn['spells'] : [stack.stored_spell || defn['spell']]
    names.compact.map(&:to_s)
  end

  def granted_spell_tier(spell, stack_tier)
    entry = (Abilities.catalog.ability(spell) rescue nil)
    t = entry && entry['tier']
    return t if t.is_a?(Integer) # single-tier base key
    if entry && t.is_a?(Array)
      # Tier-axis base key. When the spell distinguishes its tiers by name
      # (a name/prefix/suffix axis, e.g. Spark Shower → Shooting Stars), the
      # granted name is a specific variant, so use that variant's tier.
      # When the tiers are nameless (e.g. Resistance), the item's stack tier
      # selects the variant.
      named = %w[name prefix suffix].any? { |k| entry[k].is_a?(Array) }
      if named
        info = (CreatureSheet.spell_info(spell) rescue nil)
        return info[:tier].to_i if info && info[:tier]
      end
      return stack_tier
    end
    # Not a base key — a specific variant name (e.g. "Shooting Stars").
    info = (CreatureSheet.spell_info(spell) rescue nil)
    (info && info[:tier]) ? info[:tier].to_i : stack_tier
  end

  def consumable_spell_items(creature_id)
    cat   = Equipment.catalog
    owner = equipment_owner(creature_id)
    inv   = (Equipment.instance.get_inventory(owner) rescue [])
    inv.each_with_index.filter_map do |s, i|
      next unless s.quantity.to_i.positive?
      next unless cat.category_of(s.item_type) == 'Consumable'
      defn  = cat.definition_of(s.item_type) || {}
      spell = s.stored_spell || defn['spell']
      next unless spell
      form = item_form_of(s.item_type, defn)
      next unless %w[potion scroll].include?(form)
      { ref: i, owner_id: owner, item_type: s.item_type,
        display: item_display_with_variant(s, cat, spell, s.tier),
        spell: spell, tier: s.tier, form: form, quantity: s.quantity }
    end
  end

  def item_form_of(item_type, defn)
    return defn['form'].to_s if defn && defn['form']
    n = item_type.to_s.downcase
    return 'potion' if n.include?('potion')
    return 'oil'    if n.include?('oil')
    return 'scroll' if n.include?('scroll')
    return 'wand'   if n.include?('wand')
    return 'ring'   if n.include?('ring')
    ''
  end

  def build_cast_blob(caster:, acc:, spells:, pool:, title:, stub_id:, spell_label: 'Spell', cast_verb: 'Cast')
    die     = DiceResolution.config.die_size
    base_tn = DiceResolution.config.base_target_number

    targets = encounter_state.combatants.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      { id: c[:id], creature_id: c[:creature_id],
        name: tracker_name(c) + (c[:id] == caster[:id] ? ' (self)' : ''),
        pool: (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0,
        tier: (tacc&.tier rescue nil),
        dodge:   roll_inputs_for(tacc, 'dex_save', attribute_override: :dex),
        martial: roll_inputs_for(tacc, 'martial',  attribute_override: :str),
        has_shield: equipped_shield?(c[:creature_id]),
        saves: %i[str dex con int wis cha].each_with_object({}) { |a, h| h[a] = roll_inputs_for(tacc, "#{a}_save", attribute_override: a) } }
    end

    rolls = [
      { id: 'caster', side: 'supporting', creature_name: tracker_name(caster),
        roll_name: 'Cast', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 2, speed: 0, excluded: false },
      { id: 'target', side: 'opposing', creature_name: '—',
        roll_name: 'Defense', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true }
    ]

    has_skill_step = spells.any? { |sp| Array(sp[:skill_options]).size > 1 }

    inh_table  = (Creatures::Config.tier_minimum_inherent_bonus rescue [])
    caster_inh = Encounter::Attack.inherent_amount(inh_table, ((acc&.tier rescue nil) || 0))
    spell_opts = []
    spells.group_by { |sp| sp[:tier].to_i }.sort_by { |tier, _| tier }.each_with_index do |(tier, group_spells), gi|
      hdr = "tier-#{tier}-h"
      grp = "tier-#{tier}"
      br  = gi.zero? ? '' : '<br>'
      spell_opts << { kind: 'info', group: hdr, value: "#{hdr}|label", label: %(#{br}<span class="cb-tier-head tier-#{tier}">Tier #{tier}</span>) }
      group_spells.each do |sp|
        patch = { set_speed: [{ id: 'caster', speed: 0 }],
                  set_name:  [{ id: 'caster', roll_name: "#{cast_verb} #{sp[:display]}" }] }
        unless has_skill_step
          bpl = []
          bpl << sp[:competency] if sp[:competency]
          bpl << ['Inherent', caster_inh]
          bpl << ['Guidance', sp[:tier].to_i] if sp[:tier].to_i.positive?
          patch[:set_bpl] = [{ id: 'caster', bonus_penalty_list: bpl }]
        end
        button = sp[:quantity].to_i > 1 ? "#{sp[:display]} ×#{sp[:quantity]}" : sp[:display]
        spell_opts << { value: sp[:key], key: sp[:key], group: grp,
                        label: button, summary: sp[:display],
                        disabled: !sp[:affordable],
                        spell_name: sp[:name],
                        cast: { roll: sp[:requires_roll], reservoir: sp[:reservoir] },
                        patch: patch }
      end
    end
    spell_step = { key: 'spell', label: spell_label, options: spell_opts }

    dice_map = {}
    header_map = {}
    # The "which skill" button shows the Skill name plus the Character's own
    # Competency bonus for that Skill (e.g. "Arcana +3"), so the DM can compare
    # skills at a glance. The Competency is the skill-specific part of the Roll's
    # bonuses (Inherent / Guidance are the same whichever Skill is chosen).
    skill_lead_label = lambda do |so|
      amt  = (so[:competency] && so[:competency][1]).to_i
      sign = amt >= 0 ? "+#{amt}" : amt.to_s
      %(#{so[:label]} <span class="cb-skill-bonus">#{sign}</span>)
    end
    spells.each do |sp|
      variants = has_skill_step ? Array(sp[:skill_options]) :
                 [{ skill: sp[:skill], label: Encounter::Special.pretty_skill(sp[:skill]),
                    dice_cap: sp[:dice_cap], competency: sp[:competency] }]
      body   = []
      header = []
      variants.each_with_index do |so, idx|
        cap = so[:dice_cap].to_i
        min = sp[:action_min].to_i
        set = lambda do |n|
          patch = { set_dice: [{ id: 'caster', count: n }] }
          if has_skill_step
            bpl = []
            bpl << so[:competency] if so[:competency]
            bpl << ['Inherent', caster_inh]
            bpl << ['Guidance', sp[:tier].to_i] if sp[:tier].to_i.positive?
            patch[:set_bpl] = [{ id: 'caster', bonus_penalty_list: bpl }]
          end
          patch
        end
        grp    = "dice-#{so[:skill]}"
        prefix = "#{sp[:key]}|#{so[:skill]}"
        if sp[:requires_roll] || sp[:reservoir]
          if cap < min
            body << { kind: 'info', group: grp, value: "#{prefix}|none", label: "#{so[:label]} — no dice available" }
            next
          end
          g = dice_count_group(prefix: prefix, group: grp, min: min, max: cap,
                               aff: ->(n) { n <= pool }, patch: set,
                               summary: ->(n) { "#{so[:label]} — #{n} dice" },
                               lead_label: skill_lead_label.call(so),
                               header_label: skill_lead_label.call(so))
          body.concat(g[:body])
          # Only the primary (highest-prowess) skill goes on the top bar.
          header << g[:header] if idx.zero?
        else
          affordable = min <= pool
          opt = { value: "#{prefix}|#{min}", key: min, group: grp,
                  label: "#{min} dice", summary: "#{min} dice",
                  disabled: !affordable, patch: set.call(min) }
          opt[:auto] = true if affordable && variants.size == 1
          body.concat([opt])
        end
      end
      dice_map[sp[:key]]   = body
      header_map[sp[:key]] = header
    end
    dice_step = { key: 'dice', label: 'Dice', options_by: %w[spell], options_map: dice_map,
                  header_options_by: %w[spell], header_options_map: header_map, no_summary: true }

    combatant_target_opts = target_options(encounter_state.combatants, roll_id: 'target', self_id: caster[:id])
    self_combatant   = encounter_state.combatant(caster[:id])
    self_target_opts = self_combatant ? target_options([self_combatant], roll_id: 'target', self_id: caster[:id]).map { |o| o.merge(auto: true) } : []
    target_map = {}
    spells.each do |sp|
      target_map[sp[:key]] =
        if sp[:area]
          [{ value: 'place', key: 'place', group: 'place', label: 'Place on the map',
             summary: 'Place the spell effect on the Atlas',
             place: { shape: sp[:area]['shape'], size: sp[:area]['size'], save: !!sp[:save] } }]
        elsif sp[:object_target]
          # No Creature target: a single auto option that excludes the (absent)
          # defender Roll, so the builder never prompts for a target.
          [{ value: 'object', key: 'object', group: 'object', label: 'Object',
             summary: 'Object', auto: true,
             patch: { set_excluded: [{ id: 'target', excluded: true }] } }]
        elsif sp[:self_only]
          self_target_opts
        else
          combatant_target_opts
        end
    end
    multi_map = spells.each_with_object({}) { |sp, h| h[sp[:key]] = sp[:multi_max] if sp[:multi_max] }
    target_step = { key: 'target', label: 'Target', options_by: %w[spell], options_map: target_map,
                    multi_by: %w[spell], multi_map: multi_map }

    defense_map = {}
    targets.each do |t|
      spells.each do |sp|
        opts = []
        def_inh = Encounter::Attack.defender_tier_bonuses(defender_tier: t[:tier], inherent_table: inh_table)
        caster_bpl = []
        caster_bpl << sp[:competency] if sp[:competency]
        caster_bpl << ['Inherent', caster_inh]
        caster_bpl << ['Guidance', sp[:tier].to_i] if sp[:tier].to_i.positive?
        if sp[:attack_roll]
          # No defense: the target does not roll, so nothing propagates
          none_bpl = caster_bpl + def_inh.map { |type, amt| [type, -amt] }
          opts << { value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                    patch: { set_bpl: [{ id: 'caster', bonus_penalty_list: none_bpl }],
                             set_excluded: [{ id: 'target', excluded: true }] } }
          opts.concat(cast_defense_branch('dodge', 'Dodge', t[:dodge], speed: 0, save: false, pool: t[:pool],
                                          extra_bpl: def_inh, caster_bpl: caster_bpl))
          opts.concat(cast_defense_branch('block', 'Block', t[:martial], speed: 0, save: false, pool: t[:pool],
                                          extra_bpl: def_inh, caster_bpl: caster_bpl)) if t[:has_shield]
        elsif sp[:save]
          attr = sp[:save]['attribute'].to_s
          tacc  = Creatures.lookup(t[:creature_id]) rescue nil
          extra = tacc ? CreatureModifiers.save_modifiers(tacc, attr, descriptors: [sp[:school]].compact) : []
          opts.concat(cast_defense_branch("save:#{attr}", "#{attr_label(attr)} save",
                                          t[:saves][attr.to_sym] || t[:dodge], speed: 0, save: true,
                                          pool: t[:pool], extra_bpl: extra + def_inh, caster_bpl: caster_bpl))
        end
        defense_map["#{t[:id]}|#{sp[:key]}"] = opts
      end
    end
    spells.select { |sp| sp[:area] }.each do |sp|
      defense_map["place|#{sp[:key]}"] = [
        { value: 'area', key: 'area', group: 'area', label: 'Resolve in the area',
          summary: 'Apply to the creatures in the footprint',
          patch: { set_excluded: [{ id: 'target', excluded: true }] } }
      ]
    end
    defense_step = { key: 'defense', label: 'Target&rsquo;s defense', options_by: %w[target spell], options_map: defense_map }

    steps = [spell_step, dice_step, target_step, defense_step].compact
    steps.concat(luck_steps(actor_id: caster[:id],
                            targets: [{ roll_id: 'caster', label: tracker_name(caster) },
                                      { roll_id: 'target', label: 'Defender' }]))

    blob = { title: title, stub_id: stub_id, rolls: rolls, steps: steps }
    items = spells.select { |sp| sp[:item] }.each_with_object({}) { |sp, h| h[sp[:key]] = sp[:item] }
    blob[:items] = items unless items.empty?
    blob
  end

  def cast_defense_branch(key, name, inputs, speed:, save:, pool:, extra_bpl: [], caster_bpl: nil)
    di   = inputs || { dice_cap: 0 }
    dcmp = di[:competency_modifier] ? [di[:competency_modifier]] : []
    dcmp += Array(extra_bpl)
    cap  = di[:dice_cap].to_i
    mk = lambda do |dice, label, disabled|
      # A rolled defense restores the caster's base list (sheds the No-defense
      # injection); the target's own Inherent crosses via propagation instead.
      set_bpl = [{ id: 'target', bonus_penalty_list: dcmp }]
      set_bpl.unshift({ id: 'caster', bonus_penalty_list: caster_bpl }) if caster_bpl
      { value: "#{key}|#{dice}", group: key, label: label, summary: "#{name} — #{dice} dice", disabled: disabled,
        patch: { set_bpl: set_bpl,
                 set_dice: [{ id: 'target', count: dice }],
                 set_speed: [{ id: 'target', speed: speed }],
                 set_name: [{ id: 'target', roll_name: name }],
                 set_excluded: [{ id: 'target', excluded: false }] } }
    end
    if save
      o = mk.call(cap, name, cap.zero?)
      o[:summary] = name
      o[:auto] = true
      return [o]
    end

    out = []
    aff_max = (2..cap).select { |n| speed + n <= pool }.max
    out << mk.call(aff_max || cap, "#{name} (speed #{speed})", aff_max.nil?)
    (2..cap).each { |n| out << mk.call(n, n.to_s, speed + n > pool) }
    out << { kind: 'info', group: key, value: "#{key}|info",
             label: (dcmp.empty? ? 'no bonuses' : dcmp.map { |type, amt| "#{amt >= 0 ? '+' : ''}#{amt} #{type}" }.join(' ')) }
    out
  end

  # Tier → UI color name (ui_conventions.md → Tier Colors).
  TIER_COLORS = %w[red orange yellow green blue purple].freeze
  def tier_color(tier)
    TIER_COLORS[tier.to_i] || "tier #{tier}"
  end

  def attr_label(attr)
    { 'str' => 'Strength', 'dex' => 'Dexterity', 'con' => 'Constitution',
      'int' => 'Intelligence', 'wis' => 'Wisdom', 'cha' => 'Charisma' }[attr.to_s] || attr.to_s
  end

  CLASS_CASTING_SKILL = { 'cleric' => 'invocation', 'bard' => 'perform_' }.freeze

  def cast_skill_for(acc, variant, spell_name)
    default = Encounter::Cast::DEFAULT_CAST_SKILL
    klass = spell_source_classes(acc)[spell_name.to_s]
    cs = klass && class_casting_skill(acc, klass)
    cs || (Array((variant || {})['skills']).first || default)
  end

  def spell_source_classes(acc)
    map = {}
    (acc&.granted_abilities rescue []).each do |g|
      src = g[:source].to_s
      next unless src.start_with?('class:')
      info = (CreatureSheet.spell_info(g[:name]) rescue nil) or next
      map[info[:name]] ||= src.sub('class:', '')
    end
    map
  end

  def class_casting_skill(acc, class_key)
    skill = CLASS_CASTING_SKILL[class_key.to_s] or return nil
    resolved = resolve_skill_family(acc, skill)
    resolved.to_s.end_with?('_') ? nil : resolved
  end

  def resolve_skill_family(acc, skill)
    return skill unless skill.to_s.end_with?('_')
    (acc&.trained_skills rescue []).find { |s| s.start_with?(skill) } || skill
  end

  def combatant_mana_left(creature_id, acc)
    mana_max = (acc&.max_mana rescue nil)
    return nil unless mana_max
    spent = (Conditions.store.instance_for(creature_id).state.mana_spent rescue 0)
    [mana_max - spent, 0].max
  end

  def creature_raging?(creature_id)
    (Conditions.store.instance_for(creature_id).active_effect_names rescue []).include?('rage')
  rescue StandardError
    false
  end

  def reaction_mana_cost(ability_name)
    cost = (Abilities.lookup(ability_name)&.dig('mana_cost') rescue nil)
    cost ||= (Abilities.catalog.ability(ability_name)&.dig('mana_cost') rescue nil)
    cost.to_i
  end

end
