module Equipment
  # Generate Magical Item. Mixed into Instance. See equipment_design.md
  # "Generate Magical Item" and "Magical Item generation filter".
  module Magical
    NONE = 'none'.freeze

    def generate_magical_item(constraint, rng = @rng)
      constraint = constraint.transform_keys(&:to_s)
      category = constraint['category'].to_s

      tier = pick_tier(constraint, rng)
      item_type = pick_item_type(constraint, category, rng)
      property = pick_property(constraint, category, tier, rng)

      properties = []
      if property && property != NONE
        subtype = pick_subtype(property, rng)
        properties << { name: property, subtype: subtype, cost: @catalog.property_cost(property) }
      end

      Stack.new(
        item_type: item_type, quantity: 1, tier: tier,
        properties: properties, equipped: !!constraint['equipped']
      )
    end

    private

    def pick_tier(constraint, rng)
      tiers = Array(constraint['tier'])
      weights = constraint['tier_weights']
      if weights
        weighted_pick(tiers.map { |t| [t, (weights[t] || weights[t.to_s] || 0)] }, rng)
      else
        tiers[rng_index(tiers.size, rng)]
      end
    end

    def pick_item_type(constraint, category, rng)
      candidates = eligible_item_types(category)
      weights = constraint['items_weighted']
      if weights
        entries = candidates.map { |n| [n, (weights[n] || 0)] }.reject { |(_, w)| w.zero? }
        entries = candidates.map { |n| [n, 1] } if entries.empty?
        weighted_pick(entries, rng)
      else
        candidates[rng_index(candidates.size, rng)]
      end
    end

    def pick_property(constraint, category, tier, rng)
      pool = (constraint['properties_weighted'] || {})
      eligible = pool.select do |name, _w|
        name == NONE || property_eligible?(name, category, tier)
      end
      return NONE if eligible.empty?
      weighted_pick(eligible.to_a, rng)
    end

    def pick_subtype(property_name, rng)
      pdef = @catalog.property(property_name) || {}
      return nil unless pdef['has_subtype']
      subtypes = pdef['subtypes'] || []
      return nil if subtypes.empty?
      subtypes[rng_index(subtypes.size, rng)]
    end

    # min_tier <= tier AND applies_to admits the constraint category.
    def property_eligible?(name, category, tier)
      pdef = @catalog.property(name)
      return false unless pdef
      return false if (pdef['min_tier'] || 0) > tier
      applies = pdef['applies_to'] || []
      category_admitted?(category, applies)
    end

    # melee/ranged/ammo match literally. all_armor and all_body are
    # treated as interchangeable for armor Properties (body armor is a
    # kind of armor), so an `all_armor` Property is eligible under an
    # `all_body` constraint and vice versa.
    def category_admitted?(category, applies)
      case category
      when 'all_armor', 'all_body'
        applies.include?('all_armor') || applies.include?('all_body')
      else
        applies.include?(category)
      end
    end

    def eligible_item_types(category)
      case category
      when 'melee'  then @catalog.weapons.select { |_n, d| %w[One\ Handed Two\ Handed].include?(d['category']) }.keys
      when 'ranged' then @catalog.weapons.select { |_n, d| d['category'] == 'Ranged' }.keys
      when 'ammo'   then @catalog.ammunition_block.keys
      when 'all_armor' then @catalog.armor.keys
      when 'all_body'  then @catalog.armor.reject { |_n, d| d['category'] == 'Shield' }.keys
      else []
      end
    end

    # ---- weighted choice -----------------------------------------------

    def weighted_pick(entries, rng)
      entries = entries.reject { |(_, w)| w.to_f <= 0 }
      return nil if entries.empty?
      total = entries.sum { |(_, w)| w.to_f }
      u = rng.rand * total
      acc = 0.0
      entries.each do |(item, w)|
        acc += w.to_f
        return item if u < acc
      end
      entries.last[0]
    end

    def rng_index(size, rng)
      return 0 if size <= 0
      (rng.rand * size).floor.clamp(0, size - 1)
    end
  end
end
