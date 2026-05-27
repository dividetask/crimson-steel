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
      direct = direct_prowess(key, entry, driving_attr, creature)
      substituted = substituted_prowess(key, creature)

      prowess = if substituted && substituted > direct
                  substituted
                else
                  direct
                end

      dice_cap, bonus_penalty = DiceResolution.translate_prowess(prowess)
      modifier = bonus_penalty.zero? ? nil : ['Competency', bonus_penalty]
      { dice_cap: dice_cap, competency_modifier: modifier }
    end

    # ---- pipeline pieces -----------------------------------------------

    def direct_prowess(key, entry, driving_attr, creature)
      base_ranks = creature.ranks_for(key)

      floor_ranks = floor_lift(key, entry, creature)
      effective_ranks = [base_ranks, floor_ranks].max

      attr_contrib = (creature.attribute_value(driving_attr).to_f /
                      Config.attribute_contribution_divisor).floor
      penalty = effective_ranks.zero? ? Config.non_proficiency_penalty : 0

      effective_ranks + attr_contrib + penalty
    end

    def floor_lift(key, entry, creature)
      ability = Config.floor_ability
      return 0 unless ability
      return 0 unless creature.has_ability(ability)
      return 0 if entry.nil?  # Floor doesn't apply to keys without a catalog entry.
      return 0 if Config.restricted_skills.include?(key)
      # Also restricted by the resolved entry's own key: a Set
      # Instance whose family is restricted (e.g. `restricted_magic_*`)
      # would inherit. The shipped config only restricts the plain
      # `restricted_magic`, so the entry-level check is enough.
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

      sources.map do |source_key|
        source_entry = Proficiencies.look_up(source_key)
        raise ArgumentError, "Substitution source #{source_key.inspect} has no catalog entry" \
          unless source_entry

        source_ranks = creature.ranks_for(source_key)
        source_attr  = source_entry['attribute'].to_sym
        attr_contrib = (creature.attribute_value(source_attr).to_f /
                        Config.attribute_contribution_divisor).floor
        penalty = source_ranks.zero? ? Config.non_proficiency_penalty : 0
        source_ranks + attr_contrib + penalty
      end.max
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
