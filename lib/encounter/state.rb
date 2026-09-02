require 'fileutils'
require 'json'
require_relative '../data_paths'

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
    DATA_PATH    = DataPaths.path('encounter_data.json')
    EXAMPLE_PATH = File.expand_path('../../docs/common/encounter/encounter_data.example.json', __dir__)

    # The Encounter Phases the DM picks between from the menu dropdown.
    # Purely a view selector for the Encounter page (see encounter route /
    # encounter.erb) — it does not start or stop Combat mechanics.
    PHASES         = %i[combat looting traveling social downtime].freeze
    DEFAULT_PHASE  = :downtime

    # Main Actions a Combatant is granted at the start of each turn. We do not
    # enforce the cap (the counter may go negative); it is tracked so the DM
    # can see how many a Combatant has used.
    MAIN_ACTIONS_PER_TURN = 2

    attr_reader :data_path

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH, **opts)
      path = DataPaths.source(data_path, example_path)
      raw = path ? JSON.parse(File.read(path)) : {}
      new(raw, data_path: data_path, **opts)
    end

    # creature_lookup / conditions_for default to the live domains but
    # are injectable for tests. current_timestamp_fn returns Chronicle's
    # current Timestamp ({day_index:, round_of_day:}); rounds_per_day
    # and round_elapsed_fn likewise default to the live domains.
    def initialize(raw = {}, data_path: DATA_PATH,
                   creature_lookup: nil, conditions_for: nil,
                   current_timestamp_fn: nil, rounds_per_day: nil, round_elapsed_fn: nil)
      @data_path           = data_path
      @creature_lookup     = creature_lookup
      @conditions_for      = conditions_for
      @current_timestamp_fn = current_timestamp_fn
      @rounds_per_day      = rounds_per_day
      @round_elapsed_fn    = round_elapsed_fn
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
      # The Encounter Phase: a pure DM-set view selector (it does not drive
      # Combat mechanics) that decides which stubs the Encounter page shows.
      # See PHASES. Defaults to :downtime.
      @phase               = normalize_phase(raw['phase'])
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
        'dm_luck_points'       => @dm_luck_points,
        'phase'                => @phase.to_s
      }
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, pretty_json(to_h))
      File.rename(tmp, @data_path)
    end

    # Ruby's JSON.pretty_generate renders empty arrays/objects across
    # multiple blank lines (e.g. `[\n\n  ]`). Collapse those to `[]` / `{}`.
    # The newline requirement makes this safe against string values that
    # merely contain brackets, since newlines inside strings are escaped.
    def pretty_json(obj)
      JSON.pretty_generate(obj)
          .gsub(/\[\n\s*\]/, '[]')
          .gsub(/\{\n\s*\}/, '{}')
    end

    # ---------- Roster reads ----------

    def combatants               = @combatants.map(&:dup)
    def combatant(id)            = @combatants.find { |c| c[:id] == id }&.dup
    def excluded_pcs             = @excluded_pcs.dup
    def acting_combatant_id      = @acting_combatant_id
    # Absolute Round number (day_index * rounds_per_day + round_of_day), or nil
    # outside any timeline. Public so the route can expire timed Zones.
    def current_round            = current_abs_round
    def time_ticks_per_round     = @time_ticks_per_round
    def time_tick                = @time_tick
    def elapsed_time_ticks       = @elapsed_time_ticks
    def dm_luck_points           = @dm_luck_points
    def granted_actions          = @granted_actions.map(&:dup)
    def phase                    = @phase

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

    # Replace the exclusion list wholesale. Every supplied ID must
    # resolve to a Player Character (tags include player_character) via
    # creature_lookup; the call is rejected (state unchanged) otherwise.
    def set_pc_exclusions(creature_ids)
      ids = Array(creature_ids).map(&:to_s)
      ids.each do |cid|
        creature = lookup!(cid)
        unless creature && Array(creature.tags).include?('player_character')
          raise ArgumentError, "creature #{cid.inspect} is not a Player Character"
        end
      end
      @excluded_pcs = ids
      ids.each { |cid| remove_all_combatants_by_creature_id(cid) }
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

    # ---------- Encounter Phase ----------

    # Set the Encounter Phase (the DM's menu dropdown). Ignores an
    # unrecognized value, leaving the current Phase in place. Returns the
    # Phase in effect after the call.
    def set_phase(value)
      p = value.to_s.to_sym
      if PHASES.include?(p)
        @phase = p
        persist!
      end
      @phase
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
      ts = current_timestamp
      @combat_anchor = { 'day_index' => ts[:day_index], 'round_of_day' => ts[:round_of_day] }
      @dm_luck_points = 0
      @combatants.each do |c|
        c[:luck_points]         = 0
        c[:concentration]       = []
        c[:casting]             = []
        # Combat starts with an empty Combat Pool for everyone; each
        # Combatant refills at the start of their turn (Start of Turn).
        # Storing spent = full pool size makes derived remaining 0.
        c[:combat_pool_spent]   = combat_pool_size_for(c)
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
      @dm_luck_points = 0
      # Initiative is per-fight — clear every Combatant's roll so the
      # next combat starts fresh (and Roll Init rolls everyone).
      @combatants.each { |c| c[:initiative_string] = '' }
      persist!
      self
    end

    # ---------- Combat Pool ----------

    def get_combat_pool(combatant_id)
      c = find!(combatant_id)
      creature = lookup!(c[:creature_id])
      return 0 unless creature
      CombatPool.size_for(creature) + combat_pool_ability_bonus(creature, c[:creature_id])
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

    # The current in-world day (Chronicle Timestamp's day_index). Public surface
    # for once-per-day item charges (a Ring of Parry recharges when this passes
    # the day the charge was spent).
    def current_day_index
      current_timestamp[:day_index]
    end

    # Move (turn_action_stub.md → Move): spend a flat number of Combat Pool
    # dice (Config Move Cost) with no other mechanical effect. Returns
    # { ok:, pool_spent:, pool_remaining: }, or { ok: false, error: } when the
    # Combatant is unknown or cannot afford the cost.
    def apply_move(combatant_id, cost: nil)
      return { ok: false, error: 'unknown combatant' } unless combatant_for(combatant_id)
      cost = cost.nil? ? Config.move_cost : [cost.to_i, 0].max
      remaining = spend_combat_pool(combatant_id, cost)
      return { ok: false, error: 'not enough Combat Pool' } if remaining.nil?
      spend_main_action(combatant_id) # Move is a Main Action
      { ok: true, pool_spent: cost, pool_remaining: remaining }
    end

    # Debit a Combatant's per-turn Luck Points (clamped at zero). One Luck is
    # spent per reroll. Returns the remaining Luck.
    def spend_luck(combatant_id, amount)
      amt = amount.to_i
      c = combatant_for(combatant_id)
      return 0 unless c
      return c[:luck_points].to_i if amt <= 0
      c[:luck_points] = [c[:luck_points].to_i - amt, 0].max
      persist!
      c[:luck_points]
    end

    # Grant per-turn Luck Points to a Combatant (e.g. a Bardic Inspiration
    # discharge). Returns the new Luck total.
    def grant_luck(combatant_id, amount)
      c = combatant_for(combatant_id) or return nil
      c[:luck_points] = c[:luck_points].to_i + [amount.to_i, 0].max
      persist!
      c[:luck_points]
    end

    # Grant Luck Points to the DM's Combat-level pool (the DM is "player id
    # null"). Unlike a Combatant's per-turn Luck, DM Luck persists across turns
    # and rounds — it clears only at End Combat. Returns the new total.
    def grant_dm_luck(amount)
      @dm_luck_points += [amount.to_i, 0].max
      persist!
      @dm_luck_points
    end

    # Debit the DM's Luck pool (clamped at zero). Returns the remaining total.
    def spend_dm_luck(amount)
      amt = amount.to_i
      return @dm_luck_points if amt <= 0
      @dm_luck_points = [@dm_luck_points - amt, 0].max
      persist!
      @dm_luck_points
    end

    # Spend the Luck source chosen for an attack (commit only). `luck` is
    # `{ source_id, amount }` from the attack payload: `source_id == 'self'`
    # debits the attacker's own Luck Points; any other id is an ally Bard
    # whose Bardic Inspiration Reservoir is discharged by `amount` (the
    # Reaction). The reroll itself was applied client-side, so no Luck Points
    # are granted here — only the source is debited.
    def apply_attack_luck(attacker_id, luck)
      return unless luck.is_a?(Hash)
      amt = luck[:amount].to_i
      return unless amt.positive?
      if luck[:source_id].to_s == 'self'
        spend_luck(attacker_id, amt)
      else
        c = combatant_for(luck[:source_id].to_i) or return
        entry = c[:concentration].find { |e| e[:mode] == 'reservoir' && e[:reservoir].to_i.positive? } or return
        discharge_reservoir(c[:id], entry[:spell_name], amt)
      end
    end

    # Spend the Luck sources chosen during a Check's Luck steps (commit only).
    # `spends` is a list of `{ source_id, amount }`: a null/"dm" source_id
    # debits the DM's Luck pool (player id null); any other id is a Combatant
    # whose Bardic Inspiration Reservoir is discharged by `amount` (a Reaction).
    # The reroll itself is applied client-side as the DM rolls; here we only
    # debit each source by the amount it committed.
    def apply_luck_spends(spends)
      Array(spends).each do |raw|
        s   = deep_symbolize(raw)
        amt = s[:amount].to_i
        next unless amt.positive?
        sid = s[:source_id]
        if sid.nil? || sid.to_s.empty? || sid.to_s == 'dm'
          spend_dm_luck(amt)
        else
          c = combatant_for(sid.to_i) or next
          entry = c[:concentration].find { |e| e[:mode] == 'reservoir' && e[:reservoir].to_i.positive? } or next
          discharge_reservoir(c[:id], entry[:spell_name], amt)
        end
      end
    end

    # Discharge `amount` dice from a Combatant's reservoir-mode Concentration
    # (Bardic Inspiration) and grant that many Luck Points to the target
    # Creature — self or any ally — per the Ability's Discharge effect
    # (abilities_design.md → Reservoir Discharge). The discharge is a Reaction,
    # so it can fire on any Creature's turn. Returns a result hash.
    def discharge_luck_reservoir(combatant_id, target_id, amount, spell_name: 'Bardic Inspiration')
      amt = amount.to_i
      return { ok: false, error: 'amount must be positive' } if amt <= 0
      return { ok: false, error: 'unknown target' } unless combatant_for(target_id)
      entry = discharge_reservoir(combatant_id, spell_name, amt)
      return { ok: false, error: 'not enough Reservoir to discharge' } unless entry
      luck = grant_luck(target_id, amt)
      { ok: true, granted: amt, target_id: target_id, target_luck: luck,
        reservoir: entry[:reservoir], spell_name: spell_name }
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
    # descending (ASCII), ties broken by Combat ID ascending. Combatants
    # who have not rolled Initiative (empty string) sort last, matching the
    # Combat Tracker's display order so "the bottom of the tracker" is also
    # the last to act.
    def acting_combatants(tick = @time_tick)
      @combatants
        .select { |c| Array(c[:time_tick_schedule]).include?(tick) }
        .sort_by { |c| turn_sort_key(c) }
    end

    # Set one Combatant's Initiative String from a raw value (parsed to
    # valid die-result characters, sorted descending). Returns the
    # normalized string, or nil if the Combatant doesn't exist.
    def set_initiative(combatant_id, raw)
      c = combatant_for(combatant_id) or return nil
      c[:initiative_string] = Initiative.normalize_string(raw)
      persist!
      c[:initiative_string]
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
      # Turns only advance once Combat has started (initiative rolled, Time
      # Ticks seeded). Before that @time_tick is nil, so advancing a turn — e.g.
      # the End Turn button showing in the Combat phase before Start Combat —
      # must no-op rather than crash on nil Time-Tick arithmetic.
      return nil unless combat_active?
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
      # Begin the incoming Combatant's turn: refill its Combat Pool, grant its
      # Main Actions, run Per-Turn Setup, and clear its expired Effects.
      begin_turn_for(@acting_combatant_id) if @acting_combatant_id
      persist!
      @acting_combatant_id
    end

    # Apply Per-Turn Setup to the incoming Combatant: reset per-turn
    # Concentration Reservoirs to 0 (persistent reservoirs untouched).
    def apply_per_turn_setup(combatant_id)
      c = combatant_for(combatant_id)
      return unless c
      c[:concentration].each do |e|
        e[:reservoir] = 0 if e[:reservoir_reset] == 'per_turn'
      end
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

    # True iff the elapsed-Time-Tick-implied Round disagrees with
    # Chronicle's current Round. Compared as absolute rounds
    # (day_index × Rounds Per Day + round_of_day) so a Day rollover
    # between Combat ticks does not spuriously read as stale.
    def stale?
      return false if @combat_anchor.nil?
      rpd = rounds_per_day
      anchor_day = Integer(@combat_anchor['day_index'] || @combat_anchor[:day_index] || 0)
      anchor_rod = Integer(@combat_anchor['round_of_day'] || @combat_anchor[:round_of_day] || 0)
      expected_abs = (anchor_day * rpd) + anchor_rod + (@elapsed_time_ticks / (@time_ticks_per_round || 1))
      ts = current_timestamp
      current_abs = (ts[:day_index] * rpd) + ts[:round_of_day]
      expected_abs != current_abs
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

    # Current Round number (1-based), inferred from elapsed Time Ticks.
    def round_number
      return 0 unless combat_active?
      (@elapsed_time_ticks / (@time_ticks_per_round || 1)) + 1
    end

    # The Round's turn order: every Combatant once, by their first scheduled
    # Time Tick, then un-rolled last, then Initiative String (descending),
    # then Combat ID — matching the Combat Tracker's display order.
    def round_turn_order
      @combatants.sort_by do |c|
        first_tick = Array(c[:time_tick_schedule]).min || 9_999
        [first_tick, *turn_sort_key(c)]
      end
    end

    # Does this Combatant still have a turn coming this Round — i.e. it has
    # not yet acted? True when it sits later in the Round's turn order than
    # the Acting Combatant. Before Initiative is seated (no Acting
    # Combatant) nobody has acted, so every Combatant's turn is still
    # pending. The Acting Combatant itself counts as already-acting (its
    # next turn is next Round).
    def turn_pending_this_round?(combatant_id)
      return false unless combat_active?
      return true if @acting_combatant_id.nil?
      order = round_turn_order.map { |c| c[:id] }
      ai = order.index(@acting_combatant_id)
      ti = order.index(combatant_id)
      return false if ai.nil? || ti.nil?
      ti > ai
    end

    # Is this Combatant Unaware (has not yet acted in the Combat)? Inferred,
    # not stored: a Combatant is Unaware only in Round 1, before its first
    # turn comes up — i.e. its turn is still pending this Round. From Round
    # 2 on everyone has acted at least once.
    def unaware?(combatant_id)
      round_number == 1 && turn_pending_this_round?(combatant_id)
    end

    # ---------- Damage ----------

    # Apply Damage → Severity Calculation → Conditions, then trigger one
    # Concentration Save per held Concentration / Casting entry.
    #
    # `save_resolver` is a proc called once per entry with
    # { spell_name:, cast_skill:, penalty:, kind: } and returning a
    # truthy value when the save passes. The default passes every save
    # (no breakage) until a Check Resolution engine is wired in. On a
    # failed save the matching Concentration ends / Long Cast cancels
    # with reason: damage; those notifications are returned for dispatch.
    def apply_damage(combatant_id, raw, type, threshold: 0, save_resolver: ->(_) { true }, extra_resilience: 0)
      c = find!(combatant_id)
      creature = lookup!(c[:creature_id])
      # `extra_resilience` is a one-shot Damage Resilience for this hit only
      # (Danger Sense), on top of the defender's armor + active Conditions.
      resilience = defender_damage_resilience(creature) + condition_resilience(c[:creature_id]) + extra_resilience.to_i
      tags = creature ? Array(creature.tags) : []

      result = Severity.compute(raw: raw, type: type, threshold: threshold,
                                damage_resilience: resilience, target_tags: tags)
      inst = conditions_for(c[:creature_id])
      inst.apply_hit_point_damage(result[:severity_map]) unless result[:severity_map].empty?
      result[:side_effects].each do |fx|
        case fx[:kind]
        when 'acid' then inst.apply_acid_damage(fx[:amount])
        when 'inflict' then inst.state.shock += fx[:amount] if fx[:effect] == 'shock'
        end
      end

      damage_dealt = result[:severity_map].values.sum
      # Unhealed acid/fire *hit-point damage* suppresses Regeneration (see
      # Conditions). This is the damage actually dealt by the hit — distinct
      # from the acid_counter, which is a separate lingering-corrosion pool.
      if damage_dealt.positive? && regen_blocking_type?(type)
        inst.apply_elemental_wound(damage_dealt)
      end
      notifications = trigger_concentration_saves(c, damage_dealt, save_resolver)

      { severity_map: result[:severity_map], side_effects: result[:side_effects],
        concentration_notifications: notifications }
    end

    # Whether a Damage Type is one whose unhealed damage shuts down
    # Regeneration: fire or acid.
    def regen_blocking_type?(type)
      t = type.to_s.downcase
      t.include?('fire') || t.include?('acid')
    end

    # Set-Value Spend translation (encounter_design.md → Operations).
    # Prerolling N dice on a Roll with Dice Cap D spends N × Set Value
    # Spend Ratio extra dice from the pool and builds a Roll with
    # dice_count = D - N and preroll = +N. Refuses N > Dice Cap or an
    # overdraw. Returns { dice_count:, preroll: } or nil on refusal.
    def set_value_spend(combatant_id, dice_cap:, preroll_count:)
      return nil if preroll_count.negative? || preroll_count > dice_cap
      cost = preroll_count * Config.set_value_spend_ratio
      return nil if spend_combat_pool(combatant_id, cost).nil?
      { dice_count: dice_cap - preroll_count, preroll: preroll_count }
    end

    # Apply Falling Damage per encounter_design.md.
    def apply_falling_damage(combatant_id, fall_distance, modifier: 0, acrobatics_successes: 0)
      per10 = [Config.falling_damage_per_10_feet + modifier, 0].max
      raw = (fall_distance / 10) * per10
      raw = [raw - acrobatics_successes, 0].max
      apply_damage(combatant_id, raw, 'physical', threshold: Config.falling_damage_threshold)
    end

    # ---------- Resolve Attack payload ----------

    # Consume the turn-flow payload (turn_action_stub.md → Confirm
    # payload): spend Combat Pool for every participant — the weapon's flat
    # Speed cost plus one per die rolled (Speed + dice, not Speed × dice) —
    # sum Supporting DoIS minus Opposing DoIS, and apply damage when the
    # net DoS is positive. Successes are pre-rolled by the client and
    # carried in the payload. Returns { damage:, severity_map:, net_dos: }.
    #
    # Payload (symbol or string keys):
    #   target_id, attack_kind ('melee'|'ranged'|'spell', default melee),
    #   weapon:   { damage_types:, threshold:, base_damage: } (optional;
    #             falls back to damage_bonus + 'physical'),
    #   damage_bonus,
    #   attacker: { id, dice, speed, successes },
    #   defense:  { choice, id, dice, speed, successes },  # "none" skips;
    #             Dodge costs no Combat Pool; ineligible defenses reject,
    #   allies:   [ { id, dice, speed, successes }, ... ]
    def resolve_attack_payload(payload)
      p = deep_symbolize(payload)
      attacker = p[:attacker] || {}
      defense  = p[:defense]  || {}
      allies   = Array(p[:allies])
      attack_kind = (p[:attack_kind] || 'melee').to_s
      weapon = p[:weapon] || {}
      # commit:false runs a non-mutating preview — same numbers, but no Combat
      # Pool spent and no damage / bleed applied. The turn-action panel uses it
      # to show the result before the DM commits (a second Confirm).
      commit = p.fetch(:commit, true) != false

      # Reject an ineligible Defensive Action before spending anything.
      choice = defense[:choice].to_s
      # Better Lucky Than Good is a Reaction, not a Defensive Action: it spends
      # Mana and halves the attacker's dice (already done client-side) but rolls
      # no defense and costs no Combat Pool — so it nets no Successes and is not
      # in the eligibility table.
      better_lucky = (choice == 'better_lucky')
      declared = !(choice.empty? || choice == 'none' || defense.empty? || better_lucky)
      if declared && !Attack.defense_eligible?(choice, attack_kind)
        return { ok: false, error: "#{choice} is not eligible against a #{attack_kind} attack",
                 damage: 0, severity_map: {}, net_dos: 0, bleed: 0, pool_spends: [] }
      end

      # Post-roll defender Reactions (Danger Sense / Primal Tenacity), each a
      # one-shot Modifier on this single attack: Danger Sense adds Damage
      # Resilience (a wider Severity bucket), Primal Tenacity adds Damage
      # Reduction (subtracted from the damage). Specs are enriched route-side.
      reactions    = Array(p[:defender_reactions])
      extra_resil  = reactions.select { |r| r[:target].to_s == 'damage_resilience' }.sum { |r| r[:amount].to_i }
      extra_reduce = reactions.select { |r| r[:target].to_s == 'damage_reduction' }.sum { |r| r[:amount].to_i }

      # Combat Pool each participant spends (Speed + dice). Dodge (a Saving
      # Throw) spends none. Reported either way; only applied on commit.
      # DM overrides from the result panel's editable fields (commit only).
      over = p[:override] || {}

      pool_spends = []
      # A Spiritual Weapon strike (free_attacker_pool) rolls Reservoir dice, not
      # Combat Pool, so the attacker spends nothing.
      pool_spends << { id: attacker[:id], amount: pool_cost(attacker) } if attacker[:id] && !p[:free_attacker_pool]
      allies.each { |a| pool_spends << { id: a[:id], amount: pool_cost(a) } if a[:id] }
      opposing = 0
      if declared
        if Attack.defense_spec(choice)[:pool_cost] && defense[:id]
          pool_spends << { id: defense[:id], amount: pool_cost(defense) }
        end
        opposing = defense[:successes].to_i
      end
      # A shielding caster (Shield of Faith / the Shield spell) defends the target
      # as an extra Opposing Roll. Its Successes subtract from the attack like any
      # defense. The block dice come from the shield's source: a Combat-Pool block
      # (Shield) folds into pool_spends; a Reservoir block (Shield of Faith) is
      # discharged on commit.
      shield = p[:shield] || {}
      opposing += shield[:successes].to_i if shield[:id]
      shield_pool = shield[:id] && shield[:dice_source].to_s == 'combat_pool' && shield[:dice].to_i.positive?
      pool_spends << { id: shield[:id], amount: shield[:dice].to_i } if shield_pool
      pool_spends = apply_pool_override(pool_spends, over[:pool_spends])
      pool_spends.each { |s| spend_combat_pool(s[:id], s[:amount].to_i) } if commit
      if commit && shield[:id] && shield[:dice].to_i.positive? && shield[:dice_source].to_s != 'combat_pool'
        discharge_reservoir(shield[:id], (shield[:spell_name] || 'Shield of Faith').to_s, shield[:dice].to_i)
      end
      # Debit the Luck applied to this attack. Each Luck is one reroll (applied
      # client-side already); here we only spend the source: an ally Bard's
      # Reservoir (a Reaction discharge) or the attacker's own Luck Points.
      apply_attack_luck(attacker[:id], attacker[:luck]) if commit
      apply_luck_spends(p[:luck]) if commit

      # Debit the defender's Mana for the Reactions it used: Better Lucky Than
      # Good (a Defense-step Reaction) and any post-roll Danger Sense / Primal
      # Tenacity. Reported numbers are unchanged on preview; only spent on commit.
      if commit
        if better_lucky && defense[:id] && defense[:mana_cost].to_i.positive?
          spend_reaction_mana(defense[:id], defense[:mana_cost].to_i)
        end
        reactions.each do |r|
          spend_reaction_mana(p[:target_id], r[:mana_cost].to_i) if r[:mana_cost].to_i.positive?
        end
      end

      supporting = attacker[:successes].to_i + allies.sum { |a| a[:successes].to_i }
      net = supporting - opposing
      threshold = weapon[:threshold].to_i
      # Danger Sense's one-shot Damage Resilience adds to the bucketing for this
      # attack only (it is not a lingering Condition).
      resil = defender_resilience(p[:target_id]) + extra_resil
      dtype = (Array(weapon[:damage_types]).first || weapon[:damage_type] || 'physical').to_s
      # Affliction the weapon injects on a hit (e.g. a spider's venom). Drives
      # the poison input the attack resolution shows beside damage / bleed.
      poison_name = weapon[:affliction].to_s
      has_poison  = !poison_name.empty?
      poison_label = has_poison ? poison_name.split('_').map(&:capitalize).join(' ') : nil

      # Tier Mismatch Inherent damage reduction: a higher-Tier defender shrugs
      # off 5 damage per Tier it stands above the attacker (Tier 0 counts as
      # 0.5) — the same rule that reduces spell / ability damage. The attacker's
      # effective Tier may be raised by Glorious Charge (the payload's
      # `attacker.tier_bonus`) and, for a weapon, by the weapon's Glory Property
      # (`tier_advantage`), which treats the wielder as that many Tiers higher
      # when fighting up and so shrinks the gap before the reduction. Glory is
      # weapon-only; spells fold in nothing here.
      atk_tier = combatant_tier(attacker[:id]) + attacker[:tier_bonus].to_i
      atk_eff_tier = Encounter::Attack.effective_attacker_tier(
        atk_tier, combatant_tier(p[:target_id]), weapon[:tier_advantage].to_i)
      inherent_dr = TierMismatch.inherent_damage_reduction(combatant_tier(p[:target_id]), atk_eff_tier)
      # Passive Damage Reduction: the defender's equipped Armor + direct
      # attribute + active-effect DR Modifiers (e.g. Rage). Subtracted from
      # the base weapon damage before the Severity split, alongside the Tier-
      # Mismatch Inherent DR and any one-shot Primal Tenacity Reaction.
      passive_dr = defender_reduction(p[:target_id])

      if net.positive?
        base = weapon[:base_damage] ? weapon[:base_damage].to_i : p[:damage_bonus].to_i
        # Computed damage / bleed, each replaceable by a DM override. Bleed is
        # the weapon's Bleed plus the damage dealt (encounter_design.md →
        # "actual bleed = Bleed Constant + damage dealt"), so a 0-Bleed weapon
        # still bleeds for its damage. Inherent DR is subtracted before the
        # severity split (floored at 0).
        # Primal Tenacity's one-shot Damage Reduction is subtracted here, like
        # the Tier-Mismatch Inherent DR, before the Severity split (floored at 0).
        # Passive Damage Reduction (Armor / attribute / Rage) is subtracted too.
        computed = [base + net - inherent_dr - passive_dr - extra_reduce, 0].max
        damage = over.key?(:damage) ? over[:damage].to_i : computed
        bleed  = over.key?(:bleed)  ? over[:bleed].to_i  : weapon[:bleed].to_i + damage
        # Poison potency = the weapon's Affliction Potency constant + the
        # damage dealt (the same "constant + damage" shape as Bleed), editable
        # by the DM. Only weapons carrying an Affliction offer it.
        poison = if over.key?(:poison)
                   over[:poison].to_i
                 elsif has_poison
                   [weapon[:affliction_potency].to_i + damage, 1].max
                 else
                   0
                 end
        if commit
          out = apply_damage(p[:target_id], damage, dtype, threshold: threshold, extra_resilience: extra_resil)
          apply_weapon_bleed(p[:target_id], attacker[:id], bleed) if bleed.positive?
          apply_weapon_poison(p[:target_id], attacker[:id], poison_name, poison) if has_poison && poison.positive?
          sev = out[:severity_map]
        else
          sev = preview_severity(p[:target_id], damage, dtype, threshold, extra_resilience: extra_resil)
        end
        # Magical weapon Damage Riders: the 4 extra dice the DM rolls
        # client-side at the attack's Target Number once the hit lands. Each
        # rider lands as its own Severity Calculation, kept separate from the
        # weapon's base damage; a Vicious rider also bites the wielder. The
        # per-rider Success / "1" counts arrive in `rider_results`.
        riders = Array(weapon[:damage_riders]).each_with_index.map { |r, i| r.merge(id: i) }
        rider_outcomes = apply_attack_riders(p[:target_id], attacker[:id], riders, p[:rider_results], commit)
        { ok: true, damage: damage, severity_map: sev, net_dos: net, damage_type: dtype,
          threshold: threshold, damage_resilience: resil, inherent_dr: inherent_dr,
          passive_dr: passive_dr, bleed: bleed,
          poison: poison, poison_name: poison_label,
          riders: riders, rider_outcomes: rider_outcomes,
          pool_spends: pool_spends, committed: commit }
      else
        { ok: true, damage: 0, severity_map: {}, net_dos: net, damage_type: dtype,
          threshold: threshold, damage_resilience: resil, inherent_dr: inherent_dr,
          passive_dr: passive_dr, bleed: 0,
          poison: 0, poison_name: poison_label,
          pool_spends: pool_spends, committed: commit }
      end
    end

    # ---------- Resolve Cast payload ----------

    # Consume the turn-flow Cast payload (turn_action_stub.md → Cast): spend
    # the caster's Combat Pool (casting-time Speed + dice rolled), debit Mana,
    # apply Magic Toxicity (positive contributions are gated by Conditions when
    # the caster is already over the Toxicity Threshold), then route each
    # target's resolved Effects to the owning domains — Combat's Apply Damage
    # for damage, Conditions for heal / mana / Temporary HP / Active Effects.
    # A Save block per target nets the caster's Successes against the target's
    # Save Successes (Encounter::Cast.resolve_save); finally register a
    # Concentration / Long Cast Entry for a sustained spell.
    #
    # commit:false runs a non-mutating preview — same numbers, but no Combat
    # Pool / Mana / Toxicity spent and no Effects applied. Saving Throws (the
    # target Saves) never cost Combat Pool; only the caster spends.
    #
    # Payload (symbol or string keys):
    #   caster:  { id, dice, speed, successes } — speed is the casting time's
    #            flat Combat-Pool cost; successes the casting-check net.
    #   spell:   { name, tier, cast_skill, polarity, mana_cost, toxicity,
    #            source } — interpreted by Abilities; Combat just routes it.
    #   targets: [ { id, save: { successes, on_success, success_effects } | nil,
    #            effects: [ <resolved effect>, ... ] }, ... ]
    #   sustain: nil | { kind: 'concentration'|'long_cast', mode:,
    #            reservoir_reset:, initial_reservoir:, turns_required: }
    #   override (commit only): { mana:, toxicity:, pool_spends: [{id, amount}] }
    #
    # Resolved Effect kinds (the seam with Abilities.resolve_spell):
    #   { kind: 'damage',  amount:, damage_type:, threshold: }
    #   { kind: 'heal',    severity_map: { minor:, moderate:, major: } }
    #   { kind: 'mana',    amount: }
    #   { kind: 'temp_hp', amount:, ends_on_round: }
    #   { kind: 'effect',  name:, ends_on_round: }
    #   { kind: 'modifiers', modifiers: [{ target:, type:, add:, descriptors? }],
    #            duration: }  # buff Spells; amounts evaluated against the caster
    #            and applied as timed Active Effects (Magic Weapon, Magic
    #            Vestments, Expeditious Retreat, Resistance, Protection from Poison).
    def resolve_cast_payload(payload)
      p = deep_symbolize(payload)
      caster  = p[:caster] || {}
      spell   = p[:spell]  || {}
      targets = Array(p[:targets])
      commit  = p.fetch(:commit, true) != false
      over    = p[:override] || {}

      return cast_error('caster id is required') unless caster[:id]
      cc = combatant_for(caster[:id])
      return cast_error("no Combatant with id #{caster[:id]}") unless cc

      caster_creature = lookup!(cc[:creature_id])
      caster_inst     = conditions_for(cc[:creature_id])

      mana_cost = over.key?(:mana) ? over[:mana].to_i : spell[:mana_cost].to_i
      mana_max  = (caster_creature&.max_mana rescue 0).to_i
      toxicity  = over.key?(:toxicity) ? over[:toxicity].to_i : spell[:toxicity].to_i
      cha       = (caster_creature&.attribute_value(:cha) rescue 0).to_i
      tier      = (caster_creature&.tier rescue 0)
      polarity  = (spell[:polarity] || 'positive').to_s

      attack_roll  = spell[:attack_roll] ? true : false
      casting_stat = if spell[:default_damage] || attack_roll
                       (caster_creature&.attribute_value((spell[:casting_attribute] || :cha).to_sym) rescue 0).to_i
                     else
                       0
                     end

      # Default Spell damage (floor(casting stat / 4) + Tier + Successes) for a
      # Save-based damage Spell that declares no explicit damage Effect. Injected
      # per target before Save resolution, so the target's Save still halves /
      # negates it. Attack-roll Spells instead compute damage from the *net*
      # Successes per target (cast_attack_target).
      if spell[:default_damage] && !attack_roll
        default_fx = { kind: 'damage', damage_type: (spell[:damage_type] || 'force').to_s,
                       threshold: spell[:threshold].to_i,
                       amount: Cast.default_spell_damage(casting_stat: casting_stat,
                                                         tier: spell[:tier], successes: caster[:successes],
                                                         competency: spell[:cast_competency].to_i) }
        targets = targets.map do |t|
          Array(t[:effects]).any? { |e| e[:kind].to_s == 'damage' } ? t : t.merge(effects: [default_fx] + Array(t[:effects]))
        end
      end

      # Resolve every target before mutating anything. An attack-roll Spell nets
      # the casting check against the target's Defensive Action (Block / Dodge,
      # per Encounter::Attack); every other Spell nets against the target's Save.
      resolved = targets.map do |t|
        attack_roll ? cast_attack_target(t, spell, caster, casting_stat) : cast_save_target(t, caster)
      end

      # Damage reduction before the Severity split, subtracted from each
      # resolved damage Effect (after Save halving) so preview and commit agree:
      #   - Tier Mismatch Inherent DR: a higher-Tier target shrugs off 5 damage
      #     per Tier it stands above the caster (caster tier may be raised via
      #     caster.tier_bonus).
      #   - Passive DR: the target's equipped Armor + direct attribute +
      #     active-effect DR Modifiers (Rage) — spells are reduced by it too.
      caster_eff_tier = combatant_tier(caster[:id]) + caster[:tier_bonus].to_i
      resolved = resolved.map do |t|
        dr = TierMismatch.inherent_damage_reduction(combatant_tier(t[:id]), caster_eff_tier)
        passive = defender_reduction(t[:id])
        total_reduce = dr + passive
        next t if total_reduce.zero? || Array(t[:effects]).empty?
        reduced = Array(t[:effects]).map do |e|
          e[:kind].to_s == 'damage' ? e.merge(amount: [e[:amount].to_i - total_reduce, 0].max, inherent_dr: dr, passive_dr: passive) : e
        end
        t.merge(effects: reduced)
      end

      # Buff modifiers: evaluate each spell modifier's amount against the caster
      # (so Magic Weapon's `caster_tier` etc. become concrete) and compute its
      # expiry, once, so both preview and commit apply the same Active Effects.
      caster_level = (caster_creature.total_level rescue nil) || tier
      mod_binds = { 'caster_tier' => tier, 'tier' => (spell[:tier] || 0),
                    'level' => caster_level, 'rank' => caster_level }
      resolved = resolved.map do |t|
        next t if Array(t[:effects]).none? { |e| e[:kind].to_s == 'modifiers' }
        fx = Array(t[:effects]).map do |e|
          e[:kind].to_s == 'modifiers' ? resolve_modifier_effect(e, mod_binds) : e
        end
        t.merge(effects: fx)
      end

      # Temporary-HP buffs (Ward) carry a turns-based `duration`; compute the
      # expiry Round once so the temp HP — and the Ward condition that mirrors
      # it — fade together when the Spell ends.
      resolved = resolved.map do |t|
        next t if Array(t[:effects]).none? { |e| e[:kind].to_s == 'temp_hp' && e[:duration] }
        fx = Array(t[:effects]).map do |e|
          next e unless e[:kind].to_s == 'temp_hp' && e[:duration] && e[:ends_on_round].nil?
          e.merge(ends_on_round: modifier_ends_on_round(e[:duration], mod_binds))
        end
        t.merge(effects: fx)
      end

      # Combat Pool: the caster's casting-time Speed + dice, plus any pool-costed
      # Defensive Action (Dodge / Block) the defender spent. A Save spell's
      # Saving Throw costs none. DM may override the spends.
      pool_spends = apply_pool_override(
        [{ id: caster[:id], amount: pool_cost(caster) }] + resolved.filter_map { |r| r[:defender_pool] },
        over[:pool_spends]
      )

      base = { ok: true, committed: commit, spell: spell[:name],
               cast_skill: (spell[:cast_skill] || Cast::DEFAULT_CAST_SKILL).to_s,
               pool_spends: pool_spends, mana_cost: mana_cost, mana_max: mana_max }

      if commit
        # DM heal override: the confirm page exposes an editable box per Severity
        # of a heal Effect; fold those amounts onto the resolved targets before
        # they are applied so the cure heals exactly what the DM entered.
        apply_heal_override!(resolved, over[:heals]) if over[:heals]
        # DM damage override: the confirm page exposes an editable box per
        # damaged target; fold the entered amount onto its damage Effect so the
        # Severity split is recomputed from exactly what the DM committed.
        apply_damage_override!(resolved, over[:damages]) if over[:damages]
        pool_spends.each { |s| spend_combat_pool(s[:id], s[:amount].to_i) }
        apply_luck_spends(p[:luck])
        mana_spent = mana_cost.positive? ? caster_inst.apply_mana_cost(amount: mana_cost, mana_max: mana_max) : 0
        tox = apply_cast_toxicity(caster_inst, toxicity, polarity, cha, tier)
        applied = resolved.map { |t| apply_cast_target(t, spell) }
        apply_bleed_reduction!(applied, spell[:bleed_reduction].to_i, commit: true)
        sustain = p[:sustain] ? register_cast_sustain(caster[:id], spell, p[:sustain], channel_dice: caster[:dice].to_i) : nil
        base.merge(mana_spent: mana_spent, toxicity: tox, targets: applied, sustain: sustain)
      else
        available  = [mana_max - (caster_inst.state.mana_spent rescue 0), 0].max
        mana_spent = mana_cost.positive? ? [mana_cost, available].min : 0
        tox = preview_cast_toxicity(caster_inst, toxicity, polarity, cha, tier)
        previews = resolved.map { |t| preview_cast_target(t) }
        apply_bleed_reduction!(previews, spell[:bleed_reduction].to_i, commit: false)
        sustain  = p[:sustain] ? { kind: deep_symbolize(p[:sustain])[:kind].to_s, spell_name: spell[:name] } : nil
        base.merge(mana_spent: mana_spent, toxicity: tox, targets: previews, sustain: sustain)
      end
    end

    # The target's Damage Resilience (so the panel can re-bucket a DM-adjusted
    # damage into Minor/Moderate/Major exactly as Apply Damage would).
    def defender_resilience(combatant_id)
      c = combatant_for(combatant_id) or return 0
      defender_damage_resilience(lookup!(c[:creature_id])) + condition_resilience(c[:creature_id])
    rescue StandardError
      0
    end

    # The target's passive Damage Reduction — equipped Armor + direct
    # attribute + active-effect DR Modifiers (Rage) — subtracted from an
    # incoming hit before the Severity split. Mirrors defender_resilience;
    # excludes the one-shot Primal Tenacity Reaction (carried separately).
    def defender_reduction(combatant_id)
      c = combatant_for(combatant_id) or return 0
      defender_damage_reduction(lookup!(c[:creature_id])) + condition_reduction(c[:creature_id])
    rescue StandardError
      0
    end

    # Merge DM pool-spend overrides ([{id, amount}]) onto the computed spends,
    # matching by Combatant id.
    def apply_pool_override(spends, overrides)
      return spends unless overrides
      by_id = Array(overrides).each_with_object({}) { |o, h| h[o[:id]] = o[:amount].to_i }
      spends.map { |s| by_id.key?(s[:id]) ? s.merge(amount: by_id[s[:id]]) : s }
    end

    # Severity bucketing for a hypothetical hit, without applying it — mirrors
    # the front of apply_damage so the preview shows the same Minor/Moderate/
    # Major split the commit will produce.
    def preview_severity(combatant_id, raw, type, threshold, extra_resilience: 0)
      c = combatant_for(combatant_id) or return {}
      creature = lookup!(c[:creature_id])
      Severity.compute(raw: raw, type: type, threshold: threshold,
                       damage_resilience: defender_damage_resilience(creature) + condition_resilience(c[:creature_id]) + extra_resilience.to_i,
                       target_tags: creature ? Array(creature.tags) : [])[:severity_map]
    rescue StandardError
      {}
    end

    # ---------- Magical weapon Damage Riders ----------

    # Apply the weapon's Damage Riders for a landed hit. `riders` are the
    # resolved rider specs from Get Weapon Details; `results` is the client's
    # per-rider roll — a list of { id:, damage:, self_damage: } (the rolled,
    # DM-editable amounts: bonus damage to the target and self-damage to the
    # wielder). Each rider lands as its own Severity Calculation, separate from
    # the weapon's base damage. Returns one outcome per rider for the result
    # panel; only mutates Conditions when `commit` is true.
    def apply_attack_riders(target_id, attacker_id, riders, results, commit)
      return [] if riders.nil? || riders.empty?
      by_id = Array(results).each_with_object({}) do |r, h|
        rr = deep_symbolize(r)
        h[rr[:id].to_i] = rr
      end
      riders.each_with_index.map do |rider, i|
        # The client rolled each rider (4 dice at the attack's TN) and the DM may
        # have edited the result in the damage screen; the payload carries the
        # final `damage` (to the target) and `self_damage` (to the wielder).
        res      = by_id[i] || {}
        amt      = res[:damage].to_i
        self_amt = res[:self_damage].to_i
        outcome  = { id: i, label: rider[:label] }

        if rider[:kind].to_s == 'named_effect'
          outcome[:effect] = rider[:effect]
          outcome[:amount] = amt
          apply_rider_named_effect(target_id, rider[:effect], amt) if commit && amt.positive?
        else
          outcome[:damage]       = amt
          outcome[:damage_type]  = rider[:damage_type]
          outcome[:severity_map] = rider_target_severity(target_id, amt, rider, commit)
        end

        if rider[:self_damage]
          sev = rider[:self_damage][:severity]
          outcome[:self_damage] = { severity: sev.to_s, amount: self_amt }
          apply_hp_severity(attacker_id, sev, self_amt) if commit && self_amt.positive?
        end
        outcome
      end
    end

    # A Combatant's Creature Tier (0 when unknown). Tier 0 is the floor; the
    # 0.5 convention is applied where the Tier Mismatch formulas need it.
    def combatant_tier(combatant_id)
      c = combatant_for(combatant_id) or return 0
      (lookup!(c[:creature_id])&.tier rescue 0) || 0
    end

    # Bucket (and, on commit, apply) a rider's target damage. A rider with
    # an explicit `severity` lands wholly in that Severity bucket; otherwise
    # the rider's Damage Type drives a normal Severity Calculation —
    # separate from the weapon's base-damage calculation either way.
    def rider_target_severity(target_id, amount, rider, commit)
      return {} unless amount.positive?
      if rider[:severity]
        map = { rider[:severity].to_s.to_sym => amount }
        apply_hp_severity(target_id, rider[:severity], amount) if commit
        map
      elsif commit
        apply_damage(target_id, amount, rider[:damage_type].to_s)[:severity_map]
      else
        preview_severity(target_id, amount, rider[:damage_type].to_s, 0)
      end
    end

    # Apply a flat Severity-keyed Hit Point Damage amount to a Combatant
    # (rider self-damage, or a rider's forced-Severity target damage).
    def apply_hp_severity(combatant_id, severity, amount)
      c = combatant_for(combatant_id) or return
      conditions_for(c[:creature_id]).apply_hit_point_damage(severity.to_s.to_sym => amount)
    rescue StandardError
      nil
    end

    # Apply a rider's named Effect (e.g. Subdual's Shock) to the target,
    # mirroring the Damage-Type `inflict` side-effect routing in apply_damage.
    def apply_rider_named_effect(target_id, effect, amount)
      c = combatant_for(target_id) or return
      inst = conditions_for(c[:creature_id])
      inst.state.shock += amount if effect.to_s == 'shock'
    rescue StandardError
      nil
    end

    # Active-effect Damage Resilience Modifiers (e.g. Rage) for a Creature,
    # added to equipped-Armor Resilience in the bucketing pipeline.
    def condition_resilience(creature_id)
      conditions_for(creature_id).get_modifiers('damage_resilience').sum { |_type, amount| amount.to_i }
    rescue StandardError
      0
    end

    # Active-effect Damage Reduction Modifiers (e.g. Rage's Circumstance DR)
    # for a Creature, added to equipped-Armor Reduction when reducing an
    # incoming hit. Excludes the one-shot Primal Tenacity Reaction, which
    # rides the attack payload separately (`extra_reduce`).
    def condition_reduction(creature_id)
      conditions_for(creature_id).get_modifiers('damage_reduction').sum { |_type, amount| amount.to_i }
    rescue StandardError
      0
    end

    # Inflict the weapon's Bleed on the target as the Bleeding Affliction,
    # scaled to the attacker's Tier (mirrors the Falling-Damage bleed channel).
    # The first tick is scheduled to the victim's *next turn* — this Round if
    # the victim still has a turn coming, next Round if it has already acted.
    def apply_weapon_bleed(target_id, attacker_id, amount)
      tc = combatant_creature(attacker_id)
      tier = (tc&.tier rescue 0) || 0
      conditions_for(combatant_for(target_id)[:creature_id])
        .inflict_affliction('bleeding', inflicter_tier: tier, delta: amount,
                            current_round: bleed_first_resolution_round(target_id))
    rescue StandardError
      nil
    end

    # Inflict the weapon's on-hit Affliction (e.g. a spider's venom) on the
    # target, scaled to the attacker's Tier — the same channel as weapon
    # Bleed, scheduled to the victim's next turn.
    def apply_weapon_poison(target_id, attacker_id, affliction_name, amount)
      return nil if affliction_name.to_s.empty? || amount.to_i <= 0
      tc = combatant_creature(attacker_id)
      tier = (tc&.tier rescue 0) || 0
      conditions_for(combatant_for(target_id)[:creature_id])
        .inflict_affliction(affliction_name.to_s, inflicter_tier: tier, delta: amount.to_i,
                            current_round: bleed_first_resolution_round(target_id))
    rescue StandardError
      nil
    end

    # The `current_round` to hand inflict_affliction for a weapon Bleed so
    # the first tick lands on the victim's next turn. Bleeding is a
    # Round-frequency Affliction (inflict schedules first resolution at
    # `current_round + 1`), so we pass the victim's next-turn Round minus
    # one: the next-turn Round is this Round when the victim still has a turn
    # coming (has not acted), otherwise next Round.
    def bleed_first_resolution_round(target_id)
      r = current_abs_round
      return r unless r
      next_turn_round = turn_pending_this_round?(target_id) ? r : r + 1
      next_turn_round - 1
    end

    def current_abs_round
      ts = current_timestamp
      (ts[:day_index] * rounds_per_day) + ts[:round_of_day]
    rescue StandardError
      nil
    end

    # Combat Pool a Roll spends: the action's flat Speed cost plus one per
    # die rolled (Speed + dice). Speed is a flat surcharge, not a per-die
    # multiplier.
    def pool_cost(part)
      part[:speed].to_i + part[:dice].to_i
    end

    # ---------- Start of Turn ----------

    # Afflictions due this Round for a Combatant — the input list for the
    # turn-action panel's Start of Turn pane (turn_action_stub.md). An
    # Affliction is due when its Next Resolution Round has arrived
    # (`<= current Round`) OR when it is active but has no schedule yet
    # (`next_resolution_round` nil — e.g. seeded data or an Affliction
    # inflicted without a clock). Resolving a due Affliction stamps a real
    # schedule on it, so an unscheduled bleed shows on every subsequent
    # turn. Returns affliction names, or [] when the Combatant is unknown
    # or the Round can't be determined.
    def pending_afflictions(combatant_id)
      c = combatant_for(combatant_id) or return []
      round = current_abs_round or return []
      due_affliction_names(conditions_for(c[:creature_id]), round)
    end

    # Resolve a single due Affliction's Save with the DM-supplied net DoIS,
    # via Conditions' *Resolve Affliction* (which applies the consequence
    # and decays / reschedules the survivor against the current Round).
    # Driven by the per-Affliction Conditions Save Resolution Stub's Confirm
    # in the Start of Turn pane. Returns the *Resolve Affliction* result, or
    # nil when the Combatant or Affliction is unknown.
    def resolve_affliction_save(combatant_id, affliction_name, dois)
      c = combatant_for(combatant_id) or return nil
      inst = conditions_for(c[:creature_id])
      return nil unless inst.state.afflictions.key?(affliction_name.to_s)
      creature = lookup!(c[:creature_id])
      tier = (creature&.tier rescue 0) || 0
      inst.resolve_affliction(affliction_name.to_s, {}, dois: dois.to_i,
                              current_round: current_abs_round, creature_tier: tier)
    end

    # Start of Turn finalize (turn_action_stub.md): refill the Combatant's
    # Combat Pool (Combat starts empty; the pool refills at the start of the
    # turn) and clear the Active Effects that expire this Round via
    # Conditions' *Clear Expired Effects*. Afflictions are resolved
    # separately — one per Conditions Save Resolution Stub via
    # *resolve_affliction_save*. Returns { cleared: [...] }, or nil when the
    # Combatant is unknown.
    # Begin a Combatant's turn (turn_action_stub.md). Refills the Combat Pool
    # (Combat begins empty; the refill is at the start of each turn, never at
    # the end), grants the turn's two Main Actions, applies Per-Turn Setup, and
    # clears the Active Effects that expire this Round. Called automatically as
    # the turn passes to a Combatant — for the first Combatant at Start Combat,
    # and for each Combatant the turn advances to (advance_turn). Returns the
    # cleared Effects so the caller can persist Conditions.
    def begin_turn_for(combatant_id)
      c = combatant_for(combatant_id) or return nil
      c[:combat_pool_spent] = 0
      c[:main_actions_remaining] = MAIN_ACTIONS_PER_TURN
      apply_per_turn_setup(combatant_id)
      round = current_abs_round
      cleared = round ? conditions_for(c[:creature_id]).clear_expired_effects(round) : []
      regeneration = apply_round_regeneration(c[:creature_id], round)
      persist!
      { cleared: cleared, regeneration: regeneration }
    end

    # If the Combatant's Creature has the Regeneration ability, mend damage
    # at the start of its turn: Tier Minor plus 1 Moderate (so faster,
    # higher-Tier creatures with multiple turns per round heal more), plus 1
    # Major for every whole hour of game time that has elapsed. All are
    # suppressed while the Creature carries unhealed acid/fire damage. Also
    # stamps the visible `regenerating` Condition. Returns the summary, or
    # nil when the Creature does not regenerate.
    def apply_round_regeneration(creature_id, round)
      creature = lookup!(creature_id)
      return nil unless creature.respond_to?(:has_ability) && creature.has_ability('regeneration')
      inst = conditions_for(creature_id)
      stamp_regenerating_condition(inst)
      tier = (creature.tier rescue 0).to_i
      turn = inst.regenerate_turn(tier)
      major = round ? inst.regenerate_hourly_majors(round, rounds_per_day / 24) : { healed_major: 0 }
      { turn: turn, major: major }
    rescue StandardError
      nil
    end

    # Idempotently apply the marker `regenerating` Condition so it surfaces
    # as a badge (stable source_id → re-applying replaces, never stacks).
    def stamp_regenerating_condition(inst)
      return unless inst.respond_to?(:apply_named_effect)
      inst.apply_named_effect('regenerating', source_id: 'regeneration')
    rescue StandardError
      nil
    end

    # Main Actions a Combatant has left this turn (nil for an unknown
    # Combatant). -1 until the Combatant has begun a turn.
    def main_actions_remaining(combatant_id)
      c = combatant_for(combatant_id) or return nil
      c[:main_actions_remaining].to_i
    end

    # Record that a Combatant spent a Main Action (Attack / Move / Cast /
    # Item). Decrements the counter — not enforced, so it may go negative —
    # and returns the new value.
    def spend_main_action(combatant_id)
      c = combatant_for(combatant_id) or return nil
      c[:main_actions_remaining] = c[:main_actions_remaining].to_i - 1
      persist!
      c[:main_actions_remaining]
    end

    # ---------- Special Actions ----------

    # Usable Special-action Abilities for a Combatant (turn_action_stub.md →
    # Special): the non-Spell, non-Reaction Talents among the Creature's
    # Granted Abilities (a Bard's Bardic Performance and the like), each
    # with its action-economy costs and a disabled flag computed against
    # current Mana and Combat Pool. Already-running Bardic Performances are
    # marked `active`. Returns [] for an unknown Combatant or a Creature
    # that exposes no Granted Abilities.
    def special_options(combatant_id)
      c = combatant_for(combatant_id) or return []
      creature = lookup!(c[:creature_id]) or return []
      return [] unless creature.respond_to?(:granted_abilities)

      pool_rem = combat_pool_remaining(combatant_id)
      mana_rem = special_mana_remaining(c[:creature_id], creature)
      active   = c[:concentration].map { |e| e[:spell_name] }

      creature.granted_abilities.filter_map do |g|
        desc = special_descriptor(g[:name], g[:source], creature) or next
        desc[:active]   = active.include?(desc[:name])
        afford_mana     = mana_rem.nil? || mana_rem >= desc[:mana_cost]
        afford_pool     = pool_rem >= desc[:action_cost]
        desc[:disabled] = !(afford_mana && afford_pool)
        desc[:disabled_reason] =
          if !afford_pool then 'not enough Combat Pool'
          elsif !afford_mana then 'not enough Mana'
          end
        desc[:summary] = special_summary(desc)
        desc
      end
    end

    # Resolve a Special-action use (turn_action_stub.md → Special). Validates
    # the Ability is a usable non-Reaction Talent, spends its action-economy
    # Combat Pool cost and Mana cost, then:
    #   - Channeled Abilities (a Bard's Bardic Performance): begin a Bardic
    #     Performance (Begin Concentration) or continue a running one
    #     (Channel), filling a check_successes Reservoir by the `successes`
    #     the DM enters for the Performance check.
    #   - Self-target Abilities with named Effects (e.g. Rage): apply each
    #     Effect to the actor through Conditions, with a duration computed
    #     from the Ability's `duration` when expressed in turns.
    #   - Anything else (e.g. Turn Undead): spend the cost and report it; the
    #     DM resolves targets / saves manually (those flows are deferred).
    #
    # Payload (symbol or string keys): combatant_id, ability (display name),
    # successes (Performance-check Successes, optional, default 0).
    def use_special_payload(payload)
      p = deep_symbolize(payload)
      combatant_id = p[:combatant_id].to_i
      c = combatant_for(combatant_id) or return { ok: false, error: 'unknown combatant' }
      creature = lookup!(c[:creature_id]) or return { ok: false, error: 'unknown creature' }

      name = p[:ability].to_s
      raw  = Abilities.catalog.ability(name)
      return { ok: false, error: 'unknown ability' } unless raw
      activation = (Abilities.resolve_activation(raw) rescue nil)
      return { ok: false, error: "#{name} is not a usable special action" } unless Special.usable?(raw, activation)

      channeled = raw.key?('channel')
      # Resolve the Mana cost so inherited costs are charged — a Channel
      # Divinity action inherits `mana_cost` from the base Channel Divinity
      # Talent, which the raw catalog entry omits.
      resolved_mana = (Abilities.lookup(name)&.dig('mana_cost') rescue nil)
      mana_cost = Integer((resolved_mana || raw['mana_cost']) || 0)
      # Net Successes may be negative (a failed Performance check) — that is how
      # Bardic Inspiration grants Luck to the DM instead of the Reservoir, so do
      # not clamp here; use_channeled_special handles the sign.
      successes = p[:successes].to_i
      pool_rem  = combat_pool_remaining(combatant_id)

      # Channeled Abilities (Bardic Performance) spend the DM-chosen channel
      # dice — Main Action Minimum up to Combat Pool Remaining. For a
      # `channel_dice` / fire channel the Dice Cap does not apply
      # (abilities_design.md); a **check-based** channel (fill from
      # check_successes, e.g. Bardic Inspiration) rolls a real Check and IS
      # bounded by the Performance skill's Dice Cap — enforced by the
      # use_special route's `channel_dice_cap_error` before we get here. The
      # chosen dice are the Performance check the DM just rolled. Other actions
      # spend the flat Action Minimum for their category.
      if channeled
        pool_cost = p.key?(:dice) ? p[:dice].to_i : Config.main_action_minimum
        return { ok: false, error: "must channel at least #{Config.main_action_minimum} dice" } if pool_cost < Config.main_action_minimum
      else
        pool_cost = Special.action_cost(activation[:alias])
      end
      return { ok: false, error: 'not enough Combat Pool' } if pool_cost > pool_rem

      inst     = conditions_for(c[:creature_id])
      mana_rem = special_mana_remaining(c[:creature_id], creature)
      return { ok: false, error: 'not enough Mana' } if mana_cost.positive? && mana_rem && mana_rem < mana_cost

      spend_combat_pool(combatant_id, pool_cost)
      if mana_cost.positive? && creature.respond_to?(:max_mana) && creature.max_mana
        inst.apply_mana_cost(amount: mana_cost, mana_max: creature.max_mana)
      end
      # Luck an ally Bard / the DM spent (as a Reaction) on this Performance.
      apply_luck_spends(p[:luck])

      actor  = special_actor_name(c, creature)
      result = { ok: true, ability: name, pool_spent: pool_cost, mana_spent: mana_cost,
                 applied_effects: [], log: "#{actor} uses #{name}" }

      if channeled
        result.merge!(use_channeled_special(combatant_id, actor, creature, name, raw, pool_cost, successes))
      elsif raw['target'] == 'self'
        level = special_level(creature, name)
        result[:applied_effects] = apply_self_special_effects(c[:creature_id], inst, creature, level, name, raw)
      end

      result
    end

    # Resolve a Roll Table reaction (encounter_roll_table_stub.md) — a
    # Reaction Ability that fires on a provided table (talents.yaml
    # `roll_table:`, e.g. Kesser's Gambit → the Kesser Reversal Table).
    # Unlike a Special action this is a Reaction, so it does not pass
    # through #use_special_payload; the host (the attack flow) offers it
    # to a Combatant other than the attacker.
    #
    # The channeler spends `dice` from its Combat Pool (Reaction Action
    # Minimum up to the pool) — the dice the DM rolled for the channel
    # check — plus the Ability's Mana Cost, then a die is rolled on the
    # table and the matched entry reported with the Channel Successes the
    # check produced. Combat does not apply the entry; the DM adjudicates.
    #
    # Payload (symbol or string keys): combatant_id, ability (display
    # name), dice (Combat Pool spent on the channel check), successes
    # (Channel Successes rolled), face (optional — a die the DM rolled
    # client-side; omitted rolls server-side via `rng`).
    def use_roll_table_payload(payload, rng: Random.new)
      p = deep_symbolize(payload)
      # A preview (commit:false) rolls the table to show the entry and lets the
      # DM reroll, spending nothing; the Confirm (commit:true, default) commits
      # the shown face and spends the Combat Pool dice + Mana.
      commit = p.fetch(:commit, true) != false
      combatant_id = p[:combatant_id].to_i
      c = combatant_for(combatant_id) or return { ok: false, error: 'unknown combatant' }
      creature = lookup!(c[:creature_id]) or return { ok: false, error: 'unknown creature' }

      name  = p[:ability].to_s
      table_name = Abilities.roll_table_for(name)
      return { ok: false, error: "#{name} has no roll table" } unless table_name
      table = Abilities.roll_table(table_name)
      return { ok: false, error: "unknown roll table #{table_name}" } unless table

      reaction_min = Config.reaction_action_minimum
      dice = p.key?(:dice) ? p[:dice].to_i : reaction_min
      return { ok: false, error: "must spend at least #{reaction_min} dice" } if dice < reaction_min
      pool_rem = combat_pool_remaining(combatant_id)
      return { ok: false, error: 'not enough Combat Pool' } if dice > pool_rem

      # Kesser's Gambit inherits its Mana Cost from the base Channel
      # Divinity Talent — resolve the inherited value, falling back to the
      # raw catalog entry.
      raw       = Abilities.catalog.ability(name)
      mana_cost = Integer((Abilities.lookup(name)&.dig('mana_cost') rescue nil) || (raw && raw['mana_cost']) || 0)
      inst      = conditions_for(c[:creature_id])
      mana_rem  = special_mana_remaining(c[:creature_id], creature)
      return { ok: false, error: 'not enough Mana' } if mana_cost.positive? && mana_rem && mana_rem < mana_cost

      if commit
        spend_combat_pool(combatant_id, dice)
        if mana_cost.positive? && creature.respond_to?(:max_mana) && creature.max_mana
          inst.apply_mana_cost(amount: mana_cost, mana_max: creature.max_mana)
        end
      end

      successes = p[:successes].to_i
      result    = RollTable.roll(table, face: p[:face], successes: successes, rng: rng)
      return { ok: false, error: 'roll table produced no entry' } unless result

      actor = special_actor_name(c, creature)
      { ok: true, committed: commit, ability: name, table: table_name, pool_spent: dice, mana_spent: mana_cost,
        successes: successes, face: result[:face], die: result[:die],
        entry: { name: result[:name], effect: result[:effect] },
        log: "#{actor} channels #{name}: rolled #{result[:face]} (#{result[:name]})" }
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
                            mode:, reservoir_reset:, initial_reservoir: 0, expires_on_round: nil)
      c = find!(combatant_id)
      c[:concentration] << {
        spell_name: spell_name, source: source, spell_tier: Integer(spell_tier),
        cast_skill: cast_skill, mode: mode.to_s, reservoir: Integer(initial_reservoir),
        reservoir_reset: reservoir_reset.to_s, channeled_this_turn: true,
        expires_on_round: expires_on_round
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

    # Channel more dice into a Reservoir Spell (Shield of Faith), topping up the
    # block dice available. Only reservoir-mode entries refill: an auto strike
    # (Spiritual Weapon) refuses — its Reservoir is fixed at cast and never
    # changes. Returns the updated entry, or nil when there is no such entry or
    # the Spell is not a reservoir channel.
    def refill_reservoir(combatant_id, spell_name, amount)
      c = find!(combatant_id)
      entry = c[:concentration].find { |e| e[:spell_name] == spell_name } or return nil
      return nil unless entry[:mode] == 'reservoir'
      entry[:reservoir] = [entry[:reservoir].to_i + amount.to_i, 0].max
      persist!
      entry.dup
    end

    # Record which Combatant an active persistent Spell is aimed at (Spiritual
    # Weapon's current strike target). Retargeting sets this; the strike reads
    # it so it never re-asks for a target.
    def set_concentration_target(combatant_id, spell_name, target_id)
      c = find!(combatant_id)
      entry = c[:concentration].find { |e| e[:spell_name] == spell_name } or return nil
      entry[:target_id] = target_id
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

      # The Combat Pool is NOT refilled here — it refills at the start of
      # the Combatant's turn (Start of Turn), so a spent pool stays spent
      # until then. Only luck points clear at end of turn.
      c[:luck_points] = 0

      # End-of-turn channel check. A timed channel (Spiritual Weapon) ends when
      # its expiry Round arrives; a true Concentration ends if it was not
      # channeled this turn (auto channels never need the channel action).
      c[:concentration].reject! do |e|
        if e[:expires_on_round] && current_abs_round >= e[:expires_on_round]
          notes << { kind: :concentration_ended, source: e[:source], spell_name: e[:spell_name], reason: 'expired' }
          true
        elsif !e[:channeled_this_turn] && e[:mode] != 'auto'
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

    # One Concentration Save per Concentration + Casting entry. Penalty
    # magnitude = spell_tier + damage_dealt (Circumstance). On failure
    # the entry is torn down (End Concentration / Cancel Long Cast,
    # reason: damage). Returns the source-domain notifications.
    def trigger_concentration_saves(combatant, damage_dealt, save_resolver)
      notes = []
      combatant[:concentration].dup.each do |e|
        # Timed channels (Spiritual Weapon) are not true Concentration — taking
        # damage never breaks them; they end only when their time runs out.
        next if e[:expires_on_round]
        penalty = e[:spell_tier] + damage_dealt
        passed = save_resolver.call(spell_name: e[:spell_name], cast_skill: e[:cast_skill],
                                    penalty: penalty, kind: :concentration)
        unless passed
          ended = end_concentration(combatant[:id], e[:spell_name])
          notes << ended.merge(kind: :concentration_ended) if ended
        end
      end
      combatant[:casting].dup.each do |e|
        penalty = e[:spell_tier] + damage_dealt
        passed = save_resolver.call(spell_name: e[:spell_name], cast_skill: e[:cast_skill],
                                    penalty: penalty, kind: :casting)
        unless passed
          cancelled = cancel_long_cast(combatant[:id], e[:spell_name], reason: 'damage')
          notes << cancelled.merge(kind: :cast_cancelled) if cancelled
        end
      end
      notes
    end

    # ---------- Cast helpers ----------

    def cast_error(msg)
      { ok: false, error: msg, committed: false, pool_spends: [], targets: [], sustain: nil }
    end

    # Impose the cast's Magic Toxicity through Conditions, which gates a
    # positive contribution when the caster is already over threshold.
    def apply_cast_toxicity(inst, amount, polarity, charisma, tier)
      return { requested: 0, accepted: true, charisma_damage: 0 } if amount.to_i.zero?
      out = inst.apply_magic_toxicity(amount: amount, kind: polarity.to_sym, charisma: charisma, tier: tier)
      { requested: amount, accepted: out[:accepted], charisma_damage: out[:charisma_damage] }
    rescue StandardError
      { requested: amount, accepted: false, charisma_damage: 0 }
    end

    # Predict the toxicity gate for a preview without mutating: a positive
    # contribution is blocked when current toxicity already exceeds threshold.
    def preview_cast_toxicity(inst, amount, polarity, charisma, tier)
      return { requested: 0, accepted: true, charisma_damage: 0 } if amount.to_i.zero?
      threshold = (inst.toxicity_threshold(charisma, tier) rescue 0)
      current   = (inst.state.magic_toxicity rescue 0)
      blocked   = polarity.to_s == 'positive' && current > threshold
      { requested: amount, accepted: !blocked, charisma_damage: 0 }
    rescue StandardError
      { requested: amount, accepted: false, charisma_damage: 0 }
    end

    # A Save-based target: net the caster's Successes against the target's Save
    # (Encounter::Cast.resolve_save). No defender Combat-Pool cost.
    def cast_save_target(t, caster)
      outcome, effects = Cast.resolve_save(effects: t[:effects], caster_successes: caster[:successes],
                                           save: t[:save])
      { id: t[:id], outcome: outcome, effects: effects, defender_pool: nil }
    end

    # An attack-roll Spell target: net the casting check against the target's
    # Defensive Action (Block / Dodge, eligibility + Pool cost from
    # Encounter::Attack). On a positive net the Spell hits — damage is the
    # Spell's own Effects when it states them, else the default Spell damage
    # computed with the *net* Successes; otherwise it misses for no Effect.
    def cast_attack_target(t, spell, caster, casting_stat)
      defense  = t[:defense] || {}
      choice   = defense[:choice].to_s
      declared = !(choice.empty? || choice == 'none')
      if declared && !Attack.defense_eligible?(choice, 'spell')
        return { id: t[:id], outcome: 'ineligible_defense', effects: [], defender_pool: nil,
                 error: "#{choice} is not eligible against a spell attack" }
      end

      opposing = declared ? defense[:successes].to_i : 0
      net = caster[:successes].to_i - opposing
      defender_pool = nil
      if declared && Attack.defense_spec(choice)[:pool_cost] && t[:id]
        defender_pool = { id: t[:id], amount: pool_cost(defense) }
      end

      unless net.positive?
        return { id: t[:id], outcome: declared ? 'defended' : 'missed', effects: [],
                 defender_pool: defender_pool, net_dos: net }
      end

      base_effects = Array(t[:effects])
      effects = if base_effects.any? { |e| e[:kind].to_s == 'damage' }
                  base_effects
                else
                  dmg = Cast.default_spell_damage(casting_stat: casting_stat, tier: spell[:tier], successes: net,
                                                  competency: spell[:cast_competency].to_i)
                  [{ kind: 'damage', damage_type: (spell[:damage_type] || 'force').to_s,
                     threshold: spell[:threshold].to_i, amount: dmg }] + base_effects
                end
      { id: t[:id], outcome: 'hit', effects: effects, defender_pool: defender_pool, net_dos: net }
    end

    # Apply one target's resolved Effects, routing each to its owning domain.
    def apply_cast_target(t, spell)
      applied = Array(t[:effects]).map { |e| route_cast_effect(t[:id], e, spell) }.compact
      { id: t[:id], outcome: t[:outcome], applied: applied }
    end

    # A Heal-style channel reduces each target's bleeding by `amount` (the spell
    # already resolved `spell_tier*2*success` to a number). On commit it drains
    # the target's `bleeding` Affliction Potency (Conditions' Reduce Affliction
    # Potency); a preview just reports the amount. Appended to the target's
    # applied Effects so the result shows it.
    def apply_bleed_reduction!(targets, amount, commit:)
      return if amount.to_i <= 0
      targets.each do |t|
        if commit
          inst = target_conditions(t[:id])
          removed = inst ? inst.reduce_affliction_potency('bleeding', amount) : 0
          t[:applied] = Array(t[:applied]) + [{ kind: 'bleed_reduction', requested: amount, removed: removed }]
        else
          t[:applied] = Array(t[:applied]) + [{ kind: 'bleed_reduction', requested: amount }]
        end
      end
    end

    # Replace each heal Effect's Severity map with the DM-entered amounts (one
    # editable box per Severity on the confirm page). Keyed by target id; a
    # Severity left blank or non-positive is dropped, so the heal cures exactly
    # what was entered. Non-heal Effects and untouched targets are unchanged.
    def apply_heal_override!(resolved, heals)
      by_id = {}
      Array(heals).each { |h| by_id[h[:target_id].to_i] = (h[:severity_map] || {}) }
      resolved.each do |t|
        ov = by_id[t[:id].to_i] or next
        t[:effects] = Array(t[:effects]).map do |e|
          next e unless e[:kind].to_s == 'heal'
          sev = %i[minor moderate major].each_with_object({}) do |k, h|
            v = (ov[k] || ov[k.to_s]).to_i
            h[k] = v if v.positive?
          end
          e.merge(severity_map: sev)
        end
      end
    end

    # Replace each damage Effect's amount with the DM-entered value (one editable
    # box per damaged target on the confirm page). Keyed by target id; the new
    # amount (floored at 0) routes through Apply Damage exactly as the computed
    # amount would, so the Severity split is recomputed from what the DM entered.
    # Non-damage Effects and untouched targets are unchanged.
    def apply_damage_override!(resolved, damages)
      by_id = {}
      Array(damages).each { |d| by_id[d[:target_id].to_i] = d[:amount].to_i }
      resolved.each do |t|
        next unless by_id.key?(t[:id].to_i)
        amt = [by_id[t[:id].to_i], 0].max
        t[:effects] = Array(t[:effects]).map do |e|
          e[:kind].to_s == 'damage' ? e.merge(amount: amt) : e
        end
      end
    end

    def route_cast_effect(target_id, eff, spell)
      inst = target_conditions(target_id) or return nil
      case eff[:kind].to_s
      when 'damage'
        type = (eff[:damage_type] || 'physical').to_s
        raw  = eff[:amount].to_i
        out  = apply_damage(target_id, raw, type, threshold: eff[:threshold].to_i)
        { kind: 'damage', amount: raw, damage_type: type, severity_map: out[:severity_map] }
      when 'heal'
        healed = inst.apply_heal(eff[:severity_map] || {})
        { kind: 'heal', healed: healed }
      when 'mana'
        restored = inst.restore_mana(eff[:amount].to_i)
        { kind: 'mana', restored: restored }
      when 'temp_hp'
        inst.apply_temporary_hit_points(amount: eff[:amount].to_i, source_id: cast_source_id(spell),
                                        ends_on_round: eff[:ends_on_round])
        # Ward (and any temp-HP Spell that marks one) shows a matching condition
        # that expires together with its temp HP.
        if (cond = spell[:temp_hp_condition]) && inst.respond_to?(:apply_named_effect)
          inst.apply_named_effect(cond.to_s, source_id: "#{cast_source_id(spell)}:cond",
                                  ends_on_round: eff[:ends_on_round])
        end
        { kind: 'temp_hp', amount: eff[:amount].to_i }
      when 'effect'
        inst.apply_named_effect(eff[:name].to_s, source_id: cast_source_id(spell),
                                ends_on_round: eff[:ends_on_round])
        { kind: 'effect', name: eff[:name].to_s }
      when 'modifiers'
        Array(eff[:modifiers]).each do |m|
          inst.apply_effect('target_key' => m[:target_key], 'bonus_type' => m[:bonus_type],
                            'amount' => m[:amount], 'ends_on_round' => m[:ends_on_round],
                            'source_id' => "#{cast_source_id(spell)}:#{Array(m[:target_key]).join('+')}")
        end
        { kind: 'modifiers', modifiers: eff[:modifiers] }
      end
    rescue StandardError => e
      { kind: eff[:kind].to_s, error: e.message }
    end

    # Turn one spell `modifiers` Effect into concrete Active-Effect data: each
    # modifier's `add` is evaluated against the caster bindings (literals pass
    # through; formulas like Magic Weapon's `caster_tier` resolve), a non-`all`
    # descriptor narrows the target_key, and a turns-based duration sets expiry.
    def resolve_modifier_effect(eff, binds)
      ends = modifier_ends_on_round(eff[:duration], binds)
      mods = Array(eff[:modifiers]).filter_map do |raw|
        m = (raw.transform_keys(&:to_s) rescue raw)
        target = m['target'] or next
        btype  = m['type'] or next
        amount = eval_modifier_amount(m['add'], binds)
        next if amount.nil?
        descriptors = Array(m['descriptors']).map(&:to_s).reject { |d| d == 'all' }
        tkey = descriptors.empty? ? target.to_s : descriptors
        { target_key: tkey, bonus_type: btype.to_s, amount: amount, ends_on_round: ends }
      end
      { kind: 'modifiers', modifiers: mods }
    end

    # A modifier `add` resolved to an integer: a literal as-is, a Formula
    # evaluated against the caster bindings, nil when it cannot resolve.
    def eval_modifier_amount(add, binds)
      return add if add.is_a?(Integer)
      return nil if add.nil?
      return add.to_i if add.to_s.match?(/\A-?\d+\z/)
      return nil unless defined?(Abilities::Formula)
      Abilities::Formula.evaluate(add.to_s, binds).to_i
    rescue StandardError
      nil
    end

    # The absolute Round a buff expires on, when its `duration` is in turns
    # (e.g. "1 turn", "rank turns"). Minute/hour/open-ended durations return
    # nil — the DM clears them — matching the self-buff (Special) convention.
    def modifier_ends_on_round(duration, binds)
      return nil if duration.nil?
      m = duration.to_s.strip.match(/\A(.+?)\s+turns?\z/) or return nil
      turns = (Abilities::Formula.evaluate(m[1], binds).to_i rescue nil)
      turns ? current_abs_round + turns : nil
    end

    # Preview a target's resolved Effects without mutating (damage is bucketed
    # by the Severity pipeline, exactly as the commit would).
    def preview_cast_target(t)
      applied = Array(t[:effects]).map do |eff|
        case eff[:kind].to_s
        when 'damage'
          type = (eff[:damage_type] || 'physical').to_s
          { kind: 'damage', amount: eff[:amount].to_i, damage_type: type,
            severity_map: preview_severity(t[:id], eff[:amount].to_i, type, eff[:threshold].to_i) }
        when 'heal'    then { kind: 'heal', severity_map: eff[:severity_map] || {} }
        when 'mana'    then { kind: 'mana', amount: eff[:amount].to_i }
        when 'temp_hp' then { kind: 'temp_hp', amount: eff[:amount].to_i }
        when 'effect'  then { kind: 'effect', name: eff[:name].to_s }
        when 'modifiers' then { kind: 'modifiers', modifiers: eff[:modifiers] }
        end
      end.compact
      { id: t[:id], outcome: t[:outcome], applied: applied }
    end

    # Register the sustain bookkeeping a Channeled / multi-turn cast needs.
    def register_cast_sustain(caster_id, spell, sustain, channel_dice: 0)
      s = deep_symbolize(sustain)
      common = { spell_name: spell[:name].to_s, source: cast_source_id(spell),
                 spell_tier: (spell[:tier] || 0).to_i,
                 cast_skill: (spell[:cast_skill] || Cast::DEFAULT_CAST_SKILL).to_s }
      case s[:kind].to_s
      when 'concentration'
        # A reservoir- or auto-channel Spell pours the dice it was cast with
        # straight into the Reservoir (they are not rolled). Auto reservoirs are
        # persistent (Spiritual Weapon strikes from them each turn).
        initial = %w[reservoir auto].include?(s[:mode].to_s) ? channel_dice.to_i : (s[:initial_reservoir] || 0).to_i
        # A timed channel (Spiritual Weapon, "rank turns") carries an expiry
        # Round; it is not true Concentration (immune to the damage-break Save)
        # and is dropped by per-turn cleanup when its time runs out.
        exp = concentration_expiry(caster_id, spell)
        begin_concentration(caster_id, **common, mode: (s[:mode] || 'maintain').to_s,
                            reservoir_reset: (s[:reservoir_reset] || 'per_turn').to_s,
                            initial_reservoir: initial, expires_on_round: exp)
        # Spiritual Weapon shows a condition on the caster that fades when the
        # weapon's time runs out.
        if exp && spell[:name].to_s == 'Spiritual Weapon'
          ci = conditions_for(find!(caster_id)[:creature_id])
          if ci.respond_to?(:apply_named_effect)
            ci.apply_named_effect('spiritual_weapon', source_id: "#{cast_source_id(spell)}:active",
                                  ends_on_round: exp)
          end
        end
        { kind: 'concentration', spell_name: common[:spell_name], reservoir: initial }
      when 'long_cast'
        turns = (s[:turns_required] || 1).to_i
        begin_long_cast(caster_id, **common, turns_required: turns)
        { kind: 'long_cast', spell_name: common[:spell_name], turns_required: turns }
      end
    end

    def target_conditions(target_id)
      c = combatant_for(target_id) or return nil
      conditions_for(c[:creature_id])
    end

    # The absolute Round a timed channel expires on (Spiritual Weapon's
    # "rank turns"), or nil for an open-ended channel. `rank`/`level` bind to
    # the caster's Total Level so "rank turns" is one turn per caster level.
    def concentration_expiry(caster_id, spell)
      dur = spell[:duration]
      return nil if dur.nil?
      cc = combatant_for(caster_id) or return nil
      acc = (lookup!(cc[:creature_id]) rescue nil)
      lvl = (acc&.total_level rescue nil) || (acc&.tier rescue 0) || 0
      modifier_ends_on_round(dur, { 'rank' => lvl, 'level' => lvl, 'tier' => (spell[:tier] || 0) })
    end

    def cast_source_id(spell)
      (spell[:source] || "encounter:cast:#{spell[:name]}").to_s
    end

    # Names of the Afflictions to resolve at the Start of Turn: those due
    # this Round (Next Resolution Round arrived) plus any active Affliction
    # with no schedule yet (nil). Returns [] when the Round is unknown.
    def due_affliction_names(inst, round)
      return [] unless round
      inst.state.afflictions.each_with_object([]) do |(name, entry), out|
        nr = entry[:next_resolution_round]
        out << name if nr.nil? || nr <= round
      end
    end

    # A Combatant's full Combat Pool size (0 when the Creature can't be
    # resolved or computed). Used to seed an empty pool at Start Combat.
    def combat_pool_size_for(combatant)
      creature = lookup!(combatant[:creature_id])
      return 0 unless creature
      CombatPool.size_for(creature) + combat_pool_ability_bonus(creature, combatant[:creature_id])
    rescue StandardError
      0
    end

    # Conditional Combat Pool bonus from the Creature's Granted Abilities. An
    # ability that carries a `combat_pool` Modifier adds it to the max pool;
    # if the ability declares a `required_condition` (e.g. Reckless Attacks
    # needs `rage`), the bonus applies only while that Effect is active on the
    # Creature. So a raging barbarian's pool grows by her class level, and
    # shrinks back when the rage ends.
    def combat_pool_ability_bonus(creature, creature_id)
      abilities = (creature.granted_abilities rescue [])
      return 0 if abilities.empty?
      active = active_condition_names(creature_id)
      abilities.sum do |g|
        name = g[:name].to_s
        defn = ability_def(name) or next 0
        req = defn['required_condition']
        next 0 if req && !active.include?(req.to_s)
        binds = { 'level' => (creature.level_for_ability(name) rescue 0),
                  'tier'  => (creature.tier rescue 0) }
        Array(defn['modifiers'])
          .select { |m| m['target'].to_s == 'combat_pool' }
          .sum { |m| eval_modifier_amount(m['add'], binds) || 0 }
      end
    rescue StandardError
      0
    end

    # The Effect Names currently active on a Creature (e.g. `rage`), or [] when
    # Conditions can't be resolved.
    def active_condition_names(creature_id)
      inst = conditions_for(creature_id)
      Array(inst.active_effect_names(current_round: (current_round rescue nil)))
    rescue StandardError
      []
    end

    # Resolve a Granted Ability's catalog definition. Granted names may be
    # snake_case (from class ability_progression, e.g. `reckless_attacks`)
    # while talent entries are Title Case (`Reckless Attacks`), so fall back to
    # a humanized form, then to the snake-keyed Modifier-ability catalog.
    def ability_def(name)
      return nil unless defined?(Abilities)
      cat = Abilities.catalog
      cat.ability(name) ||
        cat.ability(name.to_s.split('_').map(&:capitalize).join(' ')) ||
        cat.modifier_ability(name)
    rescue StandardError
      nil
    end

    def blank_combatant(id, creature_id, name)
      { id: id, creature_id: creature_id, name: name,
        initiative_string: '', combat_pool_spent: 0, time_tick_schedule: [],
        luck_points: 0, concentration: [], casting: [], main_actions_remaining: -1 }
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

    # Debit a Combatant's Mana for a Reaction Ability it used during another
    # Combatant's action (Better Lucky Than Good / Danger Sense / Primal
    # Tenacity). Returns the Mana actually spent (clamped to what remains).
    def spend_reaction_mana(combatant_id, amount)
      return 0 unless amount.to_i.positive?
      c = combatant_for(combatant_id) or return 0
      creature = lookup!(c[:creature_id])
      mana_max = (creature.respond_to?(:max_mana) ? creature.max_mana : nil)
      return 0 unless mana_max
      conditions_for(c[:creature_id]).apply_mana_cost(amount: amount.to_i, mana_max: mana_max)
    rescue StandardError
      0
    end

    # ---- Special Action helpers (see #special_options / #use_special_payload) ----

    # A descriptor for one Granted Ability, or nil when it is not a usable
    # Special action. `name` is the snake_case Granted name; `source` is the
    # Granted Ability's source ("class:<key>" / "race") for the level used in
    # Effect-Hash / duration Formulas.
    def special_descriptor(name, source, creature)
      display = titleize_special(name)
      raw = Abilities.catalog.ability(display) || Abilities.catalog.ability(name.to_s)
      return nil unless raw
      activation = (Abilities.resolve_activation(raw) rescue nil)
      return nil unless Special.usable?(raw, activation)

      level    = special_level_from_source(creature, source)
      resolved = (Abilities.lookup(display, level: level, rank: level) rescue nil) || raw
      {
        name:        display,
        # The granted Ability's own name — NOT `resolved['name']`, which
        # inheritance resolution sets to the base template (so a specific
        # Channel Divinity action like Turn Undead would mislabel as the
        # "Channel Divinity" category).
        label:       display,
        activation:  activation[:alias].to_s,
        action_cost: Special.action_cost(activation[:alias]),
        # Mana from the resolved entry so inherited costs surface — a Channel
        # Divinity action (Turn Undead) inherits `mana_cost: 1` from the base
        # Channel Divinity Talent, which the raw catalog entry omits.
        mana_cost:   Integer((resolved['mana_cost'] || raw['mana_cost']) || 0),
        channeled:   raw.key?('channel'),
        performance: raw.dig('reservoir', 'fill', 'source') == 'check_successes',
        self_target: raw['target'] == 'self',
        effects:     (raw['target'] == 'self' ? Special.named_effects(raw['effects']) : []),
        description: (resolved['description'] || raw['description']).to_s
      }
    end

    # A terse summary of what using the Ability changes — shown next to the
    # Confirm button when the DM picks it (e.g. "Spend 1 mana, gain the rage
    # condition."). Free actions cost no Combat Pool, so that clause is
    # omitted when the cost is zero.
    def special_summary(desc)
      clauses = []
      if desc[:channeled]
        # Channeled Abilities choose their channel dice in the roll builder,
        # so don't quote a fixed Combat-Pool number here.
        clauses << "spend #{desc[:mana_cost]} mana" if desc[:mana_cost].to_i.positive?
        clauses << "#{desc[:active] ? 'continue' : 'begin'} #{desc[:label]}"
      else
        # Non-channeled (e.g. a Channel Divinity action like Turn Undead): show
        # the Mana cost AND the Combat-Pool dice count together before Confirm.
        cost = []
        cost << "#{desc[:mana_cost]} mana" if desc[:mana_cost].to_i.positive?
        if desc[:action_cost].to_i.positive?
          n = desc[:action_cost].to_i
          cost << "#{n} Combat Pool #{n == 1 ? 'die' : 'dice'}"
        end
        clauses << "spend #{cost.join(' and ')}" unless cost.empty?
        Array(desc[:effects]).each { |fx| clauses << "gain the #{fx} condition" }
      end
      return 'No Mana or Combat-Pool cost.' if clauses.empty?
      summary = clauses.join(', ')
      summary[0] = summary[0].upcase
      "#{summary}."
    end

    # Begin (or continue) a Bardic Performance for a channeled Special
    # Ability. `dice` is the DM-chosen channel dice the Performance check was
    # rolled with; a check_successes Reservoir gains `successes × fill ratio`.
    # The cast/channel itself counts as this turn's channel.
    def use_channeled_special(combatant_id, actor, creature, name, raw, dice, successes)
      mode  = raw.dig('channel', 'mode').to_s
      reset = (mode == 'auto') ? 'persistent' : 'per_turn'
      skill = (Array(raw['skills']).first || 'arcana').to_s
      tier  = (creature.tier rescue 0).to_i
      ratio = Integer(raw.dig('reservoir', 'fill', 'ratio') || 1)
      fill  = (raw.dig('reservoir', 'fill', 'source') == 'check_successes' ? successes * ratio : 0)
      fill  = 0 unless mode == 'reservoir'
      # A Bardic Inspiration check with NEGATIVE net Successes does not drain
      # the Reservoir; instead the inverse (a positive amount) is granted to
      # the DM's Luck pool (player id null), which the DM may later spend as
      # Luck. DM Luck does not expire at end of turn/round.
      dm_gain = fill.negative? ? -fill : 0
      delta   = [fill, 0].max
      grant_dm_luck(dm_gain) if dm_gain.positive?

      existing = combatant_for(combatant_id)[:concentration].find { |e| e[:spell_name] == name }
      if existing
        channel(combatant_id, name, dice_spent: dice, reservoir_delta: delta)
      else
        begin_concentration(combatant_id, spell_name: name, source: "special:#{combatant_id}:#{name}",
                            spell_tier: tier, cast_skill: skill, mode: mode,
                            reservoir_reset: reset, initial_reservoir: delta)
      end

      entry = combatant_for(combatant_id)[:concentration].find { |e| e[:spell_name] == name }
      verb  = existing ? 'continues' : 'begins'
      dm_note = dm_gain.positive? ? "; #{dm_gain} Luck to the DM" : ''
      { performance: (existing ? 'continued' : 'started'), reservoir: (entry && entry[:reservoir]),
        dm_luck_gained: dm_gain, dm_luck_points: @dm_luck_points,
        log: "#{actor} #{verb} #{name} (reservoir #{entry && entry[:reservoir]}#{dm_note})" }
    end

    # Apply a self-target Ability's unconditional named Effects to the actor
    # through Conditions. Effects absent from the Conditions catalog are
    # skipped. Returns the names actually applied.
    def apply_self_special_effects(creature_id, inst, creature, level, name, raw)
      effects = Special.named_effects(raw['effects'])
      return [] if effects.empty?
      ends   = special_ends_on_round(raw['duration'], creature, level)
      binds  = special_formula_binds(creature, level)
      applied = []
      effects.each do |fx|
        begin
          # Pass bindings so the Effect's Modifier Formulas (e.g. rage's
          # "1 + level / 3") resolve to concrete amounts the actor actually
          # gains — not just the raging flag.
          inst.apply_named_effect(fx, source_id: "special:#{creature_id}:#{name}:#{fx}",
                                  ends_on_round: ends, metadata: { 'level' => level }, bindings: binds)
          applied << fx
        rescue ArgumentError
          # Effect name not in the Conditions catalog — skip it.
        end
      end
      applied
    end

    # The absolute Round an Ability's Effect expires on, when its `duration`
    # is expressed in turns (e.g. "1 turn", "con/2 + level turns"). Other
    # duration shapes (minutes, "concentration", "1 attack") return nil
    # (open-ended — the DM clears them).
    def special_ends_on_round(duration, creature, level)
      return nil if duration.nil?
      m = duration.to_s.strip.match(/\A(.+?)\s+turns?\z/) or return nil
      turns = (Abilities::Formula.evaluate(m[1], special_formula_binds(creature, level)).to_i rescue nil)
      base  = current_abs_round
      (base && turns) ? base + turns : nil
    end

    def special_formula_binds(creature, level)
      binds = { 'level' => level, 'rank' => level, 'tier' => (creature.tier rescue 0) }
      %i[str dex con int wis cha].each { |a| binds[a.to_s] = (creature.attribute_value(a) rescue 0) }
      binds
    end

    # Class level granting an Ability (for Effect formulas), found by display
    # name across the Creature's Granted Abilities; falls back to Tier.
    def special_level(creature, display_name)
      source = nil
      if creature.respond_to?(:granted_abilities)
        g = creature.granted_abilities.find { |x| titleize_special(x[:name]) == display_name }
        source = g && g[:source]
      end
      special_level_from_source(creature, source)
    end

    def special_level_from_source(creature, source)
      if source.to_s.start_with?('class:')
        key = source.to_s.split(':', 2)[1]
        lvl = (creature.record[:classes][key][:level] rescue nil)
        return Integer(lvl) if lvl
      end
      (creature.tier rescue 0).to_i
    end

    def special_mana_remaining(creature_id, creature)
      return nil unless creature.respond_to?(:max_mana) && creature.max_mana
      [creature.max_mana - conditions_for(creature_id).state.mana_spent, 0].max
    end

    def special_actor_name(c, creature)
      return c[:name] unless c[:name].to_s.empty?
      (creature.respond_to?(:name) && creature.name) || "Creature ##{c[:creature_id]}"
    end

    def titleize_special(key)
      key.to_s.split(/[_\s]+/).reject(&:empty?).map { |w| w[0].upcase + w[1..] }.join(' ')
    end

    # The defender's Damage Resilience for Runtime Bucketing: its Tier, plus a
    # creature's own `damage_resilience` (when it exposes one directly —
    # monsters, test doubles), plus the Resilience of its equipped Armor via
    # Equipment. The sheet combines the same sources
    # (CreatureSheet#defensive_totals), so the displayed and applied values
    # agree. Defaults to 0.
    def defender_damage_resilience(creature)
      equipped_defensive_totals(creature)[:damage_resilience]
    rescue StandardError
      0
    end

    # The defender's passive Damage Reduction — the mirror of
    # defender_damage_resilience: the creature's own `damage_reduction`
    # (direct attribute) plus its equipped Armor's Reduction. Subtracted
    # from incoming damage before the Severity split (weapon and spell
    # paths), alongside the Tier-Mismatch Inherent DR.
    def defender_damage_reduction(creature)
      equipped_defensive_totals(creature)[:damage_reduction]
    rescue StandardError
      0
    end

    # { damage_reduction:, damage_resilience: } for a Creature: its direct
    # attributes (when exposed) added to its equipped-Armor totals.
    def equipped_defensive_totals(creature)
      totals = { damage_reduction: 0, damage_resilience: 0 }
      return totals unless creature
      # A Creature's Tier is flat Damage Resilience (Tier + Armor Resilience
      # + Resilience Modifiers), Tier 0 contributing 0. Damage Reduction does
      # not get the Tier.
      totals[:damage_resilience] += creature.tier.to_i if creature.respond_to?(:tier)
      if creature.respond_to?(:damage_reduction)
        totals[:damage_reduction] += creature.damage_reduction.to_i
      end
      if creature.respond_to?(:damage_resilience)
        totals[:damage_resilience] += creature.damage_resilience.to_i
      end
      if creature.respond_to?(:id)
        stacks = Equipment.instance.get_inventory("creature:#{creature.id}")
        armor  = Equipment::Details.defensive_totals(stacks, Equipment.catalog)
        totals[:damage_reduction]  += armor[:damage_reduction].to_i
        totals[:damage_resilience] += armor[:damage_resilience].to_i
      end
      totals
    rescue StandardError
      { damage_reduction: 0, damage_resilience: 0 }
    end

    def tier_of(creature_id)
      creature = lookup!(creature_id)
      creature ? (creature.tier rescue 0) : 0
    end

    # Tier of the Creature behind a Combatant ID (0 when unknown). Used by
    # the Tier Mismatch damage-reduction path in resolve_attack_payload.
    def combatant_tier(combatant_id)
      return 0 unless combatant_id
      c = @combatants.find { |x| x[:id] == combatant_id }
      c ? tier_of(c[:creature_id]) : 0
    end

    def current_timestamp
      fn = @current_timestamp_fn || -> { Encounter.current_timestamp }
      ts = fn.call || {}
      ts = ts.transform_keys(&:to_sym) if ts.respond_to?(:transform_keys)
      { day_index: Integer(ts[:day_index] || 0), round_of_day: Integer(ts[:round_of_day] || 0) }
    end

    def rounds_per_day
      @rounds_per_day || Encounter.rounds_per_day
    end

    def notify_round_elapsed
      return @round_elapsed_fn.call if @round_elapsed_fn
      Chronicle.store.advance_time(rounds: 1) if defined?(Chronicle) && Chronicle.respond_to?(:store)
    rescue StandardError
      nil
    end

    def deep_symbolize(obj)
      case obj
      when Hash  then obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize(v) }
      when Array then obj.map { |v| deep_symbolize(v) }
      else obj
      end
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

    # Sort key for turn order, matching the Combat Tracker display: rolled
    # Combatants first (by Initiative String descending), un-rolled (empty
    # Initiative String) last, Combat ID breaking ties.
    def turn_sort_key(combatant)
      init = combatant[:initiative_string].to_s
      [init.empty? ? 1 : 0, invert_string(init), combatant[:id]]
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
        concentration:       (c['concentration'] || []).map { |e| symbolize(e) },
        casting:             (c['casting'] || []).map { |e| symbolize(e) },
        # Main Actions left this turn. -1 = the Combatant has not begun a turn
        # yet (pre-combat / not their turn); a turn-start sets it to 2.
        main_actions_remaining: Integer(c['main_actions_remaining'] || -1)
      }
    end

    def stringify_combatant(c)
      {
        'id' => c[:id], 'creature_id' => c[:creature_id], 'name' => c[:name],
        'initiative_string' => c[:initiative_string], 'combat_pool_spent' => c[:combat_pool_spent],
        'time_tick_schedule' => c[:time_tick_schedule], 'luck_points' => c[:luck_points],
        'concentration' => c[:concentration].map { |e| stringify(e) },
        'casting' => c[:casting].map { |e| stringify(e) },
        'main_actions_remaining' => c[:main_actions_remaining]
      }
    end

    def symbolize(h)
      h.respond_to?(:transform_keys) ? h.transform_keys(&:to_sym) : h
    end

    # Coerce a persisted / supplied Phase to a known symbol, falling back
    # to the default when absent or unrecognized.
    def normalize_phase(value)
      p = value.to_s.to_sym
      PHASES.include?(p) ? p : DEFAULT_PHASE
    end

    def stringify(h)
      h.respond_to?(:transform_keys) ? h.transform_keys(&:to_s) : h
    end
  end
end
