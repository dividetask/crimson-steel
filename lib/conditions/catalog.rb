module Conditions
  # Read-only view onto the three YAML files Conditions consults:
  #   conditions_config.yaml        — tunables
  #   conditions_afflictions.yaml   — Affliction Rule catalog
  #   conditions_effect_names.yaml  — Effect Name catalog
  #
  # Catalog#load builds an instance from a directory; tests may also
  # construct a Catalog directly from in-memory hashes.
  class Catalog
    DEFAULT_DIR = File.expand_path('../../docs/common/conditions', __dir__)

    attr_reader :config, :afflictions, :effect_names

    def initialize(config: {}, afflictions: {}, effect_names: {})
      @config = config
      @afflictions = afflictions
      @effect_names = effect_names
    end

    def self.load(dir = DEFAULT_DIR)
      config = YAML.safe_load_file(File.join(dir, 'conditions_config.yaml')) || {}
      afflictions_doc = YAML.safe_load_file(File.join(dir, 'conditions_afflictions.yaml')) || {}
      effect_names_doc = YAML.safe_load_file(File.join(dir, 'conditions_effect_names.yaml')) || {}
      new(
        config: config,
        afflictions: afflictions_doc['Afflictions'] || {},
        effect_names: effect_names_doc['Effect Names'] || {}
      )
    end

    # ---- Magnitude / save penalty ----
    def potency_divisor
      @config.fetch('Potency Divisor', 10)
    end

    # ---- Toxicity ----
    def toxicity_threshold_attribute
      (@config.dig('Toxicity Threshold', 'Attribute') || 'cha').to_sym
    end

    def toxicity_threshold_tier_scaled?
      v = @config.dig('Toxicity Threshold', 'Tier Scaled')
      v.nil? ? true : v
    end

    def toxicity_damage_severity
      (@config.fetch('Toxicity Damage Severity', 'major')).to_sym
    end

    # ---- Death ----
    def death_multiplier
      @config.fetch('Death Multiplier', 2.0)
    end

    # ---- Potency evolution defaults ----
    def default_potency_per_success
      @config.fetch('Default Potency Per Success', 1)
    end

    def default_potency_per_failure
      @config.fetch('Default Potency Per Failure', 1)
    end

    def default_potency_decay
      @config.fetch('Default Potency Decay', 'tier')
    end

    # ---- Affliction scheduling ----
    def frequency_rounds(freq)
      (@config['Frequency Rounds'] || {})[freq.to_s] || 1
    end

    # ---- Natural Recovery ----
    def recovery_tick_rounds
      @config.dig('Natural Recovery', 'Recovery Tick') || 14400
    end

    def mana_per_recovery_tick_divisor
      @config.dig('Natural Recovery', 'Mana Per Recovery Tick Divisor') || 4
    end

    def magic_toxicity_per_recovery_tick_divisor
      @config.dig('Natural Recovery', 'Magic Toxicity Per Recovery Tick Divisor') || 4
    end

    def heal_rate(severity, tier, mode)
      lookup_rate('Heal Rate', severity, tier, mode)
    end

    def ability_heal_rate(severity, tier, mode)
      lookup_rate('Ability Heal Rate', severity, tier, mode)
    end

    # ---- Affliction lookup ----
    def affliction(name)
      @afflictions[name.to_s] || raise(ArgumentError, "unknown affliction: #{name.inspect}")
    end

    def affliction?(name)
      @afflictions.key?(name.to_s)
    end

    # ---- Effect Names lookup ----
    def effect_name(name)
      @effect_names[name.to_s] || raise(ArgumentError, "unknown effect name: #{name.inspect}")
    end

    def effect_name?(name)
      @effect_names.key?(name.to_s)
    end

    private

    def lookup_rate(table_name, severity, tier, mode)
      table = @config.dig('Natural Recovery', table_name, severity.to_s)
      raise ArgumentError, "no #{table_name} for severity #{severity}" unless table
      raise ArgumentError, "tier #{tier} out of bounds for #{table_name}" if tier < 0 || tier >= table.size
      pair = table[tier][mode.to_s]
      raise ArgumentError, "no #{table_name} entry for mode #{mode}" unless pair
      pair
    end
  end
end
