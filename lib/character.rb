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
    @attributes[key].to_i + @advancement.attribute_bonus(key) + @race.adjustment_for(key)
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
    @race.speed
  end

  # Tier 0 is treated as 0.5 in formulas; damage_resilience is
  # an integer so that floors to 0.
  def damage_resilience
    [tier, 0].max
  end

  def damage_reduction
    0
  end

  def max_hit_points
    @advancement.max_hit_points(self)
  end

  def max_mana
    @advancement.max_mana(self)
  end

  def ritual_list
    @ritual_list
  end

  # Convenience for callers (Combat, in particular) that ask for
  # a single skill's rank count by name.
  def skill_rank(name)
    @advancement.skill_ranks[name.to_s].to_i
  end

  # Combat reads martial_skill_ranks today; keep a thin
  # delegator until Combat is rewritten to use skill_rank.
  def martial_skill_ranks
    skill_rank('martial')
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
