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

  private

  def normalize_attributes(input)
    src = (input || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = v.to_i }
    ATTRIBUTE_KEYS.each_with_object({}) { |k, h| h[k] = src[k].to_i }
  end
end
