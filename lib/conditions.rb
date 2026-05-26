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
end

require_relative 'conditions/catalog'
require_relative 'conditions/state'
require_relative 'conditions/instance'
