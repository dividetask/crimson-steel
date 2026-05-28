require 'fileutils'
require 'json'

module Encounter
  # In-memory state for the active Encounter, persisted to
  # `data/encounter_data.json`. Combat is the implemented mode.
  #
  # Combatants can be added/removed even when Combat is not active
  # (Combat is a mode within an Encounter, not a prerequisite for
  # tracking who is present). Combat-mode fields (time ticks,
  # initiative ordering, turn pointer) come alive once *Start Combat*
  # runs. PC exclusions persist across lifecycles.
  class State
    DATA_PATH    = File.expand_path('../../data/encounter_data.json', __dir__)
    EXAMPLE_PATH = File.expand_path('../../docs/common/encounter/encounter_data.example.json', __dir__)

    attr_reader :data_path

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH, **opts)
      path = File.exist?(data_path) ? data_path : example_path
      raw = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      new(raw, data_path: data_path, **opts)
    end

    # creature_lookup / conditions_for default to the live domains but
    # are injectable for tests. current_round_fn returns Chronicle's
    # current Round-of-day.
    def initialize(raw = {}, data_path: DATA_PATH,
                   creature_lookup: nil, conditions_for: nil, current_round_fn: nil)
      @data_path           = data_path
      @creature_lookup     = creature_lookup
      @conditions_for      = conditions_for
      @current_round_fn    = current_round_fn
      @combatants          = (raw['combatants'] || []).map { |c| normalize_combatant(c) }
      @next_combatant_id   = Integer(raw['next_combatant_id'] || ((@combatants.map { |c| c[:id] }.max || 0) + 1))
      @excluded_pcs        = (raw['excluded_pcs'] || []).map(&:to_s)
      @time_ticks_per_round = raw['time_ticks_per_round']
      @time_tick           = raw['time_tick']
      @combat_anchor       = raw['combat_anchor']
      @elapsed_time_ticks  = Integer(raw['elapsed_time_ticks'] || 0)
      @acting_combatant_id = raw['acting_combatant_id']
      @granted_actions     = (raw['granted_actions'] || []).map { |g| symbolize(g) }
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
        'granted_actions'      => @granted_actions.map { |g| stringify(g) },
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

    def combatants               = @combatants.map(&:dup)
    def combatant(id)            = @combatants.find { |c| c[:id] == id }&.dup
    def excluded_pcs             = @excluded_pcs.dup
    def acting_combatant_id      = @acting_combatant_id
    def time_ticks_per_round     = @time_ticks_per_round
    def time_tick                = @time_tick
    def elapsed_time_ticks       = @elapsed_time_ticks
    def dm_luck_points           = @dm_luck_points
    def granted_actions          = @granted_actions.map(&:dup)

    def combatant_ids_for_creature(creature_id)
      cid = creature_id.to_s
      @combatants.select { |c| c[:creature_id] == cid }.map { |c| c[:id] }
    end

    def includes_creature?(creature_id) = !combatant_ids_for_creature(creature_id).empty?
    def copy_count(creature_id)         = combatant_ids_for_creature(creature_id).length
    def pc_excluded?(creature_id)       = @excluded_pcs.include?(creature_id.to_s)
    def combat_active?                  = !@time_ticks_per_round.nil?

    # ---------- Roster mutations ----------

    def add_combatant(creature_id, name_override: nil)
      cid = creature_id.to_s
      raise ArgumentError, 'creature_id is required' if cid.empty?

      entry = blank_combatant(@next_combatant_id, cid, (name_override || '').to_s)
      @next_combatant_id += 1
      @combatants << entry
      recompute_schedules! if combat_active?
      persist!
      entry.dup
    end

    def remove_combatant(combatant_id)
      idx = @combatants.index { |c| c[:id] == combatant_id }
      return nil unless idx
      removed = @combatants.delete_at(idx)
      clear_granted_for(combatant_id)
      @acting_combatant_id = nil if @acting_combatant_id == combatant_id
      recompute_schedules! if combat_active?
      persist!
      removed.dup
    end

    def remove_last_combatant_by_creature_id(creature_id)
      cid = creature_id.to_s
      idx = nil
      @combatants.each_with_index { |c, i| idx = i if c[:creature_id] == cid }
      return nil unless idx
      removed = @combatants[idx]
      remove_combatant(removed[:id])
      removed.dup
    end

    def remove_all_combatants_by_creature_id(creature_id)
      cid = creature_id.to_s
      ids = combatant_ids_for_creature(cid)
      ids.each { |id| remove_combatant(id) }
      ids.length
    end

    # ---------- PC exclusions ----------

    def set_pc_exclusions(creature_ids)
      @excluded_pcs = Array(creature_ids).map(&:to_s)
      @excluded_pcs.each { |cid| remove_all_combatants_by_creature_id(cid) }
      persist!
      @excluded_pcs.dup
    end

    def add_pc_exclusion(creature_id)
      cid = creature_id.to_s
      unless @excluded_pcs.include?(cid)
        @excluded_pcs << cid
        remove_all_combatants_by_creature_id(cid)
      end
      persist!
      @excluded_pcs.dup
    end

    def remove_pc_exclusion(creature_id)
      removed = @excluded_pcs.delete(creature_id.to_s)
      persist! if removed
      @excluded_pcs.dup
    end

    def reconcile_pcs(pc_creature_ids)
      added = []
      Array(pc_creature_ids).each do |id|
        cid = id.to_s
        next if cid.empty? || pc_excluded?(cid) || includes_creature?(cid)
        add_combatant(cid)
        added << cid
      end
      added
    end

    # ---------- Combat lifecycle ----------

    # Enter Combat mode. Computes Time Ticks Per Round from the
    # Combatants' Tiers and each Combatant's Time Tick Schedule, resets
    # per-Combatant turn state, and captures the Combat Anchor.
    def start_combat
      tiers = @combatants.map { |c| tier_of(c[:creature_id]) }
      @time_ticks_per_round = TimeTicks.ticks_per_round(tiers)
      @time_tick = 1
      @elapsed_time_ticks = 0
      @acting_combatant_id = nil
      @combat_anchor = { 'round_of_day' => current_round }
      @dm_luck_points = 0
      @combatants.each do |c|
        c[:combat_pool_spent]   = 0
        c[:luck_points]         = 0
        c[:performed_this_turn] = false
        c[:concentration]       = []
        c[:casting]             = []
      end
      recompute_schedules!
      persist!
      self
    end

    # Leave Combat mode. Combat-mode fields clear; the roster and PC
    # exclusions persist (the roster survives End Combat by design).
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

    # ---------- Combat Pool ----------

    def get_combat_pool(combatant_id)
      c = find!(combatant_id)
      creature = lookup!(c[:creature_id])
      return 0 unless creature
      CombatPool.size_for(creature)
    end

    def combat_pool_remaining(combatant_id)
      get_combat_pool(combatant_id) - find!(combatant_id)[:combat_pool_spent]
    end

    # Increment combat_pool_spent. Refuses negative amounts or amounts
    # that would overdraw the pool; returns nil on refusal, otherwise
    # the new remaining value.
    def spend_combat_pool(combatant_id, amount)
      return nil if amount.negative?
      c = find!(combatant_id)
      pool = get_combat_pool(combatant_id)
      return nil if c[:combat_pool_spent] + amount > pool
      c[:combat_pool_spent] += amount
      persist!
      pool - c[:combat_pool_spent]
    end

    def reset_combat_pool(combatant_id)
      find!(combatant_id)[:combat_pool_spent] = 0
      persist!
      get_combat_pool(combatant_id)
    end

    # ---------- Initiative ----------

    # Roll (or set) Initiative Strings. See encounter_design.md → Reroll
    # Initiative. `luck_insight` maps Combat ID → [luck, insight];
    # `prerolled_initiatives` maps Combat ID → string (skips the roll);
    # `missing_only` restricts random rolls to Combatants with an empty
    # Initiative String. `roller` is injectable for tests.
    def reroll_initiative(luck_insight: {}, prerolled_initiatives: {}, missing_only: false,
                          roller: Initiative.method(:default_roll))
      @combatants.each do |c|
        if prerolled_initiatives.key?(c[:id])
          c[:initiative_string] = prerolled_initiatives[c[:id]].to_s
          next
        end
        next if missing_only && !c[:initiative_string].to_s.empty?

        creature = lookup!(c[:creature_id])
        next unless creature
        count = Initiative.dice_count_for(creature)
        luck, insight = luck_insight[c[:id]] || [0, 0]
        dice = roller.call(count)
        c[:initiative_string] = Initiative.resolve(dice, luck: luck, insight: insight, roller: roller)
      end
      persist!
      self
    end

    # ---------- Turn order ----------

    # Combatants acting at a given Time Tick, sorted by Initiative String
    # descending (ASCII), ties broken by Combat ID ascending.
    def acting_combatants(tick = @time_tick)
      @combatants
        .select { |c| Array(c[:time_tick_schedule]).include?(tick) }
        .sort_by { |c| [invert_string(c[:initiative_string].to_s), c[:id]] }
    end

    def set_acting_combatant(combatant_id)
      return nil unless @combatants.any? { |c| c[:id] == combatant_id }
      @acting_combatant_id = combatant_id
      persist!
      combatant_id
    end

    # Advance to the next Combatant who can act, applying Per-Turn
    # Cleanup to the outgoing Combatant and crossing Time Ticks /
    # Rounds as needed.
    def advance_turn
      apply_per_turn_cleanup(@acting_combatant_id) if @acting_combatant_id
      guard = 0
      loop do
        guard += 1
        break if guard > (@combatants.length + 1) * (@time_ticks_per_round || 1) + 2
        order = acting_combatants
        idx = order.index { |c| c[:id] == @acting_combatant_id }
        nxt = idx ? order[idx + 1] : order.first
        if nxt.nil?
          advance_time_tick
          nxt = acting_combatants.first
        end
        if nxt.nil?
          @acting_combatant_id = nil
          break
        end
        @acting_combatant_id = nxt[:id]
        break if creature_can_act?(nxt[:id])
      end
      persist!
      @acting_combatant_id
    end

    def advance_time_tick
      @time_tick += 1
      @elapsed_time_ticks += 1
      if @time_tick > @time_ticks_per_round
        @time_tick = 1
        notify_round_elapsed
      end
      @acting_combatant_id = acting_combatants.first&.dig(:id)
      persist!
      @time_tick
    end

    # ---------- Drift / Round label ----------

    def stale?
      return false if @combat_anchor.nil?
      anchor = Integer(@combat_anchor['round_of_day'] || @combat_anchor[:round_of_day] || 0)
      expected = anchor + (@elapsed_time_ticks / (@time_ticks_per_round || 1))
      expected != current_round
    end

    # 1-based cumulative tick = elapsed + 1. Round / sub-tick per
    # encounter_tests.md "Round label" formula.
    def round_label
      return nil unless combat_active?
      tpr = @time_ticks_per_round
      cumulative = @elapsed_time_ticks + 1
      round = ((cumulative - 1) / tpr) + 1
      sub   = (cumulative - 1) % tpr
      tpr == 1 ? "Round #{round}" : "Round #{round} #{sub}/#{tpr}"
    end

    # ---------- Damage ----------

    # Apply Damage → Severity Calculation → Conditions. Returns the
    # per-Severity map and the side effects dispatched.
    def apply_damage(combatant_id, raw, type, threshold: 0)
      c = find!(combatant_id)
      creature = lookup!(c[:creature_id])
      resilience = (creature && (creature.respond_to?(:damage_resilience) ? creature.damage_resilience : 0)) || 0
      tags = creature ? Array(creature.tags) : []

      result = Severity.compute(raw: raw, type: type, threshold: threshold,
                                damage_resilience: resilience, target_tags: tags)
      inst = conditions_for(c[:creature_id])
      inst.apply_hit_point_damage(result[:severity_map]) unless result[:severity_map].empty?
      result[:side_effects].each do |fx|
        case fx[:kind]
        when 'acid'    then inst.apply_acid_damage(fx[:amount])
        when 'inflict'
          if fx[:effect] == 'shock'
            inst.state.shock += fx[:amount]
          end
        end
      end
      { severity_map: result[:severity_map], side_effects: result[:side_effects] }
    end

    # Apply Falling Damage per encounter_design.md.
    def apply_falling_damage(combatant_id, fall_distance, modifier: 0, acrobatics_successes: 0)
      per10 = [Config.falling_damage_per_10_feet + modifier, 0].max
      raw = (fall_distance / 10) * per10
      raw = [raw - acrobatics_successes, 0].max
      apply_damage(combatant_id, raw, 'physical', threshold: Config.falling_damage_threshold)
    end

    # ---------- Granted Actions ----------

    def grant_action(action)
      @granted_actions << symbolize(action)
      persist!
      @granted_actions.last.dup
    end

    def revoke_action(&predicate)
      @granted_actions.reject!(&predicate)
      persist!
    end

    def list_granted_actions(combatant_id)
      @granted_actions.select { |g| g[:combatant_id] == combatant_id }.map(&:dup)
    end

    # ---------- Creature predicates (delegate to Conditions) ----------

    def creature_can_act?(combatant_id)
      creature = combatant_creature(combatant_id)
      return true unless creature
      inst = conditions_for(combatant_for(combatant_id)[:creature_id])
      max_hp = (creature.max_hit_points rescue 0)
      inst.can_act?(max_hit_points: max_hp,
                    attribute_scores: attr_scores(creature),
                    toxicity_threshold: tox_threshold(inst, creature))
    end

    def creature_dying?(combatant_id)
      creature = combatant_creature(combatant_id)
      return false unless creature
      conditions_for(combatant_for(combatant_id)[:creature_id])
        .dying?(max_hit_points: (creature.max_hit_points rescue 0))
    end

    def creature_dead?(combatant_id)
      creature = combatant_creature(combatant_id)
      return false unless creature
      inst = conditions_for(combatant_for(combatant_id)[:creature_id])
      inst.dead?(max_hit_points: (creature.max_hit_points rescue 0),
                 attribute_scores: attr_scores(creature),
                 toxicity_threshold: tox_threshold(inst, creature))
    end

    # ---------- Concentration ----------

    def begin_concentration(combatant_id, spell_name:, source:, spell_tier:, cast_skill:,
                            mode:, reservoir_reset:, initial_reservoir: 0)
      c = find!(combatant_id)
      c[:concentration] << {
        spell_name: spell_name, source: source, spell_tier: Integer(spell_tier),
        cast_skill: cast_skill, mode: mode.to_s, reservoir: Integer(initial_reservoir),
        reservoir_reset: reservoir_reset.to_s, channeled_this_turn: true
      }
      persist!
      c[:concentration].last.dup
    end

    def channel(combatant_id, spell_name, dice_spent:, reservoir_delta: 0)
      c = find!(combatant_id)
      entry = c[:concentration].find { |e| e[:spell_name] == spell_name } or return nil
      return nil if dice_spent < Config.main_action_minimum
      return nil if entry[:mode] == 'maintain' && dice_spent != Config.main_action_minimum
      return nil if %w[auto maintain].include?(entry[:mode]) && reservoir_delta != 0
      entry[:reservoir] += reservoir_delta if entry[:mode] == 'reservoir'
      entry[:channeled_this_turn] = true
      persist!
      entry.dup
    end

    def discharge_reservoir(combatant_id, spell_name, amount)
      c = find!(combatant_id)
      entry = c[:concentration].find { |e| e[:spell_name] == spell_name } or return nil
      return nil unless entry[:mode] == 'reservoir' && entry[:reservoir_reset] == 'per_turn'
      return nil if amount > entry[:reservoir]
      entry[:reservoir] -= amount
      persist!
      entry.dup
    end

    def end_concentration(combatant_id, spell_name)
      c = find!(combatant_id)
      entry = c[:concentration].find { |e| e[:spell_name] == spell_name }
      return nil unless entry
      c[:concentration].delete(entry)
      persist!
      { source: entry[:source], spell_name: spell_name }
    end

    # ---------- Long Cast ----------

    def begin_long_cast(combatant_id, spell_name:, source:, spell_tier:, cast_skill:, turns_required:)
      c = find!(combatant_id)
      c[:casting] << {
        spell_name: spell_name, source: source, spell_tier: Integer(spell_tier),
        cast_skill: cast_skill, turns_remaining: Integer(turns_required) - 1,
        committed_this_turn: true
      }
      persist!
      c[:casting].last.dup
    end

    def commit_to_long_cast(combatant_id, spell_name)
      c = find!(combatant_id)
      entry = c[:casting].find { |e| e[:spell_name] == spell_name } or return nil
      entry[:committed_this_turn] = true
      persist!
      entry.dup
    end

    def cancel_long_cast(combatant_id, spell_name, reason:)
      c = find!(combatant_id)
      entry = c[:casting].find { |e| e[:spell_name] == spell_name }
      return nil unless entry
      c[:casting].delete(entry)
      persist!
      { source: entry[:source], spell_name: spell_name, reason: reason.to_s }
    end

    # ---------- Per-turn cleanup ----------

    # Returns a list of source-domain notifications the caller should
    # dispatch ({ kind:, source:, spell_name:, ... }).
    def apply_per_turn_cleanup(combatant_id)
      c = combatant_for(combatant_id)
      return [] unless c
      notes = []

      c[:combat_pool_spent] = 0
      c[:luck_points] = 0
      c[:performed_this_turn] = true

      # End-of-turn channel check.
      c[:concentration].reject! do |e|
        if !e[:channeled_this_turn] && e[:mode] != 'auto'
          notes << { kind: :concentration_ended, source: e[:source], spell_name: e[:spell_name] }
          true
        else
          false
        end
      end

      # End-of-turn cast check.
      c[:casting].reject! do |e|
        if !e[:committed_this_turn]
          notes << { kind: :cast_cancelled, source: e[:source], spell_name: e[:spell_name], reason: 'incomplete_commit' }
          true
        else
          e[:turns_remaining] -= 1
          if e[:turns_remaining] <= 0
            notes << { kind: :cast_completed, source: e[:source], spell_name: e[:spell_name] }
            true
          else
            false
          end
        end
      end

      c[:concentration].each { |e| e[:channeled_this_turn] = false }
      c[:casting].each { |e| e[:committed_this_turn] = false }
      notes
    end

    # ---------- Internal ----------

    private

    def blank_combatant(id, creature_id, name)
      { id: id, creature_id: creature_id, name: name,
        initiative_string: '', combat_pool_spent: 0, time_tick_schedule: [],
        luck_points: 0, performed_this_turn: false, concentration: [], casting: [] }
    end

    def recompute_schedules!
      tiers = @combatants.map { |c| tier_of(c[:creature_id]) }
      new_tpr = TimeTicks.ticks_per_round(tiers)
      @time_ticks_per_round = new_tpr
      @time_tick = [@time_tick || 1, new_tpr].min
      @combatants.each do |c|
        c[:time_tick_schedule] = TimeTicks.schedule(tier_of(c[:creature_id]), new_tpr)
      end
    end

    def clear_granted_for(combatant_id)
      @granted_actions.reject! do |g|
        g[:combatant_id] == combatant_id || Array(g[:eligible_targets]).include?(combatant_id)
      end
    end

    def find!(combatant_id)
      @combatants.find { |c| c[:id] == combatant_id } or
        raise ArgumentError, "no Combatant with id #{combatant_id}"
    end

    def combatant_for(combatant_id) = @combatants.find { |c| c[:id] == combatant_id }

    def lookup!(creature_id)
      lk = @creature_lookup || Encounter.creature_lookup
      lk.call(creature_id)
    end
    alias_method :lookup_creature, :lookup!

    def combatant_creature(combatant_id)
      c = combatant_for(combatant_id)
      c && lookup!(c[:creature_id])
    end

    def conditions_for(creature_id)
      cf = @conditions_for || ->(id) { Conditions.store.instance_for(id) }
      cf.call(creature_id)
    end

    def tier_of(creature_id)
      creature = lookup!(creature_id)
      creature ? (creature.tier rescue 0) : 0
    end

    def current_round
      fn = @current_round_fn || -> { Encounter.current_round }
      fn.call
    end

    def notify_round_elapsed
      Chronicle.store.advance_time(rounds: 1) if defined?(Chronicle) && Chronicle.respond_to?(:store)
    rescue StandardError
      nil
    end

    def attr_scores(creature)
      %i[str dex con int wis cha].each_with_object({}) { |a, h| h[a] = (creature.attribute_value(a) rescue 0) }
    end

    def tox_threshold(inst, creature)
      cha = (creature.attribute_value(:cha) rescue 0)
      tier = (creature.tier rescue 0)
      inst.toxicity_threshold(cha, tier)
    rescue StandardError
      0
    end

    # Invert a Dice Result String so ascending sort yields descending
    # initiative (higher strings act first). Maps each byte to its
    # complement so lexical ascending = initiative descending.
    def invert_string(str)
      str.bytes.map { |b| (255 - b).chr }.join
    end

    def normalize_combatant(c)
      c = c.transform_keys(&:to_s) if c.respond_to?(:transform_keys)
      {
        id:                  Integer(c['id']),
        creature_id:         c['creature_id'].to_s,
        name:                (c['name'] || '').to_s,
        initiative_string:   (c['initiative_string'] || '').to_s,
        combat_pool_spent:   Integer(c['combat_pool_spent'] || 0),
        time_tick_schedule:  Array(c['time_tick_schedule']).map { |n| Integer(n) },
        luck_points:         Integer(c['luck_points'] || 0),
        performed_this_turn: c['performed_this_turn'] || false,
        concentration:       (c['concentration'] || []).map { |e| symbolize(e) },
        casting:             (c['casting'] || []).map { |e| symbolize(e) }
      }
    end

    def stringify_combatant(c)
      {
        'id' => c[:id], 'creature_id' => c[:creature_id], 'name' => c[:name],
        'initiative_string' => c[:initiative_string], 'combat_pool_spent' => c[:combat_pool_spent],
        'time_tick_schedule' => c[:time_tick_schedule], 'luck_points' => c[:luck_points],
        'performed_this_turn' => c[:performed_this_turn],
        'concentration' => c[:concentration].map { |e| stringify(e) },
        'casting' => c[:casting].map { |e| stringify(e) }
      }
    end

    def symbolize(h)
      h.respond_to?(:transform_keys) ? h.transform_keys(&:to_sym) : h
    end

    def stringify(h)
      h.respond_to?(:transform_keys) ? h.transform_keys(&:to_s) : h
    end
  end
end
