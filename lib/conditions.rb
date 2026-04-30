require 'yaml'

# Conditions — per-creature mutable state.
#
# Owns hit-point damage counters, ability damage, temporary hit points,
# magic toxicity, shock, the acid counter, active afflictions, and
# active effects (buffs/debuffs). Deliberately ignorant of who or what
# produced any given effect — sources are identified by opaque
# Source IDs.
#
# See docs/conditions/conditions_glossary.md and conditions_design.md.
class Conditions
  VALID_SIGNS = %w[bonus penalty].freeze

  attr_reader :hit_point_damage, :ability_damage,
              :temporary_hit_points, :current_mana, :magic_toxicity,
              :shock, :acid_counter,
              :afflictions, :effects

  def initialize(config_path:, dice_system:, severities:, initial_state: nil)
    @conditions_config = YAML.load_file(config_path) || {}
    @dice_system = dice_system
    @severities = severities.map(&:to_s)

    if initial_state
      load_state(initial_state)
    else
      reset_state!
    end
  end

  # ---------- Hit point damage and healing ------------------------

  def apply_hit_point_damage(incoming)
    validate_severity_keys!(incoming)
    absorbed = empty_severity_map
    dealt = empty_severity_map
    pool = (@temporary_hit_points && @temporary_hit_points['amount']) || 0

    worst_first.each do |category|
      amount = (incoming[category] || incoming[category.to_sym] || 0).to_i
      absorb = [amount, pool].min
      absorbed[category] = absorb
      pool -= absorb
      dealt[category] = amount - absorb
      @hit_point_damage[category] += dealt[category]
    end

    if @temporary_hit_points
      if pool <= 0
        @temporary_hit_points = nil
      else
        @temporary_hit_points['amount'] = pool
      end
    end

    { 'absorbed' => absorbed, 'dealt' => dealt }
  end

  def apply_hit_point_heal_cascade(pools)
    validate_severity_keys!(pools)
    healed = empty_severity_map
    remainder = 0

    worst_first.each do |category|
      pool = (pools[category] || pools[category.to_sym] || 0).to_i + remainder
      available = @hit_point_damage[category]
      applied = [pool, available].min
      healed[category] = applied
      @hit_point_damage[category] = available - applied
      remainder = pool - applied
    end

    healed
  end

  def set_temporary_hit_points(amount, source_id, ends_on_round = nil)
    previous_source = @temporary_hit_points && @temporary_hit_points['source_id']

    if amount.to_i <= 0
      @temporary_hit_points = nil
      return { 'accepted' => true, 'replaced_source_id' => previous_source }
    end

    current_amount = (@temporary_hit_points && @temporary_hit_points['amount']) || 0
    if amount.to_i <= current_amount
      return { 'accepted' => false, 'replaced_source_id' => nil }
    end

    @temporary_hit_points = {
      'amount'         => amount.to_i,
      'source_id'      => source_id,
      'ends_on_round'  => ends_on_round
    }
    { 'accepted' => true, 'replaced_source_id' => previous_source }
  end

  # ---------- Natural recovery -------------------------------------

  # Roll every per-day rule forward by `days` days.
  # Returns a structured summary of what changed.
  #
  # Required parameters:
  #   days:           positive integer
  #   mode:           'short_rest' or 'long_term_recovery'
  #   character_tier: integer, used to index Heal Rate / Ability Heal Rate
  #   mana_max:       cap for mana restore
  #   magic_toxicity_attribute_score: integer for the toxicity decay
  #                   formula (typically Character#cha)
  def apply_natural_recovery(days:, mode:, character_tier:, mana_max:, magic_toxicity_attribute_score:)
    raise ArgumentError, 'days must be positive' unless days.to_i.positive?
    raise ArgumentError, "unknown mode: #{mode}" unless %w[short_rest long_term_recovery].include?(mode.to_s)

    rules = @conditions_config['Natural Recovery'] || {}
    use_high = mode.to_s == 'long_term_recovery'

    hp_healed = recover_hit_point_damage(rules['Heal Rate'], character_tier, days, use_high)
    ability_healed = recover_ability_damage(rules['Ability Heal Rate'], character_tier, days, use_high)

    mana_per_day = mana_max.to_i / (rules['Mana Per Day Divisor'] || 4).to_i
    mana_before = @current_mana
    restore_mana(mana_per_day * days.to_i, max: mana_max)
    mana_gained = @current_mana - mana_before

    tox_per_day = magic_toxicity_attribute_score.to_i / (rules['Magic Toxicity Per Day Divisor'] || 4).to_i
    tox_before = @magic_toxicity
    clear_magic_toxicity(tox_per_day * days.to_i)
    tox_lost = tox_before - @magic_toxicity

    temp_cleared = !@temporary_hit_points.nil?
    @temporary_hit_points = nil

    {
      'days'                          => days.to_i,
      'mode'                          => mode.to_s,
      'hit_point_healed'              => hp_healed,
      'ability_healed'                => ability_healed,
      'mana_gained'                   => mana_gained,
      'magic_toxicity_lost'           => tox_lost,
      'temporary_hit_points_cleared'  => temp_cleared
    }
  end

  # ---------- Ability damage ---------------------------------------

  def apply_ability_damage(attribute, severity, amount)
    severity = severity.to_s
    raise ArgumentError, "Unknown severity: #{severity}" unless @severities.include?(severity)
    return if amount.to_i <= 0

    attr_key = attribute.to_s
    @ability_damage[attr_key] ||= empty_severity_map
    @ability_damage[attr_key][severity] += amount.to_i
  end

  def apply_ability_heal_cascade(pools)
    validate_severity_keys!(pools)
    healed = empty_severity_map
    remainder = 0

    worst_first.each do |category|
      pool = (pools[category] || pools[category.to_sym] || 0).to_i + remainder
      @ability_damage.each_key do |attribute|
        break if pool == 0
        available = @ability_damage[attribute][category]
        applied = [pool, available].min
        @ability_damage[attribute][category] = available - applied
        healed[category] += applied
        pool -= applied
      end
      remainder = pool
    end

    @ability_damage.delete_if { |_, severities| severities.values.all?(&:zero?) }
    healed
  end

  # ---------- Mana ------------------------------------------------

  def apply_mana_cost(amount)
    return 0 if amount.to_i <= 0
    spent = [@current_mana, amount.to_i].min
    @current_mana -= spent
    spent
  end

  def restore_mana(amount, max:)
    return @current_mana if amount.to_i <= 0
    @current_mana = [@current_mana + amount.to_i, max.to_i].min
  end

  def set_mana(amount, max:)
    @current_mana = [[amount.to_i, 0].max, max.to_i].min
  end

  # ---------- Magic toxicity --------------------------------------

  def apply_magic_toxicity(amount)
    return @magic_toxicity if amount.to_i <= 0
    @magic_toxicity += amount.to_i
  end

  def clear_magic_toxicity(amount)
    return @magic_toxicity if amount.to_i <= 0
    @magic_toxicity = [0, @magic_toxicity - amount.to_i].max
  end

  # ---------- Shock ------------------------------------------------

  def apply_shock(amount)
    return @shock if amount.to_i <= 0
    @shock += amount.to_i
  end

  def consume_shock(max_consume)
    return 0 if max_consume.to_i <= 0 || @shock == 0
    consumed = [@shock, max_consume.to_i].min
    @shock -= consumed
    consumed
  end

  # ---------- Acid counter ----------------------------------------

  def apply_acid_damage(amount)
    return @acid_counter if amount.to_i <= 0
    @acid_counter += amount.to_i
  end

  def resolve_acid_turn_start
    return { 'damage_dealt' => nil, 'counter_after' => 0 } if @acid_counter <= 0
    @acid_counter /= 2
    if @acid_counter <= 0
      @acid_counter = 0
      return { 'damage_dealt' => nil, 'counter_after' => 0 }
    end
    result = apply_hit_point_damage('minor' => @acid_counter)
    { 'damage_dealt' => result, 'counter_after' => @acid_counter }
  end

  # ---------- Afflictions -----------------------------------------

  def inflict_affliction(name, amount, inflicter_tier)
    name = name.to_s
    raise ArgumentError, "Unknown affliction: #{name}" unless affliction_rule(name)

    if amount.to_i <= 0
      existing = @afflictions[name]
      return existing ?
        { 'severity' => existing['severity'], 'inflicting_tier' => existing['inflicting_tier'], 'newly_added' => false } :
        { 'severity' => 0, 'inflicting_tier' => 0, 'newly_added' => false }
    end

    newly_added = !@afflictions.key?(name)
    if newly_added
      @afflictions[name] = { 'severity' => 0, 'inflicting_tier' => inflicter_tier.to_i }
    else
      @afflictions[name]['inflicting_tier'] = [@afflictions[name]['inflicting_tier'], inflicter_tier.to_i].max
    end
    @afflictions[name]['severity'] += amount.to_i

    {
      'severity'        => @afflictions[name]['severity'],
      'inflicting_tier' => @afflictions[name]['inflicting_tier'],
      'newly_added'     => newly_added
    }
  end

  def remove_affliction(name)
    @afflictions.delete(name.to_s)
  end

  def get_affliction(name)
    name = name.to_s
    return nil unless @afflictions.key?(name)
    rule = affliction_rule(name) || {}
    entry = @afflictions[name]
    {
      'name'            => name,
      'severity'        => entry['severity'],
      'inflicting_tier' => entry['inflicting_tier'],
      'category'        => rule['category'] || 'other',
      'save_frequency'  => rule['save_frequency'] || 'round',
      'save_attribute'  => rule['save'] || 'con'
    }
  end

  def resolve_affliction(name, save_input, creature_tier, current_round = nil)
    name = name.to_s
    if !@afflictions.key?(name) || @afflictions[name]['severity'] <= 0
      raise ArgumentError, "Affliction not active: #{name}"
    end
    rule = affliction_rule(name)
    severity_before = @afflictions[name]['severity']
    divisor = @conditions_config['Severity Divisor'].to_i
    severity_save_penalty = severity_before / divisor

    merged = (save_input['modifiers'] || {}).dup
    merged['Competency Penalty'] = (merged['Competency Penalty'] || 0).to_i + severity_save_penalty
    params = @dice_system.compute_roll_parameters(merged)
    dice = @dice_system.rand_roll_dice(save_input['dice_count'].to_i)
    result = @dice_system.compute_results(dice, params['tn'], params['starting_value'])
    dois = result['degree_of_individual_success'].to_i
    successes = [0, dois].max
    failures = [0, -dois].max

    magnitude = 1 + (severity_before / divisor)
    net_magnitude = [0, magnitude - successes].max

    effect_kind = rule['effect']['kind']
    applied = apply_affliction_effect(rule['effect'], net_magnitude, current_round)

    per_success = resolve_tier_scaled_value(rule.fetch('severity_per_success', @conditions_config['Default Severity Per Success']), creature_tier)
    per_failure = resolve_tier_scaled_value(rule.fetch('severity_per_failure', @conditions_config['Default Severity Per Failure']), creature_tier)
    decay       = resolve_tier_scaled_value(rule.fetch('severity_decay',       @conditions_config['Default Severity Decay']),       creature_tier)

    delta = -decay.floor - (successes * per_success).floor + (failures * per_failure).floor
    new_severity = [0, severity_before + delta].max
    removed = false
    if new_severity <= 0
      @afflictions.delete(name)
      removed = true
    else
      @afflictions[name]['severity'] = new_severity
    end

    {
      'successes'             => successes,
      'failures'              => failures,
      'severity_save_penalty' => severity_save_penalty,
      'magnitude'             => magnitude,
      'net_magnitude'         => net_magnitude,
      'effect_kind'           => effect_kind,
      'applied'               => applied,
      'severity_before'       => severity_before,
      'severity_after'        => new_severity,
      'removed'               => removed
    }
  end

  # ---------- Named effects (Effect Names catalog) -----------------

  def apply_named_effect(name, ends_on_round, source_id)
    raise ArgumentError, 'source_id must be non-empty' if source_id.to_s.empty?
    name = name.to_s
    entry = effect_name_entry(name)
    raise ArgumentError, "Unknown named effect: #{name}" unless entry

    applied = []
    Array(entry['mechanics']).each_with_index do |mechanic, i|
      next unless mechanic['kind'].to_s == 'modifier'
      modifier_source_id = "#{source_id}:#{i}"
      result = apply_effect(
        target_key: derive_target_key(mechanic),
        bonus_type: mechanic['modifier_type'],
        sign:       mechanic['sign'],
        amount:     mechanic['magnitude'].to_i,
        ends_on_round: ends_on_round,
        source_id:  modifier_source_id,
        metadata:   { 'named_effect' => name, 'mechanic_index' => i }
      )
      applied << result
    end
    { 'name' => name, 'applied' => applied }
  end

  # ---------- Effects (generic buffs/debuffs) ----------------------

  def apply_effect(target_key:, bonus_type:, sign:, amount:, ends_on_round: nil, source_id:, metadata: {})
    raise ArgumentError, 'sign must be bonus or penalty' unless VALID_SIGNS.include?(sign.to_s)
    raise ArgumentError, 'amount must be non-negative' if amount.to_i < 0
    raise ArgumentError, 'source_id must be non-empty' if source_id.to_s.empty?

    entry = {
      'target_key'    => target_key.to_s,
      'bonus_type'    => bonus_type.to_s,
      'sign'          => sign.to_s,
      'amount'        => amount.to_i,
      'ends_on_round' => ends_on_round,
      'source_id'     => source_id.to_s,
      'metadata'      => metadata || {}
    }

    existing_index = @effects.find_index { |e| e['source_id'] == source_id.to_s }
    if existing_index
      previous = @effects[existing_index]
      @effects[existing_index] = entry
      return { 'replaced' => true, 'previous' => previous }
    end

    @effects << entry
    { 'replaced' => false, 'previous' => nil }
  end

  def remove_effect(source_id)
    source_id = source_id.to_s
    index = @effects.find_index { |e| e['source_id'] == source_id }
    return nil unless index
    @effects.delete_at(index)
  end

  def remove_effects_by_prefix(prefix)
    prefix = prefix.to_s
    removed, kept = @effects.partition { |e| e['source_id'].start_with?(prefix) }
    @effects = kept
    removed
  end

  def clear_expired_effects(current_round)
    removed = []
    @effects = @effects.reject do |entry|
      if entry['ends_on_round'] && entry['ends_on_round'] <= current_round
        removed << entry
        true
      else
        false
      end
    end
    temp_cleared = false
    if @temporary_hit_points && @temporary_hit_points['ends_on_round'] && @temporary_hit_points['ends_on_round'] <= current_round
      @temporary_hit_points = nil
      temp_cleared = true
    end
    { 'removed_effects' => removed, 'temporary_hit_points_cleared' => temp_cleared }
  end

  def get_modifiers(target_key, current_round = nil)
    target_key = target_key.to_s
    highest_bonus = {}
    highest_penalty = {}
    @effects.each do |entry|
      next unless entry['target_key'] == target_key
      next if entry['amount'].to_i == 0
      next if current_round && entry['ends_on_round'] && entry['ends_on_round'] <= current_round
      type = entry['bonus_type']
      bucket = entry['sign'] == 'bonus' ? highest_bonus : highest_penalty
      bucket[type] = entry['amount'] if !bucket.key?(type) || entry['amount'] > bucket[type]
    end
    result = {}
    highest_bonus.each   { |type, value| result["#{type} Bonus"]   = value }
    highest_penalty.each { |type, value| result["#{type} Penalty"] = value }
    result
  end

  # ---------- Serialization ---------------------------------------

  def to_dict
    {
      'hit_point_damage'     => @hit_point_damage.dup,
      'ability_damage'       => deep_copy(@ability_damage),
      'temporary_hit_points' => @temporary_hit_points && @temporary_hit_points.dup,
      'current_mana'         => @current_mana,
      'magic_toxicity'       => @magic_toxicity,
      'shock'                => @shock,
      'acid_counter'         => @acid_counter,
      'afflictions'          => deep_copy(@afflictions),
      'effects'              => deep_copy(@effects)
    }
  end

  def load_state(state)
    state ||= {}
    reset_state!

    if state['hit_point_damage']
      state['hit_point_damage'].each do |category, value|
        category = category.to_s
        unless @severities.include?(category)
          raise ArgumentError, "Unrecognized severity in state: #{category}"
        end
        @hit_point_damage[category] = value.to_i
      end
    end

    (state['ability_damage'] || {}).each do |attribute, severities|
      @ability_damage[attribute.to_s] = empty_severity_map
      (severities || {}).each do |category, value|
        category = category.to_s
        unless @severities.include?(category)
          raise ArgumentError, "Unrecognized severity in state: #{category}"
        end
        @ability_damage[attribute.to_s][category] = value.to_i
      end
    end

    @temporary_hit_points = state['temporary_hit_points']
    @current_mana = state['current_mana'].to_i
    @magic_toxicity = state['magic_toxicity'].to_i
    @shock = state['shock'].to_i
    @acid_counter = state['acid_counter'].to_i

    (state['afflictions'] || {}).each do |name, entry|
      unless affliction_rule(name.to_s)
        raise ArgumentError, "Unknown affliction in state: #{name}"
      end
      @afflictions[name.to_s] = {
        'severity'        => entry['severity'].to_i,
        'inflicting_tier' => (entry['inflicting_tier'] || 0).to_i
      }
    end

    (state['effects'] || []).each do |entry|
      unless VALID_SIGNS.include?(entry['sign'].to_s)
        raise ArgumentError, "Unrecognized effect sign in state: #{entry['sign']}"
      end
      @effects << deep_copy_value(entry)
    end
  end

  private

  def reset_state!
    @hit_point_damage = empty_severity_map
    @ability_damage = {}
    @temporary_hit_points = nil
    @current_mana = 0
    @magic_toxicity = 0
    @shock = 0
    @acid_counter = 0
    @afflictions = {}
    @effects = []
  end

  def recover_hit_point_damage(table, tier, days, use_high)
    healed = empty_severity_map
    return healed unless table.is_a?(Array)
    @severities.each_with_index do |severity, i|
      row = table[tier.to_i * @severities.length + i]
      next unless row.is_a?(Array)
      low, high, unit = row
      per = (use_high ? high : low).to_i
      next if per.zero?
      periods = unit.to_i.zero? ? 0 : days.to_i / unit.to_i
      amount = per * periods
      next if amount.zero?
      available = @hit_point_damage[severity]
      applied = [amount, available].min
      healed[severity] = applied
      @hit_point_damage[severity] = available - applied
    end
    healed
  end

  def recover_ability_damage(table, tier, days, use_high)
    healed = empty_severity_map
    return healed unless table.is_a?(Array)
    pools = empty_severity_map
    @severities.each_with_index do |severity, i|
      row = table[tier.to_i * @severities.length + i]
      next unless row.is_a?(Array)
      low, high, unit = row
      per = (use_high ? high : low).to_i
      next if per.zero?
      periods = unit.to_i.zero? ? 0 : days.to_i / unit.to_i
      pools[severity] = per * periods
    end
    return healed if pools.values.all?(&:zero?)
    apply_ability_heal_cascade(pools)
  end

  def empty_severity_map
    @severities.each_with_object({}) { |s, h| h[s] = 0 }
  end

  def worst_first
    @severities.reverse
  end

  def validate_severity_keys!(map)
    return unless map
    map.each_key do |key|
      key = key.to_s
      unless @severities.include?(key)
        raise ArgumentError, "Unrecognized severity category: #{key}"
      end
    end
  end

  def affliction_rule(name)
    (@conditions_config['Afflictions'] || {})[name]
  end

  def effect_name_entry(name)
    (@conditions_config['Effect Names'] || {})[name]
  end

  def apply_affliction_effect(effect_spec, net_magnitude, current_round)
    return nil if net_magnitude == 0
    case effect_spec['kind']
    when 'hit_point_damage'
      apply_hit_point_damage(effect_spec['severity'] => net_magnitude)
    when 'ability_damage'
      apply_ability_damage(effect_spec['attribute'], effect_spec['severity'], net_magnitude)
      { 'attribute' => effect_spec['attribute'], 'severity' => effect_spec['severity'], 'amount' => net_magnitude }
    when 'named_effect'
      raise ArgumentError, 'named_effect kind requires current_round' if current_round.nil?
      ends_on_round = current_round + [1, effect_spec['duration_rounds'].to_i].max
      apply_named_effect(effect_spec['name'], ends_on_round, "affliction:#{effect_spec['name']}")
    else
      raise ArgumentError, "Unknown affliction effect kind: #{effect_spec['kind']}"
    end
  end

  def resolve_tier_scaled_value(value, creature_tier)
    return value if value.is_a?(Numeric)
    if value.to_s == 'tier'
      return 0.5 if creature_tier.to_i == 0
      return creature_tier.to_i
    end
    raise ArgumentError, "Unrecognized tier-scaled value: #{value.inspect}"
  end

  # The Effect Names catalog uses `applies_to` as a list of free-form
  # scope tags; for the purposes of GET_MODIFIERS lookup we expose each
  # tag as its own target_key. When no `applies_to` is declared, the
  # mechanic is treated as a generic effect with target_key matching
  # the named-effect's own key (e.g. "paralyzed").
  def derive_target_key(mechanic)
    list = mechanic['applies_to']
    return Array(list).first.to_s if list && !Array(list).empty?
    mechanic['target_key'] || ''
  end

  def deep_copy(value)
    deep_copy_value(value)
  end

  def deep_copy_value(value)
    case value
    when Hash  then value.each_with_object({}) { |(k, v), h| h[k] = deep_copy_value(v) }
    when Array then value.map { |v| deep_copy_value(v) }
    else value
    end
  end
end
