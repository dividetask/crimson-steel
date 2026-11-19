require 'securerandom'

# Actions a player has asked for from the Android app on their turn
# (docs/project/android_app.md → Initiative screen). A request spends nothing:
# it is shown to the DM on the turn panel, and the DM resolves it with the
# normal Attack / Move / Cast / Item / Special flow, which does the spending.
#
# Requests belong to one turn. Each is stamped with a turn key (Combatant id,
# Round label and Time Tick); once the turn moves on, reads no longer return
# it and it is pruned. Kept in memory only — a server restart clears them,
# which is fine for a per-turn request list.
class PlayerRequests
  def self.instance
    @instance ||= new
  end

  def self.instance=(store)
    @instance = store
  end

  def initialize
    @entries = []
    @mutex   = Mutex.new
  end

  # Turn key for +combatant_id+'s current turn, or nil when that Combatant is
  # not the one acting (so its requests are no longer current).
  def self.turn_key(state, combatant_id)
    return nil unless combatant_id && state.acting_combatant_id == combatant_id
    "#{combatant_id}|#{state.round_label}|#{state.time_tick}"
  end

  # Record a request. +attrs+: combatant_id, creature_id, turn_key, key, label,
  # category, dice (may be nil), pool_cost, mana_cost.
  def add(attrs)
    entry = attrs.transform_keys(&:to_s).merge('id' => SecureRandom.hex(6), 'at' => Time.now.to_i)
    @mutex.synchronize { @entries << entry }
    entry
  end

  # This turn's requests for a Combatant, oldest first. A nil +turn_key+ (not
  # their turn) returns nothing and prunes what they had.
  def for_turn(combatant_id, turn_key)
    @mutex.synchronize do
      @entries.reject! { |e| e['combatant_id'] == combatant_id && e['turn_key'] != turn_key }
      @entries.select { |e| e['combatant_id'] == combatant_id && e['turn_key'] == turn_key }.map(&:dup)
    end
  end

  # Remove one request (the player's Undo, or the DM dismissing it). Returns
  # true when something was removed.
  def remove(id, combatant_id: nil)
    @mutex.synchronize do
      before = @entries.length
      @entries.reject! { |e| e['id'] == id.to_s && (combatant_id.nil? || e['combatant_id'] == combatant_id) }
      @entries.length != before
    end
  end

  # The acting Combatant's requests this turn (requests are only made on
  # one's own turn), for the DM's notice.
  def current(state)
    id = state.acting_combatant_id
    id ? for_turn(id, PlayerRequests.turn_key(state, id)) : []
  end

  def clear!
    @mutex.synchronize { @entries.clear }
  end
end
