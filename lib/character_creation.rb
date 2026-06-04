require 'yaml'
require 'creatures'
require 'abilities'
require 'proficiencies'

# Character Creation domain — backs the DM's "New Character" wizard
# (the Character Creation Stub) reached from the Character Sheets
# roster. A freshly created Creature is a level-1 (Tier 0) Player
# Character.
#
# This module is the single source of truth for the wizard:
#   - `blob` assembles every catalog the browser needs (attribute
#     allocation rules, races, classes, per-class skill groupings and
#     spell-selection rules) so the client-side flow runs without
#     further round-trips.
#   - `create!` validates an assembled character and persists it through
#     the Creatures domain.
#
# Attribute Allocation rules come from
# `docs/common/creatures/character_creation.yaml`; per-Class Spell
# Selection rules live on each Class in `creatures_advancement.yaml`.
module CharacterCreation
  CONFIG_PATH = File.expand_path(
    '../docs/common/creatures/character_creation.yaml', __dir__
  )
  # A new Player Character starts at level 1 / Tier 0.
  CREATION_LEVEL = 1
  CREATION_TIER  = 0
  # New PCs persist to the Player Character data file (data/ overlay).
  PC_SOURCE = 'creatures_data_pcs.yaml'.freeze

  module_function

  def config
    @config ||= YAML.safe_load_file(CONFIG_PATH) || {}
  end

  def reset!
    @config = nil
  end

  # Attribute Allocation (Point Buy) rules, normalized to integers.
  def attribute_allocation
    a = config['Attribute Allocation'] || {}
    {
      starting: Integer(a['starting_value'] || 10),
      pool:     Integer(a['point_buy'] || 0),
      min:      Integer(a['minimum'] || 7),
      max:      Integer(a['maximum'] || 18),
      cost:     (a['cost'] || {}).each_with_object({}) { |(k, v), h| h[Integer(k)] = Integer(v) }
    }
  end

  def attribute_keys
    Creatures::Config.attribute_keys.map(&:to_s)
  end

  # The full data blob handed to the Character Creation page.
  def blob
    {
      create_url:           '/character-creation',
      level:                CREATION_LEVEL,
      attributes:           attribute_keys,
      attribute_allocation: attribute_allocation,
      # Every attribute gains this inherent bonus at the creation Tier;
      # the browser folds it into Effective Attributes (so the Skill Pick
      # count, floor(int / 4) + bonus_skills, matches the saved Creature).
      inherent_bonus:       inherent_bonus,
      races:                races,
      classes:              classes,
      skill_catalog:        skill_catalog
    }
  end

  # The Tier a fresh level-1 Player Character resolves to (Get Tier on
  # the player_character breakpoints), and the inherent attribute bonus
  # granted at that Tier.
  def creation_tier
    bps = Creatures::Advancement.breakpoints['player_character'] || [0]
    (0...bps.length).select { |i| Integer(bps[i]) <= CREATION_LEVEL }.max || 0
  end

  def inherent_bonus
    Integer(Creatures::Config.tier_minimum_inherent_bonus[creation_tier] || 0)
  end

  # ---- Races ----------------------------------------------------------

  # The playable races offered at creation (config order). Abstract
  # parent/root races are never selectable — they only carry shared
  # attributes down their chains.
  def playable_race_keys
    Array(config['Playable Races']).map(&:to_s).select { |k| Creatures::Races.known?(k) }
  end

  def playable_race?(key)
    playable_race_keys.include?(key.to_s)
  end

  def races
    playable_race_keys.map { |key| race_entry(key) }
  end

  def race_entry(key)
    resolved = Creatures::Races.look_up(key) || {}
    {
      key:         key,
      label:       humanize(key),
      chain:       Creatures::Races.chain_summary(key),
      size:        resolved[:size],
      speed:       resolved[:speed],
      adjustments: (resolved[:attribute_adjustments] || {}).transform_keys(&:to_s),
      abilities:   Array(resolved[:abilities]).map { |a| humanize(a[:name]) }
    }
  end

  # ---- Classes --------------------------------------------------------

  def classes
    Creatures::Advancement.classes.keys.map { |key| class_entry(key) }
  end

  def class_entry(key)
    cls = Creatures::Advancement.look_up_class(key) || {}
    {
      key:            key,
      label:          humanize(key),
      bonus_skills:   Integer(cls['bonus_skills'] || 0),
      mana_per_level: Integer(cls['mana_per_level'] || 0),
      martial:        cls['martial_advancement'],
      saves: {
        aligned: Array(cls.dig('saves', 'aligned')).map(&:to_s),
        opposed: Array(cls.dig('saves', 'opposed')).map(&:to_s)
      },
      abilities:       level_one_abilities(cls).map { |a| humanize(a) },
      skill_groups:    skill_groups(key),
      spell_selection: spell_selection_blob(cls)
    }
  end

  # Abilities a Class grants by its creation level.
  def level_one_abilities(cls)
    prog = cls['ability_progression'] || {}
    prog.select { |lvl, _| lvl.to_i <= CREATION_LEVEL }.values.flatten
  end

  # Categorize every Skill in the catalog into the Class's Aligned /
  # Unaligned / Opposed groups (Proficiencies' Skill Rate Resolution).
  def skill_groups(class_key)
    groups = { aligned: [], unaligned: [], opposed: [] }
    Proficiencies.skills.each_key do |skill_key|
      cat = Proficiencies::Ranks.skill_rate(class_key, skill_key, trained: true)
      groups[cat] << skill_key if cat && groups.key?(cat)
    end
    groups
  end

  # Display metadata for every Skill key, keyed by the catalog key.
  def skill_catalog
    Proficiencies.skills.each_with_object({}) do |(key, entry), h|
      h[key] = {
        label:       humanize(key.to_s.chomp('_')),
        attribute:   entry['attribute'],
        set:         key.to_s.end_with?('_'),
        description: entry['description']
      }
    end
  end

  # ---- Spell Selection ------------------------------------------------

  # Resolve a Class's spell_selection block into the client view. Returns
  # nil for non-casters and for `auto` casters (no pick → step skipped).
  def spell_selection_blob(cls)
    sel = cls['spell_selection']
    return nil unless sel

    case sel['mode']
    when 'domain'
      { mode: 'domain', deities: deities_blob }
    when 'count'
      { mode: 'count', budget: eval_budget(sel['budget']),
        spells: spell_pool(sel['filter']) }
    when 'points'
      { mode: 'points', budget: eval_budget(sel['budget']),
        spells: spell_pool(sel['filter'], cost_expr: sel['cost']) }
    else
      # `auto` (and any unknown mode): nothing to pick.
      nil
    end
  end

  # Catalog spells matching `filter`, sorted by Tier then name. When a
  # `cost_expr` is given (points mode) each entry carries its cost.
  def spell_pool(filter, cost_expr: nil)
    pool = []
    Abilities.catalog.catalog.each do |name, entry|
      next unless entry['type'] == 'spell'
      skills = Array(entry['skills'])
      skills = ['arcana'] if skills.empty? # catalog default per spells.yaml
      next unless spell_matches?(skills, filter)

      tier = base_tier(entry['tier'])
      item = { key: name, label: name, tier: tier }
      # Cost is floored to an integer: a Tier 0 spell costs 1, not 1.5.
      item[:cost] = Creatures::Formula.eval(cost_expr, tier: formula_tier(tier)).floor if cost_expr
      pool << item
    end
    pool.sort_by { |s| [s[:tier], s[:label]] }
  end

  def spell_matches?(skills, filter)
    return true if filter.nil? || filter.to_s == 'any'
    skills.any? { |s| s.to_s.start_with?(filter.to_s) }
  end

  # Lowest Tier a spell can be learned at (scalar tier, or the minimum of
  # a Tier-axis array).
  def base_tier(tier)
    return 0 if tier.nil?
    tier.is_a?(Array) ? tier.map(&:to_i).min : tier.to_i
  end

  # Tier 0 is treated as 0.5 in all formulas (project convention).
  def formula_tier(tier)
    tier.zero? ? 0.5 : tier
  end

  def eval_budget(expr)
    Creatures::Formula.eval(expr, level: CREATION_LEVEL)
  end

  def deities_blob
    Creatures::Deities.deities.map do |dname, d|
      {
        name: dname,
        domains: Array(d['domains']).map do |dom|
          { name: dom, spells: Creatures::Deities.domain_spells(dname, dom) }
        end
      }
    end
  end

  # ---- Persistence ----------------------------------------------------

  # Build and persist a new Creature from an assembled-character payload
  # (string-keyed). Returns the new Creature's integer id. Raises
  # ArgumentError on invalid input.
  #
  # Expected keys:
  #   'name'       — required display name.
  #   'player'     — optional player name.
  #   'race'       — race key.
  #   'class'      — class key.
  #   'attributes' — { attr_key => integer } base scores.
  #   'skills'     — [concrete skill key, …] trained Skills.
  #   'spells'     — [catalog spell name, …] for count/points casters.
  #   'deity' / 'domain' — for the Cleric's domain mode.
  def create!(params)
    name = params['name'].to_s.strip
    raise ArgumentError, 'a character name is required' if name.empty?

    race = params['race'].to_s
    unless playable_race?(race)
      raise ArgumentError, "#{race.inspect} is not a playable race"
    end

    class_key = params['class'].to_s
    unless Creatures::Advancement.classes.key?(class_key)
      raise ArgumentError, "unknown class #{class_key.inspect}"
    end

    skills = Array(params['skills']).map(&:to_s).reject(&:empty?)
    skills.each do |s|
      raise ArgumentError, "incomplete Set Skill #{s.inspect}" if s.end_with?('_')
    end

    loose = {
      'id'         => Creatures::Dataset.next_id,
      'name'       => name,
      'race'       => race,
      'attributes' => build_attributes(params['attributes']),
      'tags'       => ['player_character'],
      'advancement' => {
        'classes' => {
          class_key => {
            'level'   => CREATION_LEVEL,
            'skills'  => skills,
            'choices' => build_choices(class_key, params)
          }
        }
      }
    }
    player = params['player'].to_s.strip
    loose['player'] = player unless player.empty?

    record = Creatures::Record.normalize(loose, source: PC_SOURCE)
    record[:source] = PC_SOURCE
    Creatures::Dataset.insert!(record)
    record[:id]
  end

  def build_attributes(raw)
    raw = raw.is_a?(Hash) ? raw : {}
    starting = attribute_allocation[:starting]
    attribute_keys.each_with_object({}) do |k, h|
      v = raw[k] || raw[k.to_sym] || starting
      h[k] = Integer(v)
    end
  end

  # Translate the wizard's spell / deity picks into the Class's
  # `choices` map. Non-casters (and `auto` casters) contribute nothing.
  def build_choices(class_key, params)
    sel = (Creatures::Advancement.look_up_class(class_key) || {})['spell_selection']
    return {} unless sel

    case sel['mode']
    when 'domain'
      choices = {}
      deity = params['deity'].to_s
      domain = params['domain'].to_s
      choices['deity']  = deity  unless deity.empty?
      choices['domain'] = domain unless domain.empty?
      choices
    when 'count', 'points'
      spells = Array(params['spells']).map(&:to_s).reject(&:empty?)
      spells.empty? ? {} : { 'spellcasting' => spells }
    else
      {}
    end
  end

  # ---- helpers --------------------------------------------------------

  def humanize(key)
    key.to_s.split(/[_\s]+/).reject(&:empty?).map { |w| w[0].upcase + w[1..].to_s }.join(' ')
  end
end
