# Combat — round-by-round combat tracker.
#
# Owns:
#   * who is currently in combat (PCs and enemies, two-id scheme:
#     a per-instance combat_id, plus the underlying char_id so two
#     copies of the same monster track separately)
#   * the dice rolled for each combatant's initiative (sorted high-
#     to-low; tie-break compares dice value-by-value)
#   * how many rounds have elapsed
#   * whose turn it is now
#   * how many action dice each combatant has left
#
# Two YAML files:
#
#   * Rules file — tunable values (Initiative Divisor, Combat Pool
#     Range, Combat Pool Minimum). Hand-edited; loaded once at
#     boot. Schema documented in
#     docs/combat/combat_config.yaml.example.
#   * State file — round, current turn pointer, combatants list.
#     Atomically rewritten on every mutation. Schema documented in
#     docs/combat/combat_data.yaml.example.
#
# Initiative dice count: floor(initiative_attribute / Initiative
# Divisor). The attribute used (wisdom by default) is set by
# `Initiative Attribute` in the rules file.
# Action dice (combat pool) max:
#   raw = martial_skill_rank + (combat_pool_attribute / 2)
#   action_dice_max = (raw % Combat Pool Range) + Combat Pool Minimum
#   unused_bonus   = raw / Combat Pool Range  (deferred — exposed
#     now so callers can read it, but no combat-roll math consumes
#     it yet).
#
# Initiative rolling goes through DiceSystem. Initiative has no TN,
# so the generic Luck/Insight helpers (which both require a TN)
# don't apply. The rules for this module:
#   * Positive Luck    — reroll the lowest non-critical die.
#   * Negative Luck    — reroll the highest non-failure die.
#   * Positive Insight — bump the lowest die that can become a
#     critical (value + insight >= die_size); if none qualify,
#     bump the highest non-critical instead.
#   * Negative Insight — penalize the highest die.
# Magnitudes greater than 1 repeat the operation that many times.

require 'yaml'
require 'fileutils'
require 'securerandom'

class Combat
  DEFAULT_INITIATIVE_ATTRIBUTE  = 'wis'
  DEFAULT_INITIATIVE_DIVISOR    = 2
  DEFAULT_COMBAT_POOL_ATTRIBUTE = 'wis'
  DEFAULT_COMBAT_POOL_RANGE     = 10
  DEFAULT_COMBAT_POOL_MINIMUM   = 11

  def initialize(state_path:, rules_path:, dice_system:, character_lookup:,
                 damage_types: nil, conditions_lookup: nil, condition_evaluator: nil)
    @state_path          = state_path
    @rules_path          = rules_path
    @dice_system         = dice_system
    @character_lookup    = character_lookup
    @damage_types        = damage_types
    @conditions_lookup   = conditions_lookup
    @condition_evaluator = condition_evaluator || ->(_combat_id, _tag) { false }

    load_rules!

    @active             = false
    @round              = 0
    @current_turn_index = 0
    @combatants         = []

    load_state! if @state_path && File.exist?(@state_path)
  end

  attr_reader :round, :combatants,
              :initiative_attribute, :initiative_divisor,
              :combat_pool_attribute, :combat_pool_range, :combat_pool_minimum

  def active?
    @active
  end

  # Combatants in turn order: highest initiative first, ties broken
  # die-by-die (next-highest die wins), final tie-break by combat_id
  # so the order is stable across reads.
  def turn_order
    @combatants.sort_by { |c| [initiative_sort_key(c['initiative_dice']), c['id']] }
  end

  def current_combatant
    order = turn_order
    return nil if order.empty?
    order[@current_turn_index % order.length]
  end

  # ----- Combatant management ------------------------------------------

  def add_combatant(char_id:, name:)
    rec = {
      'id'              => next_combat_id!,
      'char_id'         => char_id,
      'name'            => name.to_s,
      'initiative_dice' => [],
      'action_dice'     => action_dice_max(char_id)
    }
    @combatants << rec
    save!
    rec
  end

  def remove_combatant(combat_id)
    order = turn_order
    current = order[@current_turn_index % order.length] if order.any?

    idx = @combatants.index { |c| c['id'] == combat_id }
    return false unless idx
    @combatants.delete_at(idx)

    if @combatants.empty?
      @current_turn_index = 0
    elsif current && current['id'] != combat_id
      # Keep the same combatant on deck after the removal shifts the
      # turn order. If the removed combatant was the active one, the
      # index already points at the next combatant in line.
      new_order = turn_order
      new_idx = new_order.index { |c| c['id'] == current['id'] }
      @current_turn_index = new_idx if new_idx
    else
      @current_turn_index %= @combatants.length
    end

    save!
    true
  end

  # ----- Derived per-character values ---------------------------------

  def initiative_dice_count(char_id)
    char = require_character(char_id)
    char.attribute(@initiative_attribute) / @initiative_divisor
  end

  def action_dice_max(char_id)
    char = require_character(char_id)
    raw = action_dice_raw(char)
    (raw % @combat_pool_range) + @combat_pool_minimum
  end

  # Quotient half of the action-dice formula. Per the combat
  # glossary this is the Unused Bonus — exposed now so callers
  # can read it; combat-roll math doesn't consume it yet.
  def unused_bonus(char_id)
    char = require_character(char_id)
    action_dice_raw(char) / @combat_pool_range
  end

  # ----- Initiative ---------------------------------------------------

  # Reroll initiative for every combatant. luck_by_id and
  # insight_by_id are { combat_id => signed integer }. Combat
  # becomes active, the round counter resets to 1, and the turn
  # pointer goes back to the top of the order.
  def reroll_all_initiative(luck_by_id: {}, insight_by_id: {})
    @combatants.each do |c|
      n = initiative_dice_count(c['char_id'])
      dice = n > 0 ? @dice_system.rand_roll_dice(n) : []
      apply_initiative_luck!(dice, luck_by_id[c['id']].to_i)
      apply_initiative_insight!(dice, insight_by_id[c['id']].to_i)
      c['initiative_dice'] = dice.sort.reverse
    end
    @active             = true
    @round              = 1
    @current_turn_index = 0
    save!
  end

  # ----- Turn pointer -------------------------------------------------

  def next_turn
    return if @combatants.empty?
    @current_turn_index += 1
    if @current_turn_index >= @combatants.length
      @current_turn_index = 0
      @round += 1
    end
    save!
  end

  def end_combat
    @active             = false
    @round              = 0
    @current_turn_index = 0
    @combatants.each { |c| c['initiative_dice'] = [] }
    save!
  end

  # ----- Action dice --------------------------------------------------

  def set_action_dice(combat_id, value)
    c = @combatants.find { |x| x['id'] == combat_id }
    return false unless c
    c['action_dice'] = [0, value.to_i].max
    save!
    true
  end

  def spend_action_dice(combat_id, amount)
    c = @combatants.find { |x| x['id'] == combat_id }
    return false unless c
    c['action_dice'] = [0, c['action_dice'].to_i - amount.to_i].max
    save!
    true
  end

  def reset_action_dice(combat_id = nil)
    targets = combat_id ? @combatants.select { |c| c['id'] == combat_id } : @combatants
    return false if targets.empty?
    targets.each { |c| c['action_dice'] = action_dice_max(c['char_id']) }
    save!
    true
  end

  # ----- Attack resolution / Severity Calculation pipeline -----------
  #
  # Takes an already-resolved damage payload (amount + damage_type) and
  # routes it through the damage_types catalog mechanics, then through
  # severity decision (declared severity for non-physical, runtime
  # bucketing for physical), then into the target's Conditions
  # instance, then through post-damage side-effects (apply_acid_counter,
  # inflict for shock, etc.).
  #
  # The to-hit roll itself is not performed here — clients (or callers)
  # have already decided that damage lands, and how much. This is the
  # damage-application half of attack resolution.
  #
  # Parameters:
  #   target_combat_id    — the Combatant on the receiving end
  #   amount              — base damage points
  #   damage_type         — name from the damage_types catalog
  #   dice_count          — optional. Used by damage_per_dice mechanics.
  #   threshold           — optional. Used by runtime bucketing for
  #                         Physical Damage. For weapon attacks, the
  #                         caller looks this up from the weapon; for
  #                         physical damage from an ability, from the
  #                         ability's threshold field.
  #   attacker_combat_id  — optional. Reserved for future logging /
  #                         attribution; not consumed today.
  #
  # Returns a hash describing what happened.
  def apply_attack_damage(target_combat_id, amount, damage_type:, dice_count: nil, threshold: nil, attacker_combat_id: nil)
    raise 'damage_types instance required' unless @damage_types
    raise 'conditions_lookup required'     unless @conditions_lookup

    target = @combatants.find { |c| c['id'] == target_combat_id }
    raise "Unknown target #{target_combat_id}" unless target

    raise "Unknown damage type: #{damage_type}" unless @damage_types.known?(damage_type)
    mechanics = @damage_types.mechanics_for(damage_type)

    base_amount = amount.to_i
    multiplier  = 1.0
    bonus       = 0

    mechanics.each do |mechanic|
      case mechanic['kind']
      when 'damage_per_dice'
        next unless dice_count
        bonus += (dice_count.to_i / mechanic['per'].to_i) * mechanic['bonus'].to_i
      when 'damage_multiplier'
        next unless @condition_evaluator.call(target_combat_id, mechanic['condition'])
        multiplier *= mechanic['factor'].to_f
      end
    end

    final_amount = ((base_amount + bonus) * multiplier).floor
    final_amount = 0 if final_amount.negative?

    severity_split = compute_severity_split(damage_type, final_amount, target['char_id'], threshold)

    target_conditions = @conditions_lookup.call(target['char_id'])
    raise "No conditions instance for #{target['char_id']}" unless target_conditions
    damage_result = target_conditions.apply_hit_point_damage(severity_split)

    side_effects = mechanics.map do |mechanic|
      case mechanic['kind']
      when 'apply_acid_counter'
        per_damage = (mechanic['per_damage'] || 1).to_i
        applied = final_amount * per_damage
        target_conditions.apply_acid_damage(applied)
        { 'kind' => 'apply_acid_counter', 'amount' => applied }
      when 'inflict'
        per_damage = (mechanic['per_damage'] || 1).to_i
        applied = final_amount * per_damage
        case mechanic['condition_name']
        when 'shock'
          target_conditions.apply_shock(applied)
          { 'kind' => 'inflict', 'condition_name' => 'shock', 'amount' => applied }
        else
          { 'kind' => 'inflict', 'condition_name' => mechanic['condition_name'], 'amount' => applied, 'unrouted' => true }
        end
      end
    end.compact

    {
      'attacker_combat_id' => attacker_combat_id,
      'target_combat_id'   => target_combat_id,
      'damage_type'        => damage_type,
      'base_amount'        => base_amount,
      'multiplier'         => multiplier,
      'damage_per_dice_bonus' => bonus,
      'final_amount'       => final_amount,
      'severity_split'     => severity_split,
      'damage_result'      => damage_result,
      'side_effects'       => side_effects
    }
  end

  # Tells dice resolution which damage type's `critical_value` (if any)
  # applies to a Roll. Returns the override or the dice resolution
  # default. The caller passes this as `critical_modifier` to
  # COMPUTE_RESULTS / APPLY_NUDGE / etc.
  def critical_modifier_for(damage_type)
    return DiceSystem::DEFAULT_CRITICAL_MODIFIER unless @damage_types && damage_type
    return DiceSystem::DEFAULT_CRITICAL_MODIFIER unless @damage_types.known?(damage_type)
    mechanic = @damage_types.mechanics_for(damage_type).find { |m| m['kind'] == 'critical_value' }
    return DiceSystem::DEFAULT_CRITICAL_MODIFIER unless mechanic
    mechanic['value'].to_i
  end

  private

  # Splits final_amount into { minor, moderate, major } per the damage
  # type's severity rules.
  def compute_severity_split(damage_type, amount, target_char_id, threshold)
    return { 'minor' => 0, 'moderate' => 0, 'major' => 0 } if amount <= 0
    if @damage_types.runtime_bucketing?(damage_type)
      runtime_bucket(amount, target_char_id, threshold)
    else
      severity = @damage_types.severity_for(damage_type)
      { 'minor' => 0, 'moderate' => 0, 'major' => 0 }.merge(severity => amount)
    end
  end

  # Runtime bucketing for Physical Damage:
  #   first (Threshold + Damage Resilience) points  → minor
  #   next  (Threshold + Damage Resilience) points  → moderate
  #   everything beyond                              → major
  def runtime_bucket(amount, target_char_id, threshold)
    target_char = @character_lookup.call(target_char_id)
    resilience = target_char.respond_to?(:damage_resilience) ? target_char.damage_resilience.to_i : 0
    bucket_size = [(threshold || 0).to_i + resilience, 0].max
    return { 'minor' => amount, 'moderate' => 0, 'major' => 0 } if bucket_size.zero? && amount > 0 && false
    if bucket_size.zero?
      # No threshold and no resilience: every point becomes major.
      return { 'minor' => 0, 'moderate' => 0, 'major' => amount }
    end
    minor    = [amount, bucket_size].min
    rest     = amount - minor
    moderate = [rest, bucket_size].min
    major    = rest - moderate
    { 'minor' => minor, 'moderate' => moderate, 'major' => major }
  end

  def require_character(char_id)
    char = @character_lookup.call(char_id)
    raise ArgumentError, "no character for char_id=#{char_id.inspect}" unless char
    char
  end

  def action_dice_raw(char)
    char.skill_ranks['martial'].to_i + (char.attribute(@combat_pool_attribute) / 2)
  end

  # Compares dice value-by-value descending so [10, 7] beats [10, 6]
  # but loses to [10, 8]. Negated so Ruby's ascending sort places
  # higher initiative first.
  def initiative_sort_key(dice)
    (dice || []).sort.reverse.map { |v| -v }
  end

  def die_size
    @dice_system.dice_resolution_config['Die Size']
  end

  def apply_initiative_luck!(dice, luck_value)
    return if luck_value == 0 || dice.empty?
    remaining = luck_value.abs
    if luck_value > 0
      # Reroll lowest non-critical first, then next-lowest, etc.
      dice.each_with_index.sort_by { |v, _| v }.each do |v, i|
        break if remaining == 0
        next if v == die_size
        dice[i] = @dice_system.rand_roll_die
        remaining -= 1
      end
    else
      dice.each_with_index.sort_by { |v, _| -v }.each do |v, i|
        break if remaining == 0
        next if v == 1
        dice[i] = @dice_system.rand_roll_die
        remaining -= 1
      end
    end
  end

  def apply_initiative_insight!(dice, insight_value)
    return if insight_value == 0 || dice.empty?
    if insight_value > 0
      crit_capable = dice.each_with_index.select do |v, _|
        v < die_size && v + insight_value >= die_size
      end
      target_index =
        if crit_capable.any?
          crit_capable.min_by { |v, _| v }[1]
        else
          non_crit = dice.each_with_index.reject { |v, _| v == die_size }
          non_crit.empty? ? nil : non_crit.max_by { |v, _| v }[1]
        end
      return if target_index.nil?
      dice[target_index] = [die_size, dice[target_index] + insight_value].min
    else
      _, target_index = dice.each_with_index.max_by { |v, _| v }
      dice[target_index] = [1, dice[target_index] + insight_value].max
    end
  end

  # One past the current max id, falling back to 1 when the list
  # is empty. Derived rather than persisted so the state file stays
  # to the values that actually describe combat.
  def next_combat_id!
    (@combatants.map { |c| c['id'].to_i }.max || 0) + 1
  end

  def load_rules!
    data = (@rules_path && File.exist?(@rules_path)) ? (YAML.safe_load_file(@rules_path) || {}) : {}
    @initiative_attribute  = (data['Initiative Attribute']  || DEFAULT_INITIATIVE_ATTRIBUTE).to_sym
    @initiative_divisor    = data['Initiative Divisor']     || DEFAULT_INITIATIVE_DIVISOR
    @combat_pool_attribute = (data['Combat Pool Attribute'] || DEFAULT_COMBAT_POOL_ATTRIBUTE).to_sym
    @combat_pool_range     = data['Combat Pool Range']      || DEFAULT_COMBAT_POOL_RANGE
    @combat_pool_minimum   = data['Combat Pool Minimum']    || DEFAULT_COMBAT_POOL_MINIMUM
  end

  def save!
    return unless @state_path
    FileUtils.mkdir_p(File.dirname(@state_path))
    payload = {
      'active'             => @active,
      'round'              => @round,
      'current_turn_index' => @current_turn_index,
      'combatants'         => @combatants
    }
    tmp = "#{@state_path}.tmp.#{SecureRandom.hex(4)}"
    File.write(tmp, payload.to_yaml)
    File.rename(tmp, @state_path)
  end

  def load_state!
    data = YAML.safe_load_file(@state_path, permitted_classes: [Symbol]) || {}
    @active             = data['active'] ? true : false
    @round              = data['round'].to_i
    @current_turn_index = data['current_turn_index'].to_i
    @combatants         = data['combatants'] || []
  end
end
