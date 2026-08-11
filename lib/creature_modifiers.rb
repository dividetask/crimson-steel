require 'dice_resolution'

# Cross-domain bridge that aggregates the numeric modifiers a Creature
# carries — equipped Guidance / Property bonuses (Equipment), passive
# Modifier-ability bonuses (Abilities), and active-effect Attribute Modifiers
# (Conditions, e.g. Strength Devotion's +2 str/con while the buff is up) — for
# two consumers:
#
#   * Attribute bonuses (Belt of Strength, Headband of Wisdom, ...) fold
#     into the Creature's Effective Attributes (Creatures::Accessor).
#   * Save bonuses (Cloak of Resistance; racial poison / enchantment
#     resistance) feed Saving-Throw Rolls (Encounter) and the green "+X"
#     the character sheet shows next to an Attribute or Save.
#
# Per-Bonus-Type stacking matches Dice Resolution: for each Bonus Type
# only the highest-positive and lowest-negative entry contributes;
# different Types sum. Conditional bonuses carry `descriptors` (e.g.
# [poison]) and apply only when the caller supplies a matching descriptor
# context — so an unconditional query (descriptors: []) never sees them,
# which is exactly why conditional Saves do not surface on the sheet.
module CreatureModifiers
  module_function

  def attribute_bonus(accessor, attr)
    DiceResolution.net_modifier(attribute_pairs(accessor, attr.to_s))
  end

  def attribute_bonus_tokens(accessor, attr)
    stack_pairs(attribute_pairs(accessor, attr.to_s)).map do |type, amount|
      { amount: amount, type: type }
    end
  end

  def save_modifiers(accessor, attr, descriptors: [])
    ctx = Array(descriptors).map(&:to_s)
    applicable = raw_save_entries(accessor, attr).select do |en|
      !en[:conditional] || (en[:descriptors] & ctx).any?
    end
    stack_pairs(applicable.map { |en| [en[:type], en[:amount]] })
  end

  def save_bonus_tokens(accessor, attr)
    entries = raw_save_entries(accessor, attr).reject { |en| en[:type] == 'Inherent' }
    entries.group_by { |en| [en[:type], en[:conditional]] }.flat_map do |(type, cond), list|
      amts = list.map { |en| en[:amount] }
      out  = []
      pos  = amts.select(&:positive?).max
      neg  = amts.select(&:negative?).min
      out << { amount: pos, conditional: cond, type: type } if pos
      out << { amount: neg, conditional: cond, type: type } if neg
      out
    end.sort_by { |t| [t[:conditional] ? 1 : 0, t[:type]] }
  end

  def unconditional_save_bonus(accessor, attr)
    DiceResolution.net_modifier(save_modifiers(accessor, attr, descriptors: []))
  end

  def skill_modifiers(accessor, key)
    k = key.to_s
    pairs = equipped_effects(accessor).filter_map do |e|
      next unless e[:target_key].to_s == k
      next unless e[:amount].is_a?(Integer) && !e[:amount].zero?
      [e[:bonus_type].to_s, e[:amount]]
    end
    stack_pairs(pairs)
  end

  def skill_bonus(accessor, key)
    DiceResolution.net_modifier(skill_modifiers(accessor, key))
  end

  # ---- internals -----------------------------------------------------
  def raw_save_entries(accessor, attr)
    entries = []
    equipped_effects(accessor).each do |e|
      tk = e[:target_key].to_s
      next unless tk == 'saves' || tk == "#{attr}_save"
      next unless e[:amount].is_a?(Integer) && !e[:amount].zero?
      entries << { type: e[:bonus_type].to_s, amount: e[:amount], conditional: false, descriptors: [] }
    end
    ability_modifier_entries(accessor).each do |name, m|
      next unless m['target'].to_s == 'save'
      amt = eval_amount(m['add'], accessor, name)
      next unless amt.is_a?(Integer) && !amt.zero?
      d = Array(m['descriptors']).map(&:to_s)
      conditional = !(d.empty? || d.include?('all'))
      entries << { type: m['type'].to_s, amount: amt, conditional: conditional, descriptors: d }
    end
    entries
  end

  def attribute_pairs(accessor, target)
    pairs = []
    equipped_effects(accessor).each do |e|
      next unless e[:target_key].to_s == target
      pairs << [e[:bonus_type].to_s, e[:amount]] if e[:amount].is_a?(Integer)
    end
    ability_modifier_entries(accessor).each do |name, m|
      next unless m['target'].to_s == target
      next unless descriptor_match?(m['descriptors'], [])
      amt = eval_amount(m['add'], accessor, name)
      pairs << [m['type'].to_s, amt] if amt.is_a?(Integer) && !amt.zero?
    end
    condition_attribute_pairs(accessor, target).each { |p| pairs << p }
    pairs
  end

  def condition_attribute_pairs(accessor, target)
    return [] unless defined?(Conditions)
    inst = (Conditions.store.instance_for(accessor.id) rescue nil)
    return [] unless inst
    (inst.get_modifiers(target) rescue []).map { |type, amount| [type.to_s, amount.to_i] }
  rescue StandardError
    []
  end

  # Per-Bonus-Type condition Modifiers a Creature carries for a Check
  # category key — e.g. `attack_checks`, `ability_checks`, `spell_checks`
  # (the fear ladder's Morale penalties) or `<attr>_checks`. Returns
  # stacked [[type, amount], …] ready to drop into a Roll's bonus/penalty
  # list. Empty when Conditions is unavailable or the Creature carries none.
  def check_modifiers(accessor, key)
    condition_attribute_pairs(accessor, key.to_s)
  end

  # Per-Bonus-Type stacking → at most one positive and one negative entry
  # per Type (mirrors Conditions' Get Modifiers / Dice Resolution).
  def stack_pairs(pairs)
    pairs.group_by { |type, _| type }.flat_map do |type, list|
      amts = list.map { |_, a| a }
      out  = []
      pos  = amts.select(&:positive?).max
      neg  = amts.select(&:negative?).min
      out << [type, pos] if pos
      out << [type, neg] if neg
      out
    end
  end

  # An ability's descriptors match a context when the ability is
  # unconditional (no descriptors, or the catch-all `all`) or when any of
  # its descriptors appears in the supplied context.
  def descriptor_match?(descriptors, context)
    d = Array(descriptors).map(&:to_s)
    return true if d.empty? || d.include?('all')
    (d & context).any?
  end

  def equipped_effects(accessor)
    return [] unless defined?(Equipment) && Equipment.respond_to?(:instance)
    Equipment.instance.equipped_effects("creature:#{accessor.id}")
  rescue StandardError
    []
  end

  def ability_modifier_entries(accessor)
    return [] unless defined?(Abilities)
    (accessor.granted_abilities rescue []).flat_map do |g|
      name = g[:name]
      next [] if active_ability?(name)
      (Abilities.get_modifiers(name) rescue []).map { |m| [name, m] }
    end
  rescue StandardError
    []
  end

  def active_ability?(name)
    entry = (Abilities.catalog.ability(name) rescue nil)
    !!(entry && !entry['activation_time'].to_s.strip.empty?)
  rescue StandardError
    false
  end

  def eval_amount(add, accessor, ability_name)
    return add if add.is_a?(Integer)
    return nil if add.nil?
    binds = { 'level' => (accessor.level_for_ability(ability_name) rescue 0),
              'tier'  => (accessor.tier rescue 0) }
    Integer(Abilities::Formula.evaluate(add.to_s, binds))
  rescue StandardError
    nil
  end
end
