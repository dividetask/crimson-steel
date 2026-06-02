require 'creatures'
require 'proficiencies'
require 'proficiencies/compute'
require 'conditions'
require 'encounter'
require 'equipment'
require 'abilities'
require 'dice_resolution'

# Builds the sheet hash the character-sheet partials
# (_creature_minimal / _creature_full) consume, sourced exclusively
# from the live domains — Creatures (identity, attributes, classes,
# skills, abilities), Conditions (current HP / Mana / Toxicity), and
# Encounter / Equipment (Combat Pool, equipped weapon actions). This
# is the live replacement for Status::SampleCreatures' hand-curated
# demos; Status data is never used here.
module CreatureSheet
  module_function

  # accessor — a Creatures::Accessor. Returns the demo-shaped Hash.
  def build(accessor)
    rec     = accessor.record
    # Sheets display Effective Attributes (base + racial + inherent +
    # chosen) — the same values the HP / Mana / skill formulas use.
    attrs   = Creatures::Config.attribute_keys.each_with_object({}) { |k, h| h[k] = accessor.attribute_value(k) }
    classes = rec[:classes].map { |key, e| { key: key, level: e[:level], trained_skills: Array(e[:skills]) } }
    tier    = (accessor.tier rescue 0)

    {
      id:           accessor.id,
      label:        accessor.name,
      roster_group: roster_group(rec),
      header:       header(accessor, classes, tier),
      attributes:   attrs,
      classes:      classes,
      skills:       skills(accessor),
      vitals:       vitals(accessor, tier),
      initiative:   { dice_count: (Encounter::Initiative.dice_count_for(accessor) rescue 0) },
      perception:   perception(accessor),
      speed:        (accessor.speed rescue 30),
      actions:      actions(accessor),
      attributes_table: attributes_table(accessor, attrs),
      items:        items(accessor),
      item_descriptions: item_descriptions(accessor),
      abilities:    abilities(accessor),
      spells:       spells(accessor), rituals: rituals(accessor), item_spells: item_spells(accessor),
      active_effects: active_effects(accessor), usable_spells: [], notes: []
    }
  end

  # Conditions (named Active Effects) currently on the Creature — e.g. Rage —
  # for the sheet's Active Effects section. Names are titleized for display.
  def active_effects(accessor)
    cond = conditions_for(accessor.id)
    return [] unless cond
    cond.active_effect_names.map { |name| { name: titleize_ability(name) } }
  rescue StandardError
    []
  end

  def roster_group(rec)
    return :npcs     if rec[:group] == 'npc'
    return :template if rec[:tags].include?('enemy_template')
    :players
  end

  def header(accessor, classes, tier)
    race  = (accessor.race || '').to_s.split('_').map(&:capitalize).join(' ')
    cls   = classes.map { |c| "#{c[:key].split('_').map(&:capitalize).join(' ')} #{c[:level]}" }.join(' / ')
    { name: accessor.name, player: accessor.player,
      summary: [race, cls].reject(&:empty?).join(' '),
      tier: tier, bab: (accessor.ranks_for('martial') rescue 0) }
  end

  # Trained skills across all the Creature's classes, with Dice Cap +
  # Bonus requested from Proficiencies (never recomputed here).
  def skills(accessor)
    trained = accessor.record[:classes].values.flat_map { |e| Array(e[:skills]) }.uniq
    trained.filter_map do |key|
      next unless Proficiencies.attribute_for(key)
      ri = Proficiencies::Compute.roll_inputs(key: key, creature: accessor)
      { name: pretty_skill_name(key), ranks: (accessor.ranks_for(key) rescue 0),
        dice: ri[:dice_cap], bonus: (ri[:competency_modifier] ? ri[:competency_modifier][1] : 0) }
    end
  rescue StandardError
    []
  end

  def vitals(accessor, tier)
    max_hp   = (accessor.max_hit_points rescue 0)
    max_mana = (accessor.max_mana rescue 0)
    cond     = conditions_for(accessor.id)
    st       = cond&.state
    cha      = (accessor.attribute_value(:cha) rescue 0)
    hp_dmg   = st ? st.hp_damage.values.sum : 0
    defense  = defensive_totals(accessor)
    # Damage Reduction / Resilience = equipped Armor + active-effect Modifiers
    # (e.g. Rage's Circumstance bonuses), so a Condition the Creature is under
    # shows up in these totals.
    dr  = defense[:damage_reduction]  + condition_modifier_total(cond, 'damage_reduction')
    res = defense[:damage_resilience] + condition_modifier_total(cond, 'damage_resilience')
    {
      hp:   { current: [max_hp - hp_dmg, 0].max, max: max_hp },
      mana: { current: (st ? [max_mana - st.mana_spent, 0].max : max_mana), max: max_mana,
              regen: mana_regen_per_day(max_mana) },
      toxicity: { current: (st ? st.magic_toxicity : 0),
                  threshold: (cond ? (cond.toxicity_threshold(cha, tier) rescue 0) : 0) },
      temp_hp: (st&.temporary_hit_points ? st.temporary_hit_points[:amount] : 0),
      moderate_damage: (st ? st.hp_damage[:moderate] || 0 : 0),
      major_damage:    (st ? st.hp_damage[:major] || 0 : 0),
      combat_pool: (Encounter::CombatPool.size_for(accessor) rescue 0),
      damage_reduction: dr, damage_resilience: res
    }
  end

  # Sum of the active-effect Modifiers targeting a key (e.g. damage_reduction),
  # after Conditions' per-Bonus-Type stacking. Zero when no Conditions record.
  def condition_modifier_total(cond, key)
    return 0 unless cond
    cond.get_modifiers(key).sum { |_type, amount| amount.to_i }
  rescue StandardError
    0
  end

  # Mana regained per Day of Natural Recovery: floor(Max Mana / Mana
  # Per Recovery Tick Divisor), where one Recovery Tick is one Day (see
  # conditions_config.yaml → Natural Recovery).
  def mana_regen_per_day(max_mana)
    div = (Conditions.store.catalog.mana_per_recovery_tick_divisor rescue nil).to_i
    div = 4 if div.zero?
    max_mana / div
  rescue StandardError
    0
  end

  # Sum equipped Armor + Shield mitigation via Equipment.
  def defensive_totals(accessor)
    cat    = Equipment.catalog
    stacks = Equipment.instance.get_inventory("creature:#{accessor.id}")
    Equipment::Details.defensive_totals(stacks, cat)
  rescue StandardError
    { damage_reduction: 0, damage_resilience: 0 }
  end

  def perception(accessor)
    return { dice: 0, bonus: 0 } unless Proficiencies.attribute_for('perception')
    ri = Proficiencies::Compute.roll_inputs(key: 'perception', creature: accessor)
    { dice: ri[:dice_cap], bonus: (ri[:competency_modifier] ? ri[:competency_modifier][1] : 0) }
  rescue StandardError
    { dice: 0, bonus: 0 }
  end

  # Equipped weapons become the Combat action rows (Equipment is the
  # source). Each row carries the real attack Roll Dice Cap + Competency
  # (Proficiencies Martial, driven by Strength for melee / Dexterity for
  # ranged) and the damage bonus from the weapon's damage formula
  # evaluated against the wielder. Always offers Dodge (a Dexterity Save).
  def actions(accessor)
    rows = equipped_weapons(accessor).map do |w|
      attack_attr = ranged_weapon?(w) ? :dex : :str
      ri  = roll_inputs(accessor, 'martial', attack_attr)
      { name: w[:display_name], speed: w[:speed], roll: "#{ri[:dice_cap]}d",
        attack_bonus: competency_bonus(ri), dmg_bonus: weapon_damage(w, accessor),
        bleed: w[:bleed], mt: w[:threshold], notes: Array(w[:damage_types]).join('/') }
    end
    dodge = roll_inputs(accessor, 'dex_save', :dex)
    rows << { name: 'Dodge', speed: 0, roll: "#{dodge[:dice_cap]}d",
              attack_bonus: competency_bonus(dodge), dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
    rows
  end

  def ranged_weapon?(weapon)
    defn = weapon[:definition]
    defn.is_a?(Hash) && defn['category'] == 'Ranged'
  end

  # Proficiencies *Compute Roll inputs*, tolerant of a creature with no
  # resolvable record (mirrors the Encounter route helper).
  def roll_inputs(accessor, key, attribute_override = nil)
    Proficiencies::Compute.roll_inputs(key: key, creature: accessor, attribute_override: attribute_override)
  rescue StandardError
    { dice_cap: 0, competency_modifier: nil }
  end

  def competency_bonus(inputs)
    inputs[:competency_modifier] ? inputs[:competency_modifier][1] : 0
  end

  # Evaluate a weapon's damage formula against the wielder's Effective
  # Attributes (Combat owns this evaluation per equipment_design.md).
  # Clamped at zero; nil when the weapon carries no formula.
  def weapon_damage(weapon, accessor)
    formula = weapon[:damage_formula]
    return nil if formula.nil? || formula.to_s.strip.empty?
    binds = Creatures::Config.attribute_keys.each_with_object({}) { |a, h| h[a] = (accessor.attribute_value(a) rescue 0) }
    [(Abilities::Formula.evaluate(formula, binds).to_i rescue 0), 0].max
  rescue StandardError
    nil
  end

  def items(accessor)
    cat = (Equipment.catalog rescue nil)
    inv = (Equipment.instance.get_inventory("creature:#{accessor.id}") rescue [])
    grouped = { equipped: [], consumable: [], ammunition: [], other: [] }
    inv.each do |s|
      it = cat&.item_type(s.item_type)
      name = (Equipment::Details.item_details(s, cat)[:display_name] rescue s.item_type)
      row = { name: name, quantity: s.quantity }
      if s.equipped
        grouped[:equipped] << row
      elsif it && it[:category] == 'Ammunition'
        grouped[:ammunition] << row
      elsif it && it[:category] == 'Consumable'
        grouped[:consumable] << row
      else
        grouped[:other] << row
      end
    end
    grouped
  rescue StandardError
    { equipped: [], consumable: [], ammunition: [], other: [] }
  end

  # Descriptions of the named magic items the Creature carries, for the
  # sheet's Item Descriptions section (creatures_full_stub.md). The text
  # is each Stack's resolved description — a unique-item override, or the
  # generic Item Type's catalog description — supplied by Equipment's
  # Get Item Details. Items with no description on file are skipped, and
  # identical rows are collapsed.
  def item_descriptions(accessor)
    cat = Equipment.catalog
    inventory(accessor).filter_map do |s|
      d = Equipment::Details.item_details(s, cat)
      desc = d[:description]
      next if desc.nil? || desc.to_s.strip.empty?
      { name: d[:display_name], description: desc }
    end.uniq
  rescue StandardError
    []
  end

  def abilities(accessor)
    (accessor.granted_abilities rescue []).map do |g|
      { name: titleize_ability(g[:name]), description: ability_description(g[:name]) }
    end
  end

  # Resolve a granted Ability's description across the Ability catalogs.
  # Granted names arrive as snake_case keys; Catalog Abilities (talents)
  # are keyed by display name while Modifier / Stateful abilities are
  # keyed snake_case, so we try the key both verbatim and Title-Cased.
  # Returns '' (blank) when no description is on file — never a
  # placeholder string.
  def ability_description(key)
    [key.to_s, titleize_ability(key)].uniq.each do |name|
      entry = (Abilities.lookup(name)&.dig('description') rescue nil)
      return entry if entry && !entry.to_s.empty?
      mod = (Abilities.lookup_modifier_ability(name) rescue nil)
      return mod[:description] if mod && !mod[:description].to_s.empty?
      st = (Abilities.lookup_stateful(name) rescue nil)
      return st[:description] if st && !st[:description].to_s.empty?
    end
    ''
  rescue StandardError
    ''
  end

  def titleize_ability(key)
    key.to_s.split(/[_\s]+/).reject(&:empty?).map { |w| w[0].upcase + w[1..] }.join(' ')
  end

  # Spells the Creature knows from Class spellcasting — the spell-typed
  # entries among its Granted Abilities, grouped by Tier.
  def spells(accessor)
    keys = (accessor.granted_abilities rescue []).map { |g| g[:name] }
    spell_groups(keys)
  end

  # Rituals — the spells inscribed in the Creature's carried Ritual
  # books (Equipment Stacks whose Item Type is `inscribable`).
  def rituals(accessor)
    cat = Equipment.catalog
    inventory(accessor).select { |s| inscribable?(s, cat) }
                       .flat_map { |s| Array(s.inscribed_spells) }
                       .then { |keys| spell_groups(keys) }
  rescue StandardError
    []
  end

  # Item Spells — spells stored in carried scrolls / wands (Stacks with
  # a `stored_spell`).
  def item_spells(accessor)
    inventory(accessor).filter_map { |s| s.stored_spell unless s.stored_spell.to_s.empty? }
                       .then { |keys| spell_groups(keys) }
  rescue StandardError
    []
  end

  # Group a list of spell keys into [{ tier:, names: }] ordered by Tier.
  # Non-spell keys (e.g. talents in the granted-abilities list) are
  # dropped. Tier-variant spells fall back to their lowest Tier.
  def spell_groups(keys)
    by_tier = Hash.new { |h, t| h[t] = [] }
    Array(keys).each do |key|
      info = spell_info(key)
      next unless info
      by_tier[info[:tier]] << info[:name] unless by_tier[info[:tier]].include?(info[:name])
    end
    by_tier.keys.sort.map { |t| { tier: t, names: by_tier[t] } }
  rescue StandardError
    []
  end

  # Resolve a spell key to { tier:, name: }, or nil when it is not a
  # Catalog spell. Granted keys arrive snake_case; the spell catalog is
  # keyed by display name, so we try the Title-Cased form too.
  def spell_info(key)
    title = titleize_ability(key)
    entry = (Abilities.catalog.ability(title) || Abilities.catalog.ability(key.to_s) rescue nil)
    return nil unless entry && entry['type'] == 'spell'
    tier = entry['tier']
    tier = Array(tier).map(&:to_i).min if tier.is_a?(Array)
    { tier: tier.to_i, name: title }
  rescue StandardError
    nil
  end

  def inventory(accessor)
    Equipment.instance.get_inventory("creature:#{accessor.id}")
  rescue StandardError
    []
  end

  def inscribable?(stack, catalog)
    it = catalog.item_type(stack.item_type)
    it && it[:definition].is_a?(Hash) && it[:definition]['inscribable']
  end

  def attributes_table(accessor, attrs)
    %i[Strength Dexterity Constitution Intelligence Wisdom Charisma]
      .zip(%i[str dex con int wis cha]).map do |label, k|
      save = (Proficiencies::Compute.roll_inputs(key: "#{k}_save", creature: accessor, attribute_override: k) rescue nil)
      # Attribute Check Prowess is floor(Effective Attribute / 2),
      # translated through Dice Resolution into a Dice Cap + bonus.
      check_dice, check_bonus = DiceResolution.translate_prowess(attrs[k] / 2)
      { attr: label.to_s, score: attrs[k], half: attrs[k] / 2,
        check: { dice: check_dice, bonus: check_bonus },
        save:  { dice: (save ? save[:dice_cap] : 0), bonus: (save && save[:competency_modifier] ? save[:competency_modifier][1] : 0) } }
    end
  end

  def equipped_weapons(accessor)
    cat = Equipment.catalog
    Equipment.instance.get_inventory("creature:#{accessor.id}")
             .select { |s| s.equipped && (it = cat.item_type(s.item_type)) && it[:category] == 'Weapon' }
             .map { |s| Equipment::Details.weapon_details(s, cat) }
  rescue StandardError
    []
  end

  def conditions_for(creature_id)
    Conditions.store.instance_for(creature_id)
  rescue StandardError
    nil
  end

  def pretty_skill_name(key)
    if key.include?('_') && Proficiencies.skills.key?("#{key.split('_').first}_")
      family, *rest = key.split('_')
      return "#{family.capitalize} (#{rest.map(&:capitalize).join(' ')})"
    end
    key.split('_').map(&:capitalize).join(' ')
  end
end
