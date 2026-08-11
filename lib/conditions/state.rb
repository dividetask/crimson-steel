module Conditions
  # Per-Creature mutable state. Round-trips through Conditions State
  # serialization. Field defaults match `conditions_design.md`:
  # missing fields → "no state of that kind".
  class State
    attr_accessor :hp_damage, :ability_damage, :temporary_hit_points,
                  :mana_spent, :magic_toxicity, :shock, :acid_counter,
                  :elemental_wound, :regen_major_round,
                  :afflictions, :effects, :named_effect_mechanics

    def initialize(
      hp_damage: {},
      ability_damage: {},
      temporary_hit_points: nil,
      mana_spent: 0,
      magic_toxicity: 0,
      shock: 0,
      acid_counter: 0,
      elemental_wound: 0,
      regen_major_round: nil,
      afflictions: {},
      effects: [],
      named_effect_mechanics: []
    )
      @hp_damage = normalize_hp_damage(hp_damage)
      @ability_damage = normalize_ability_damage(ability_damage)
      @temporary_hit_points = temporary_hit_points ? normalize_temp_hp(temporary_hit_points) : nil
      @mana_spent = Integer(mana_spent)
      @magic_toxicity = Integer(magic_toxicity)
      @shock = Integer(shock)
      @acid_counter = Integer(acid_counter)
      @elemental_wound = Integer(elemental_wound)
      @regen_major_round = regen_major_round.nil? ? nil : Integer(regen_major_round)
      @afflictions = normalize_afflictions(afflictions)
      @effects = effects.map { |e| normalize_effect(e) }
      @named_effect_mechanics = named_effect_mechanics.map { |m| m.transform_keys(&:to_sym) }
      validate!
    end

    def self.load(data)
      data ||= {}
      data = data.transform_keys(&:to_s) if data.respond_to?(:transform_keys)
      new(
        hp_damage:            data['hp_damage'] || {},
        ability_damage:       data['ability_damage'] || {},
        temporary_hit_points: data['temporary_hit_points'],
        mana_spent:           data.fetch('mana_spent', 0),
        magic_toxicity:       data.fetch('magic_toxicity', 0),
        shock:                data.fetch('shock', 0),
        acid_counter:         data.fetch('acid_counter', 0),
        elemental_wound:      data.fetch('elemental_wound', 0),
        regen_major_round:    data['regen_major_round'],
        afflictions:          data['afflictions'] || {},
        effects:              data['effects'] || [],
        named_effect_mechanics: data['named_effect_mechanics'] || []
      )
    end

    # Save State — produces a hash representation; empty / zero fields
    # are omitted so a baseline Creature serializes as {}.
    def to_h
      h = {}
      h['hp_damage'] = @hp_damage.transform_keys(&:to_s) if @hp_damage.any?
      if @ability_damage.any?
        h['ability_damage'] = @ability_damage.each_with_object({}) do |(sev, attrs), m|
          m[sev.to_s] = attrs.transform_keys(&:to_s)
        end
      end
      h['temporary_hit_points'] = @temporary_hit_points.transform_keys(&:to_s) if @temporary_hit_points
      h['mana_spent']     = @mana_spent     unless @mana_spent.zero?
      h['magic_toxicity'] = @magic_toxicity unless @magic_toxicity.zero?
      h['shock']          = @shock          unless @shock.zero?
      h['acid_counter']   = @acid_counter   unless @acid_counter.zero?
      h['elemental_wound'] = @elemental_wound unless @elemental_wound.zero?
      h['regen_major_round'] = @regen_major_round unless @regen_major_round.nil?
      if @afflictions.any?
        h['afflictions'] = @afflictions.each_with_object({}) do |(name, a), m|
          m[name] = a.transform_keys(&:to_s)
        end
      end
      h['effects'] = @effects.map { |e| e.transform_keys(&:to_s) } if @effects.any?
      h['named_effect_mechanics'] = @named_effect_mechanics.map { |m| m.transform_keys(&:to_s) } if @named_effect_mechanics.any?
      h
    end

    # Treat counter as zero when the Severity key is absent.
    def hp_damage_at(severity)
      @hp_damage[severity.to_sym] || 0
    end

    def ability_damage_at(severity)
      @ability_damage[severity.to_sym] || {}
    end

    # Exposed for callers that need to normalize a single Active Effect
    # hash (e.g. Apply Effect, Apply Named Effect's modifier dispatch).
    def self.normalize_effect(e)
      new(effects: [e]).effects.first
    end

    private

    def normalize_hp_damage(input)
      out = {}
      input.each do |k, v|
        sev = k.to_sym
        unless SEVERITIES.include?(sev)
          raise ArgumentError, "unknown Severity in hp_damage: #{k.inspect}"
        end
        n = Integer(v)
        raise ArgumentError, "hp_damage[#{sev}] must be >= 0" if n < 0
        out[sev] = n if n > 0
      end
      out
    end

    def normalize_ability_damage(input)
      out = {}
      input.each do |sev_k, attrs|
        sev = sev_k.to_sym
        unless SEVERITIES.include?(sev)
          raise ArgumentError, "unknown Severity in ability_damage: #{sev_k.inspect}"
        end
        bucket = {}
        attrs.each do |attr_k, v|
          n = Integer(v)
          raise ArgumentError, "ability_damage[#{sev}][#{attr_k}] must be >= 0" if n < 0
          bucket[attr_k.to_sym] = n if n > 0
        end
        out[sev] = bucket unless bucket.empty?
      end
      out
    end

    def normalize_temp_hp(t)
      t = t.transform_keys(&:to_s) if t.respond_to?(:transform_keys)
      amount = Integer(t.fetch('amount'))
      source_id = t.fetch('source_id').to_s
      ends = t['ends_on_round']
      ends = Integer(ends) unless ends.nil?
      { amount: amount, source_id: source_id, ends_on_round: ends }
    end

    def normalize_afflictions(input)
      out = {}
      input.each do |name, a|
        a = a.transform_keys(&:to_s) if a.respond_to?(:transform_keys)
        potency = Integer(a.fetch('potency'))
        raise ArgumentError, "affliction potency must be >= 1" if potency < 1
        out[name.to_s] = {
          potency: potency,
          inflicting_tier: Integer(a.fetch('inflicting_tier')),
          next_resolution_round: a['next_resolution_round']&.then { |r| Integer(r) }
        }
      end
      out
    end

    def normalize_effect(e)
      e = e.transform_keys(&:to_s) if e.respond_to?(:transform_keys)
      tk = e.fetch('target_key')
      tk = tk.is_a?(Array) ? tk.map(&:to_s) : tk.to_s
      amt = e.fetch('amount')
      amt = Integer(amt) if amt.is_a?(Numeric) || (amt.is_a?(String) && amt.match?(/\A-?\d+\z/))
      {
        target_key: tk,
        bonus_type: e.fetch('bonus_type').to_s,
        amount: amt,
        ends_on_round: e['ends_on_round']&.then { |r| Integer(r) },
        source_id: e.fetch('source_id').to_s,
        metadata: e['metadata'] || {}
      }
    end

    def validate!
      raise ArgumentError, "mana_spent must be >= 0" if @mana_spent < 0
      raise ArgumentError, "magic_toxicity must be >= 0" if @magic_toxicity < 0
      raise ArgumentError, "shock must be >= 0" if @shock < 0
      raise ArgumentError, "acid_counter must be >= 0" if @acid_counter < 0
      raise ArgumentError, "elemental_wound must be >= 0" if @elemental_wound < 0
    end
  end
end
