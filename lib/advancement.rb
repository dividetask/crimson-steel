# Advancement — tracks a character's classes (with their levels
# and chosen class skills), tier, and tier-up choices, and reports
# the bonuses those grant.
#
# Character holds the *base* attribute scores. When something
# asks "what's this character's strength?" Character delegates
# to its Advancement to find out how much the character's tier
# adds on top. Each tier grants two attribute-side adjustments:
# a flat bonus applied to every attribute, and a focused bonus
# applied to a small number of attributes the player picks at
# each tier-up. Both come from advancement.yaml's tier rules.
#
# Tier itself is auto-computed from the character's total class
# levels via the breakpoint list for their `type`
# (`player_character`, `boss`, `noble`, `common`, …) — but a
# character may set an explicit `tier:` override in their YAML
# and that always wins.
#
# Ability granting works per-class. Each class lists abilities
# with a `min_level` (defaults to 1) and an optional
# `scales_with_level` flag. When a character qualifies for a
# scaling ability the ability's effective level is the *sum*
# of their levels across every class that grants it; non-scaling
# abilities are simply present or absent.
#
# Archetypes are modeled as classes with a `parent_class` field.
# A character's levels in an archetype also count toward the
# parent class's abilities and grant the parent's class skills
# and saves.
#
# Skills and saves likewise advance per class via the
# class-skill / opposed-skill / neither rate scheme. See
# `skill_ranks` and `save_ranks` for details.

require 'yaml'

class Advancement
  DEFAULT_ATTRIBUTE_BONUS_PER_TIER = 1
  DEFAULT_MIN_LEVEL                = 1
  DEFAULT_CHARACTER_TYPE           = 'player_character'.freeze

  Ability = Struct.new(:name, :level, :sub_choices, keyword_init: true) do
    # `level` is nil for non-scaling abilities.
    def scales?
      !level.nil?
    end

    # Per-grant choices the player picked for this ability (e.g.
    # the chosen performances for Versatile Performance). Always
    # an array — defaults to empty when the character entry has no
    # choices recorded.
    def sub_choices
      self[:sub_choices] || []
    end
  end

  attr_reader :character_type, :class_levels, :class_skill_choices, :tier_attribute_advancement,
              :ability_sub_choices

  def initialize(
    tier: nil,
    character_type: DEFAULT_CHARACTER_TYPE,
    class_levels: {},
    class_skill_choices: {},
    tier_attribute_advancement: [],
    attribute_bonus_per_tier: DEFAULT_ATTRIBUTE_BONUS_PER_TIER,
    focused_attribute_bonus_per_tier: [],
    focused_attribute_count: 0,
    tier_advancement: {},
    class_definitions: {},
    skill_definitions: {},
    ability_sub_choices: {}
  )
    @tier_override                    = tier.nil? ? nil : tier.to_i
    @character_type                   = character_type.to_s
    @class_levels                     = normalize_class_levels(class_levels)
    @class_skill_choices              = normalize_skill_choices(class_skill_choices)
    @tier_attribute_advancement       = Array(tier_attribute_advancement).map(&:to_s)
    @attribute_bonus_per_tier         = attribute_bonus_per_tier
    @focused_attribute_bonus_per_tier = Array(focused_attribute_bonus_per_tier).map(&:to_i)
    @focused_attribute_count          = focused_attribute_count.to_i
    @tier_advancement                 = tier_advancement || {}
    @class_definitions                = class_definitions || {}
    @skill_definitions                = skill_definitions || {}
    @ability_sub_choices              = normalize_ability_sub_choices(ability_sub_choices)
  end

  # The character's current tier. Returns the explicit override
  # if one was set; otherwise computes it from total class level
  # via the breakpoint list for their character type.
  def tier
    return @tier_override if @tier_override
    breakpoints = tier_breakpoints
    return 0 if breakpoints.empty?
    total = @class_levels.values.sum
    breakpoints.count { |bp| total >= bp.to_i }
  end

  # True iff the tier value came from an explicit override.
  def tier_overridden?
    !@tier_override.nil?
  end

  # The classes the character has at least one level in.
  def character_classes
    @class_levels.keys
  end

  def class_level(klass)
    @class_levels[klass.to_s].to_i
  end

  # Skills the character has chosen to advance under the given
  # class. Returns [] if the class is unknown or no skills are
  # tracked.
  def chosen_skills_for(klass)
    Array(@class_skill_choices[klass.to_s])
  end

  # Bonus to add to the named attribute on top of the base score.
  # The bonus combines the cumulative flat per-tier bonus with
  # any focused bonuses earned by picking this attribute at one
  # or more tier-ups.
  def attribute_bonus(attr_sym)
    current_tier = tier
    return 0 if current_tier <= 0
    flat_attribute_bonus(current_tier) + focused_attribute_bonus(attr_sym, current_tier)
  end

  # All abilities the character has earned, as Ability structs.
  # Scaling abilities carry their effective level (the sum of
  # qualifying class levels across every class that grants them);
  # non-scaling abilities carry a nil level.
  def abilities
    granted = {} # name => { level: Integer|nil, scales: Boolean }

    @class_levels.each do |klass, level|
      next if level <= 0
      classes_in_chain(klass).each do |chain_klass|
        Array(class_ability_defs(chain_klass)).each do |ability_def|
          name = ability_def['name']
          next if name.nil?
          min_level = (ability_def['min_level'] || DEFAULT_MIN_LEVEL).to_i
          next if level < min_level

          scales = ability_def['scales_with_level'] ? true : false
          slot   = granted[name] ||= { level: nil, scales: false }
          if scales
            slot[:scales] = true
            slot[:level]  = (slot[:level] || 0) + level
          end
        end
      end
    end

    granted.map do |name, info|
      Ability.new(
        name:        name,
        level:       info[:scales] ? info[:level] : nil,
        sub_choices: Array(@ability_sub_choices[name]).dup
      )
    end
  end

  # Skill name => rank. A skill is contributed to by a class when
  # the character chose it under that class, or when it's flagged
  # `mandatory: true` in the skill definitions (so every class
  # contributes regardless of the chosen list — that's how martial
  # works). A class's contribution depends on how it categorizes
  # the skill:
  #
  #   class skill   floor(5 * class_level / 3)
  #   non-class     class_level                  (the "average" rate)
  #   opposed       floor(2 * class_level / 3)
  #
  # See `skill_category_for_class` for how the category is
  # decided. Skill sets match by prefix: a chosen `perform_dance`
  # qualifies under a class_skill entry of `perform_`.
  def skill_ranks
    ranks = Hash.new(0)
    auto  = mandatory_skills

    @class_levels.each do |klass, level|
      next if level <= 0
      contributing = (chosen_skills_for(klass) | auto)
      contributing.each do |skill|
        ranks[skill] += rank_contribution(klass, skill, level)
      end
    end
    ranks
  end

  # Save attribute => rank. Every save attribute is treated as a
  # mandatory skill: a class contributes the class-skill rate if
  # it specializes in that save (its `saves` list, including any
  # inherited from parent_class), otherwise the opposed-skill
  # rate.
  def save_ranks
    ranks = Hash.new(0)
    Character::ATTRIBUTE_KEYS.each do |attr|
      key = attr.to_s
      @class_levels.each do |klass, level|
        next if level <= 0
        ranks[key] += if class_save_attributes(klass).include?(key)
                        class_skill_rate(level)
                      else
                        opposed_skill_rate(level)
                      end
      end
    end
    ranks
  end

  # Build an Advancement from a character entry's `advancement`
  # subhash plus the loaded rules and class definitions. The
  # character's `type` (selecting which tier-advancement
  # breakpoint list to use) is passed in separately because it
  # lives at the character level, not under `advancement:`.
  def self.from_entry(entry, type: nil, rules: {}, class_definitions: {}, skill_definitions: {})
    entry ||= {}
    rules ||= {}
    classes_block = entry['classes'] || {}
    levels, skills = split_classes_block(classes_block)
    new(
      tier:                             entry['tier'],
      character_type:                   type || DEFAULT_CHARACTER_TYPE,
      class_levels:                     levels,
      class_skill_choices:              skills,
      tier_attribute_advancement:       entry['tier_attribute_advancement'] || [],
      attribute_bonus_per_tier:         rules.fetch('attribute_bonus_per_tier', DEFAULT_ATTRIBUTE_BONUS_PER_TIER),
      focused_attribute_bonus_per_tier: rules['focused_attribute_bonus_per_tier'] || [],
      focused_attribute_count:          rules['focused_attribute_count'] || 0,
      tier_advancement:                 rules['tier_advancement'] || {},
      class_definitions:                class_definitions,
      skill_definitions:                skill_definitions,
      ability_sub_choices:              extract_ability_sub_choices(entry)
    )
  end

  # Pulls per-ability sub-choices off a character's `advancement`
  # entry. Today only `versatile_performance` is recognized — the
  # entry's `versatile_performance:` key is a list of chosen
  # performance keys (one per grant). Future abilities with their
  # own sub-choices register here without changing the entry shape.
  def self.extract_ability_sub_choices(entry)
    out = {}
    list = entry['versatile_performance'] || entry[:versatile_performance]
    out['versatile_performance'] = Array(list).map(&:to_s) if list
    out
  end

  # Loads the combined advancement file. Returns:
  #   { 'rules' => Hash, 'classes' => Hash }
  # Each class's `abilities` list is normalized — any sticky
  # context entries are flattened so every entry in the resulting
  # list is `{ 'name' => ..., 'min_level' => ..., ... }`.
  def self.load_config(path)
    return { 'rules' => {}, 'classes' => {} } unless path && File.exist?(path)
    data    = YAML.safe_load_file(path) || {}
    classes = data.delete('classes') || {}
    classes = classes.each_with_object({}) do |(key, definition), out|
      out[key] = definition ? definition.merge('abilities' => normalize_abilities_list(definition['abilities'])) : definition
    end
    { 'rules' => data, 'classes' => classes }
  end

  # Loads the skill list. Returns a hash keyed by skill name.
  def self.load_skills(path)
    return {} unless path && File.exist?(path)
    data = YAML.safe_load_file(path) || {}
    data['skills'] || {}
  end

  # Walks a list of ability entries, applying sticky context
  # entries (entries without a `name`) to every following ability
  # entry until the next context entry. Only `min_level` is sticky
  # — every other field (notably `scales_with_level`) is treated
  # as per-ability and must be set on the ability entry itself.
  def self.normalize_abilities_list(raw)
    context = {}
    Array(raw).each_with_object([]) do |entry, out|
      next unless entry.is_a?(Hash)
      string_keyed = entry.transform_keys(&:to_s)
      if string_keyed.key?('name')
        out << context.merge(string_keyed)
      else
        context = context.merge(string_keyed.slice('min_level'))
      end
    end
  end

  # Splits a characters.yaml `classes:` block into a level map
  # and a chosen-skills map. The block may mix shorthand integer
  # entries with hash entries that carry both `level` and `skills`.
  def self.split_classes_block(block)
    levels = {}
    skills = {}
    return [levels, skills] unless block.is_a?(Hash)
    block.each do |klass, value|
      key = klass.to_s
      case value
      when Integer
        levels[key] = value
      when Hash
        levels[key] = (value['level'] || value[:level] || 0).to_i
        chosen      = value['skills'] || value[:skills]
        skills[key] = Array(chosen).map(&:to_s) if chosen
      end
    end
    [levels, skills]
  end

  private

  def normalize_class_levels(input)
    case input
    when Hash
      input.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_i }
    when Array
      input.each_with_object({}) { |k, h| h[k.to_s] = 1 }
    else
      {}
    end
  end

  def normalize_skill_choices(input)
    return {} unless input.is_a?(Hash)
    input.each_with_object({}) { |(k, v), h| h[k.to_s] = Array(v).map(&:to_s) }
  end

  def normalize_ability_sub_choices(input)
    return {} unless input.is_a?(Hash)
    input.each_with_object({}) { |(k, v), h| h[k.to_s] = Array(v).map(&:to_s) }
  end

  def tier_breakpoints
    return [] unless @tier_advancement.is_a?(Hash)
    list = @tier_advancement[@character_type] || @tier_advancement[DEFAULT_CHARACTER_TYPE]
    Array(list)
  end

  def flat_attribute_bonus(tier)
    list = @attribute_bonus_per_tier
    if list.is_a?(Array)
      list.first(tier).map(&:to_i).sum
    else
      list.to_i * tier
    end
  end

  def focused_attribute_bonus(attr_sym, tier)
    return 0 if tier < 2 || @focused_attribute_count <= 0 || @tier_attribute_advancement.empty?
    attr_str = attr_sym.to_s
    total    = 0
    (2..tier).each do |t|
      bonus = focused_bonus_at(t)
      next if bonus.zero?
      picks_start = (t - 2) * @focused_attribute_count
      tier_picks  = @tier_attribute_advancement[picks_start, @focused_attribute_count] || []
      total += tier_picks.count(attr_str) * bonus
    end
    total
  end

  def focused_bonus_at(tier)
    (@focused_attribute_bonus_per_tier[tier - 1] || 0).to_i
  end

  def class_definition(klass)
    @class_definitions[klass] || @class_definitions[klass.to_s] || @class_definitions[klass.to_sym] || {}
  end

  def class_ability_defs(klass)
    class_definition(klass)['abilities'] || []
  end

  # Yields the class itself plus each ancestor (via parent_class)
  # in order. Cycles are guarded against to keep mistuned data
  # from looping forever.
  def classes_in_chain(klass)
    chain = []
    seen  = {}
    cursor = klass.to_s
    while cursor && !seen[cursor]
      seen[cursor] = true
      chain << cursor
      parent = class_definition(cursor)['parent_class']
      cursor = parent ? parent.to_s : nil
    end
    chain
  end

  # Save attributes (as strings) the class specializes in,
  # including those inherited from parent classes.
  def class_save_attributes(klass)
    classes_in_chain(klass).flat_map { |c| Array(class_definition(c)['saves']).map(&:to_s) }.uniq
  end

  # Names of skills flagged mandatory in the loaded skill
  # definitions.
  def mandatory_skills
    @skill_definitions.each_with_object([]) do |(name, definition), out|
      out << name.to_s if definition.is_a?(Hash) && definition['mandatory']
    end
  end

  def rank_contribution(klass, skill, level)
    case skill_category_for_class(klass, skill)
    when :class   then class_skill_rate(level)
    when :opposed then opposed_skill_rate(level)
    else               level # :average
    end
  end

  def class_skill_rate(level)
    (5 * level) / 3
  end

  def opposed_skill_rate(level)
    (2 * level) / 3
  end

  # Returns :class, :average, or :opposed for the given skill in
  # the context of `klass` (and its parent_class chain).
  #
  # Each class has up to three explicit skill lists in its
  # definition: `class_skills` (faster), `non_class_skills`
  # (average), and `opposed_skills` (slower). Skill sets are
  # matched by prefix — a chosen `perform_dance` falls under a
  # class_skill entry of `perform_`. The chain is walked first
  # for any explicit match.
  #
  # If no class in the chain mentions the skill explicitly, the
  # category falls through to the *default* rate for the class
  # the character actually has levels in:
  #   * if its definition declares `class_skills` (even an empty
  #     list), the default is :average
  #   * if it omits `class_skills` entirely, the default is
  #     :class — i.e. the class trains "everything not listed
  #     elsewhere" at the fast rate.
  def skill_category_for_class(klass, skill)
    skill_str = skill.to_s
    classes_in_chain(klass).each do |chain_klass|
      definition = class_definition(chain_klass)
      return :opposed if list_matches_skill?(definition['opposed_skills'],   skill_str)
      return :class   if list_matches_skill?(definition['class_skills'],     skill_str)
      return :average if list_matches_skill?(definition['non_class_skills'], skill_str)
    end
    default_skill_category(klass)
  end

  def default_skill_category(klass)
    definition = class_definition(klass)
    return :average if definition.key?('class_skills') || definition.key?(:class_skills)
    :class
  end

  def list_matches_skill?(list, skill)
    Array(list).any? do |entry|
      entry_str = entry.to_s
      entry_str == skill ||
        (entry_str.end_with?('_') && skill.start_with?(entry_str) && skill != entry_str)
    end
  end
end
