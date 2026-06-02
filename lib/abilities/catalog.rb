module Abilities
  # Read-only view onto the abilities data files plus load-time
  # validation:
  #   spells.yaml            — Catalog Abilities (type: spell)
  #   talents.yaml           — Catalog Abilities (type: talent)
  #   stateful_abilities.yaml
  #   modifier_abilities.yaml
  #   abilities_config.yaml  — via Config
  #
  # Holds raw (un-resolved) entries; Resolver turns a raw Catalog Ability
  # into a resolved Variant. Validation runs once at load and raises
  # ArgumentError on the first violation.
  class Catalog
    DEFAULT_DIR = File.expand_path('../../docs/common/abilities', __dir__)

    # Fields that may be parallel lists indexed by the Variant Axis.
    PARALLEL_FIELDS = %w[name prefix suffix damage_type target area].freeze
    STRUCTURAL_OVERRIDE_FIELDS = %w[tier aspects prefix suffix name variant_overrides].freeze
    # Toxicity Source Kinds a Spell's polarity may name (owned by
    # Conditions; see conditions_design.md "Toxicity Source Kind").
    POLARITIES = %w[positive forced].freeze

    attr_reader :config, :catalog, :stateful, :modifier_abilities

    def initialize(config: nil, catalog: {}, stateful: {}, modifier_abilities: {})
      @config = config || Config.new
      @catalog = catalog
      @stateful = stateful
      @modifier_abilities = modifier_abilities
    end

    def self.load(dir = DEFAULT_DIR, config: nil)
      config ||= Config.load
      spells = YAML.safe_load_file(File.join(dir, 'spells.yaml')) || {}
      talents = YAML.safe_load_file(File.join(dir, 'talents.yaml')) || {}
      stateful = YAML.safe_load_file(File.join(dir, 'stateful_abilities.yaml')) || {}
      modifier_abilities = YAML.safe_load_file(File.join(dir, 'modifier_abilities.yaml')) || {}

      catalog = {}
      [spells, talents].each do |doc|
        doc.each { |name, entry| catalog[name] = normalize_entry(entry) }
      end

      instance = new(
        config: config,
        catalog: catalog,
        stateful: stateful,
        modifier_abilities: modifier_abilities
      )
      instance.validate!
      instance
    end

    # YAML 1.1 coerces a bare `on:` key to boolean `true`. The Trigger
    # Spec's field is named `on`, so restore the string key after load.
    def self.normalize_entry(entry)
      return entry unless entry.is_a?(Hash)
      trigger = entry['trigger']
      if trigger.is_a?(Hash) && trigger.key?(true)
        trigger['on'] = trigger.delete(true)
      end
      entry
    end

    def ability(name)
      @catalog[name.to_s]
    end

    def ability?(name)
      @catalog.key?(name.to_s)
    end

    def stateful_ability(name)
      @stateful[name.to_s]
    end

    def modifier_ability(name)
      @modifier_abilities[name.to_s]
    end

    # ---- Validation -----------------------------------------------------

    def validate!
      @catalog.each { |name, entry| validate_ability!(name, entry) }
      @modifier_abilities.each { |name, entry| validate_modifier_ability!(name, entry) }
      true
    end

    private

    def err(name, msg)
      raise ArgumentError, "#{name}: #{msg}"
    end

    def validate_ability!(name, a)
      type = a['type']
      err(name, "unknown type #{type.inspect}") unless @config.ability_types.include?(type)
      talent = (type == 'talent')

      validate_axis!(name, a)
      validate_inheritance!(name, a)
      validate_school!(name, a, talent)
      validate_polarity!(name, a, talent)
      validate_skills!(name, a)
      validate_items!(name, a, talent)
      validate_properties!(name, a)
      validate_activation!(name, a)
      validate_range!(name, a)
      validate_saves!(name, a)
      validate_damage!(name, a)
      validate_area!(name, a)
      validate_trigger!(name, a)
      validate_modifiers!(name, a['modifiers'])
      validate_variant_overrides!(name, a)
      validate_parallel_lengths!(name, a)
    end

    def axis_length(a)
      return a['tier'].length if a['tier'].is_a?(Array)
      return a['aspects'].length if a['aspects'].is_a?(Array)
      1
    end

    def validate_axis!(name, a)
      if a['tier'].is_a?(Array) && a['aspects'].is_a?(Array)
        err(name, 'declares both a tier list and aspects (mutually exclusive)')
      end
    end

    def validate_inheritance!(name, a)
      parent = a['inherits_from']
      return unless parent
      err(name, "inherits_from unknown ability #{parent.inspect}") unless ability?(parent)
    end

    def validate_school!(name, a, talent)
      school = a['school']
      if talent
        err(name, 'school is not allowed on a Talent') if school
        return
      end
      return unless school
      err(name, "unknown school #{school.inspect}") unless @config.spell_schools.key?(school)
    end

    def validate_polarity!(name, a, talent)
      p = a['polarity']
      return if p.nil?
      err(name, 'polarity is not allowed on a Talent') if talent
      err(name, "unknown polarity #{p.inspect}") unless POLARITIES.include?(p)
    end

    def validate_skills!(name, a)
      skills = a['skills']
      return unless skills
      err(name, 'skills must be a list') unless skills.is_a?(Array)
      skills.each do |s|
        err(name, "unknown casting skill #{s.inspect}") unless @config.casting_skill?(s)
        if @config.universal_casting_skills.include?(s)
          err(name, "must not list the universal casting skill #{s.inspect}")
        end
      end
    end

    def validate_items!(name, a, talent)
      if talent
        err(name, 'items are not allowed on a Talent') if a.key?('items')
        err(name, 'item_only is not allowed on a Talent') if a.key?('item_only')
        return
      end
      items = a['items']
      return unless items
      err(name, 'items must be a list') unless items.is_a?(Array)
      items.each do |i|
        err(name, "unknown item form #{i.inspect}") unless @config.item_forms.key?(i)
        if @config.universal_item_forms.include?(i)
          err(name, "must not list the universal item form #{i.inspect}")
        end
      end
    end

    def validate_properties!(name, a)
      props = a['properties']
      return unless props
      props.each do |p|
        err(name, "unknown property #{p.inspect}") unless @config.properties.key?(p)
      end
    end

    def validate_activation!(name, a)
      at = a['activation_time']
      return if at.nil?
      return if @config.action_aliases.key?(at)
      return if @config.real_time_aliases.key?(at)
      return if at =~ /\A\d+\s+turns?\z/
      return if at =~ /\A\d+\s+minutes?\z/
      err(name, "unknown activation_time #{at.inspect}")
    end

    def validate_range!(name, a)
      r = a['range']
      return if r.nil? || r.is_a?(Integer)
      values = r.is_a?(Array) ? r : [r]
      values.each do |v|
        next if v.nil? || v.is_a?(Integer)
        next if @config.range_formulas.key?(v)
        err(name, "unknown range #{v.inspect}")
      end
    end

    def each_save_spec(a)
      return enum_for(:each_save_spec, a) unless block_given?
      Array(a['save']).each { |spec| yield spec }
      area = a['area']
      areas = area.is_a?(Array) ? area : [area]
      areas.each do |ar|
        next unless ar.is_a?(Hash)
        %w[on_enter on_end_of_turn].each do |key|
          Array(ar[key]).each { |spec| yield spec }
        end
      end
    end

    def validate_saves!(name, a)
      each_save_spec(a) do |spec|
        next unless spec.is_a?(Hash)
        attr = spec['attribute']
        err(name, "unknown save attribute #{attr.inspect}") unless @config.save_attributes.include?(attr)
        cond = spec['condition']
        if cond && !%w[on_fail on_fumble].include?(cond)
          err(name, "unknown save condition #{cond.inspect}")
        end
        st = spec['save_target']
        if st && !%w[target observers area_creatures caster].include?(st)
          err(name, "unknown save_target #{st.inspect}")
        end
        err(name, 'save spec must define a fail outcome') unless spec.key?('fail')
      end
    end

    # Damage Type / Severity / Threshold rules. A damage Effect must have
    # a determinable Severity (explicit in the string, or via the
    # Ability's damage_type). physical damage_type requires a threshold;
    # threshold is rejected on non-physical Abilities.
    def validate_damage!(name, a)
      dts = a['damage_type'].is_a?(Array) ? a['damage_type'] : [a['damage_type']].compact
      dts.each do |dt|
        err(name, "unknown damage_type #{dt.inspect}") unless @config.damage_type?(dt)
      end

      physical = dts.include?('physical')
      if a.key?('threshold')
        err(name, 'threshold is only allowed when damage_type is physical') unless physical
        th = a['threshold']
        err(name, 'threshold must be a non-negative integer') unless th.is_a?(Integer) && th >= 0
      elsif physical
        err(name, 'damage_type physical requires a threshold')
      end

      has_damage_type = !dts.empty?
      damage_effect_strings(a).each do |str|
        m = Effect::DAMAGE_RE.match(str.to_s)
        next unless m
        explicit_severity = m[2]
        next if explicit_severity || has_damage_type
        err(name, "damage effect #{str.inspect} has no determinable severity")
      end
    end

    def damage_effect_strings(a)
      strings = []
      strings.concat(Array(a['effects']))
      each_save_spec(a) do |spec|
        next unless spec.is_a?(Hash)
        @config.save_outcome_keys.each do |k|
          strings << spec[k] if spec[k].is_a?(String)
        end
      end
      strings
    end

    def validate_area!(name, a)
      area = a['area']
      return if area.nil?
      areas = area.is_a?(Array) ? area : [area]
      areas.each do |ar|
        next if ar.nil?
        err(name, 'area must be a mapping') unless ar.is_a?(Hash)
        shape = ar['shape']
        err(name, "unknown area shape #{shape.inspect}") unless @config.area_shapes.key?(shape)
        size = ar['size']
        err(name, 'area size must be a non-negative integer') unless size.is_a?(Integer) && size >= 0
      end
    end

    def validate_trigger!(name, a)
      trigger = a['trigger']
      return unless trigger
      on = trigger['on']
      err(name, "unknown trigger event #{on.inspect}") unless @config.trigger_events.include?(on)
      err(name, 'trigger requires an effect') unless trigger['effect'].is_a?(Hash)
    end

    def validate_modifiers!(name, modifiers)
      return unless modifiers
      err(name, 'modifiers must be a list') unless modifiers.is_a?(Array)
      modifiers.each do |m|
        type = m['type']
        next if type.nil?
        err(name, "unknown bonus type #{type.inspect}") unless @config.bonus_types.key?(type)
      end
    end

    def validate_variant_overrides!(name, a)
      overrides = a['variant_overrides']
      return unless overrides
      err(name, 'variant_overrides must be a list') unless overrides.is_a?(Array)
      overrides.each do |o|
        next if o.nil?
        err(name, 'each variant override must be a mapping or null') unless o.is_a?(Hash)
        o.keys.each do |k|
          if STRUCTURAL_OVERRIDE_FIELDS.include?(k)
            err(name, "variant override may not change structural field #{k.inspect}")
          end
        end
      end
    end

    def validate_parallel_lengths!(name, a)
      len = axis_length(a)
      (PARALLEL_FIELDS + ['variant_overrides']).each do |field|
        v = a[field]
        next unless v.is_a?(Array)
        if v.length != len
          err(name, "#{field} has #{v.length} entries but the Variant Axis has #{len}")
        end
      end
      eh = a['effect_hash']
      return unless eh.is_a?(Hash) && len > 1
      eh.each do |k, v|
        next unless v.is_a?(Array)
        if v.length != len
          err(name, "effect_hash #{k.inspect} has #{v.length} entries but the Variant Axis has #{len}")
        end
      end
    end

    def validate_modifier_ability!(name, entry)
      return unless entry.is_a?(Hash)
      validate_modifiers!(name, entry['modifiers'])
    end
  end
end
