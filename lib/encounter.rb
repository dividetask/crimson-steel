require_relative 'encounter/state'

# Encounter domain. See docs/common/encounter/encounter_design.md.
#
# Governs what is happening in the present moment of play. First
# pass covers the Combat roster — Combatants can be added and
# removed even when Combat is not active; PC exclusions persist
# across Combat lifecycles. Combat-mode operations (initiative,
# turn tracking, action economy, damage routing) land in later
# passes.
module Encounter
  module_function

  def state
    @state ||= State.load
  end

  # Test seam — swap the live state. Pass nil to lazy-reload.
  def state=(s)
    @state = s
  end

  def reset!
    @state = nil
  end
end
