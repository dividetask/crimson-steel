module Equipment
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
      @guidance_attribute = guidance_attribute&.to_s
      @restock_target    = restock_target.nil? ? nil : Integer(restock_target)
      @description       = description
      @parry_used_day    = parry_used_day.nil? ? nil : Integer(parry_used_day)
    end

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

    def self.from_catalog(name, catalog)
      defn = (catalog.item_type(name) || {})[:definition] || {}
      raw = { 'item' => name }
      props = defn['intrinsic_properties']
      raw['properties'] = props if props.is_a?(Array) && !props.empty?
      normalize(raw)
    end

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
