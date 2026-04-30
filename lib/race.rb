# Race — looks up a character's race definition (and any parent
# races via parent_race) and reports the bonuses and abilities
# the race grants.
#
# Character holds the *base* attribute scores and delegates to its
# Race to find out the racial adjustment to add on top of the base
# (alongside the tier and focused-attribute bonuses from
# Advancement). Race also exposes the character's speed, size, and
# the racial abilities they have — including any that scale with
# the character's total class level.
#
# Sub-races are modeled with `parent_race`. A sub-race's speed,
# ability adjustments, and abilities are merged with the parent's;
# a sub-race that omits a field inherits the parent's value.

require 'yaml'
require_relative 'advancement'

class Race
  DEFAULT_MIN_LEVEL = Advancement::DEFAULT_MIN_LEVEL

  Ability = Advancement::Ability

  attr_reader :key

  def initialize(key:, race_definitions: {}, character_level: 0)
    @key              = key.to_s
    @race_definitions = race_definitions || {}
    @character_level  = character_level.to_i
  end

  def name
    first_in_chain('name') || @key
  end

  def size
    first_in_chain('size')
  end

  def speed
    first_in_chain('speed')
  end

  # Cumulative adjustment to each attribute, summed across the
  # parent_race chain. Returns a hash keyed by attribute string
  # (only the attributes the race actually adjusts — unset keys
  # have an implicit zero).
  def ability_score_adjustments
    result = Hash.new(0)
    chain.each do |race_key|
      defn = race_definition(race_key)
      Array(defn['ability_score_adjustments'] || defn[:ability_score_adjustments] || {}).each do |attr, val|
        result[attr.to_s] += val.to_i
      end
    end
    result
  end

  def adjustment_for(attr_sym)
    ability_score_adjustments[attr_sym.to_s].to_i
  end

  # Racial abilities the character has earned, as Ability structs
  # (same shape Advancement uses). Scaling abilities carry the
  # character's total class level; non-scaling abilities carry a
  # nil level. Abilities accumulate up the parent_race chain.
  def abilities
    granted = {} # name => { level: Integer|nil, scales: Boolean, description: String|nil }

    chain.each do |race_key|
      Array(race_ability_defs(race_key)).each do |ability_def|
        name = ability_def['name'] || ability_def[:name]
        next if name.nil?
        min_level = (ability_def['min_level'] || ability_def[:min_level] || DEFAULT_MIN_LEVEL).to_i
        next if @character_level < min_level

        scales = ability_def['scales_with_level'] || ability_def[:scales_with_level] ? true : false
        slot   = granted[name] ||= { level: nil, scales: false, description: nil }
        slot[:description] ||= (ability_def['description'] || ability_def[:description])
        if scales
          slot[:scales] = true
          slot[:level]  = (slot[:level] || 0) + @character_level
        end
      end
    end

    granted.map do |name, info|
      Ability.new(
        name:        name,
        level:       info[:scales] ? info[:level] : nil,
        description: info[:description]
      )
    end
  end

  # Flat list of modifier hashes contributed by every racial
  # ability the character qualifies for. Pre-Modifier shape so
  # the consumer (Character) can fold these into a single
  # Modifiers instance alongside class-driven contributions.
  def modifiers
    result = []
    chain.each do |race_key|
      Array(race_ability_defs(race_key)).each do |ability_def|
        next if ability_def['name'].nil? && ability_def[:name].nil?
        min_level = (ability_def['min_level'] || ability_def[:min_level] || DEFAULT_MIN_LEVEL).to_i
        next if @character_level < min_level
        Array(ability_def['modifiers'] || ability_def[:modifiers]).each do |mod|
          result << mod
        end
      end
    end
    result
  end

  # Loads the races definition file. Returns a hash keyed by
  # race key. Each race's `abilities` list is normalized using
  # the same sticky-min_level rules as classes.
  def self.load_yaml(path)
    return {} unless path && File.exist?(path)
    data  = YAML.safe_load_file(path) || {}
    races = data['races'] || {}
    races.each_with_object({}) do |(key, definition), out|
      out[key] = definition ? definition.merge('abilities' => Advancement.normalize_abilities_list(definition['abilities'])) : definition
    end
  end

  private

  def race_definition(key)
    @race_definitions[key] || @race_definitions[key.to_s] || @race_definitions[key.to_sym] || {}
  end

  def race_ability_defs(key)
    defn = race_definition(key)
    defn['abilities'] || defn[:abilities] || []
  end

  # The race itself plus each ancestor (via parent_race) in
  # order. Cycles are guarded against.
  def chain
    chain  = []
    seen   = {}
    cursor = @key
    while cursor && !seen[cursor]
      seen[cursor] = true
      chain << cursor
      defn = race_definition(cursor)
      parent = defn['parent_race'] || defn[:parent_race]
      cursor = parent ? parent.to_s : nil
    end
    chain
  end

  def first_in_chain(field)
    chain.each do |race_key|
      defn = race_definition(race_key)
      value = defn[field] || defn[field.to_sym]
      return value unless value.nil?
    end
    nil
  end
end
