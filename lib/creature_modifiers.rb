require 'dice_resolution'

# Cross-domain bridge that aggregates the Always-On numeric modifiers a
# Creature carries — equipped Guidance / Property bonuses (Equipment) and
# Modifier-ability bonuses (Abilities) — for two consumers:
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

  # Net (per-Type-stacked) integer bonus to an Attribute target — e.g.
  # 'str'. Today only equipped Guidance items target Attributes; ability
  # modifiers are folded in too for forward-compatibility. Unconditional
  # only (Attribute bonuses carry no descriptor context).
  def attribute_bonus(accessor, attr)
    DiceResolution.net_modifier(attribute_pairs(accessor, attr.to_s))
  end

  # The [[bonus_type, amount], ...] pairs (already per-Type-stacked) that
  # apply to an Attribute's Saving Throw, given a descriptor context.
  # Equipment Guidance to `saves` (the Cloak) and any "<attr>_save" effect
  # always apply; Modifier-ability Save bonuses apply only when
  # unconditional or when one of their descriptors is in `descriptors`.
  # Suitable for appending to a Roll's bonus_penalty_list.
  def save_modifiers(accessor, attr, descriptors: [])
    ctx = Array(descriptors).map(&:to_s)
    applicable = raw_save_entries(accessor, attr).select do |en|
      !en[:conditional] || (en[:descriptors] & ctx).any?
    end
    stack_pairs(applicable.map { |en| [en[:type], en[:amount]] })
  end

  # Display tokens for the green "+X" beside a Save: every applicable Save
  # bonus broken out as a signed amount, with `conditional: true` on
  # descriptor-scoped ones (poison / enchantment / charm) so the sheet can
  # flag them with a `*`. Inherent bonuses are excluded — per the project
  # rule they stay baked into the underlying value rather than itemised.
  # Returns [{ amount:, conditional:, type: }] (per-Type, per-conditional
  # stacked), unconditional entries first.
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

  # Net unconditional Save bonus for an Attribute — kept for callers that
  # want a single integer. Conditional resistances are excluded.
  def unconditional_save_bonus(accessor, attr)
    DiceResolution.net_modifier(save_modifiers(accessor, attr, descriptors: []))
  end

  # ---- internals -----------------------------------------------------

  # Every Save-applicable modifier the Creature carries for `attr`, before
  # context filtering or stacking: equipped Guidance / Property effects on
  # `saves` (or "<attr>_save") and Modifier-ability Save bonuses. Each
  # entry tracks its descriptors and whether it is conditional (descriptor-
  # scoped rather than unconditional / `all`).
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
    pairs
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

  # [[ability_name, modifier_hash], ...] across every **passive** Modifier
  # Entry the Creature's Granted Abilities carry. An **active** ability — one
  # with an `activation_time` (a Channel Divinity action like Strength
  # Devotion, used as a Main/Bonus/Free action) — does NOT contribute its
  # Modifiers Always-On; those apply only when the action is used.
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

  # Whether a Granted Ability is an action (declares an `activation_time`), as
  # opposed to a passive Modifier ability whose Modifiers are Always-On.
  def active_ability?(name)
    entry = (Abilities.catalog.ability(name) rescue nil)
    !!(entry && !entry['activation_time'].to_s.strip.empty?)
  rescue StandardError
    false
  end

  # A Modifier's `add`: an Integer verbatim, or a Formula string resolved
  # against the granting ability's level and the Creature's Tier.
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
