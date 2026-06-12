require 'dice_resolution'
require_relative 'config'

module Proficiencies
  # Compute Roll inputs for a Proficiency. Implements
  # proficiencies_design.md's `Compute Roll inputs` pipeline:
  # resolves the catalog entry, computes Direct Prowess, computes
  # Substituted Prowess when the Substitution Ability is present
  # and the queried key is in the Substitution Map, picks the
  # higher Prowess (Direct wins ties), and translates through
  # dice_resolution.
  module Compute
    module_function

    # Inputs:
    #   key (string) — proficiency key being resolved.
    #   creature      — anything responding to ranks_for(key),
    #                   attribute_value(attr), has_ability(name),
    #                   level_for_ability(name). The Creature
    #                   Accessor satisfies this.
    #   attribute_override (Symbol|nil) — overrides the driving
    #                   attribute. Required when the key has no
    #                   catalog entry.
    #
    # Returns: { dice_cap:, competency_modifier: } where
    # competency_modifier is either nil (when bonus_penalty is zero)
    # or a [type_name, signed_value] pair.
    def roll_inputs(key:, creature:, attribute_override: nil)
      key = key.to_s
      raise ArgumentError, "bare Set Skill key #{key.inspect}" if key.end_with?('_')

      entry = Proficiencies.look_up(key)
      if entry.nil? && attribute_override.nil?
        raise ArgumentError, "unknown key #{key.inspect} requires attribute_override"
      end

      driving_attr = (attribute_override || entry['attribute']).to_sym
      direct_value, direct_trained = direct_prowess(key, entry, driving_attr, creature)
      substituted = substituted_prowess(key, creature)

      prowess, trained = if substituted && substituted.first > direct_value
                           substituted
                         else
                           [direct_value, direct_trained]
                         end

      dice_cap, bonus_penalty = DiceResolution.translate_prowess(prowess)
      # The Non-Proficiency Penalty is a Target-Number penalty — it adjusts the
      # Competency Modifier, never the dice count (a bonus/penalty never moves
      # dice; only ranks + attribute do). It applies only to an *untrained Skill
      # check*; a Saving Throw (`*_save`) never takes it.
      bonus_penalty += Config.non_proficiency_penalty if !trained && !key.end_with?('_save')
      modifier = bonus_penalty.zero? ? nil : ['Competency', bonus_penalty]
      out = { dice_cap: dice_cap, competency_modifier: modifier }
      # Equipped skill-targeted Guidance (an Elven Cloak's +1 to `stealth`) only
      # decorates the result when present, so the bare proficiency shape (and the
      # pure-module specs) are unchanged for a skill with no such Item.
      skill_mods = skill_modifiers_for(creature, key)
      out[:skill_modifiers] = skill_mods unless skill_mods.empty?
      out
    end

    # Equipped Guidance Bonuses that target this skill key by name (e.g. an
    # Elven Cloak's +1 to `stealth`), as a list of [type, amount] pairs to
    # append to the Roll's bonus_penalty_list — a different Bonus Type than the
    # Competency, so it stacks alongside rather than merging. Empty when the
    # creature does not expose the bridge (pure-proficiency unit specs).
    def skill_modifiers_for(creature, key)
      return [] unless creature.respond_to?(:skill_modifiers)
      Array(creature.skill_modifiers(key))
    rescue StandardError
      []
    end

    # Roll inputs for an *untrained* (zero-rank) non-Restricted Skill
    # driven by `attribute`. This is what the Floor Ability (Jack of
    # All Trades) grants on Skills the Creature has no ranks in: it
    # mirrors direct_prowess with base ranks pinned to zero, so without
    # the Floor Ability it collapses to attr_contrib + the
    # Non-Proficiency Penalty. Restricted Skills are out of scope here.
    #
    # Returns the same { dice_cap:, competency_modifier: } shape as
    # roll_inputs.
    def untrained_roll_inputs(attribute:, creature:)
      effective_ranks = floor_ability_ranks(creature)
      attr_contrib = (creature.attribute_value(attribute).to_f /
                      Config.attribute_contribution_divisor).floor
      prowess = effective_ranks + attr_contrib

      dice_cap, bonus_penalty = DiceResolution.translate_prowess(prowess)
      # Untrained Skill check: the Non-Proficiency Penalty rides the Competency
      # Modifier (Target Number), not the dice. The Floor Ability lift may make
      # it trained (effective_ranks > 0), in which case no penalty applies.
      bonus_penalty += Config.non_proficiency_penalty if effective_ranks.zero?
      modifier = bonus_penalty.zero? ? nil : ['Competency', bonus_penalty]
      { dice_cap: dice_cap, competency_modifier: modifier }
    end

    # ---- pipeline pieces -----------------------------------------------

    # Returns `[prowess, trained?]`. Prowess (effective ranks + attribute
    # contribution) is what sets the dice count and the base Competency — it
    # carries no bonus/penalty, because a bonus/penalty must never move the
    # dice. `trained?` (effective ranks > 0) tells the caller whether the
    # Non-Proficiency Penalty applies, which the caller layers onto the Target
    # Number.
    def direct_prowess(key, entry, driving_attr, creature)
      base_ranks = creature.ranks_for(key)

      floor_ranks = floor_lift(key, entry, creature)
      effective_ranks = [base_ranks, floor_ranks].max

      attr_contrib = (creature.attribute_value(driving_attr).to_f /
                      Config.attribute_contribution_divisor).floor

      [effective_ranks + attr_contrib, effective_ranks.positive?]
    end

    def floor_lift(key, entry, creature)
      return 0 if entry.nil?  # Floor doesn't apply to keys without a catalog entry.
      return 0 if Config.restricted_skills.include?(key)
      # Also restricted by the resolved entry's own key: a Set
      # Instance whose family is restricted (e.g. `restricted_magic_*`)
      # would inherit. The shipped config only restricts the plain
      # `restricted_magic`, so the entry-level check is enough.
      floor_ability_ranks(creature)
    end

    # floor(granting class level / 2) the Floor Ability grants, or 0
    # when the Creature lacks the ability. Callers apply any
    # Restricted-Skill / catalog-entry guards before calling (see
    # floor_lift).
    def floor_ability_ranks(creature)
      ability = Config.floor_ability
      return 0 unless ability
      return 0 unless creature.has_ability(ability)
      (creature.level_for_ability(ability).to_f / 2).floor
    end

    def substituted_prowess(key, creature)
      ability = Config.substitution_ability
      return nil unless ability
      return nil unless creature.has_ability(ability)

      sources = Config.substitution_map.select do |_src, targets|
        Array(targets).include?(key)
      end.keys
      return nil if sources.empty?

      # Each source yields `[prowess, trained?]` (penalty-free, like
      # direct_prowess); the highest Prowess wins, and its `trained?` flows back
      # so the caller can decide the Target-Number penalty.
      sources.map do |source_key|
        source_entry = Proficiencies.look_up(source_key)
        raise ArgumentError, "Substitution source #{source_key.inspect} has no catalog entry" \
          unless source_entry

        source_ranks = creature.ranks_for(source_key)
        source_attr  = source_entry['attribute'].to_sym
        attr_contrib = (creature.attribute_value(source_attr).to_f /
                        Config.attribute_contribution_divisor).floor
        [source_ranks + attr_contrib, source_ranks.positive?]
      end.max_by(&:first)
    end
  end

  module_function

  # Convenient module-level surface mirroring the design's
  # "Compute Roll inputs" entry-point name.
  def compute(key:, creature:, attribute_override: nil)
    Compute.roll_inputs(key: key, creature: creature, attribute_override: attribute_override)
  end

  def list_skills
    Proficiencies.skills.dup
  end
end
