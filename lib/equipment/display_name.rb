module Equipment
  # Generated Display Name composition. See equipment_design.md
  # "Generated Display Name". A Name Override short-circuits everything.
  module DisplayName
    module_function

    def call(stack, catalog)
      return stack.name_override if present?(stack.name_override)

      it = catalog.item_type(stack.item_type)
      category = it && it[:category]

      prefixes = []
      suffixes = []
      stack.properties.each do |prop|
        disp = property_display(catalog, prop)
        next unless disp
        word = disp['word'] || disp[:word]
        next unless present?(word)
        position = (disp['position'] || disp[:position] || catalog.default_property_position).to_s
        (position == 'suffix' ? suffixes : prefixes) << word
      end

      tokens = []
      tp = tier_prefix(stack, category, catalog, it && it[:definition])
      tokens << tp if present?(tp)
      tokens.concat(prefixes)
      tokens << stack.item_type
      tokens.concat(suffixes)
      tokens.join(' ')
    end

    # The leading "+N" prefix. For a Guidance Item the N is the Guidance
    # Bonus (the player-facing number — a +2 Belt of Strength reads "+2"
    # even though it is Tier 1); for every other Item it is the Tier.
    def tier_prefix(stack, category, catalog, definition = nil)
      if definition.is_a?(Hash) && definition.key?('guidance_bonus') && stack.guidance_bonus
        return '' if stack.guidance_bonus.to_i < 1
        return catalog.tier_prefix_format.gsub('{tier}', stack.guidance_bonus.to_s)
      end
      return '' if stack.tier.to_i < 1
      return '' if category && catalog.tier_hidden_for.include?(category)
      catalog.tier_prefix_format.gsub('{tier}', stack.tier.to_s)
    end

    def property_display(catalog, prop)
      entry = catalog.property(prop[:name])
      return nil unless entry
      display = entry['display']
      return nil unless display
      if entry['has_subtype'] && prop[:subtype]
        display[prop[:subtype].to_s]
      else
        display
      end
    end

    def present?(s)
      !s.nil? && !s.to_s.empty?
    end
  end
end
