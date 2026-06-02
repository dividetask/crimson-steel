require_relative 'atlas/config'
require_relative 'atlas/state'

# Atlas domain. See docs/common/atlas/atlas_design.md.
#
# Owns the Campaign's spatial state: the catalog of Maps and the Tokens
# (and Zones) placed on them, plus the pointer naming the Active Map.
# Atlas is a record-keeping domain — it does not interpret Map Units,
# snap Tokens to grids, or evaluate visibility. Tokens cross-reference the
# Creatures domain by Creature ID; the consuming UI resolves display data
# (name, Tier, token image) through `creature_lookup`.
module Atlas
  module_function

  def state
    @state ||= State.load(movement_notifier: ->(note) { @movement_notifier&.call(note) })
  end

  # Test seam — swap the live state. Pass nil to lazy-reload.
  def state=(s)
    @state = s
  end

  # Resolves a Creature ID to a Creatures Accessor (name, Tier, tags) for
  # Token display. Overridable for tests.
  def creature_lookup
    @creature_lookup ||= ->(id) { Creatures.lookup(id) }
  end

  def creature_lookup=(callable)
    @creature_lookup = callable
  end

  # Register a Movement Notification recipient (typically Combat). Called
  # with { creature_id:, map_id:, entered:, exited: } when a Move Token
  # changes a Token's Zone Membership.
  def on_movement(&block)
    @movement_notifier = block
  end

  def reset!
    @state = nil
    @creature_lookup = nil
    @movement_notifier = nil
    Config.reset!
  end
end
