# Character — static, unchanging character data.
#
# Holds only what doesn't change once a character is created:
#   * id           — unique character identifier
#   * name         — character name
#   * player       — player's name
#   * race         — character race
#   * attributes   — base ability scores (str/dex/con/int/wis/cha)
#
# Attributes returned here are the *base* values. Bonuses from magical
# items, spells, or level advancement live elsewhere and are applied by
# whatever class composes those effects on top of this one.

require 'yaml'

class Character
  ATTRIBUTE_KEYS = %i[str dex con int wis cha].freeze

  attr_reader :id, :name, :player, :race, :attributes

  def initialize(id:, name:, player:, race:, attributes:)
    @id         = id
    @name       = name
    @player     = player
    @race       = race
    @attributes = normalize_attributes(attributes)
  end

  def attribute(sym)
    @attributes[sym.to_sym].to_i
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
  def self.load_yaml(path)
    return [] unless File.exist?(path)
    data = YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
    (data['characters'] || []).map do |entry|
      new(
        id:         entry['id'],
        name:       entry['name'].to_s,
        player:     entry['player'].to_s,
        race:       entry['race'].to_s,
        attributes: entry['attributes'] || {}
      )
    end
  end

  private

  def normalize_attributes(input)
    src = (input || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = v.to_i }
    ATTRIBUTE_KEYS.each_with_object({}) { |k, h| h[k] = src[k].to_i }
  end
end
