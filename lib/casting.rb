require_relative 'abilities'
require_relative 'conditions'

# Casting — orchestration for a direct spell cast.
#
# Parallel to ItemUse: looks up the spell entry through abilities,
# applies the resolved effect_hash conventions (cure / mana / ward)
# to the target's Conditions, imposes Magic Toxicity on the
# **caster** (not the target — that's the item flow), and spends
# the caster's mana. Damage effects and save-based effects are
# returned in their deferred form so callers can roll the casting
# check, evaluate the formulas, and route damage through
# Combat#apply_attack_damage themselves.
#
# This module owns no state. The participants — Conditions
# instances, the abilities catalog — are passed in via callbacks.
class Casting
  CONCENTRATION_DURATION = nil # caller decides when concentration ends

  def initialize(abilities:, conditions_lookup:)
    @abilities = abilities
    @conditions_lookup = conditions_lookup
  end

  # Required parameters:
  #   spell_name     — entry name in the abilities catalog
  #   caster_char_id — the casting character's id (for conditions
  #                    lookup; receives mana cost + magic toxicity)
  #   target_char_id — the target's id (for conditions lookup;
  #                    receives heals / wards / mana restoration).
  #                    Same id as caster_char_id for self-targeted
  #                    spells.
  #   rank           — caster's rank in the chosen casting skill;
  #                    drives every formula in the spell.
  #   mana_cost      — integer; how much mana the caster spends.
  #                    The schema doesn't yet carry this directly,
  #                    so the caller decides the value (typically
  #                    tier-based).
  #
  # Optional parameters:
  #   tier_index, aspect_index — passed to AbilitySystem.resolve_entry
  #   caster_max_toxicity      — saturation cap on the caster.
  #                              Cure and mana effects refuse to
  #                              land when caster's current
  #                              magic_toxicity >= this. Pass nil
  #                              to disable the gate.
  #   target_max_mana          — cap for restore_mana on the target.
  #                              When omitted, mana applications
  #                              come back tagged unrouted.
  #
  # Returns a hash describing the cast outcome. Possible top-level
  # keys:
  #   error                — set to 'insufficient_mana' if the
  #                          caster can't afford the cost. No
  #                          mana is spent in that case.
  #   saturation_blocked   — true when the saturation gate fires.
  #                          No mana is spent.
  #   spell_name, caster_char_id, target_char_id, resolved_name
  #   mana_spent           — actual amount the caster paid
  #   applications         — list of immediate effects landed on
  #                          the target (heal / ward / mana) and
  #                          on the caster (magic_toxicity_caster)
  #   damage_effects       — deferred damage objects from the
  #                          spell's `effects` list (for the
  #                          caster to evaluate via abilities and
  #                          route through combat)
  #   save_specs           — deferred save list for caller-driven
  #                          save resolution
  #   concentration        — the resolved Concentration Block, or
  #                          nil. Caller is responsible for
  #                          tracking concentration on the caster.
  def cast(spell_name:, caster_char_id:, target_char_id:,
           rank:, mana_cost: 0,
           tier_index: nil, aspect_index: nil,
           caster_max_toxicity: nil, target_max_mana: nil)
    caster_conditions = @conditions_lookup.call(caster_char_id)
    raise "No conditions instance for #{caster_char_id}" unless caster_conditions
    target_conditions = @conditions_lookup.call(target_char_id)
    raise "No conditions instance for #{target_char_id}" unless target_conditions

    # Mana check. Failing this returns early — no spell side-effects,
    # no mana spent.
    if caster_conditions.current_mana < mana_cost.to_i
      return {
        'error'        => 'insufficient_mana',
        'mana_cost'    => mana_cost.to_i,
        'current_mana' => caster_conditions.current_mana
      }
    end

    resolved = @abilities.resolve_entry(
      spell_name,
      rank,
      tier_index: tier_index,
      aspect_index: aspect_index
    )
    effect_hash = resolved['effect_hash'] || {}

    # Saturation gate (caster-side, mirroring ItemUse's target-side
    # gate for items). Cure and mana effects refuse to land when
    # the caster is at or above the supplied cap.
    saturation_blocked = false
    if caster_max_toxicity && caster_conditions.magic_toxicity >= caster_max_toxicity
      if has_cure?(effect_hash) || has_mana?(effect_hash)
        saturation_blocked = true
      end
    end

    if saturation_blocked
      return {
        'spell_name'         => spell_name,
        'resolved_name'      => resolved['name'],
        'saturation_blocked' => true,
        'mana_spent'         => 0,
        'applications'       => []
      }
    end

    spent = caster_conditions.apply_mana_cost(mana_cost.to_i)
    applications = []

    applications.concat(apply_cure(effect_hash, target_conditions))
    applications.concat(apply_mana(effect_hash, target_conditions, target_max_mana))
    applications.concat(apply_ward(effect_hash, target_conditions, spell_name, caster_char_id))
    applications.concat(apply_caster_toxicity(effect_hash, caster_conditions))

    {
      'spell_name'      => spell_name,
      'caster_char_id'  => caster_char_id,
      'target_char_id'  => target_char_id,
      'resolved_name'   => resolved['name'],
      'mana_spent'      => spent,
      'applications'    => applications,
      'damage_effects'  => Array(resolved['effects']),
      'save_specs'      => Array(resolved['saves']),
      'concentration'   => resolved['concentration']
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

  def apply_mana(effect_hash, target_conditions, target_max_mana)
    return [] unless has_mana?(effect_hash)
    amount = effect_hash['mana'].to_i
    if target_max_mana.nil?
      return [{ 'kind' => 'mana', 'amount' => amount, 'unrouted' => true }]
    end
    before = target_conditions.current_mana
    target_conditions.restore_mana(amount, max: target_max_mana)
    [{ 'kind' => 'mana', 'amount' => amount, 'gained' => target_conditions.current_mana - before }]
  end

  def apply_ward(effect_hash, target_conditions, spell_name, caster_char_id)
    return [] unless has_ward?(effect_hash)
    amount = effect_hash['temp_hp'].to_i
    grant = target_conditions.set_temporary_hit_points(amount, "spell:#{caster_char_id}:#{spell_name}")
    [{ 'kind' => 'ward', 'amount' => amount, 'grant' => grant }]
  end

  # Direct casting imposes Magic Toxicity on the caster, not the
  # target. Formula mirrors ItemUse's potion math but without the
  # potion overhead — there's no item tier vs user tier delta to
  # account for.
  def apply_caster_toxicity(effect_hash, caster_conditions)
    base = effect_hash['saturation'].to_i
    minimum = effect_hash['minimum_saturation'].to_i
    return [] if base.zero? && minimum.zero?
    amount = [base, minimum].max
    return [] if amount <= 0
    caster_conditions.apply_magic_toxicity(amount)
    [{ 'kind' => 'magic_toxicity_caster', 'amount' => amount }]
  end
end
