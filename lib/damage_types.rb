require 'yaml'
require 'set'

# DamageTypes — reference catalog of damage types.
#
# Loads the catalog from YAML at construction. Exposes per-type
# severity (or a runtime-bucketing flag for physical), a description,
# and a structured mechanics list. Consuming modules (combat,
# conditions, dice resolution) interpret the mechanics; this module
# only validates and returns them.
class DamageTypes
  RECOGNIZED_KINDS = %w[
    damage_per_dice
    apply_acid_counter
    damage_multiplier
    inflict
    critical_value
  ].freeze

  REQUIRED_FIELDS = {
    'damage_per_dice'    => %w[bonus per],
    'apply_acid_counter' => [],
    'damage_multiplier'  => %w[factor condition],
    'inflict'            => %w[condition_name per_damage],
    'critical_value'     => %w[value]
  }.freeze

  attr_reader :severities, :damage_types

  def initialize(config_path)
    raw = YAML.load_file(config_path) || {}
    @severities = (raw['Severities'] || []).map(&:to_s)
    @damage_types = (raw['Damage Types'] || {}).each_with_object({}) do |(key, definition), out|
      out[key.to_s] = (definition || {}).dup
    end
    validate!
  end

  def names
    @damage_types.keys
  end

  def known?(name)
    @damage_types.key?(name.to_s)
  end

  def definition(name)
    @damage_types[name.to_s] || raise(ArgumentError, "Unknown damage type: #{name}")
  end

  def description_for(name)
    definition(name)['description']
  end

  def runtime_bucketing?(name)
    definition(name)['runtime_bucketing'] == true
  end

  # Returns the declared severity, or nil for a runtime-bucketed type.
  def severity_for(name)
    definition(name)['severity']
  end

  def mechanics_for(name)
    Array(definition(name)['mechanics'])
  end

  private

  def validate!
    @damage_types.each do |name, definition|
      validate_severity!(name, definition)
      validate_mechanics!(name, definition)
    end
  end

  def validate_severity!(name, definition)
    has_severity = definition.key?('severity') && !definition['severity'].nil?
    has_bucketing = definition['runtime_bucketing'] == true
    if has_severity && has_bucketing
      raise ArgumentError,
            "Damage type #{name}: cannot declare both severity and runtime_bucketing"
    end
    return if has_bucketing
    unless has_severity
      raise ArgumentError,
            "Damage type #{name}: must declare either severity or runtime_bucketing"
    end
    severity = definition['severity'].to_s
    return if @severities.include?(severity)
    raise ArgumentError,
          "Damage type #{name}: severity #{severity.inspect} is not in #{@severities.inspect}"
  end

  def validate_mechanics!(name, definition)
    Array(definition['mechanics']).each_with_index do |mechanic, i|
      unless mechanic.is_a?(Hash)
        raise ArgumentError, "Damage type #{name}: mechanic[#{i}] must be a hash"
      end
      kind = mechanic['kind'] || mechanic[:kind]
      unless RECOGNIZED_KINDS.include?(kind.to_s)
        raise ArgumentError,
              "Damage type #{name}: mechanic[#{i}] has unrecognized kind #{kind.inspect}"
      end
      missing = REQUIRED_FIELDS.fetch(kind.to_s).reject do |field|
        mechanic.key?(field) || mechanic.key?(field.to_sym)
      end
      next if missing.empty?
      raise ArgumentError,
            "Damage type #{name}: mechanic[#{i}] (#{kind}) missing fields #{missing.inspect}"
    end
  end
end
