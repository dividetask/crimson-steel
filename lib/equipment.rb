require 'yaml'

# Equipment domain. Sole owner of inventory data — Items a Creature
# carries or wears, plus the Currency, Gem, Shop, Loot Table, Ground
# Pile, and Loot Archive state that surround inventory mutation. See
# docs/common/equipment/equipment_design.md.
#
# Other domains read or mutate items through the Equipment::Instance
# public entry points rather than touching the YAML files directly.
module Equipment
  module_function

  def catalog
    @catalog ||= Catalog.load
  end

  def reset!
    @catalog = nil
  end
end

require_relative 'equipment/config'
require_relative 'equipment/stack'
require_relative 'equipment/dice_expression'
require_relative 'equipment/pricing'
require_relative 'equipment/display_name'
require_relative 'equipment/details'
