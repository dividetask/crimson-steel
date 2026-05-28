require 'creatures'
require 'proficiencies'
require 'proficiencies/compute'
require 'conditions'
require 'encounter'

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
    attrs   = Creatures::Config.attribute_keys.each_with_object({}) { |k, h| h[k] = accessor.base_attribute_value(k) }
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
      item_descriptions: [],
      abilities:    abilities(accessor),
      spells:       [], rituals: [], item_spells: [],
      active_effects: [], usable_spells: [], notes: []
    }
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
    {
      hp:   { current: [max_hp - hp_dmg, 0].max, max: max_hp },
      mana: { current: (st ? [max_mana - st.mana_spent, 0].max : max_mana), max: max_mana, regen: 0 },
      toxicity: { current: (st ? st.magic_toxicity : 0),
                  threshold: (cond ? (cond.toxicity_threshold(cha, tier) rescue 0) : 0) },
      temp_hp: (st&.temporary_hit_points ? st.temporary_hit_points[:amount] : 0),
      moderate_damage: (st ? st.hp_damage[:moderate] || 0 : 0),
      major_damage:    (st ? st.hp_damage[:major] || 0 : 0),
      combat_pool: (Encounter::CombatPool.size_for(accessor) rescue 0),
      damage_reduction: 0, damage_resilience: 0
    }
  end

  def perception(accessor)
    return { dice: 0, bonus: 0 } unless Proficiencies.attribute_for('perception')
    ri = Proficiencies::Compute.roll_inputs(key: 'perception', creature: accessor)
    { dice: ri[:dice_cap], bonus: (ri[:competency_modifier] ? ri[:competency_modifier][1] : 0) }
  rescue StandardError
    { dice: 0, bonus: 0 }
  end

  # Equipped weapons become the Combat action rows (Equipment is the
  # source). Always offers Dodge.
  def actions(accessor)
    rows = equipped_weapons(accessor).map do |w|
      { name: w[:display_name], speed: w[:speed], roll: '—',
        attack_bonus: 0, dmg_bonus: nil, bleed: w[:bleed], mt: w[:threshold],
        notes: Array(w[:damage_types]).join('/') }
    end
    rows << { name: 'Dodge', speed: 0, roll: '—', attack_bonus: 0, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
    rows
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

  def abilities(accessor)
    (accessor.granted_abilities rescue []).map do |g|
      desc = (Abilities.lookup(g[:name])&.dig('description') rescue nil)
      { name: g[:name], description: desc || 'No description yet.' }
    end
  end

  def attributes_table(accessor, attrs)
    %i[Strength Dexterity Constitution Intelligence Wisdom Charisma]
      .zip(%i[str dex con int wis cha]).map do |label, k|
      save = (Proficiencies::Compute.roll_inputs(key: "#{k}_save", creature: accessor, attribute_override: k) rescue nil)
      { attr: label.to_s, score: attrs[k], half: attrs[k] / 2,
        check: { dice: (accessor.attribute_value(k) rescue attrs[k]) / 2, bonus: 0 },
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
