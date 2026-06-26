module Equipment
  class Stack
    attr_accessor :item_type, :quantity, :tier, :properties, :inscribed_spells,
                  :stored_spell, :durability_damage, :name_override, :equipped,
                  :value_in_gold, :gem_name, :guidance_bonus, :guidance_attribute,
                  :restock_target, :description
    attr_reader :daily_charges

    def initialize(item_type:, quantity: 1, tier: 0, properties: [],
                   inscribed_spells: [], stored_spell: nil, durability_damage: 0,
                   name_override: nil, equipped: false, value_in_gold: nil,
                   gem_name: nil, guidance_bonus: nil, guidance_attribute: nil,
                   restock_target: nil, description: nil, daily_charges: nil,
                   parry_used_day: nil)
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
      # Per-day item charges keyed by feature (e.g. 'parry'): { day:, used: }.
      # The cap (uses per day) lives in the catalog; recharge is implicit — a
      # use stamped on an earlier day reads as 0 today.
      @daily_charges     = self.class.normalize_daily_charges(daily_charges)
      # Migrate the legacy once-per-day parry charge onto the general map.
      if parry_used_day && !@daily_charges.key?('parry')
        @daily_charges['parry'] = { day: Integer(parry_used_day), used: 1 }
      end
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
        daily_charges:     h['daily_charges'],
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

    # Coerce a raw daily-charges map ({key => {day:, used:}}, string- or
    # symbol-keyed) into a normalized { 'key' => { day: Int, used: Int } }.
    def self.normalize_daily_charges(raw)
      return {} unless raw.is_a?(Hash)
      raw.each_with_object({}) do |(k, v), out|
        v = v.transform_keys(&:to_s) if v.respond_to?(:transform_keys)
        next unless v.is_a?(Hash) && v['day']
        out[k.to_s] = { day: Integer(v['day']), used: Integer(v['used'] || 1) }
      end
    end

    # Uses of `key` already spent on `today` — 0 once the last use was on an
    # earlier day (the charge has recharged).
    def daily_uses(key, today)
      c = @daily_charges[key.to_s]
      c && c[:day] == Integer(today) ? c[:used] : 0
    end

    # Record one use of `key` on `today`, resetting the count on a new day.
    def record_daily_use(key, today)
      key = key.to_s
      today = Integer(today)
      c = @daily_charges[key]
      if c && c[:day] == today
        c[:used] += 1
      else
        @daily_charges[key] = { day: today, used: 1 }
      end
      self
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
        description: @description, daily_charges: serialize_daily_charges
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
      h['daily_charges']     = serialize_daily_charges unless @daily_charges.empty?
      h
    end

    private

    def serialize_daily_charges
      @daily_charges.each_with_object({}) do |(k, v), out|
        out[k] = { 'day' => v[:day], 'used' => v[:used] }
      end
    end
  end
end
