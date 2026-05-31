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
        threshold: threshold(defn, types, catalog),
        speed: speed(defn, catalog),
        tags: defn['tags'] || [],
        ammo_type: defn['ammo_type']
      )
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
  end
end
