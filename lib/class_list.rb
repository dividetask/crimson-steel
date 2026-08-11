require 'yaml'
require_relative 'creatures/advancement'
require_relative 'proficiencies/ranks'
require 'abilities'

# Rows + detail for the Compendium's Classes page (docs/common/ui/class_list_stub.md).
#
# The list is every BASE playable Class — NPC-only classes (`npc_class: true`)
# and archetypes (a Class with `parent_class:`, e.g. Ranger, Arcane Trickster)
# are excluded — each with a short summary.
#
# Clicking a Class opens its detail page, laid out like the Classes design
# document: Proficiencies (Armor / Weapons / Saving Throws), the Skills count,
# Class Skills and All Skills, a level progression table, and the Class
# Features with their descriptions. The detail page carries no prose blurb —
# the summary lives only on the list. Armor and Weapon lines come from
# class_descriptions.yaml; everything else is derived live from the advancement
# config, the Skill catalog, and the Abilities catalog.
module ClassList
  module_function

  CONTENT_PATH = File.expand_path(
    '../docs/common/creatures/class_descriptions.yaml', __dir__
  )
  SKILLS_PATH = File.expand_path(
    '../docs/common/proficiencies/skills.yaml', __dir__
  )

  ATTRS = %w[str dex con int wis cha].freeze
  ATTR_NAMES = {
    'str' => 'Strength', 'dex' => 'Dexterity', 'con' => 'Constitution',
    'int' => 'Intelligence', 'wis' => 'Wisdom', 'cha' => 'Charisma'
  }.freeze

  def content
    @content ||= (YAML.safe_load_file(CONTENT_PATH) || {})
  rescue StandardError
    {}
  end

  def skill_catalog
    @skill_catalog ||= ((YAML.safe_load_file(SKILLS_PATH) || {})['Skills'] || {})
  rescue StandardError
    {}
  end

  # Base playable Class keys: every player Class that is not an archetype.
  def base_class_keys
    Creatures::Advancement.pc_class_keys.reject { |k| archetype?(k) }
  end

  # An archetype is a Class that declares a parent_class (checked on the raw
  # entry, not the archetype-merged one).
  def archetype?(key)
    entry = Creatures::Advancement.classes[key.to_s]
    !!(entry && entry['parent_class'])
  end

  # Base playable Classes, each { key, name, summary }, sorted by name. The
  # list shows base Classes only — archetypes are reached by clicking through
  # from their parent Class's page.
  def rows
    base_class_keys.map do |key|
      c = content[key] || {}
      { key: key, name: titleize(key), summary: c['summary'].to_s }
    end.sort_by { |r| r[:name] }
  end

  # Full detail for a playable Class — a base Class OR one of its archetypes
  # (an archetype's page lists every Class ability from the parent plus its
  # own, via the archetype-merged catalog entry). nil for an NPC-only or
  # unknown key.
  def detail(key)
    key = key.to_s
    return nil unless Creatures::Advancement.pc_class_keys.include?(key)
    cls    = Creatures::Advancement.look_up_class(key) or return nil
    c      = content_for(key)
    parent = parent_key(key)
    prog   = progression(cls)
    {
      key:           key,
      name:          titleize(key),
      parent_class:  parent && titleize(parent),
      armor:         c['armor'].to_s,
      weapons:       c['weapons'].to_s,
      saving_throws: good_saves(cls).join(', '),
      skills_line:   skills_line(cls),
      aligned_skills: aligned_skills(cls),
      all_skills:    all_skill_labels,
      spell_tiers:   spell_tiers(cls),
      spellcasting:  spellcasting_note(cls),
      progression:   prog,
      tier_advancement: tier_advancement(prog.map { |r| r[:level] }.max || 5),
      features:      features(cls),
      # A base Class lists its archetypes (branching at level 3); an archetype
      # lists none of its own.
      archetypes:    parent ? [] : archetypes_of(key)
    }
  end

  # The raw parent_class of an archetype (nil for a base Class).
  def parent_key(key)
    entry = Creatures::Advancement.classes[key.to_s]
    entry && entry['parent_class']
  end

  # Per-Class Compendium content (armor / weapons / summary). An archetype with
  # no entry of its own inherits its parent's.
  def content_for(key)
    content[key.to_s] || content[parent_key(key).to_s] || {}
  end

  # The playable archetypes of a base Class, each { key, name }, sorted by
  # name. (NPC-only children, if any, are excluded.)
  def archetypes_of(parent)
    Creatures::Advancement.classes.filter_map do |k, entry|
      next unless entry['parent_class'].to_s == parent.to_s
      next if Creatures::Advancement.npc_class?(k)
      { key: k, name: titleize(k) }
    end.sort_by { |a| a[:name] }
  end

  # ---- proficiencies / skills ----------------------------------------

  # The two "good" saves advance at the Class rate; the other four (the
  # `opposed` list) advance slowly, so the good saves are the Attributes NOT
  # listed as opposed.
  def good_saves(cls)
    opposed = Array(cls.dig('saves', 'opposed')).map(&:to_s)
    (ATTRS - opposed).map { |a| ATTR_NAMES[a] || a.upcase }
  end

  def skills_line(cls)
    "Gain #{cls['bonus_skills'].to_i} + ¼ Intelligence skills. " \
      '(Optional Rule) Gain an additional background skill.'
  end

  # The Aligned Skills (those advancing at the fast rate). An inclusion-form
  # Class (`aligned_proficiencies`) names them directly; an inverse-form Class
  # (`unaligned_proficiencies`) trains every Skill fast except the ones it
  # names (and any opposed). `martial` is Combat training, not a listed Skill.
  def aligned_skills(cls)
    aligned   = cls['aligned_proficiencies']
    unaligned = cls['unaligned_proficiencies']
    opposed   = Array(cls['opposed_proficiencies']).map(&:to_s)
    keys =
      if aligned
        Array(aligned).map(&:to_s)
      elsif unaligned
        all_skill_keys - Array(unaligned).map(&:to_s) - opposed
      else
        []
      end
    keys.reject { |k| k == 'martial' }.map { |k| skill_label(k) }.uniq.sort
  end

  def all_skill_keys
    skill_catalog.keys.map(&:to_s)
  end

  def all_skill_labels
    (all_skill_keys - ['martial']).map { |k| skill_label(k) }.sort
  end

  # ---- level progression table ---------------------------------------

  # The `tiered_count` spell_selection block (from creatures_advancement.yaml)
  # when the Class learns a number of spells of each Tier per level — the
  # single source of truth shared with character creation — or nil otherwise.
  def tiered_spells(cls)
    sel = cls['spell_selection']
    (sel.is_a?(Hash) && sel['mode'].to_s == 'tiered_count') ? sel : nil
  end

  # The Spell Tiers a Class tracks in its progression table (e.g. [0, 1, 2]
  # for the Bard), or nil when the Class has no per-Tier Spell progression.
  # Only `tiered_count` Classes show Spell columns — no counts are invented
  # for the others; they carry only the spellcasting note.
  def spell_tiers(cls)
    sp = tiered_spells(cls)
    sp ? Array(sp['tiers']) : nil
  end

  # Levels 1–N (N is the deepest level with authored Spell data, at least 5),
  # each with per-level Mana, the ranks/save-bonus gained at each of the three
  # Proficiency Rates (Aligned / Unaligned / Opposed), the Special Abilities
  # gained, and — for a `tiered_count` Class — the Spells known at each tracked
  # Tier. The rate values come straight from the game's own rate formulas
  # (Proficiencies::Ranks): an Aligned Skill or Save advances at 5·level/3, an
  # Unaligned one at level, and an Opposed one at 2·level/3.
  def progression(cls)
    mpl   = cls['mana_per_level'].to_i
    prog  = cls['ability_progression'] || {}
    sp    = tiered_spells(cls)
    tiers = sp ? Array(sp['tiers']) : nil
    by_lv = (sp && sp['by_level']) || {}
    table_levels(sp).map do |lvl|
      row = {
        level:     lvl,
        mana:      lvl * mpl,
        aligned:   Proficiencies::Ranks.apply_rate(lvl, :aligned),
        unaligned: Proficiencies::Ranks.apply_rate(lvl, :unaligned),
        opposed:   Proficiencies::Ranks.apply_rate(lvl, :opposed),
        special:   Array(prog[lvl.to_s]).map { |k| titleize(k) }
      }
      if tiers
        counts = by_lv[lvl.to_s] || by_lv[lvl] || []
        row[:spells_by_tier] = tiers.each_index.map { |i| counts[i] }
      end
      row
    end
  end

  # Tier advancement to list beneath the table: each Tier a Player Character
  # reaches within the table's level span (from the `player_character` Tier
  # Breakpoints [0, 1, 4, 8, 16, 30] → Tier 1 at level 1, Tier 2 at level 4).
  def tier_advancement(max_level)
    bps = Array(Creatures::Advancement.breakpoints['player_character'])
    (1...bps.length).filter_map do |tier|
      lvl = bps[tier].to_i
      { tier: tier, level: lvl } if lvl >= 1 && lvl <= max_level
    end
  end

  # The table runs to level 5, or deeper when a Class has authored Spell
  # progression beyond it (the Bard's runs to 6).
  def table_levels(tiered)
    max = 5
    by_lv = tiered && tiered['by_level']
    max = [max, by_lv.keys.map(&:to_i).max || max].max if by_lv.is_a?(Hash)
    (1..max).to_a
  end

  # A one-line note describing how the Class learns Spells (its scope / mode),
  # shown under the table. Empty for a non-caster.
  def spellcasting_note(cls)
    sel = cls['spell_selection']
    return '' unless sel.is_a?(Hash)
    filter = sel['filter'].to_s
    scope  = (filter.empty? || filter == 'any') ? 'any spell' : "#{titleize(filter)} spells"
    case sel['mode'].to_s
    when 'count'  then "Learns #{scope}."
    when 'points' then "Spends a per-level point pool on #{scope}."
    when 'domain' then 'Prepares spells from the chosen deity domains.'
    when 'auto'   then "Automatically knows every #{scope}."
    else ''
    end
  end

  # ---- class features -------------------------------------------------

  # Display-name overrides for Class Features whose shown name differs from a
  # plain Title Case of the progression key (e.g. a category qualifier, or a
  # renamed feat).
  FEATURE_DISPLAY_NAMES = {
    'performance_feat'   => 'Magical Performance Feat',
    'bardic_inspiration' => 'Bardic Inspiration (magical performance)',
    'unsettling_words'   => 'Unsettling Words/Notes (magical performance)',
    'jack_of_all_trades' => 'Jack of All Trades',
    'domain'             => 'Domains',
    'turn_undead'        => 'Turn Undead (channel divinity)',
    'destroy_undead'     => 'Destroy Undead (channel divinity)',
    'precise_poisoner'   => 'Precise Poisoner (sneak attack)'
  }.freeze

  # Class Features grouped by the level they are gained, each with its
  # Abilities-catalog description when one exists.
  def features(cls)
    prog = cls['ability_progression'] || {}
    prog.keys.sort_by(&:to_i).map do |lvl|
      abilities = Array(prog[lvl]).map do |k|
        { key: k.to_s, name: feature_name(k), description: ability_description(k) }
      end
      { level: lvl.to_i, abilities: abilities }
    end
  end

  def feature_name(key)
    FEATURE_DISPLAY_NAMES[key.to_s] || titleize(key)
  end

  # Best-effort description for a Class Feature. Look in the Talents / Spells
  # catalog (Title Case keys) first, then the raw key, then the Modifier
  # Abilities catalog (snake_case keys — Jack of All Trades, Silver Tongue,
  # Versatile Performance, the feat grants). Empty string when nothing is found.
  def ability_description(key)
    entry = (Abilities.catalog.ability(titleize(key)) rescue nil) ||
            (Abilities.catalog.ability(key.to_s) rescue nil)
    desc  = entry.is_a?(Hash) ? entry['description'].to_s : ''
    if desc.empty?
      mod = (Abilities.lookup_modifier_ability(key.to_s) rescue nil)
      desc = mod[:description].to_s if mod.is_a?(Hash)
    end
    desc
  rescue StandardError
    ''
  end

  # ---- labels ---------------------------------------------------------

  # A Skill key rendered for display. A Set Skill (trailing `_`) shows with an
  # empty instance slot, e.g. craft_ → "Craft ()"; others Title Case.
  def skill_label(key)
    k = key.to_s
    k.end_with?('_') ? "#{titleize(k.chomp('_'))} ()" : titleize(k)
  end

  def titleize(key)
    key.to_s.tr('_', ' ').split.map { |w| w.empty? ? w : (w[0].upcase + w[1..]) }.join(' ')
  end
end
