require 'creatures/formula'

module Conditions
  # Pairs a Catalog and a State and exposes the public entry points
  # documented in conditions_design.md. Operations mutate the State
  # in place; reads do not.
  class Instance
    attr_reader :state, :catalog

    def initialize(state: State.new, catalog: Catalog.new)
      @state = state
      @catalog = catalog
    end

    # ===== Apply Hit Point Damage =====
    def apply_hit_point_damage(severity_map)
      sev_map = sym_severity_map(severity_map)
      absorbed_by_temp = sev_zero_map
      to_counters = sev_zero_map
      displaced_source_id = nil

      pool = @state.temporary_hit_points
      pool_remaining = pool ? pool[:amount] : 0

      REVERSE_SEVERITIES.each do |sev|
        amount = sev_map[sev]
        next if amount.zero?
        absorbed = [amount, pool_remaining].min
        pool_remaining -= absorbed
        absorbed_by_temp[sev] = absorbed
        landed = amount - absorbed
        next if landed.zero?
        @state.hp_damage[sev] = (@state.hp_damage[sev] || 0) + landed
        to_counters[sev] = landed
      end

      if pool && pool_remaining <= 0
        displaced_source_id = pool[:source_id]
        @state.temporary_hit_points = nil
      elsif pool
        pool[:amount] = pool_remaining
      end

      {
        absorbed_by_temp: absorbed_by_temp,
        to_counters: to_counters,
        displaced_source_id: displaced_source_id
      }
    end

    # ===== Apply Heal =====
    def apply_heal(severity_map)
      sev_map = sym_severity_map(severity_map)
      healed = sev_zero_map
      leftover = 0

      REVERSE_SEVERITIES.each do |sev|
        pool = sev_map[sev] + leftover
        counter = @state.hp_damage[sev] || 0
        h = [pool, counter].min
        healed[sev] = h
        new_counter = counter - h
        if new_counter.zero?
          @state.hp_damage.delete(sev)
        else
          @state.hp_damage[sev] = new_counter
        end
        leftover = pool - h
      end

      reduce_elemental_wound(healed.values.sum)
      healed
    end

    # ===== Apply Ability Damage =====
    def apply_ability_damage(attribute, severity_map)
      attribute = attribute.to_sym
      sev_map = sym_severity_map(severity_map)
      sev_map.each do |sev, amount|
        next if amount <= 0
        bucket = (@state.ability_damage[sev] ||= {})
        if bucket.key?(attribute)
          bucket[attribute] += amount
        else
          bucket[attribute] = amount
        end
      end
      nil
    end

    # ===== Apply Ability Heal =====
    def apply_ability_heal(severity_map)
      sev_map = sym_severity_map(severity_map)
      healed = sev_zero_map
      leftover = 0

      REVERSE_SEVERITIES.each do |sev|
        pool = sev_map[sev] + leftover
        h_at_sev = 0
        bucket = @state.ability_damage[sev]

        if bucket
          bucket.keys.each do |attr|
            break if pool.zero?
            n = bucket[attr]
            take = [pool, n].min
            bucket[attr] -= take
            pool -= take
            h_at_sev += take
          end
          bucket.reject! { |_, v| v.zero? }
          @state.ability_damage.delete(sev) if bucket.empty?
        end

        healed[sev] = h_at_sev
        leftover = pool
      end

      healed
    end

    # ===== Apply Temporary Hit Points =====
    def apply_temporary_hit_points(amount:, source_id:, ends_on_round: nil)
      current = @state.temporary_hit_points

      if amount <= 0
        if current
          displaced = current[:source_id]
          @state.temporary_hit_points = nil
          return { accepted: true, displaced_source_id: displaced }
        else
          return { accepted: true, displaced_source_id: nil }
        end
      end

      current_amount = current ? current[:amount] : 0
      if amount > current_amount
        displaced = current ? current[:source_id] : nil
        @state.temporary_hit_points = {
          amount: amount, source_id: source_id.to_s, ends_on_round: ends_on_round
        }
        { accepted: true, displaced_source_id: displaced }
      else
        { accepted: false, displaced_source_id: nil }
      end
    end

    # ===== Consume Shock =====
    def consume_shock(max_consume)
      consumed = [@state.shock, max_consume].min
      @state.shock -= consumed
      consumed
    end

    # ===== Apply Magic Toxicity =====
    def apply_magic_toxicity(amount:, kind:, charisma:, tier:)
      kind = kind.to_sym
      threshold = toxicity_threshold(charisma, tier)

      if kind == :positive && @state.magic_toxicity > threshold
        return { accepted: false, charisma_damage: 0 }
      end

      pre = @state.magic_toxicity
      @state.magic_toxicity += amount

      charisma_damage =
        [0, @state.magic_toxicity - threshold].max - [0, pre - threshold].max

      if charisma_damage > 0
        apply_ability_damage(:cha, @catalog.toxicity_damage_severity => charisma_damage)
      end

      { accepted: true, charisma_damage: charisma_damage }
    end

    def toxicity_threshold(charisma, tier)
      if @catalog.toxicity_threshold_tier_scaled?
        tier_value = [0.5, tier].max
        (charisma * tier_value).floor
      else
        charisma.floor
      end
    end

    # ===== Inflict Affliction =====
    def inflict_affliction(name, inflicter_tier:, delta: 1, current_round: nil)
      name = name.to_s
      rule = @catalog.affliction(name)
      existing = @state.afflictions[name]

      if existing
        new_potency = [1, existing[:potency] + delta].max
        existing[:potency] = new_potency
        existing[:inflicting_tier] = [existing[:inflicting_tier], inflicter_tier].max
        # next_resolution_round untouched
        existing.dup
      else
        next_round = current_round ? current_round + @catalog.frequency_rounds(save_frequency(rule)) : nil
        entry = {
          potency: [1, delta].max,
          inflicting_tier: inflicter_tier,
          next_resolution_round: next_round
        }
        @state.afflictions[name] = entry
        entry.dup
      end
    end

    # ===== Reduce Affliction Potency =====
    #
    # A magical cure that drains an active Affliction's Potency by `amount`
    # (e.g. a Heal spell clears bleeding by spell_tier*2 per casting success).
    # Floors at zero, removing the Affliction when its Potency reaches zero.
    # Returns the Potency actually removed; a no-op (0) when the Affliction is
    # not active or `amount` is not positive.
    def reduce_affliction_potency(name, amount)
      name  = name.to_s
      entry = @state.afflictions[name]
      return 0 unless entry && amount.to_i.positive?
      before  = entry[:potency].to_i
      removed = [amount.to_i, before].min
      after   = before - removed
      if after <= 0
        @state.afflictions.delete(name)
      else
        entry[:potency] = after
      end
      removed
    end

    # ===== Resolve Affliction =====
    #
    # The save Roll happens in the caller (Dice Resolution). Pass the
    # rolled DoIS in via `dois:`. The Potency Save Penalty is appended
    # to `save_input[:modifiers]` and surfaced on the result as
    # `:modified_input` so callers can confirm the value used.
    def resolve_affliction(name, save_input, dois:, current_round: nil, creature_tier: 0)
      name = name.to_s
      rule = @catalog.affliction(name)
      entry = @state.afflictions[name] or raise ArgumentError, "no active affliction: #{name}"

      potency_before = entry[:potency]
      divisor = @catalog.potency_divisor

      # 1. Potency Save Penalty (appended, not merged).
      modifiers = (save_input[:modifiers] || save_input['modifiers'] || []).dup
      modifiers << ['Competency', -(potency_before / divisor)]
      modified_input = save_input.merge(modifiers: modifiers)

      successes = [0, dois].max
      failures = [0, -dois].max

      # 3. Magnitude.
      magnitude = 1 + (potency_before / divisor)
      net_magnitude = [0, magnitude - successes].max

      # 4. Apply effect.
      applied = nil
      if net_magnitude > 0 && rule['effect']
        applied = dispatch_affliction_effect(rule['effect'], net_magnitude, name, current_round)
      end

      # 5. Evolve Potency.
      per_success_raw = rule['potency_per_success'] || @catalog.default_potency_per_success
      per_failure_raw = rule['potency_per_failure'] || @catalog.default_potency_per_failure
      decay_raw       = rule['potency_decay']       || @catalog.default_potency_decay

      per_success = tier_substitute(per_success_raw, creature_tier)
      per_failure = tier_substitute(per_failure_raw, creature_tier)
      decay       = tier_substitute(decay_raw,       creature_tier)

      delta = -(decay.floor) - (successes * per_success).floor + (failures * per_failure).floor
      new_potency = [0, potency_before + delta].max

      next_round = nil
      if new_potency.zero?
        @state.afflictions.delete(name)
      else
        entry[:potency] = new_potency
        if current_round
          freq = @catalog.frequency_rounds(save_frequency(rule))
          # Advance from the PREVIOUS scheduled round, not the current
          # round — so when time jumps forward (e.g. +1 minute = 10 rounds)
          # the Affliction stays due and owes one save per missed interval
          # instead of skipping straight to "now". Falls back to the current
          # round only when there was no prior schedule.
          prev = entry[:next_resolution_round]
          next_round = (prev || current_round) + freq
          entry[:next_resolution_round] = next_round
        else
          next_round = entry[:next_resolution_round]
        end
      end

      {
        dois: dois,
        successes: successes,
        failures: failures,
        magnitude: magnitude,
        net_magnitude: net_magnitude,
        applied: applied,
        new_potency: new_potency,
        next_resolution_round: next_round,
        modified_input: modified_input
      }
    end

    # ===== List Pending Afflictions =====
    def list_pending_afflictions(current_round)
      @state.afflictions.each_with_object([]) do |(name, entry), out|
        next_round = entry[:next_resolution_round]
        out << name if next_round && next_round <= current_round
      end
    end

    # ===== Resolve Due Afflictions =====
    #
    # The block is called with each pending Affliction name and must
    # return a hash with `:save_input` and `:dois` keys.
    def resolve_due_afflictions(current_round:, creature_tier: 0)
      raise ArgumentError, "block required" unless block_given?
      results = []
      loop do
        pending = list_pending_afflictions(current_round)
        break if pending.empty?
        name = pending.first
        provided = yield(name)
        results << resolve_affliction(
          name, provided.fetch(:save_input),
          dois: provided.fetch(:dois),
          current_round: current_round, creature_tier: creature_tier
        )
      end
      results
    end

    # ===== Apply Effect =====
    def apply_effect(effect)
      e = State.normalize_effect(effect)
      existing_index = @state.effects.find_index { |x| x[:source_id] == e[:source_id] }
      if existing_index
        @state.effects[existing_index] = e
      else
        @state.effects << e
      end
      nil
    end

    # ===== Remove Effects by Prefix =====
    def remove_effects_by_prefix(prefix)
      kept = []
      removed = []
      @state.effects.each do |e|
        if e[:source_id].start_with?(prefix)
          removed << e
        else
          kept << e
        end
      end
      @state.effects = kept
      # Non-modifier Mechanics (flag / display / reroll, e.g. Spiritual Weapon's
      # `spiritual_weapon` marker) live on the sidecar list under the same
      # source_id contract, so purge them by the same prefix.
      kept_mechs = []
      @state.named_effect_mechanics.each do |m|
        if m[:source_id].to_s.start_with?(prefix)
          removed << m
        else
          kept_mechs << m
        end
      end
      @state.named_effect_mechanics = kept_mechs
      removed
    end

    # ===== Get Modifiers =====
    def get_modifiers(target_key, current_round: nil)
      relevant = @state.effects.select do |e|
        next false unless effect_targets?(e[:target_key], target_key)
        next false if current_round && e[:ends_on_round] && e[:ends_on_round] <= current_round
        next false unless e[:amount].is_a?(Integer)
        true
      end

      by_type = relevant.group_by { |e| e[:bonus_type] }
      out = []
      by_type.each do |bonus_type, list|
        amounts = list.map { |e| e[:amount] }
        pos = amounts.select(&:positive?).max
        neg = amounts.select(&:negative?).min
        out << [bonus_type, pos] if pos
        out << [bonus_type, neg] if neg
      end
      out
    end

    # ===== Modifier Breakdown =====
    # Per-source view of the Modifiers on a target, *before* the per-Bonus-Type
    # collapsing Get Modifiers does — so a sheet can name the ability / spell
    # behind each bonus and show which ones lost the non-stacking contest.
    # Each entry: { source:, bonus_type:, amount:, applied: }. `applied` is
    # true only for the single winner of each (Bonus Type, sign) group (the
    # max positive / min negative, matching Get Modifiers' totals); the rest
    # are still returned, flagged `applied: false`, for a struck-out display.
    # Zero amounts are dropped.
    def modifier_breakdown(target_key, current_round: nil)
      relevant = @state.effects.select do |e|
        next false unless effect_targets?(e[:target_key], target_key)
        next false if current_round && e[:ends_on_round] && e[:ends_on_round] <= current_round
        next false unless e[:amount].is_a?(Integer)
        next false if e[:amount].zero?
        true
      end
      winners = {}
      relevant.group_by { |e| e[:bonus_type] }.each do |bt, list|
        if (p = list.select { |e| e[:amount].positive? }.max_by { |e| e[:amount] })
          winners[[bt, :pos]] = p.object_id
        end
        if (n = list.select { |e| e[:amount].negative? }.min_by { |e| e[:amount] })
          winners[[bt, :neg]] = n.object_id
        end
      end
      relevant.map do |e|
        sign = e[:amount].positive? ? :pos : :neg
        { source: modifier_source_label(e), bonus_type: e[:bonus_type].to_s,
          amount: e[:amount], applied: winners[[e[:bonus_type], sign]] == e.object_id }
      end
    end

    # A human-facing source name for a Modifier Active Effect: the granting
    # Named Effect (Rage, Magic Vestments — carried in `metadata.effect_name`)
    # when present, else the most meaningful segment of the `source_id`
    # (skipping domain prefixes), else the Bonus Type as a last resort.
    def modifier_source_label(e)
      md = e[:metadata] || {}
      name = md['effect_name'] || md[:effect_name]
      return name.to_s unless name.nil? || name.to_s.strip.empty?
      generic = %w[spell equipment encounter cast special affliction condition creature]
      seg = e[:source_id].to_s.split(':').reject { |s| s.empty? }
      (seg.reject { |s| generic.include?(s.downcase) }.first || seg.last || e[:bonus_type]).to_s
    end

    # ===== Apply Acid Damage =====
    def apply_acid_damage(amount)
      return @state.acid_counter if amount <= 0
      @state.acid_counter += amount
      @state.acid_counter
    end

    # ===== Resolve Acid Turn Start =====
    def resolve_acid_turn_start
      @state.acid_counter = (@state.acid_counter / 2)
      damage = @state.acid_counter
      apply_hit_point_damage(minor: damage) if damage > 0
      damage
    end

    # ===== Apply Elemental (acid/fire) Wound =====
    # Track unhealed acid/fire hit-point damage. While this is positive,
    # Regeneration is suppressed — but ordinary (natural) healing still
    # works and chips this back down toward zero. Once it clears,
    # Regeneration resumes.
    def apply_elemental_wound(amount)
      return @state.elemental_wound if amount <= 0
      @state.elemental_wound += amount
      @state.elemental_wound
    end

    # Regeneration does nothing while unhealed acid or fire damage remains.
    def regeneration_blocked?
      @state.elemental_wound.positive?
    end

    # ===== Regenerate (per turn) =====
    # Each turn, Regeneration mends `minor_amount` Minor hit-point damage
    # (the Creature's Tier, so faster, higher-Tier creatures — which take
    # multiple turns per round — heal more) plus 1 Moderate. Each Severity
    # heals only its own counter (no cascade, no Minor↔Moderate conversion).
    # Major damage is left to the hourly Regeneration. Suppressed entirely
    # while the Creature carries unhealed acid or fire damage.
    def regenerate_turn(minor_amount)
      return { regenerated: false, blocked: true } if regeneration_blocked?

      minor    = heal_severity(:minor, [minor_amount.to_i, 0].max)
      moderate = heal_severity(:moderate, 1)
      { regenerated: (minor + moderate).positive?,
        healed: { minor: minor, moderate: moderate } }
    end

    # ===== Regenerate (hourly Major) =====
    # Regeneration mends 1 Major hit-point damage per whole hour of elapsed
    # game time. `now_round` is the absolute game Round; `rounds_per_hour`
    # converts hours to Rounds. The next-due Round is stored on the
    # Creature's state (`regen_major_round`) so the cadence survives across
    # turns, rests, and reloads — this is the "last fired at" bookkeeping.
    #
    # The schedule always advances with the clock; a Major only mends on an
    # elapsed hour when the Creature is not suppressed and actually carries
    # Major damage, so hours spent blocked (or undamaged) are not banked.
    def regenerate_hourly_majors(now_round, rounds_per_hour)
      rounds_per_hour = rounds_per_hour.to_i
      return { healed_major: 0 } if rounds_per_hour <= 0 || now_round.nil?

      @state.regen_major_round ||= now_round + rounds_per_hour
      healed = 0
      while now_round >= @state.regen_major_round
        if !regeneration_blocked? && (@state.hp_damage[:major] || 0).positive?
          set_hp_counter(:major, @state.hp_damage[:major] - 1)
          healed += 1
        end
        @state.regen_major_round += rounds_per_hour
      end
      { healed_major: healed, blocked: regeneration_blocked? }
    end

    # ===== Apply Mana Cost =====
    def apply_mana_cost(amount:, mana_max:)
      available = mana_max - @state.mana_spent
      spent = [amount, available].min
      spent = 0 if spent < 0
      @state.mana_spent += spent
      spent
    end

    # ===== Restore Mana =====
    def restore_mana(amount)
      restored = [amount, @state.mana_spent].min
      restored = 0 if restored < 0
      @state.mana_spent -= restored
      restored
    end

    # ===== Set Mana Spent =====
    def set_mana_spent(amount:, mana_max:)
      @state.mana_spent = [[amount, 0].max, mana_max].min
    end

    # ===== Apply Natural Recovery =====
    def apply_natural_recovery(recovery_ticks:, mode:, character_tier:, mana_max:, magic_toxicity_attribute_score:)
      mode = mode.to_sym
      summary = { hp_healed: sev_zero_map, ability_healed: sev_zero_map,
                  mana_restored: 0, toxicity_decayed: 0, temp_hp_cleared: false }

      # 1. HP healing per Severity. Each Severity's heal pool applies
      # only to that Severity's counter (no cascading across severities
      # — Natural Recovery's rate table is the cap, not a Heal Cascade
      # input).
      hp_healed = sev_zero_map
      SEVERITIES.each do |sev|
        amount, tick_length = @catalog.heal_rate(sev, character_tier, mode)
        pool = (amount * recovery_ticks) / tick_length
        counter = @state.hp_damage[sev] || 0
        h = [pool, counter].min
        hp_healed[sev] = h
        new_counter = counter - h
        if new_counter.zero?
          @state.hp_damage.delete(sev)
        else
          @state.hp_damage[sev] = new_counter
        end
      end
      summary[:hp_healed] = hp_healed
      reduce_elemental_wound(hp_healed.values.sum)

      # 2. Ability Damage healing per Severity. Same per-Severity cap
      # rule as HP; within each Severity, attributes pop FIFO.
      ability_healed = sev_zero_map
      SEVERITIES.each do |sev|
        amount, tick_length = @catalog.ability_heal_rate(sev, character_tier, mode)
        pool = (amount * recovery_ticks) / tick_length
        next if pool.zero?
        bucket = @state.ability_damage[sev]
        next unless bucket
        h_at_sev = 0
        bucket.keys.each do |attr|
          break if pool.zero?
          n = bucket[attr]
          take = [pool, n].min
          bucket[attr] -= take
          pool -= take
          h_at_sev += take
        end
        bucket.reject! { |_, v| v.zero? }
        @state.ability_damage.delete(sev) if bucket.empty?
        ability_healed[sev] = h_at_sev
      end
      summary[:ability_healed] = ability_healed

      # 3. Mana.
      per_tick = mana_max / @catalog.mana_per_recovery_tick_divisor
      summary[:mana_restored] = restore_mana(per_tick * recovery_ticks)

      # 4. Magic Toxicity decay.
      tox_per_tick = magic_toxicity_attribute_score / @catalog.magic_toxicity_per_recovery_tick_divisor
      decay = [tox_per_tick * recovery_ticks, @state.magic_toxicity].min
      decay = 0 if decay < 0
      @state.magic_toxicity -= decay
      summary[:toxicity_decayed] = decay

      # 5. Temporary HP clears regardless of ends_on_round.
      if @state.temporary_hit_points
        summary[:temp_hp_cleared] = true
        @state.temporary_hit_points = nil
      end

      summary
    end

    # ===== Apply Named Effect =====
    # Apply a named Effect's Mechanics. `metadata` rides along on each
    # resulting Active Effect (and the formula string, for later read-through).
    # `bindings` supplies values (e.g. `level`) for any Modifier `amount`
    # expressed as a Formula: when given, the Formula is evaluated now and the
    # concrete amount stored, so Get Modifiers surfaces it. Combat / Creatures
    # own deciding the bindings (per the design); Conditions just does the
    # arithmetic. Without `bindings`, a Formula amount stays 0 as before.
    def apply_named_effect(name, source_id:, ends_on_round: nil, metadata: {}, bindings: {})
      entry = @catalog.effect_name(name)
      mechanics = entry['mechanics'] || []
      applied_ids = []

      mechanics.each_with_index do |mech, idx|
        mech_source_id = "#{source_id}:#{idx}"
        applied_ids << mech_source_id

        case mech['kind']
        when 'modifier'
          amount = mech['amount']
          amount = evaluate_modifier_amount(amount, bindings) unless amount.is_a?(Integer)
          apply_effect(
            target_key: mech['applies_to'] || [],
            bonus_type: mech['modifier_type'].to_s,
            amount: amount,
            source_id: mech_source_id,
            ends_on_round: ends_on_round,
            metadata: metadata.merge('formula' => mech['amount'].is_a?(String) ? mech['amount'] : nil,
                                     'effect_name' => name.to_s).compact
          )
        else
          # Non-modifier Mechanics (reroll, nudge, set_value, scale_value,
          # flag, display) are recorded on a sidecar list with the same
          # replace-by-source_id contract.
          replace_named_effect_mechanic(
            source_id: mech_source_id,
            kind: mech['kind'],
            data: mech,
            ends_on_round: ends_on_round,
            effect_name: name.to_s
          )
        end
      end

      applied_ids
    end

    # Evaluate a Modifier `amount` Formula (e.g. "1 + level / 3") against the
    # caller-supplied bindings. Falls back to 0 when there are no bindings or
    # the Formula references an unbound name.
    def evaluate_modifier_amount(expr, bindings)
      return 0 unless expr.is_a?(String) && !bindings.empty?
      Creatures::Formula.eval(expr, bindings)
    rescue StandardError
      0
    end

    # ===== Clear Expired Effects =====
    def clear_expired_effects(current_round)
      removed = []
      kept = []
      @state.effects.each do |e|
        if e[:ends_on_round] && e[:ends_on_round] <= current_round
          removed << e
        else
          kept << e
        end
      end
      @state.effects = kept

      if @state.temporary_hit_points && @state.temporary_hit_points[:ends_on_round] &&
         @state.temporary_hit_points[:ends_on_round] <= current_round
        removed << @state.temporary_hit_points.merge(kind: :temp_hp)
        @state.temporary_hit_points = nil
      end

      kept_mechs = []
      @state.named_effect_mechanics.each do |m|
        if m[:ends_on_round] && m[:ends_on_round] <= current_round
          removed << m
        else
          kept_mechs << m
        end
      end
      @state.named_effect_mechanics = kept_mechs

      removed
    end

    # ===== Dead? =====
    def dead?(max_hit_points:, attribute_scores:, toxicity_threshold:)
      mult = @catalog.death_multiplier
      hp_total = @state.hp_damage.values.sum
      return true if hp_total >= (mult * max_hit_points).floor

      attribute_scores.each do |attr, score|
        total = SEVERITIES.sum { |sev| @state.ability_damage[sev]&.[](attr.to_sym) || 0 }
        return true if total >= (mult * score).floor
      end

      return true if @state.magic_toxicity >= (mult * toxicity_threshold).floor
      false
    end

    # ===== Dying? =====
    #
    # A Creature whose accumulated HP damage has reached its Max HP but
    # not the death threshold is Dying — down but not dead. First-pass
    # interpretation pending a formal Dying spec in conditions_design.md.
    def dying?(max_hit_points:)
      hp_total = @state.hp_damage.values.sum
      hp_total >= max_hit_points &&
        hp_total < (@catalog.death_multiplier * max_hit_points).floor
    end

    # ===== Has a "cannot act" Active Effect? =====
    #
    # Named Effects (e.g. paralyzed, stunned, unconscious) record a
    # `flag: cannot_act` mechanic on the sidecar list. True when any
    # such flag is active.
    def cannot_act_effect?
      @state.named_effect_mechanics.any? do |m|
        m[:kind].to_s == 'flag' && (m[:data] && (m[:data]['flag'] || m[:data][:flag])) == 'cannot_act'
      end
    end

    # ===== Creature Can Act? =====
    #
    # Delegated target for Encounter's *Creature Can Act?*. False when
    # the Creature is Dead, Dying, or carries a "cannot act" effect.
    def can_act?(max_hit_points:, attribute_scores: {}, toxicity_threshold: 0)
      # dead?'s toxicity check is `toxicity >= mult * threshold`, which a
      # zero threshold turns into `0 >= 0` (everyone "dead"). When the
      # caller has no real threshold, neutralize that arm with a sentinel.
      tox = toxicity_threshold.to_i > 0 ? toxicity_threshold : 10**9
      return false if dead?(max_hit_points: max_hit_points,
                            attribute_scores: attribute_scores,
                            toxicity_threshold: tox)
      return false if dying?(max_hit_points: max_hit_points)
      return false if cannot_act_effect?
      true
    end

    # ===== Affliction badges =====
    #
    # Display-facing summary of active Afflictions: name, the catalog
    # `category` (bleed / poison / disease / curse / other) for badge
    # coloring, and current Potency. Used by the Combat Tracker.
    def affliction_badges
      @state.afflictions.map do |name, entry|
        rule = (@catalog.affliction(name) rescue nil) || {}
        { name: name, category: (rule['category'] || 'other').to_s, potency: entry[:potency] }
      end
    end

    # ===== Active Effect display helpers =====
    #
    # The downtime PC card surfaces "Active Effects" as colored badges
    # for non-Modifier Active Effects only. Non-modifier mechanics
    # applied via Apply Named Effect live on a sidecar list — this
    # accessor lets a UI layer read them without poking at internals.
    def active_named_effect_mechanics
      @state.named_effect_mechanics
    end

    # The distinct names of the Conditions (named Effects) currently active
    # on the Creature — e.g. `rage`, `dazzled` — gathered across both the
    # Modifier Active Effects (`effects`) and the non-Modifier sidecar
    # (`named_effect_mechanics`), each tagged with its source Effect Name.
    # Expired entries are dropped when `current_round` is given. For display
    # (character sheet, Combat Tracker badges).
    def active_effect_names(current_round: nil)
      live = ->(ends) { !(current_round && ends && ends <= current_round) }
      names = []
      @state.named_effect_mechanics.each do |m|
        names << m[:effect_name] if m[:effect_name] && live.call(m[:ends_on_round])
      end
      @state.effects.each do |e|
        nm = e[:metadata] && (e[:metadata]['effect_name'] || e[:metadata][:effect_name])
        names << nm if nm && live.call(e[:ends_on_round])
      end
      names.compact.uniq
    end

    private

    def replace_named_effect_mechanic(source_id:, kind:, data:, ends_on_round:, effect_name:)
      list = @state.named_effect_mechanics
      existing = list.find_index { |m| m[:source_id] == source_id }
      entry = {
        source_id: source_id,
        kind: kind,
        data: data,
        ends_on_round: ends_on_round,
        effect_name: effect_name
      }
      if existing
        list[existing] = entry
      else
        list << entry
      end
    end

    def sym_severity_map(input)
      out = sev_zero_map
      input.each do |k, v|
        sev = k.to_sym
        next unless SEVERITIES.include?(sev)
        out[sev] = v.to_i
      end
      out
    end

    def sev_zero_map
      SEVERITIES.each_with_object({}) { |s, h| h[s] = 0 }
    end

    # Set a Severity's hit-point-damage counter, deleting the key when it
    # reaches zero so a fully-healed Creature serializes clean.
    def set_hp_counter(sev, value)
      if value <= 0
        @state.hp_damage.delete(sev)
      else
        @state.hp_damage[sev] = value
      end
    end

    # Heal up to `amount` from one Severity's counter (no cascade to other
    # Severities). Returns how much was actually mended.
    def heal_severity(sev, amount)
      have = @state.hp_damage[sev] || 0
      h = [amount.to_i, have].min
      set_hp_counter(sev, have - h) if h.positive?
      h
    end

    # Ordinary healing chips away at any unhealed acid/fire (elemental)
    # wound; once it clears, Regeneration is free to resume.
    def reduce_elemental_wound(total)
      return if total <= 0 || @state.elemental_wound.zero?
      @state.elemental_wound = [@state.elemental_wound - total, 0].max
    end

    def effect_targets?(entry_target, query)
      return true if entry_target == query
      return entry_target.include?(query) if entry_target.is_a?(Array)
      false
    end

    def save_frequency(rule)
      (rule['save_frequency'] || 'round').to_s
    end

    # Substitute "tier" with the Creature's Tier (Tier 0 → 0.5).
    # Returns a Numeric (Integer or Float).
    def tier_substitute(value, creature_tier)
      if value.is_a?(String) && value.downcase == 'tier'
        creature_tier <= 0 ? 0.5 : creature_tier
      else
        value
      end
    end

    def dispatch_affliction_effect(effect, net_magnitude, name, current_round)
      case effect['kind']
      when 'hit_point_damage'
        result = apply_hit_point_damage(effect['severity'] => net_magnitude)
        { kind: 'hit_point_damage', severity: effect['severity'], amount: net_magnitude, result: result }
      when 'ability_damage'
        apply_ability_damage(effect['attribute'], effect['severity'] => net_magnitude)
        { kind: 'ability_damage', attribute: effect['attribute'], severity: effect['severity'], amount: net_magnitude }
      when 'named_effect'
        duration = effect['duration_rounds']
        ends = (current_round && duration) ? current_round + duration : nil
        ids = apply_named_effect(effect['name'], source_id: "affliction:#{name}", ends_on_round: ends)
        { kind: 'named_effect', name: effect['name'], applied: ids, ends_on_round: ends }
      else
        raise ArgumentError, "unknown affliction effect kind: #{effect['kind']}"
      end
    end
  end
end
