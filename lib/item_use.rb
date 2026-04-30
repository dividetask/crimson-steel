require_relative 'equipment'
require_relative 'abilities'
require_relative 'conditions'

# ItemUse — orchestration for consuming an item.
#
# Looks up the item's spell entry through abilities, reads the
# resolved Effect Hash for the conventional keys that signal the
# kind of effect (minor_damage / moderate_damage / major_damage =
# cure pools, mana = mana restore, temp_hp = ward), applies the
# effect to the target's Conditions, imposes Magic Toxicity per
# the item-form rules, and decrements the item quantity.
#
# This is reference orchestration: callers supply the participants
# (equipment, abilities, conditions_lookup) and the item-form
# rules look up the right paths from there.
class ItemUse
  POTION_FORM = 'potion'
  OIL_FORM    = 'oil'
  SCROLL_FORM = 'scroll'
  WAND_FORM   = 'wand'

  CONSUMABLE_FORMS = [POTION_FORM, OIL_FORM, SCROLL_FORM].freeze
  TOXICITY_GATED_KINDS = %i[heal mana].freeze

  attr_reader :equipment, :abilities

  def initialize(equipment:, abilities:, conditions_lookup:)
    @equipment = equipment
    @abilities = abilities
    @conditions_lookup = conditions_lookup
  end

  # Consume an item by inventory stack index. Returns a hash
  # describing what was applied. Does not raise on saturation-cap
  # violation — the caller checks `result['saturation_blocked']`
  # and decides how to surface the failure.
  #
  # Required parameters:
  #   owner_id           — Owner ID of the item's holder
  #   stack_index        — index into get_inventory(owner_id)
  #   item_form          — POTION_FORM / OIL_FORM / SCROLL_FORM / WAND_FORM
  #   spell_name         — the contained spell's entry name
  #   target_char_id     — target's character id (for conditions lookup)
  #
  # Optional parameters:
  #   rank               — defaults to the item's tier (potions/oils
  #                        invoke at item tier; scrolls without an
  #                        explicit rank invoke at item tier).
  #   user_tier          — the consuming character's tier; default 0.
  #   target_tier        — the target's tier; default 0.
  #   target_max_toxicity — saturation cap for the target; if the
  #                        target's current magic_toxicity is >= this,
  #                        cure / mana effects refuse to land.
  #   user_abilities     — list of class/racial ability names the
  #                        user has (e.g. ['improved_healing']).
  def consume(owner_id:, stack_index:, item_form:, spell_name:, target_char_id:,
              rank: nil, user_tier: 0, target_tier: 0,
              target_max_toxicity: nil, user_abilities: [])
    inventory = @equipment.get_inventory(owner_id)
    raw_stack = inventory[stack_index]
    raise ArgumentError, "No stack at index #{stack_index}" unless raw_stack

    item_tier = raw_stack['tier'].to_i
    rank ||= item_tier
    tier_index = nil
    entry = @abilities.get_entry(spell_name)
    if entry['tier'].is_a?(Array)
      tier_index = entry['tier'].index(item_tier) || [item_tier - entry['tier'].first, 0].max
    end

    resolved = @abilities.resolve_entry(spell_name, rank, tier_index: tier_index)
    target_conditions = @conditions_lookup.call(target_char_id)
    raise "No conditions instance for #{target_char_id}" unless target_conditions

    effect_hash = resolved['effect_hash'] || {}
    applications = []

    # Saturation gate: cure / mana refuse to land at the cap.
    saturation_blocked = false
    if target_max_toxicity && target_conditions.magic_toxicity >= target_max_toxicity
      if has_cure?(effect_hash) || has_mana?(effect_hash)
        saturation_blocked = true
      end
    end

    unless saturation_blocked
      applications.concat(apply_cure(effect_hash, target_conditions))
      applications.concat(apply_mana(effect_hash, target_conditions))
    end
    applications.concat(apply_ward(effect_hash, target_conditions, spell_name, owner_id))

    # Magic toxicity (always applied unless gated, and respected even
    # if cure/mana were the only effects).
    toxicity = compute_magic_toxicity(effect_hash, item_form, item_tier, user_tier, target_tier, user_abilities)
    if toxicity > 0 && !saturation_blocked
      target_conditions.apply_magic_toxicity(toxicity)
      applications << { 'kind' => 'magic_toxicity', 'amount' => toxicity }
    end

    quantity_decrement = 0
    if CONSUMABLE_FORMS.include?(item_form) && !saturation_blocked
      @equipment.adjust_stack_quantity(owner_id, stack_index, -1)
      @equipment.cleanup_zero_quantity(owner_id)
      quantity_decrement = 1
    end

    {
      'spell_name'         => spell_name,
      'item_form'          => item_form,
      'item_tier'          => item_tier,
      'resolved_name'      => resolved['name'],
      'applications'       => applications,
      'saturation_blocked' => saturation_blocked,
      'quantity_decrement' => quantity_decrement
    }
  end

  private

  def has_cure?(effect_hash)
    %w[minor_damage moderate_damage major_damage].any? { |k| effect_hash.key?(k) && effect_hash[k].to_i.positive? }
  end

  def has_mana?(effect_hash)
    effect_hash.key?('mana') && effect_hash['mana'].to_i.positive?
  end

  def has_ward?(effect_hash)
    effect_hash.key?('temp_hp') && effect_hash['temp_hp'].to_i.positive?
  end

  def apply_cure(effect_hash, target_conditions)
    return [] unless has_cure?(effect_hash)
    pools = {
      'minor'    => effect_hash['minor_damage'].to_i,
      'moderate' => effect_hash['moderate_damage'].to_i,
      'major'    => effect_hash['major_damage'].to_i
    }
    healed = target_conditions.apply_hit_point_heal_cascade(pools)
    [{ 'kind' => 'heal', 'pools' => pools, 'healed' => healed }]
  end

  def apply_mana(effect_hash, _target_conditions)
    return [] unless has_mana?(effect_hash)
    # Mana isn't tracked in conditions yet; the caller's character
    # module owns mana storage. We surface the amount so the caller
    # can apply it externally.
    [{ 'kind' => 'mana', 'amount' => effect_hash['mana'].to_i, 'unrouted' => true }]
  end

  def apply_ward(effect_hash, target_conditions, spell_name, owner_id)
    return [] unless has_ward?(effect_hash)
    amount = effect_hash['temp_hp'].to_i
    grant = target_conditions.set_temporary_hit_points(amount, "item:#{owner_id}:#{spell_name}")
    [{ 'kind' => 'ward', 'amount' => amount, 'grant' => grant }]
  end

  # Returns the saturation amount to impose on the target.
  # Per-form formulas come from before-refactor's compendium logic:
  #   Potion:
  #     base   = (effect_saturation - target_tier), floored at minimum
  #     bonus  = floor(2 * tier_value(item_tier) * 2^max(item_tier - user_tier, 0))
  #     total  = base + bonus
  #   Oil: same as potion (toxicity falls on the user)
  #   Scroll:
  #     base   = (effect_saturation - target_tier - improved_healing_reduction),
  #              floored at minimum
  #     no bonus
  #   Wand: deferred
  def compute_magic_toxicity(effect_hash, item_form, item_tier, user_tier, target_tier, user_abilities)
    base_saturation = effect_hash['saturation'].to_i
    minimum = effect_hash['minimum_saturation'].to_i
    return 0 if base_saturation.zero? && minimum.zero?

    tier_reduction = target_tier
    if item_form == SCROLL_FORM && user_abilities.include?('improved_healing')
      tier_reduction += 2 * user_tier
    end

    base = [base_saturation - tier_reduction, minimum].max

    case item_form
    when POTION_FORM, OIL_FORM
      base + potion_overhead(item_tier, user_tier)
    when SCROLL_FORM
      base
    when WAND_FORM
      0
    else
      base
    end
  end

  # floor(2 * tier_value * 2^max(item_tier - user_tier, 0))
  def potion_overhead(item_tier, user_tier)
    tier_value = item_tier == 0 ? 0.5 : item_tier.to_f
    diff = [item_tier.to_i - user_tier.to_i, 0].max
    (2 * tier_value * (2**diff)).floor
  end
end
