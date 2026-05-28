module Equipment
  # Consume Item: invoke the spell a Potion / Oil / Scroll / Wand /
  # spell-storing item carries, route its Effects, impose Item-form
  # Magic Toxicity, and decrement Consumables. Mixed into Instance.
  # See equipment_design.md "Consume Item" and "Item-Form Toxicity".
  module Consumption
    SEVERITY_KEYS = { 'minor_damage' => :minor, 'moderate_damage' => :moderate,
                      'major_damage' => :major }.freeze
    TOXIC_FORMS = %i[potion oil].freeze

    Result = Struct.new(:spell, :outcomes, :toxicity_cost, keyword_init: true)

    def consume_item(owner_id, ref, target_creature_id:, toxicity_threshold:,
                     saturation_reducer: 0, target_tier: nil)
      inv = read_inventory(owner_id)
      idx = resolve_index(inv, ref)
      return ERROR if idx.nil?
      stack = inv[idx]
      defn = @catalog.definition_of(stack.item_type) || {}
      category = @catalog.category_of(stack.item_type)

      spell = stack.stored_spell || defn['spell']
      return ERROR unless spell

      resolved = @abilities.resolve_spell(spell, tier: stack.tier)
      effects = resolved[:effects] || resolved['effects'] || []
      polarity = (resolved[:polarity] || resolved['polarity'] || :positive).to_sym

      gated = saturation_gated?(toxicity_threshold)
      outcomes = effects.flat_map { |e| route_effect(e.transform_keys(&:to_s), spell, target_creature_id, gated) }.compact

      toxicity_cost = impose_toxicity(stack, defn, polarity, target_tier, saturation_reducer)

      remove_item(owner_id, idx, quantity: 1) if category == 'Consumable'
      cleanup(owner_id)

      Result.new(spell: spell, outcomes: outcomes, toxicity_cost: toxicity_cost)
    end

    # Exposed for direct testing and reuse. See "Item-Form Toxicity".
    def item_form_toxicity(item_tier:, target_tier: nil, saturation_reducer: 0)
      base = @catalog.consumable_saturation_base[item_tier] || 0
      minimum = @catalog.consumable_saturation_minimum[item_tier] || 0
      if target_tier && target_tier < item_tier
        base *= @catalog.lower_tier_multiplier
        minimum *= @catalog.lower_tier_multiplier
      end
      [base - saturation_reducer, minimum].max
    end

    private

    def route_effect(eff, spell, target, gated)
      heal_map = heal_severity_map(eff)
      damage_map = damage_severity_map(eff)

      if heal_map.any?
        return [] if gated
        @conditions&.apply_heal(heal_map)
        [[:heal, heal_map]]
      elsif damage_map.any?
        @combat&.apply_damage(target: target, severities: damage_map)
        [[:damage, damage_map]]
      elsif eff.key?('mana')
        return [] if gated
        @creatures&.restore_mana(target, eff['mana'])
        [[:mana, eff['mana']]]
      elsif eff.key?('temp_hp')
        @conditions&.apply_temporary_hit_points(amount: eff['temp_hp'], source_id: "equipment:consume:#{spell}")
        [[:temp_hp, eff['temp_hp']]]
      elsif eff.key?('damage')
        @combat&.apply_damage(target: target, **symbolize(eff['damage']))
        [[:damage, eff['damage']]]
      else
        []
      end
    end

    # Negative *_damage entries are heals (worst-first cascade keyed by
    # Severity); the magnitude is the absolute value.
    def heal_severity_map(eff)
      SEVERITY_KEYS.each_with_object({}) do |(key, sev), h|
        v = eff[key]
        h[sev] = -v if v && v < 0
      end
    end

    # Positive *_damage entries are attacks routed through Combat.
    def damage_severity_map(eff)
      SEVERITY_KEYS.each_with_object({}) do |(key, sev), h|
        v = eff[key]
        h[sev] = v if v && v > 0
      end
    end

    def saturation_gated?(threshold)
      return false if threshold.nil? || !@conditions.respond_to?(:magic_toxicity)
      @conditions.magic_toxicity >= threshold
    end

    def impose_toxicity(stack, defn, polarity, target_tier, reducer)
      form = item_form(stack.item_type, defn)
      return 0 unless TOXIC_FORMS.include?(form)

      cost = item_form_toxicity(item_tier: stack.tier, target_tier: target_tier, saturation_reducer: reducer)
      kind = polarity == :forced ? :forced : :positive
      @conditions&.apply_magic_toxicity(amount: cost, kind: kind)
      cost
    end

    # Item form drives per-form Toxicity. A catalog `form:` wins;
    # otherwise it is inferred from the Item Type name.
    def item_form(item_type, defn)
      return defn['form'].to_s.to_sym if defn['form']
      name = item_type.downcase
      return :potion if name.include?('potion')
      return :oil    if name.include?('oil')
      return :scroll if name.include?('scroll')
      return :wand   if name.include?('wand')
      nil
    end
  end
end
