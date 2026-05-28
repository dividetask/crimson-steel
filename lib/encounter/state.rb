require 'fileutils'
require 'json'

module Encounter
  # In-memory state for the active Encounter, persisted to
  # `data/encounter_data.json`. Mirrors the Chronicle::Store pattern:
  # load order is data file first, falling back to the example.
  #
  # First-pass scope: combatant roster + PC exclusions. Combat-mode
  # fields (`time_ticks_per_round`, `time_tick`, `combat_anchor`, etc.)
  # are present in the persisted shape but not yet driven by any
  # entry point — initiative / turn tracking lands in a later pass.
  class State
    DATA_PATH    = File.expand_path('../../data/encounter_data.json', __dir__)
    EXAMPLE_PATH = File.expand_path('../../docs/common/encounter/encounter_data.example.json', __dir__)

    attr_reader :data_path

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH)
      path = File.exist?(data_path) ? data_path : example_path
      raw = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      new(raw, data_path: data_path)
    end

    def initialize(raw = {}, data_path: DATA_PATH)
      @data_path           = data_path
      @combatants          = (raw['combatants'] || []).map { |c| normalize_combatant(c) }
      @next_combatant_id   = Integer(raw['next_combatant_id'] || ((@combatants.map { |c| c[:id] }.max || 0) + 1))
      @excluded_pcs        = (raw['excluded_pcs'] || []).map(&:to_s)
      @time_ticks_per_round = raw['time_ticks_per_round']
      @time_tick           = raw['time_tick']
      @combat_anchor       = raw['combat_anchor']
      @elapsed_time_ticks  = Integer(raw['elapsed_time_ticks'] || 0)
      @acting_combatant_id = raw['acting_combatant_id']
      @granted_actions     = raw['granted_actions'] || []
      @dm_luck_points      = Integer(raw['dm_luck_points'] || 0)
    end

    # ---------- Snapshot / persistence ----------

    def to_h
      {
        'combatants'           => @combatants.map { |c| stringify_combatant(c) },
        'next_combatant_id'    => @next_combatant_id,
        'excluded_pcs'         => @excluded_pcs,
        'time_ticks_per_round' => @time_ticks_per_round,
        'time_tick'            => @time_tick,
        'combat_anchor'        => @combat_anchor,
        'elapsed_time_ticks'   => @elapsed_time_ticks,
        'acting_combatant_id'  => @acting_combatant_id,
        'granted_actions'      => @granted_actions,
        'dm_luck_points'       => @dm_luck_points
      }
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, JSON.pretty_generate(to_h))
      File.rename(tmp, @data_path)
    end

    # ---------- Roster reads ----------

    def combatants
      @combatants.map(&:dup)
    end

    def combatant(combatant_id)
      @combatants.find { |c| c[:id] == combatant_id }&.dup
    end

    def combatant_ids_for_creature(creature_id)
      cid = normalize_creature_id(creature_id)
      @combatants.select { |c| c[:creature_id] == cid }.map { |c| c[:id] }
    end

    def includes_creature?(creature_id)
      !combatant_ids_for_creature(creature_id).empty?
    end

    def copy_count(creature_id)
      combatant_ids_for_creature(creature_id).length
    end

    def excluded_pcs
      @excluded_pcs.dup
    end

    def pc_excluded?(creature_id)
      @excluded_pcs.include?(normalize_creature_id(creature_id))
    end

    # ---------- Roster mutations ----------

    # Append a Combatant referencing `creature_id`. The optional
    # `name_override` is stored as the display name; otherwise the
    # display name is the empty string and consumers resolve through
    # the Creature record. Returns the new Combatant Hash.
    def add_combatant(creature_id, name_override: nil)
      cid = normalize_creature_id(creature_id)
      raise ArgumentError, 'creature_id is required' if cid.nil? || cid.empty?

      entry = {
        id:          @next_combatant_id,
        creature_id: cid,
        name:        (name_override || '').to_s
      }
      @next_combatant_id += 1
      @combatants << entry
      persist!
      entry.dup
    end

    # Remove the Combatant with the given combatant_id. Returns the
    # removed entry or nil.
    def remove_combatant(combatant_id)
      idx = @combatants.index { |c| c[:id] == combatant_id }
      return nil unless idx
      removed = @combatants.delete_at(idx)
      @acting_combatant_id = nil if @acting_combatant_id == combatant_id
      persist!
      removed.dup
    end

    # Remove the most recently added Combatant referencing this
    # `creature_id` (per the sidebar's `−` button). Returns the
    # removed entry or nil.
    def remove_last_combatant_by_creature_id(creature_id)
      cid = normalize_creature_id(creature_id)
      idx = nil
      @combatants.each_with_index { |c, i| idx = i if c[:creature_id] == cid }
      return nil unless idx
      removed = @combatants.delete_at(idx)
      @acting_combatant_id = nil if @acting_combatant_id == removed[:id]
      persist!
      removed.dup
    end

    # Remove every Combatant referencing this `creature_id`. Returns
    # the count removed.
    def remove_all_combatants_by_creature_id(creature_id)
      cid = normalize_creature_id(creature_id)
      before = @combatants.length
      @combatants.reject! { |c| c[:creature_id] == cid }
      removed = before - @combatants.length
      if removed.positive?
        @acting_combatant_id = nil unless @combatants.any? { |c| c[:id] == @acting_combatant_id }
        persist!
      end
      removed
    end

    # ---------- PC exclusions ----------

    # Replace the exclusion list wholesale. Removes any matching
    # Combatants from the roster as a side effect (per the design
    # doc's *Set PC Exclusions*).
    def set_pc_exclusions(creature_ids)
      @excluded_pcs = Array(creature_ids).map { |c| normalize_creature_id(c) }
      @excluded_pcs.each { |cid| remove_all_combatants_by_creature_id(cid) }
      persist!
      @excluded_pcs.dup
    end

    def add_pc_exclusion(creature_id)
      cid = normalize_creature_id(creature_id)
      return @excluded_pcs.dup if @excluded_pcs.include?(cid)
      @excluded_pcs << cid
      remove_all_combatants_by_creature_id(cid)
      persist!
      @excluded_pcs.dup
    end

    def remove_pc_exclusion(creature_id)
      cid = normalize_creature_id(creature_id)
      removed = @excluded_pcs.delete(cid)
      persist! if removed
      @excluded_pcs.dup
    end

    # ---------- Combat-mode lifecycle (minimal stubs) ----------

    def combat_active?
      !@time_ticks_per_round.nil?
    end

    # Minimal Start Combat — flags the Encounter as in active combat.
    # Initiative rolling, time-tick scheduling, and round wiring land
    # in a later pass.
    def start_combat(time_ticks_per_round: 1)
      @time_ticks_per_round = Integer(time_ticks_per_round)
      @time_tick = 1
      @elapsed_time_ticks = 0
      persist!
      self
    end

    # Clear combat-mode fields. Combatants and exclusions persist —
    # the roster survives End Combat by design.
    def end_combat
      @time_ticks_per_round = nil
      @time_tick = nil
      @combat_anchor = nil
      @elapsed_time_ticks = 0
      @acting_combatant_id = nil
      @granted_actions = []
      persist!
      self
    end

    # ---------- Internal ----------

    private

    def normalize_combatant(c)
      c = c.transform_keys(&:to_s) if c.respond_to?(:transform_keys)
      {
        id:          Integer(c['id']),
        creature_id: c['creature_id'].to_s,
        name:        (c['name'] || '').to_s
      }
    end

    def stringify_combatant(c)
      { 'id' => c[:id], 'creature_id' => c[:creature_id], 'name' => c[:name] }
    end

    def normalize_creature_id(creature_id)
      return nil if creature_id.nil?
      creature_id.to_s
    end
  end
end
