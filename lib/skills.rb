# Skills — coordinator for Skill Roll inputs.
#
# The skills module owns the Skill catalog (`data/skills.yaml`)
# and the math that turns a Character's Skill Ranks plus Effective
# Attribute into the `[Dice Count, Competency Bonus, Starting
# Value]` triple a Skill Roll needs. It does not roll dice and
# does not store per-character rank data — those belong to
# DiceSystem and Advancement respectively.
#
# The single read API is `skill_details(skill_name, character,
# advancement)`. It looks up the Skill's Attribute (resolving
# Skill Set Members by prefix), asks Advancement for the
# Character's Skill Ranks, asks Character for the Effective
# Attribute, computes the Skill Prowess, and hands it to
# DiceSystem's `compute_check_details`. The result is wrapped
# with the Skill's name and the Competency Bonus folded into a
# `bonuses` hash keyed by the standard modifier names
# DiceSystem's `compute_roll_parameters` accepts.
#
# Versatile Performance is honored in `skill_details`: when the
# requested Skill matches one of the configured performances and
# the Character has the `versatile_performance` ability with that
# performance among its sub-choices, the Performance Skill is
# evaluated alongside the requested Skill and the higher Prowess
# wins. The returned hash always carries the requested Skill's
# name regardless of which side won.

require 'yaml'

class Skills
  DEFAULT_ATTRIBUTE_CONTRIBUTION_DIVISOR = 2
  DEFAULT_VERSATILE_PERFORMANCE_ABILITY  = 'versatile_performance'.freeze
  PERFORM_SET_KEY = 'perform_'.freeze

  attr_reader :skills_config

  def initialize(config_path: nil, config: nil, dice_system:)
    @skills_config = config || (config_path && File.exist?(config_path) ? YAML.load_file(config_path) : nil) || {}
    @dice_system   = dice_system
    @catalog       = @skills_config['skills'] || {}
    prowess_block  = @skills_config['skill_prowess'] || {}
    @attribute_contribution_divisor = (prowess_block['attribute_contribution_divisor'] || DEFAULT_ATTRIBUTE_CONTRIBUTION_DIVISOR).to_i
    vp_block = @skills_config['versatile_performance'] || {}
    @vp_ability_name = (vp_block['ability_name'] || DEFAULT_VERSATILE_PERFORMANCE_ABILITY).to_s
    @vp_performances = (vp_block['performances'] || {}).each_with_object({}) do |(perf, skills), h|
      h[perf.to_s] = Array(skills).map(&:to_s)
    end
    @vp_skill_to_performances = invert_performances(@vp_performances)
  end

  # The Attribute key (`str`/`dex`/`con`/`int`/`wis`/`cha`) for
  # the named Skill, with Skill Set Member prefix resolution. Raises
  # if the Skill (and any prefix Set) is unknown.
  def attribute_for(skill_name)
    definition = lookup(skill_name)
    raise ArgumentError, "Unknown skill: #{skill_name}" unless definition
    definition['attribute'].to_s
  end

  # Whether the named entry is a declared Skill Set (key ends in
  # `_` and `set: true`). Skill Sets cannot be rolled directly.
  def set?(skill_name)
    entry = @catalog[skill_name.to_s]
    entry.is_a?(Hash) && entry['set'] == true
  end

  # The roll-input bundle for `skill_name` against the given
  # Character and Advancement. Returns:
  #
  #   {
  #     'name'           => <skill_name as requested>,
  #     'ranks'          => <integer>,
  #     'prowess'        => <integer>,
  #     'dice_count'     => <integer>,
  #     'starting_value' => <signed integer>,
  #     'bonuses'        => { 'Competency Bonus' => <integer> }
  #   }
  #
  # When Versatile Performance applies and a chosen Performance
  # has a higher Prowess than the requested Skill, the returned
  # `ranks` / `prowess` / `dice_count` / `starting_value` /
  # `bonuses` come from the Performance — but `name` is always
  # the originally-requested Skill name.
  def skill_details(skill_name, character, advancement)
    skill_str = skill_name.to_s
    raise ArgumentError, "Cannot roll a Skill Set directly: #{skill_str}" if set?(skill_str)
    requested = compute_details(skill_str, character, advancement)
    best = requested

    versatile_candidates(skill_str, advancement).each do |performance_skill|
      candidate = compute_details(performance_skill, character, advancement)
      best = candidate if candidate['prowess'] > best['prowess']
    end

    best.merge('name' => skill_str)
  end

  private

  def compute_details(skill_name, character, advancement)
    attribute_key       = attribute_for(skill_name)
    attribute_value     = character.attribute(attribute_key)
    attribute_contrib   = floor_div(attribute_value, @attribute_contribution_divisor)
    ranks               = advancement.skill_ranks[skill_name].to_i
    prowess             = ranks + attribute_contrib
    check_details       = @dice_system.compute_check_details(prowess)

    bonuses = {}
    bonuses['Competency Bonus']   = check_details['competency_bonus']   if check_details['competency_bonus'].to_i.positive?
    bonuses['Competency Penalty'] = check_details['competency_penalty'] if check_details['competency_penalty'].to_i.positive?

    {
      'name'           => skill_name,
      'ranks'          => ranks,
      'prowess'        => prowess,
      'dice_count'     => check_details['dice_count'],
      'starting_value' => check_details['starting_value'],
      'bonuses'        => bonuses
    }
  end

  # Returns the list of `perform_<x>` Skills the character may
  # use to satisfy `skill_name` via Versatile Performance —
  # filtered to the performances the character has actually
  # chosen.
  def versatile_candidates(skill_name, advancement)
    performances = @vp_skill_to_performances[skill_name]
    return [] if performances.nil? || performances.empty?
    chosen = chosen_performances(advancement)
    return [] if chosen.empty?
    (performances & chosen).map { |p| "#{PERFORM_SET_KEY}#{p}" }
  end

  # Parses `Versatile Performance (Wind)` / `Versatile Performance
  # Wind` ability names from the character's ability list and
  # returns the lowercase performance keys. The hardcoded prefix
  # match keeps the lookup independent of the abilities catalog.
  def chosen_performances(advancement)
    abilities = advancement.respond_to?(:abilities) ? Array(advancement.abilities) : []
    abilities.each_with_object([]) do |ability, out|
      next unless ability.respond_to?(:name)
      raw = ability.name.to_s
      next unless raw.start_with?('Versatile Performance')
      remainder = raw.sub(/\AVersatile Performance/, '').strip
      next if remainder.empty?
      key = remainder.gsub(/[()]/, '').strip.downcase.gsub(/\s+/, '_')
      out << key unless key.empty?
    end
  end

  # Finds the Skill definition for `skill_name`, falling back to
  # the parent Skill Set when the name is a Set Member.
  def lookup(skill_name)
    name = skill_name.to_s
    return nil if name.empty?
    return @catalog[name] if @catalog[name].is_a?(Hash) && @catalog[name]['set'] != true
    # Set Member: scan declared Sets for a prefix match.
    @catalog.each do |key, entry|
      next unless entry.is_a?(Hash) && entry['set'] == true
      return entry if key.end_with?('_') && name.start_with?(key) && name != key
    end
    nil
  end

  def invert_performances(map)
    inverted = Hash.new { |h, k| h[k] = [] }
    map.each do |performance, skills|
      skills.each { |skill| inverted[skill] << performance }
    end
    inverted
  end

  def floor_div(numerator, divisor)
    return 0 if divisor.zero?
    (numerator.to_i.to_f / divisor).floor
  end
end
