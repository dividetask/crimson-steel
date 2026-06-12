module Equipment
  # An Item Stack: a Quantity of one Item Type sharing every
  # per-instance characteristic. See equipment_design.md "Item Stack"
  # and "Stack Identity matching".
  #
  # The internal representation uses the design-doc field names
  # (`item_type`, `name_override`, Property Applications carrying
  # `cost`). Stack.normalize also accepts the shorthand used in the
  # YAML data files (`item:`, `name:`, bare-string Properties).
  class Stack
    attr_accessor :item_type, :quantity, :tier, :properties, :inscribed_spells,
                  :stored_spell, :durability_damage, :name_override, :equipped,
                  :value_in_gold, :gem_name, :guidance_bonus, :guidance_attribute,
                  :restock_target, :description, :parry_used_day

    def initialize(item_type:, quantity: 1, tier: 0, properties: [],
                   inscribed_spells: [], stored_spell: nil, durability_damage: 0,
                   name_override: nil, equipped: false, value_in_gold: nil,
                   gem_name: nil, guidance_bonus: nil, guidance_attribute: nil,
                   restock_target: nil, description: nil, parry_used_day: nil)
      @item_type         = item_type.to_s
      @quantity          = quantity
      @tier              = Integer(tier)
      @properties        = properties.map { |p| self.class.normalize_property(p) }
      @inscribed_spells  = Array(inscribed_spells).map(&:to_s)
      @stored_spell      = stored_spell&.to_s
      @durability_damage = Integer(durability_damage || 0)
      @name_override     = name_override
      @equipped          = !!equipped
      @value_in_gold     = value_in_gold
      @gem_name          = gem_name
      @guidance_bonus    = guidance_bonus.nil? ? nil : Integer(guidance_bonus)
      # An optional per-Stack Guidance target (a skill key like `stealth` or
      # `perform_drums`): lets a one-off magic Item grant a Guidance Bonus to a
      # named check without a bespoke catalog Item Type. Falls back to the
      # Item Type's own `guidance_attribute` when absent (the catalog Belts).
      @guidance_attribute = guidance_attribute&.to_s
      @restock_target    = restock_target.nil? ? nil : Integer(restock_target)
      @description       = description
      # The in-world day_index a once-per-day item charge was last spent (a Ring
      # of Parry). nil = never spent / fully charged. Not an identity field — a
      # spent and an unspent Ring still merge as the same Item (quantity 1 in
      # practice). Recharges when the current day_index passes this value.
      @parry_used_day    = parry_used_day.nil? ? nil : Integer(parry_used_day)
    end

    # Accepts a Stack (returned as-is), or a raw hash with either the
    # design-doc keys or the YAML data-file shorthand.
    def self.normalize(raw)
      return raw if raw.is_a?(Stack)
      h = raw.transform_keys(&:to_s)
      item_type = h['item_type'] || h['item']
      is_gem = item_type.to_s == 'Gem'
      new(
        item_type:         item_type,
        quantity:          h.fetch('quantity', 1),
        tier:              h.fetch('tier', 0),
        properties:        h['properties'] || [],
        inscribed_spells:  h['inscribed_spells'] || [],
        stored_spell:      h['stored_spell'],
        durability_damage: h.fetch('durability_damage', 0),
        # On a Gem, `name:` is the gem name, not a display override.
        name_override:     h['name_override'] || (is_gem ? nil : h['name']),
        equipped:          h.fetch('equipped', false),
        value_in_gold:     h['value_in_gold'],
        gem_name:          h['gem_name'] || (is_gem ? h['name'] : nil),
        guidance_bonus:    h['guidance_bonus'],
        guidance_attribute: h['guidance_attribute'],
        restock_target:    h['restock_target'],
        description:       h['description'],
        parry_used_day:    h['parry_used_day']
      )
    end

    # A Property Application is `{name:, subtype:, cost:}`. Accepts a
    # bare string (non-subtyped), or a hash with any subset of keys.
    def self.normalize_property(p)
      if p.is_a?(String)
        { name: p, subtype: nil, cost: nil }
      else
        h = p.transform_keys(&:to_s)
        { name: h['name'].to_s,
          subtype: h['subtype'],
          cost: h['cost'] }
      end
    end

    # The ordered tuple of identity fields. Two Stacks merge iff their
    # identity tuples are equal. `restock_target` is deliberately absent.
    def identity
      [
        @item_type, @tier,
        @properties.map { |p| [p[:name], p[:subtype], p[:cost]] },
        @inscribed_spells.dup,
        @stored_spell, @durability_damage, @name_override, @equipped,
        @value_in_gold, @gem_name, @guidance_bonus, @guidance_attribute
      ]
    end

    def same_identity?(other)
      identity == other.identity
    end

    # Merge another matching-identity Stack into this one. Quantity is
    # summed; a Restock Target conflict keeps this (earlier) Stack's
    # value and warns.
    def merge!(other)
      @quantity += other.quantity
      if @restock_target.nil?
        @restock_target = other.restock_target
      elsif other.restock_target && other.restock_target != @restock_target
        warn "Equipment: restock_target conflict on #{@item_type} " \
             "(keeping #{@restock_target}, ignoring #{other.restock_target})"
      end
      self
    end

    # A copy carrying the same identity fields but an explicit Quantity.
    # Used by Transfer / Drop / Distribute.
    def with_quantity(qty)
      dup_stack = dup_identity
      dup_stack.quantity = qty
      dup_stack
    end

    def dup_identity
      Stack.new(
        item_type: @item_type, quantity: @quantity, tier: @tier,
        properties: @properties.map(&:dup), inscribed_spells: @inscribed_spells.dup,
        stored_spell: @stored_spell, durability_damage: @durability_damage,
        name_override: @name_override, equipped: @equipped,
        value_in_gold: @value_in_gold, gem_name: @gem_name,
        guidance_bonus: @guidance_bonus, guidance_attribute: @guidance_attribute,
        restock_target: @restock_target,
        description: @description, parry_used_day: @parry_used_day
      )
    end

    def gem?      ; @item_type == 'Gem' ; end

    # Serialized back to the YAML data-file shorthand. Default-valued
    # fields are omitted. Property `cost` is dropped (re-hydrated from
    # the catalog on load).
    def to_h
      h = { 'item' => @item_type }
      h['quantity']          = @quantity          unless @quantity == 1
      h['tier']              = @tier              unless @tier.zero?
      unless @properties.empty?
        h['properties'] = @properties.map do |p|
          p[:subtype] ? { 'name' => p[:name], 'subtype' => p[:subtype] } : p[:name]
        end
      end
      h['inscribed_spells']  = @inscribed_spells  unless @inscribed_spells.empty?
      h['stored_spell']      = @stored_spell      if @stored_spell
      h['durability_damage'] = @durability_damage unless @durability_damage.zero?
      if gem?
        h['name'] = @gem_name if @gem_name
      elsif @name_override
        h['name'] = @name_override
      end
      h['equipped']          = true               if @equipped
      h['value_in_gold']     = @value_in_gold     unless @value_in_gold.nil?
      h['guidance_bonus']    = @guidance_bonus    unless @guidance_bonus.nil?
      h['guidance_attribute'] = @guidance_attribute if @guidance_attribute
      h['restock_target']    = @restock_target    unless @restock_target.nil?
      h['description']       = @description        if @description
      h['parry_used_day']    = @parry_used_day     unless @parry_used_day.nil?
      h
    end
  end
end
