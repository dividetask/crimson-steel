module Equipment
  # The three detail-fetchers. Each returns a plain Hash so callers
  # (Combat, UI) read everything about a Stack from one call. See
  # equipment_design.md "Get Item / Weapon / Armor Details".
  module Details
    module_function

    def item_details(stack, catalog)
      it = catalog.item_type(stack.item_type) || { definition: {}, category: nil }
      defn = it[:definition] || {}
      category = it[:category]

      {
        category: category,
        item_type: stack.item_type,
        definition: defn,
        tier: stack.tier,
        properties: stack.properties,
        equipped: stack.equipped,
        durability_damage: stack.durability_damage,
        display_name: DisplayName.call(stack, catalog),
        # A Stack `description` override (unique items, e.g. a named
        # magic Lute) wins over the Item Type's catalog description
        # (the authoritative source for generic items). See
        # equipment_design.md → Item fields.
        description: (stack.description || defn['description']),
        unit_price: Pricing.unit_price(stack, catalog),
        slot: defn['slot'],
        value_in_gold: (stack.value_in_gold if %w[Gem Currency].include?(category)),
        guidance_attribute: defn['guidance_attribute'],
        guidance_bonus: stack.guidance_bonus,
        inscribed_spells: stack.inscribed_spells,
        stored_spell: stack.stored_spell,
        innately_usable: !!defn['innately_usable']
      }
    end

    def weapon_details(stack, catalog)
      base = item_details(stack, catalog)
      defn = base[:definition]
      types = Array(defn['damage_type'])

      base.merge(
        damage_formula: damage_formula(defn, catalog),
        damage_types: types,
        bleed: bleed(defn, types, catalog),
        threshold: threshold_with_modifiers(stack, defn, types, catalog),
        speed: speed(defn, catalog),
        tags: defn['tags'] || [],
        ammo_type: defn['ammo_type'],
        damage_riders: damage_riders(stack, types, catalog)
      )
    end

    # The resolved per-hit Damage Riders a weapon Stack adds when an
    # attack lands — one entry per magical Property that declares a
    # `damage_rider` (equipment_design.md → Property Effects). The
    # sentinel Damage Types are resolved here so Combat reads a concrete
    # type: `from_subtype` → the Property's Subtype, `from_weapon` → the
    # weapon's first Damage Type. Combat rolls these dice at the attack's
    # Target Number and applies each as its own Severity Calculation.
    def damage_riders(stack, weapon_types, catalog)
      stack.properties.filter_map do |prop|
        pdef = catalog.property(prop[:name]) || {}
        rider = pdef['damage_rider'] or next
        on_success = rider['on_success'] || {}
        on_failure = rider['on_failure']
        disp = DisplayName.property_display(catalog, prop) || {}

        entry = {
          property: prop[:name], subtype: prop[:subtype],
          label: (disp['word'] || disp[:word] || prop[:name]),
          dice: Integer(rider['dice'] || 0), kind: on_success['kind'].to_s
        }
        if on_success['kind'].to_s == 'named_effect'
          entry[:effect] = on_success['name']
          entry[:amount] = Integer(on_success['amount'] || 1)
        else
          entry[:damage_type] = resolve_rider_type(on_success['damage_type'], prop[:subtype], weapon_types)
          entry[:amount]   = Integer(on_success['amount'] || 1)
          entry[:severity] = on_success['severity']
        end
        if on_failure && on_failure['kind'].to_s == 'self_damage'
          entry[:self_damage] = { severity: (on_failure['severity'] || 'minor').to_s,
                                  amount: Integer(on_failure['amount'] || 1),
                                  minimum: Integer(on_failure['minimum'] || 0) }
        end
        entry
      end
    end

    # Resolve a rider Damage Type, expanding the `from_subtype` /
    # `from_weapon` sentinels to a concrete lowercase Damage Type name.
    def resolve_rider_type(raw, subtype, weapon_types)
      case raw.to_s
      when 'from_subtype' then subtype.to_s.downcase
      when 'from_weapon'  then (Array(weapon_types).first || 'physical').to_s.downcase
      else raw.to_s
      end
    end

    # Combat-Pool cost multiplier for an attack with this weapon:
    # per-weapon `speed` → first Tag carrying `speed` → Weapon Category.
    def speed(defn, catalog)
      return defn['speed'] if defn.key?('speed')
      Array(defn['tags']).each do |tag|
        tag_def = catalog.weapon_tags[tag] || {}
        return tag_def['speed'] if tag_def.key?('speed')
      end
      cat = catalog.weapon_categories[defn['category']] || {}
      cat['speed']
    end

    def armor_details(stack, catalog)
      base = item_details(stack, catalog)
      defn = base[:definition]

      cat_defaults = catalog.armor_category_defaults[defn['category']] || {}
      material = defn['material']
      mat = catalog.materials[material] || {}
      base_hardness = mat['hardness']
      increment = cat_defaults['resilience_increment']

      base.merge(
        damage_reduction: cat_defaults['damage_reduction'],
        material: material,
        base_hardness: base_hardness,
        effective_hardness: (base_hardness.nil? ? nil : base_hardness + 2 * stack.tier),
        hit_points_formula: mat['hit_points'],
        thickness: cat_defaults['thickness'],
        resilience_increment: increment,
        resilience: (increment.nil? ? 0 : stack.tier * increment),
        is_metal_armor: !!defn['metal']
      )
    end

    # Sum a Creature's defensive mitigation across its equipped Armor
    # and Shield Stacks (both live in the 'Armor' Item Category). Null
    # Damage Reduction (Shields) and null Resilience Increment count as
    # zero. See equipment_design.md → Get Armor Details. Returns
    # { damage_reduction:, damage_resilience: }.
    def defensive_totals(stacks, catalog)
      Array(stacks)
        .select { |s| s.equipped && (it = catalog.item_type(s.item_type)) && it[:category] == 'Armor' }
        .each_with_object(damage_reduction: 0, damage_resilience: 0) do |s, acc|
          ad = armor_details(s, catalog)
          acc[:damage_reduction]  += ad[:damage_reduction].to_i
          acc[:damage_resilience] += ad[:resilience].to_i
        end
    end

    # ---- weapon field resolution ---------------------------------------

    # Per-weapon `base_damage` override → first Tag carrying a
    # `damage_formula` → Weapon Category default.
    def damage_formula(defn, catalog)
      return defn['base_damage'] if defn.key?('base_damage')

      Array(defn['tags']).each do |tag|
        tag_def = catalog.weapon_tags[tag] || {}
        return tag_def['damage_formula'] if tag_def.key?('damage_formula')
      end

      cat = catalog.weapon_categories[defn['category']] || {}
      cat['base_damage']
    end

    # Per-weapon override → max over the Damage Types' default Bleed.
    def bleed(defn, types, catalog)
      return defn['bleed'] if defn.key?('bleed')
      vals = types.filter_map { |t| catalog.damage_type_defaults.dig(t, 'bleed') }
      vals.max
    end

    # Per-weapon override (including explicit null) → min over the
    # Damage Types' default Threshold.
    def threshold(defn, types, catalog)
      return defn['threshold'] if defn.key?('threshold')
      vals = types.filter_map { |t| catalog.damage_type_defaults.dig(t, 'threshold') }
      vals.min
    end

    # The weapon Threshold plus the sum of every equipped Property's
    # `weapon_modifiers.threshold_delta` (equipment_design.md → Property
    # Effects). A weapon whose Threshold is explicitly null (e.g. Whip)
    # stays null — there is nothing to add a delta to.
    def threshold_with_modifiers(stack, defn, types, catalog)
      base = threshold(defn, types, catalog)
      return base if base.nil?
      delta = stack.properties.sum do |prop|
        wm = (catalog.property(prop[:name]) || {})['weapon_modifiers'] || {}
        Integer(wm['threshold_delta'] || 0)
      end
      base + delta
    end
  end
end
