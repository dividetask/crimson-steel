require 'yaml'
require 'json'

# Conditions domain. See docs/common/conditions/conditions_design.md.
#
# Module owns:
#   - SEVERITIES — canonical Damage Severity order (least → most serious)
#   - Catalog    — config + Affliction Rules + Effect Names
#   - State      — per-Creature mutable state
#   - Instance   — pairs Catalog + State and exposes the public entry points
module Conditions
  SEVERITIES = %i[minor moderate major].freeze
  REVERSE_SEVERITIES = SEVERITIES.reverse.freeze

  module_function

  def severities
    SEVERITIES
  end

  # +value+ after the Creature's active set_value / scale_value mechanics for
  # +target+ (str, dex, …, speed, combat_pool): a set_value wins (the lowest);
  # otherwise the strongest scale_value, its reduction rounded down.
  def adjust_value(creature_id, target, value)
    inst = (store.instance_for(creature_id) rescue nil)
    return value unless inst
    inst.adjusted_value(target, value)
  rescue StandardError
    value
  end
end

require_relative 'conditions/catalog'
require_relative 'conditions/state'
require_relative 'conditions/instance'
require_relative 'conditions/store'
