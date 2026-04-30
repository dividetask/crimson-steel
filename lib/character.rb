# Character — coordinator for everything the rest of the app
# wants to know about a character.
#
# Character itself stays simplistic: it owns the immutable
# identity bits (id, name, player, tags, base attributes) and
# delegates anything derived to Race, Advancement, or — once
# they exist — Skills, Combat, Conditions, Inventory, and
# EffectsState.
#
# External callers go through Character rather than reaching
# into its components directly. Character is the single front
# door so the eventual effects layer can hook every read by
# wrapping methods here.

require 'yaml'
require_relative 'advancement'
require_relative 'race'
require_relative 'modifiers'

class Character
  ATTRIBUTE_KEYS = %i[str dex con int wis cha].freeze

  DEFAULT_TAGS = ['player_character'].freeze

  attr_reader :id, :name, :player, :tags, :race, :attributes, :advancement

  def initialize(
    id:, name:, player:, race:, attributes:,
    tags: nil,
    tier: nil,
    advancement: nil,
    ritual_list: nil
  )
    @id             = id
    @name           = name
    @player         = player
    @tags           = normalize_tags(tags)
    @race           = race.is_a?(Race) ? race : Race.new(key: race.to_s)
    @attributes     = normalize_attributes(attributes)
    @advancement    = advancement || Advancement.new
    @ritual_list    = Array(ritual_list).map { |sub| Array(sub) }
    @tier_override  = tier.nil? ? nil : tier.to_i
  end

  def attribute(sym)
    key = sym.to_sym
    base = @attributes[key].to_i + @advancement.attribute_bonus(key) + @race.adjustment_for(key)
    base + modifiers.total_for("attribute.#{key}")
  end

  # Combined modifier set from race + advancement. Memoized
  # because both inputs are immutable per Character. Once the
  # EffectsState layer lands, the spell / item / condition
  # contributions get folded in here.
  def modifiers
    @modifiers ||= Modifiers.new(@race.modifiers + @advancement.modifiers)
  end

  def tier
    return @tier_override unless @tier_override.nil?
    @advancement.tier
  end

  def classes
    @advancement.character_classes
  end

  # Combined abilities from race and advancement, deduped by
  # name. The first occurrence wins on level so a character with
  # both a racial and a class source for the same ability name
  # doesn't get a doubled scaling level.
  def abilities
    seen = {}
    (@race.abilities + @advancement.abilities).each do |ability|
      seen[ability.name] ||= ability
    end
    seen.values
  end

  def skill_ranks
    @advancement.skill_ranks
  end

  def save_ranks
    @advancement.save_ranks
  end

  def speed
    @race.speed.to_i + modifiers.total_for('speed')
  end

  # Tier 0 is treated as 0.5 in formulas; damage_resilience is
  # an integer so the tier-derived base floors to 0. Classes can
  # raise it further through Advancement, and abilities (or, later,
  # spells / items / conditions) layer additional modifiers on top.
  def damage_resilience
    [tier, 0].max + @advancement.damage_resilience + modifiers.total_for('damage_resilience')
  end

  def damage_reduction
    @advancement.damage_reduction + modifiers.total_for('damage_reduction')
  end

  def max_hit_points
    @advancement.max_hit_points(self) + modifiers.total_for('max_hit_points')
  end

  def max_mana
    @advancement.max_mana(self) + modifiers.total_for('max_mana')
  end

  def ritual_list
    @ritual_list
  end

  # Load a YAML roster from `path`. Returns [] if the file doesn't
  # exist (production starts empty until the DM drops one in). The
  # file format is documented in docs/characters.yaml.example.
  def self.load_yaml(path, advancement_path: nil, skills_path: nil, races_path: nil)
    return [] unless File.exist?(path)
    config            = Advancement.load_config(advancement_path)
    skill_definitions = Advancement.load_skills(skills_path)
    race_definitions  = Race.load_yaml(races_path)
    data              = YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
    (data['characters'] || []).map do |entry|
      class_levels_total = total_class_levels(entry)
      race = Race.new(
        key:              entry['race'].to_s,
        race_definitions: race_definitions,
        character_level:  class_levels_total
      )
      tags = entry['tags']
      new(
        id:          entry['id'],
        name:        entry['name'].to_s,
        player:      entry['player'].to_s,
        tags:        tags,
        tier:        entry['tier'],
        race:        race,
        attributes:  entry['attributes'] || {},
        ritual_list: entry['ritual_list'],
        advancement: Advancement.from_entry(
          entry['advancement'],
          tier:              entry['tier'],
          tags:              tags,
          rules:             config['rules'],
          class_definitions: config['classes'],
          skill_definitions: skill_definitions
        )
      )
    end
  end

  def self.total_class_levels(entry)
    classes = (entry['advancement'] || {})['classes'] || {}
    return 0 unless classes.is_a?(Hash)
    classes.values.sum do |v|
      case v
      when Integer then v
      when Hash    then (v['level'] || v[:level] || 0).to_i
      else 0
      end
    end
  end

  private

  def normalize_attributes(input)
    src = (input || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = v.to_i }
    ATTRIBUTE_KEYS.each_with_object({}) { |k, h| h[k] = src[k].to_i }
  end

  def normalize_tags(input)
    list = Array(input).map(&:to_s).reject(&:empty?)
    list.empty? ? DEFAULT_TAGS.dup : list
  end
end
