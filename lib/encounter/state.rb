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
        c[:combat_pool_spent]   = 0
        c[:luck_points]         = 0
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
      apply_per_turn_setup(@acting_combatant_id) if @acting_combatant_id
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
    # Time Tick, then Initiative String (descending), then Combat ID.
    def round_turn_order
      @combatants.sort_by do |c|
        first_tick = Array(c[:time_tick_schedule]).min || 9_999
        [first_tick, invert_string(c[:initiative_string].to_s), c[:id]]
      end
    end

    # Is this Combatant Unaware (has not yet acted in the Combat)? Inferred,
    # not stored: a Combatant is Unaware only in Round 1, before its first
    # turn comes up — i.e. it falls later in the Round's turn order than the
    # Acting Combatant. From Round 2 on everyone has acted at least once;
    # before Initiative is seated (no Acting Combatant) no one has acted.
    def unaware?(combatant_id)
      return false unless combat_active?
      return false unless round_number == 1
      return true if @acting_combatant_id.nil?
      order = round_turn_order.map { |c| c[:id] }
      ai = order.index(@acting_combatant_id)
      ti = order.index(combatant_id)
      return false if ai.nil? || ti.nil?
      ti > ai
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
    def apply_damage(combatant_id, raw, type, threshold: 0, save_resolver: ->(_) { true })
      c = find!(combatant_id)
      creature = lookup!(c[:creature_id])
      resilience = defender_damage_resilience(creature)
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
      notifications = trigger_concentration_saves(c, damage_dealt, save_resolver)

      { severity_map: result[:severity_map], side_effects: result[:side_effects],
        concentration_notifications: notifications }
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
      declared = !(choice.empty? || choice == 'none' || defense.empty?)
      if declared && !Attack.defense_eligible?(choice, attack_kind)
        return { ok: false, error: "#{choice} is not eligible against a #{attack_kind} attack",
                 damage: 0, severity_map: {}, net_dos: 0, bleed: 0, pool_spends: [] }
      end

      # Combat Pool each participant spends (Speed + dice). Dodge (a Saving
      # Throw) spends none. Reported either way; only applied on commit.
      # DM overrides from the result panel's editable fields (commit only).
      over = p[:override] || {}

      pool_spends = []
      pool_spends << { id: attacker[:id], amount: pool_cost(attacker) } if attacker[:id]
      allies.each { |a| pool_spends << { id: a[:id], amount: pool_cost(a) } if a[:id] }
      opposing = 0
      if declared
        if Attack.defense_spec(choice)[:pool_cost] && defense[:id]
          pool_spends << { id: defense[:id], amount: pool_cost(defense) }
        end
        opposing = defense[:successes].to_i
      end
      pool_spends = apply_pool_override(pool_spends, over[:pool_spends])
      pool_spends.each { |s| spend_combat_pool(s[:id], s[:amount].to_i) } if commit

      supporting = attacker[:successes].to_i + allies.sum { |a| a[:successes].to_i }
      net = supporting - opposing
      threshold = weapon[:threshold].to_i
      resil = defender_resilience(p[:target_id])
      dtype = (Array(weapon[:damage_types]).first || weapon[:damage_type] || 'physical').to_s

      if net.positive?
        base = weapon[:base_damage] ? weapon[:base_damage].to_i : p[:damage_bonus].to_i
        # Computed damage / bleed, each replaceable by a DM override. Bleed is
        # the weapon's Bleed plus the damage dealt (encounter_design.md →
        # "actual bleed = Bleed Constant + damage dealt"), so a 0-Bleed weapon
        # still bleeds for its damage.
        damage = over.key?(:damage) ? over[:damage].to_i : base + net
        bleed  = over.key?(:bleed)  ? over[:bleed].to_i  : weapon[:bleed].to_i + damage
        if commit
          out = apply_damage(p[:target_id], damage, dtype, threshold: threshold)
          apply_weapon_bleed(p[:target_id], attacker[:id], bleed) if bleed.positive?
          sev = out[:severity_map]
        else
          sev = preview_severity(p[:target_id], damage, dtype, threshold)
        end
        { ok: true, damage: damage, severity_map: sev, net_dos: net, damage_type: dtype,
          threshold: threshold, damage_resilience: resil, bleed: bleed,
          pool_spends: pool_spends, committed: commit }
      else
        { ok: true, damage: 0, severity_map: {}, net_dos: net, damage_type: dtype,
          threshold: threshold, damage_resilience: resil, bleed: 0,
          pool_spends: pool_spends, committed: commit }
      end
    end

    # The target's Damage Resilience (so the panel can re-bucket a DM-adjusted
    # damage into Minor/Moderate/Major exactly as Apply Damage would).
    def defender_resilience(combatant_id)
      c = combatant_for(combatant_id) or return 0
      defender_damage_resilience(lookup!(c[:creature_id]))
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
    def preview_severity(combatant_id, raw, type, threshold)
      c = combatant_for(combatant_id) or return {}
      creature = lookup!(c[:creature_id])
      Severity.compute(raw: raw, type: type, threshold: threshold,
                       damage_resilience: defender_damage_resilience(creature),
                       target_tags: creature ? Array(creature.tags) : [])[:severity_map]
    rescue StandardError
      {}
    end

    # Inflict the weapon's Bleed on the target as the Bleeding Affliction,
    # scaled to the attacker's Tier (mirrors the Falling-Damage bleed channel).
    def apply_weapon_bleed(target_id, attacker_id, amount)
      tc = combatant_creature(attacker_id)
      tier = (tc&.tier rescue 0) || 0
      conditions_for(combatant_for(target_id)[:creature_id])
        .inflict_affliction('bleeding', inflicter_tier: tier, delta: amount, current_round: current_abs_round)
    rescue StandardError
      nil
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

    # One Concentration Save per Concentration + Casting entry. Penalty
    # magnitude = spell_tier + damage_dealt (Circumstance). On failure
    # the entry is torn down (End Concentration / Cancel Long Cast,
    # reason: damage). Returns the source-domain notifications.
    def trigger_concentration_saves(combatant, damage_dealt, save_resolver)
      notes = []
      combatant[:concentration].dup.each do |e|
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

    def blank_combatant(id, creature_id, name)
      { id: id, creature_id: creature_id, name: name,
        initiative_string: '', combat_pool_spent: 0, time_tick_schedule: [],
        luck_points: 0, concentration: [], casting: [] }
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

    # The defender's Damage Resilience for Runtime Bucketing. Honors a
    # creature that exposes it directly (test doubles); otherwise sums
    # the resilience of its equipped Armor via Equipment. Defaults to 0
    # when neither source is available.
    def defender_damage_resilience(creature)
      return 0 unless creature
      return creature.damage_resilience.to_i if creature.respond_to?(:damage_resilience)
      return 0 unless creature.respond_to?(:id)
      stacks = Equipment.instance.get_inventory("creature:#{creature.id}")
      Equipment::Details.defensive_totals(stacks, Equipment.catalog)[:damage_resilience]
    rescue StandardError
      0
    end

    def tier_of(creature_id)
      creature = lookup!(creature_id)
      creature ? (creature.tier rescue 0) : 0
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
        casting:             (c['casting'] || []).map { |e| symbolize(e) }
      }
    end

    def stringify_combatant(c)
      {
        'id' => c[:id], 'creature_id' => c[:creature_id], 'name' => c[:name],
        'initiative_string' => c[:initiative_string], 'combat_pool_spent' => c[:combat_pool_spent],
        'time_tick_schedule' => c[:time_tick_schedule], 'luck_points' => c[:luck_points],
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
