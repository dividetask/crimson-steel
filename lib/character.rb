# Character — static, unchanging character data.
#
# Holds only what doesn't change once a character is created:
#   * id           — unique character identifier
#   * name         — character name
#   * player       — player's name
#   * race         — Race instance for the character's race key
#   * attributes   — base ability scores (str/dex/con/int/wis/cha)
#   * advancement  — Advancement record (per-class levels, chosen
#                    skills, and tier) consulted whenever an
#                    attribute is read so class- and tier-driven
#                    bonuses stack on top of the base.
#
# Reading an attribute returns the base score plus the racial
# adjustment plus any tier/focused bonus from advancement.
# Bonuses from magical items, spells, or transient effects live
# elsewhere and are applied by whatever class composes those
# effects on top of this one.

require 'yaml'
require_relative 'advancement'
require_relative 'race'

class Character
  ATTRIBUTE_KEYS = %i[str dex con int wis cha].freeze

  attr_reader :id, :name, :player, :race, :type, :attributes, :advancement

  def initialize(id:, name:, player:, race:, attributes:, type: nil, advancement: nil)
    @id          = id
    @name        = name
    @player      = player
    @race        = race.is_a?(Race) ? race : Race.new(key: race.to_s)
    @type        = type ? type.to_s : Advancement::DEFAULT_CHARACTER_TYPE
    @attributes  = normalize_attributes(attributes)
    @advancement = advancement || Advancement.new
  end

  def attribute(sym)
    key = sym.to_sym
    @attributes[key].to_i + @advancement.attribute_bonus(key) + @race.adjustment_for(key)
  end

  # Placeholder until the skill system lands. Other modules (Combat,
  # for one) need a martial-ranks value to plug into their formulas;
  # returning 0 lets them wire up now and pick up real numbers later
  # without an interface change.
  def martial_skill_ranks
    0
  end

  # Load a YAML roster from `path`. Returns [] if the file doesn't
  # exist (production starts empty until the DM drops one in). The
  # file format is documented in docs/characters.yaml.example.
  #
  # `advancement_path`, `skills_path`, and `races_path` are
  # optional; when provided, each character's advancement entry
  # is resolved against the rules in those files (see
  # docs/advancement.yaml.example, docs/skills.yaml.example,
  # docs/races.yaml.example).
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
      new(
        id:          entry['id'],
        name:        entry['name'].to_s,
        player:      entry['player'].to_s,
        race:        race,
        type:        entry['type'],
        attributes:  entry['attributes'] || {},
        advancement: Advancement.from_entry(
          entry['advancement'],
          type:              entry['type'],
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
end
