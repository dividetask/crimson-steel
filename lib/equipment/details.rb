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
        # Affliction (e.g. a venom) the weapon injects on a hit — Combat
        # offers a poison input alongside damage / bleed when present.
        # `affliction_potency` is the Bleed-style constant added to the
        # damage dealt to form the injected Potency.
        affliction: defn['affliction'],
        affliction_potency: defn['affliction_potency'],
        enhancement: enhancement(stack, defn),
        enchantment: enchantment(stack, types, catalog)
      )
    end

    # The weapon's +X enhancement: its Tier (0 for a mundane or natural
    # weapon). +X adds X Guidance to the attack and X extra dice
    # (equipment_design.md → Enhancement and Enchantment).
    def enhancement(stack, defn)
      return 0 if defn['natural']
      [stack.tier.to_i, 0].max
    end

    # The weapon's single typed enchantment (the last Property that declares
    # a `flavor` — a newer enchantment supersedes an older one), resolved so
    # Combat reads a concrete Damage Type, or nil.
    # A typed weapon's X extra dice are flavored, and its bonus damage
    # converts to the flavor's type (or to Merciful shock).
    def enchantment(stack, weapon_types, catalog)
      stack.properties.reverse_each do |prop|
        pdef = catalog.property(prop[:name]) || {}
        fl = pdef['flavor'] or next
        disp = DisplayName.property_display(catalog, prop) || {}
        entry = { property: prop[:name], subtype: prop[:subtype],
                  label: (disp['word'] || disp[:word] || prop[:name]).to_s }
        if fl['effect']
          entry[:effect] = fl['effect'].to_s
          entry[:amount] = Integer(fl['amount'] || 1)
        else
          entry[:damage_type] = resolve_rider_type(fl['damage_type'], prop[:subtype], weapon_types)
        end
        entry[:severity]   = fl['severity'].to_s if fl['severity']
        entry[:multiplier] = Integer(fl['multiplier'] || 1)
        entry[:only_vs_higher_tier] = true if fl['only_vs_higher_tier']
        if (sd = fl['self_damage_per_one'])
          entry[:self_damage_per_one] = { severity: (sd['severity'] || 'minor').to_s, amount: Integer(sd['amount'] || 1) }
        end
        return entry
      end
      nil
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

    # Per-equipped-Armor contributions, so a sheet can spell out the math
    # behind the Damage Reduction / Resilience totals piece by piece. One
    # entry per equipped Armor / Shield Stack: its display name, Tier, the
    # Damage Reduction it grants, and its Resilience with the
    # `tier × increment` factors that produced it (increment nil for a
    # Shield). See defensive_totals for the summed form.
    def defensive_components(stacks, catalog)
      Array(stacks)
        .select { |s| s.equipped && (it = catalog.item_type(s.item_type)) && it[:category] == 'Armor' }
        .map do |s|
          ad = armor_details(s, catalog)
          { name: ad[:display_name], tier: s.tier.to_i,
            damage_reduction: ad[:damage_reduction].to_i,
            resilience: ad[:resilience].to_i,
            resilience_increment: ad[:resilience_increment] }
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
