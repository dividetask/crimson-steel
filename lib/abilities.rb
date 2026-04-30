require 'yaml'
require 'json'
require 'set'

# AbilitySystem — reference module for spells, ability entries, and
# class/racial procedural-ability triggers.
#
# Loads a config (Casting Time aliases, Range formulas, recognized
# Spell Schools / Item Forms / Properties / Save Attributes) and an
# entry data file (the compendium). Validates every entry on load.
# Reads return the data shape downstream consumers need without ever
# rolling dice or applying effects.
class AbilitySystem
  # Semantic constants tied to abilities-domain logic: the two
  # save conditions (on_fail / on_fumble) and the casting-time
  # "<N> rounds" parser. Adding to either requires a code
  # change, so they live here as constants. Area shapes, in
  # contrast, are a configurable list and come from the YAML.
  RECOGNIZED_SAVE_CONDITIONS = %w[on_fail on_fumble].freeze
  DEFAULT_REACH_FEET_KEY = 'Default Reach Feet'
  ROUND_REGEX = /\A(\d+(?:\.\d+)?)\s+rounds?\z/i

  attr_reader :abilities_config, :abilities_data

  def initialize(config_path:, data_path:, damage_types: nil)
    @abilities_config = YAML.load_file(config_path) || {}
    @abilities_data = load_entries(data_path)
    @damage_types = damage_types
    @evaluator = FormulaEvaluator.new
    @abilities_data.each { |name, entry| validate_entry!(name, entry) }
  end

  # ---------- Lookups ---------------------------------------------

  def list_entries(type_filter: nil, school_filter: nil)
    @abilities_data.select do |_name, entry|
      next false if type_filter && entry['type'] != type_filter.to_s
      next false if school_filter && entry['school'] != school_filter.to_s
      true
    end.keys
  end

  def get_entry(name)
    @abilities_data[name.to_s] || raise(ArgumentError, "Unknown entry: #{name}")
  end

  def is_item_only?(entry)
    entry['item_only'] == true
  end

  def get_casting_skills(entry)
    skills = Array(entry['skills']).map(&:to_s)
    return skills unless entry['type'] == 'spell'
    Array(@abilities_config['Universal Spell Casting Skills']).each do |universal|
      skills << universal.to_s unless skills.include?(universal.to_s)
    end
    skills
  end

  def valid_item_forms(entry)
    return [] unless entry['type'] == 'spell'
    explicit = Array(entry['items']).map(&:to_s)
    return explicit if entry['item_only'] == true
    forms = explicit.dup
    Array(@abilities_config['Universal Item Forms']).each do |universal|
      forms << universal.to_s unless forms.include?(universal.to_s)
    end
    forms
  end

  # ---------- Per-field resolvers ----------------------------------

  def resolve_casting_time(entry)
    casting_time = entry['casting_time'].to_s
    aliases = @abilities_config['Casting Time Aliases'] || {}
    return aliases[casting_time].to_f if aliases.key?(casting_time)
    if (m = casting_time.match(ROUND_REGEX))
      return m[1].to_f
    end
    raise ArgumentError, "Unrecognized casting time: #{casting_time}"
  end

  def resolve_range(entry, rank, reach: nil)
    value = entry['range']
    return value.to_i if value.is_a?(Numeric)
    raise ArgumentError, "Unrecognized range string: #{value}" unless (@abilities_config['Range Formulas'] || {}).key?(value)
    reach ||= @abilities_config[DEFAULT_REACH_FEET_KEY]
    formula = @abilities_config['Range Formulas'][value]
    @evaluator.eval(formula, 'rank' => rank, 'reach' => reach).floor
  end

  def resolve_target(entry, rank)
    target = entry['target']
    return 'self' if target == 'self'
    count = @evaluator.eval(target, 'rank' => rank).floor
    [0, count].max
  end

  # ---------- Variant resolution -----------------------------------

  def get_variant_name(entry_name, entry, axis_index = nil)
    if entry['tier'].is_a?(Array) || entry['aspects']
      if entry['name'].is_a?(Array)
        candidate = entry['name'][axis_index]
        return candidate if candidate && !candidate.empty?
      end
      parts = []
      if entry['prefix'].is_a?(Array)
        prefix = entry['prefix'][axis_index]
        parts << prefix if prefix && !prefix.empty?
      end
      parts << entry_name.to_s
      if entry['suffix'].is_a?(Array)
        suffix = entry['suffix'][axis_index]
        parts << suffix if suffix && !suffix.empty?
      end
      parts.join(' ')
    else
      entry_name.to_s
    end
  end

  def apply_variant_overrides(entry, axis_index)
    return entry unless axis_index
    overrides = entry['variant_overrides']
    return entry unless overrides.is_a?(Array)
    chosen = overrides[axis_index]
    return entry if chosen.nil?
    raise ArgumentError, 'variant_overrides entry must be hash or null' unless chosen.is_a?(Hash)
    merged = entry.dup
    chosen.each do |key, value|
      if value.nil?
        merged.delete(key)
      else
        merged[key] = value
      end
    end
    merged
  end

  def resolve_effect_hash(entry, axis_index, rank)
    resolved = {}
    context = { 'rank' => rank, 'tier' => tier_value_for(entry, axis_index) }
    Array(entry['effect_hash']&.to_a).each do |name, raw_value|
      value = raw_value
      if raw_value.is_a?(Array) && (entry['tier'].is_a?(Array) || entry['aspects'])
        value = raw_value[axis_index]
      end
      if value.is_a?(String)
        if value =~ /\b(success|critical|attribute)\b/
          # Defer evaluation: roll-result variables aren't known yet.
          # Leave the formula string in place for the caller to resolve.
        else
          value = @evaluator.eval(value, context)
        end
      end
      resolved[name.to_s] = value
      context[name.to_s] = value if value.is_a?(Numeric)
    end
    resolved
  end

  def resolve_entry(entry_name, rank, tier_index: nil, aspect_index: nil, reach: nil)
    raw = get_entry(entry_name)
    axis_index = tier_index || aspect_index
    entry = apply_variant_overrides(raw, axis_index)
    effect_hash = resolve_effect_hash(entry, axis_index, rank)
    description = substitute_tokens(entry['description'].to_s, effect_hash, raw, axis_index)

    {
      'name'                => get_variant_name(entry_name, raw, axis_index),
      'type'                => entry['type'],
      'school'              => entry['school'],
      'casting_time_rounds' => resolve_casting_time(entry),
      'casting_time_label'  => entry['casting_time'],
      'range_feet'          => resolve_range(entry, rank, reach: reach),
      'target'              => resolve_target(entry, rank),
      'area'                => entry['area'],
      'attack_roll'         => entry['attack_roll'] == true,
      'properties'          => Array(entry['properties']),
      'damage_type'         => damage_type_for(entry, axis_index),
      'effects'             => classify_effects(Array(entry['effects']), entry, axis_index, effect_hash, rank),
      'saves'               => classify_save_list(Array(entry['save']), entry, axis_index, effect_hash, rank),
      'duration'            => entry['duration'].to_s,
      'skills'              => get_casting_skills(entry),
      'items'               => valid_item_forms(entry),
      'item_only'           => is_item_only?(entry),
      'effect_hash'         => effect_hash,
      'description'         => description,
      'concentration'       => resolve_concentration(entry, axis_index, rank, effect_hash)
    }
  end

  # ---------- Damage evaluation -----------------------------------

  def evaluate_damage(effect, success_count, critical_count, attribute_value: 0)
    raise ArgumentError, 'evaluate_damage called on non-damage effect' unless effect['kind'] == 'damage'
    context = effect['context'].dup
    context['success']   = success_count
    context['critical']  = critical_count
    context['attribute'] = attribute_value || 0
    value = @evaluator.eval(effect['formula'], context).floor
    [0, value].max
  end

  # ---------- Procedural ability stubs -----------------------------

  # Returns the trigger spec list for a class/racial ability name, or
  # an empty array. The Procedural Abilities catalog is partial today;
  # missing names return [] rather than raising.
  def get_procedural_triggers(ability_name)
    catalog = @abilities_config['Procedural Abilities'] || {}
    Array((catalog[ability_name.to_s] || {})['triggers'])
  end

  # ---------- Cost lookups ----------------------------------------

  # Default mana cost for a spell at a given tier_index/aspect_index.
  # Reads the integer tier from the entry (not the 0.5-substituted
  # formula context) and looks up `Default Mana Cost Per Tier`.
  # Spells with override costs (per the spell description; not yet
  # a structured field) are the caller's concern to add on top.
  def default_mana_cost(spell_name, tier_index: nil, aspect_index: nil)
    entry = get_entry(spell_name)
    axis_index = tier_index || aspect_index
    integer_tier = integer_tier_for(entry, axis_index)
    table = @abilities_config['Default Mana Cost Per Tier'] || {}
    (table[integer_tier] || table[integer_tier.to_s] || 0).to_i
  end

  # Ritual material cost in gold for a spell at a given tier.
  def ritual_gold_cost(spell_name, tier_index: nil, aspect_index: nil)
    entry = get_entry(spell_name)
    axis_index = tier_index || aspect_index
    integer_tier = integer_tier_for(entry, axis_index)
    table = (@abilities_config.dig('Ritual Cost', 'gold_per_tier') || {})
    (table[integer_tier] || table[integer_tier.to_s] || 0).to_i
  end

  # Total casting time in rounds for casting the spell as a ritual.
  # Equals max(spell_casting_time_rounds, 1) + the per-tier ritual
  # additional casting time.
  def ritual_casting_time_rounds(spell_name, tier_index: nil, aspect_index: nil)
    entry = get_entry(spell_name)
    axis_index = tier_index || aspect_index
    integer_tier = integer_tier_for(entry, axis_index)
    base_rounds = [resolve_casting_time(entry).to_f, 1.0].max
    table = (@abilities_config.dig('Ritual Cost', 'casting_time_per_tier') || {})
    addition = (table[integer_tier] || table[integer_tier.to_s] || 0).to_f
    base_rounds + addition
  end

  private

  def load_entries(path)
    raw = if path.end_with?('.json')
            JSON.parse(File.read(path))
          else
            YAML.load_file(path)
          end
    raw || {}
  end

  def tier_value_for(entry, axis_index)
    tier = entry['tier']
    if tier.is_a?(Array)
      raw = tier[axis_index]
    else
      raw = tier
    end
    raw.to_i == 0 ? 0.5 : raw.to_i
  end

  # Like tier_value_for but returns the integer tier as declared in
  # the entry (no 0.5 substitution). Used by cost-table lookups
  # that key by the integer 0-5.
  def integer_tier_for(entry, axis_index)
    tier = entry['tier']
    return (tier.is_a?(Array) ? tier[axis_index] : tier).to_i
  end

  def damage_type_for(entry, axis_index)
    dt = entry['damage_type']
    return dt[axis_index] if dt.is_a?(Array)
    dt
  end

  def aspect_for(entry, axis_index)
    return nil unless entry['aspects']
    entry['aspects'][axis_index]
  end

  def substitute_tokens(text, effect_hash, entry, axis_index)
    result = text.dup
    effect_hash.each { |name, value| result.gsub!("{#{name}}", value.to_s) }
    aspect = aspect_for(entry, axis_index)
    result.gsub!('{aspect}', aspect.to_s) if aspect
    result
  end

  def classify_effects(list, entry, axis_index, effect_hash, rank)
    partial_context = build_partial_context(effect_hash, entry, axis_index, rank)
    damage_type = damage_type_for(entry, axis_index)
    list.map { |s| classify_effect(s, partial_context, damage_type) }
  end

  def classify_save_list(list, entry, axis_index, effect_hash, rank)
    partial_context = build_partial_context(effect_hash, entry, axis_index, rank)
    damage_type = damage_type_for(entry, axis_index)
    list.map do |spec|
      resolved = { 'attribute' => spec['attribute'] }
      resolved['condition'] = spec['condition'] if spec.key?('condition')
      Array(@abilities_config['Save Outcome Keys']).each do |key|
        next unless spec.key?(key)
        resolved[key] = classify_effect(spec[key], partial_context, damage_type)
      end
      resolved
    end
  end

  def build_partial_context(effect_hash, entry, axis_index, rank)
    ctx = effect_hash.dup
    ctx['rank'] = rank
    ctx['tier'] = tier_value_for(entry, axis_index)
    ctx
  end

  DAMAGE_REGEX = /\A(.+?)\s+(?:(minor|moderate|major)\s+)?damage\z/

  def classify_effect(effect, partial_context, damage_type)
    s = effect.to_s.strip
    return { 'kind' => 'none' } if s == '0' || s == 'none'
    if (m = s.match(DAMAGE_REGEX))
      formula = m[1].strip
      severity = m[2]
      return {
        'kind'        => 'damage',
        'formula'     => formula,
        'severity'    => severity,
        'damage_type' => damage_type,
        'context'     => partial_context.dup
      }
    end
    { 'kind' => 'effect', 'name' => s }
  end

  def resolve_concentration(entry, axis_index, rank, _entry_effect_hash)
    block = entry['concentration']
    return nil unless block.is_a?(Hash)
    inner_effect_hash = resolve_effect_hash(
      { 'tier' => entry['tier'], 'effect_hash' => block['effect_hash'], 'aspects' => entry['aspects'] },
      axis_index,
      rank
    )
    partial_context = inner_effect_hash.dup
    partial_context['rank'] = rank
    partial_context['tier'] = tier_value_for(entry, axis_index)
    damage_type = damage_type_for(entry, axis_index)
    saves = Array(block['save']).map do |spec|
      resolved = { 'attribute' => spec['attribute'] }
      resolved['condition'] = spec['condition'] if spec.key?('condition')
      Array(@abilities_config['Save Outcome Keys']).each do |key|
        next unless spec.key?(key)
        resolved[key] = classify_effect(spec[key], partial_context, damage_type)
      end
      resolved
    end
    description = substitute_tokens((block['description'] || '').to_s, inner_effect_hash, entry, axis_index)
    {
      'action'         => block['action'],
      'action_rounds'  => resolve_casting_time({ 'casting_time' => block['action'] }),
      'apply_on_cast'  => block['apply_on_cast'] == true,
      'retarget'       => block['retarget'] == true,
      'attack_roll'    => block['attack_roll'] == true,
      'saves'          => saves,
      'effect_hash'    => inner_effect_hash,
      'description'    => description
    }
  end

  # ---------- Validation ------------------------------------------

  def validate_entry!(entry_name, entry)
    types = Array(@abilities_config['Entry Types'])
    types = %w[spell ability] if types.empty?
    raise ArgumentError, "Unrecognized entry type in #{entry_name}: #{entry['type']}" unless types.include?(entry['type'])

    if entry['type'] == 'spell'
      validate_in_list!(entry_name, 'school', entry['school'], @abilities_config['Spell Schools'])
      Array(entry['items']).each do |form|
        validate_in_list!(entry_name, 'items', form, @abilities_config['Item Forms'])
        if Array(@abilities_config['Universal Item Forms']).include?(form)
          raise ArgumentError, "#{entry_name}: universal item form #{form} must not be listed explicitly"
        end
      end
    end

    Array(entry['skills']).each do |skill|
      validate_in_list!(entry_name, 'skills', skill, @abilities_config['Casting Skills List'])
      if Array(@abilities_config['Universal Spell Casting Skills']).include?(skill)
        raise ArgumentError, "#{entry_name}: universal casting skill #{skill} must not be listed explicitly"
      end
    end

    casting_time = entry['casting_time'].to_s
    aliases = @abilities_config['Casting Time Aliases'] || {}
    unless aliases.key?(casting_time) || casting_time =~ ROUND_REGEX
      raise ArgumentError, "#{entry_name}: unrecognized casting time #{casting_time.inspect}"
    end

    range = entry['range']
    if range.is_a?(String)
      validate_in_list!(entry_name, 'range', range, @abilities_config['Range Formulas'])
    elsif !range.is_a?(Numeric) || range.to_i < 0
      raise ArgumentError, "#{entry_name}: range must be a named Range or non-negative integer"
    end

    if entry['area']
      area = entry['area']
      raise ArgumentError, "#{entry_name}: area must be a hash" unless area.is_a?(Hash)
      shapes = @abilities_config['Area Shapes']
      raise ArgumentError, 'abilities config missing Area Shapes' unless shapes
      shapes = shapes.respond_to?(:keys) ? shapes.keys : shapes
      raise ArgumentError, "#{entry_name}: unrecognized area shape" unless shapes.include?(area['shape'])
      raise ArgumentError, "#{entry_name}: area size must be a non-negative integer" unless area['size'].is_a?(Numeric) && area['size'].to_i >= 0
    end

    if entry.key?('attack_roll') && ![true, false].include?(entry['attack_roll'])
      raise ArgumentError, "#{entry_name}: attack_roll must be a boolean"
    end

    Array(entry['properties']).each do |property|
      validate_in_list!(entry_name, 'properties', property, @abilities_config['Properties'])
    end

    if entry.key?('damage_type') && entry['damage_type'] && @damage_types
      Array(entry['damage_type']).flatten.each do |dt|
        next if dt.nil?
        raise ArgumentError, "#{entry_name}: unknown damage_type #{dt}" unless @damage_types.known?(dt)
      end
    end

    Array(entry['save']).each { |spec| validate_save_spec!(entry_name, spec) }

    validate_axis!(entry_name, entry)
    validate_concentration!(entry_name, entry['concentration']) if entry['concentration']
  end

  def validate_save_spec!(entry_name, spec)
    attrs = Array(@abilities_config['Save Attributes List'])
    raise ArgumentError, "#{entry_name}: unknown save attribute" unless attrs.include?(spec['attribute'])
    # attribute: none is shorthand for "no save"; skip the fail-required rule.
    unless spec['attribute'] == 'none'
      raise ArgumentError, "#{entry_name}: save spec missing fail" unless spec.key?('fail')
    end
    spec.each_key do |key|
      next if %w[attribute condition].include?(key)
      next if Array(@abilities_config['Save Outcome Keys']).include?(key)
      raise ArgumentError, "#{entry_name}: unknown save outcome key #{key}"
    end
    if spec.key?('condition') && !RECOGNIZED_SAVE_CONDITIONS.include?(spec['condition'])
      raise ArgumentError, "#{entry_name}: unrecognized save condition #{spec['condition']}"
    end
  end

  def validate_axis!(entry_name, entry)
    has_tier_list = entry['tier'].is_a?(Array)
    has_aspects   = entry['aspects'].is_a?(Array)
    if has_tier_list && has_aspects
      raise ArgumentError, "#{entry_name}: cannot declare both tier list and aspects"
    end
    return unless has_tier_list || has_aspects

    axis_length = (has_tier_list ? entry['tier'] : entry['aspects']).length
    %w[prefix suffix name variant_overrides].each do |field|
      next unless entry.key?(field)
      list = entry[field]
      next unless list.is_a?(Array)
      if list.length != axis_length
        raise ArgumentError, "#{entry_name}: #{field} length #{list.length} doesn't match axis length #{axis_length}"
      end
    end

    Array(entry['variant_overrides']).each do |override|
      next if override.nil?
      raise ArgumentError, "#{entry_name}: variant_overrides entry must be hash or null" unless override.is_a?(Hash)
      override.each_key do |key|
        next unless %w[tier aspects prefix suffix name variant_overrides].include?(key)
        raise ArgumentError, "#{entry_name}: variant_overrides may not override #{key}"
      end
    end
  end

  def validate_concentration!(entry_name, block)
    raise ArgumentError, "#{entry_name}: concentration missing action" unless block.key?('action')
    aliases = @abilities_config['Casting Time Aliases'] || {}
    unless aliases.key?(block['action']) || block['action'].to_s =~ ROUND_REGEX
      raise ArgumentError, "#{entry_name}: unrecognized concentration action"
    end
    %w[apply_on_cast retarget attack_roll].each do |bool_key|
      next unless block.key?(bool_key)
      raise ArgumentError, "#{entry_name}: concentration #{bool_key} must be a boolean" unless [true, false].include?(block[bool_key])
    end
    Array(block['save']).each { |spec| validate_save_spec!(entry_name, spec) }
  end

  def validate_in_list!(entry_name, field, value, list)
    list = list.respond_to?(:keys) ? list.keys : Array(list)
    raise ArgumentError, "#{entry_name}: unknown #{field} #{value.inspect}" unless list.include?(value)
  end
end

# Internal helper. Substitutes named variables, then evaluates the
# arithmetic expression. Supports +, -, *, /, parentheses, and a
# floor() function. Variable names not in the supplied context raise.
class FormulaEvaluator
  SAFE_REGEX = /\A[\d\s\.+\-*\/(),floor]+\z/

  def eval(expression, context)
    return expression if expression.is_a?(Numeric)
    expr = expression.to_s.dup
    context.keys.sort_by { |k| -k.to_s.length }.each do |name|
      expr.gsub!(/\b#{Regexp.escape(name.to_s)}\b/) { context[name].to_f.to_s }
    end
    if expr =~ /\b[a-z_][a-z0-9_]*\b/i && !expr.gsub('floor', '').match?(/\b[a-z_][a-z0-9_]*\b/i)
      # Only `floor` references remain.
    elsif expr =~ /\b[a-z_][a-z0-9_]*\b/i
      stripped = expr.gsub('floor', '')
      if stripped =~ /\b([a-z_][a-z0-9_]*)\b/i
        raise ArgumentError, "Unresolved name in formula: #{Regexp.last_match(1)} (from #{expression.inspect})"
      end
    end
    raise ArgumentError, "Unsafe formula: #{expression}" unless expr =~ SAFE_REGEX
    safe_eval(expr)
  end

  private

  def safe_eval(expr)
    # `floor(x)` becomes `(x).floor` so Ruby evaluates it correctly.
    expr = expr.gsub(/floor\(([^()]*(?:\([^()]*\)[^()]*)*)\)/) { "(#{Regexp.last_match(1)}).floor" }
    Kernel.eval(expr)
  end
end
