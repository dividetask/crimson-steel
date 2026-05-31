module Equipment
  # Unit Price math. See equipment_design.md "Unit Price formula by
  # Category". A Property Application's `cost` is used when present,
  # otherwise the catalog's current cost for that Property.
  module Pricing
    module_function

    def unit_price(stack, catalog)
      it = catalog.item_type(stack.item_type)
      return 0 unless it
      category = it[:category]
      defn = it[:definition]

      price =
        case category
        when 'Gem'      then stack.value_in_gold || 0
        when 'Currency' then currency_value(catalog, stack)
        else
          if guidance_item?(defn)
            guidance_price(stack, catalog)
          else
            category_price(stack, catalog, category, defn)
          end
        end

      price *= catalog.innately_usable_price_multiplier if defn['innately_usable']
      price
    end

    def guidance_item?(defn)
      defn.is_a?(Hash) && defn.key?('guidance_bonus')
    end

    def currency_value(catalog, stack)
      c = catalog.currency[stack.item_type]
      (c && c['value_in_gold']) || stack.value_in_gold || 0
    end

    def guidance_price(stack, catalog)
      ts = catalog.default_tier_surcharge[stack.tier] || 0
      bs = catalog.default_bonus_surcharge[stack.guidance_bonus] || 0
      ts + bs
    end

    def category_price(stack, catalog, category, defn)
      base    = catalog.base_price_for(stack.item_type, stack.tier)
      tier_sc = tier_surcharge(defn, stack.tier, catalog)
      prop    = property_cost_sum(stack, catalog)

      case category
      when 'Ammunition'
        bundle = (catalog.ammunition(stack.item_type) || {})['bundle_size'] || 1
        (base.to_f / bundle) + (tier_sc + prop).to_f / catalog.magical_ammunition_divisor
      when 'Consumable'
        base + (tier_sc + prop).to_f / catalog.consumable_surcharge_divisor
      else
        # Weapon, Armor, and generic Item / Book / Misc.
        base + tier_sc + prop
      end
    end

    # Tier 0 contributes no surcharge. A per-Item `tier_surcharge` map
    # replaces the Default. (Guidance Items never reach here.)
    def tier_surcharge(defn, tier, catalog)
      return 0 if tier.to_i <= 0
      map =
        if defn.is_a?(Hash) && defn['tier_surcharge']
          int_keyed(defn['tier_surcharge'])
        else
          catalog.default_tier_surcharge
        end
      map[tier] || 0
    end

    def property_cost_sum(stack, catalog)
      stack.properties.sum { |p| p[:cost] || catalog.property_cost(p[:name]) || 0 }
    end

    def int_keyed(map)
      map.each_with_object({}) do |(k, v), h|
        h[k.is_a?(Integer) ? k : Integer(k)] = v
      end
    end
  end
end
