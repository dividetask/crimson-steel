require_relative 'encounter/config'
require_relative 'encounter/combat_pool'
require_relative 'encounter/time_ticks'
require_relative 'encounter/initiative'
require_relative 'encounter/severity'
require_relative 'encounter/state'

# Encounter domain. See docs/common/encounter/encounter_design.md.
#
# Governs what is happening in the present moment of play. Combat is
# the implemented mode: the Combatant roster, Combat lifecycle, Time
# Ticks + Initiative ordering, Combat Pool, turn advancement, Damage /
# Severity routing to Conditions, Granted Actions, Concentration and
# Long Cast bookkeeping. Combatants can be added/removed even when
# Combat is not active; PC exclusions persist across lifecycles.
module Encounter
  module_function

  def state
    @state ||= State.load
  end

  # Test seam — swap the live state. Pass nil to lazy-reload.
  def state=(s)
    @state = s
  end

  # Resolves a Creature ID to a Creatures Accessor (tier, attributes,
  # martial ranks, max HP/Mana). Overridable for tests.
  def creature_lookup
    @creature_lookup ||= ->(id) { Creatures.lookup(id) }
  end

  def creature_lookup=(callable)
    @creature_lookup = callable
  end

  # Chronicle's current Round-of-day, used as the Combat Anchor and by
  # Is Stale?. Overridable for tests.
  def current_round
    @current_round_fn ||= -> { (Chronicle.store.timestamp[:round_of_day] rescue 0) }
    @current_round_fn.call
  end

  def current_round_fn=(callable)
    @current_round_fn = callable
  end

  def reset!
    @state = nil
    @creature_lookup = nil
    @current_round_fn = nil
    Config.reset!
  end
end
