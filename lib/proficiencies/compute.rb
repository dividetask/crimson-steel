require 'dice_resolution'
require_relative 'config'

module Proficiencies
  module Compute
    module_function

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
      bonus_penalty += Config.non_proficiency_penalty if !trained && !key.end_with?('_save')
      modifier = bonus_penalty.zero? ? nil : ['Competency', bonus_penalty]
      out = { dice_cap: dice_cap, competency_modifier: modifier }
      skill_mods = skill_modifiers_for(creature, key)
      out[:skill_modifiers] = skill_mods unless skill_mods.empty?
      out
    end

    def skill_modifiers_for(creature, key)
      return [] unless creature.respond_to?(:skill_modifiers)
      Array(creature.skill_modifiers(key))
    rescue StandardError
      []
    end

    def untrained_roll_inputs(attribute:, creature:)
      effective_ranks = floor_ability_ranks(creature)
      attr_contrib = (creature.attribute_value(attribute).to_f /
                      Config.attribute_contribution_divisor).floor
      prowess = effective_ranks + attr_contrib

      dice_cap, bonus_penalty = DiceResolution.translate_prowess(prowess)
      bonus_penalty += Config.non_proficiency_penalty if effective_ranks.zero?
      modifier = bonus_penalty.zero? ? nil : ['Competency', bonus_penalty]
      { dice_cap: dice_cap, competency_modifier: modifier }
    end

    def direct_prowess(key, entry, driving_attr, creature)
      base_ranks = creature.ranks_for(key)

      floor_ranks = floor_lift(key, entry, creature)
      effective_ranks = [base_ranks, floor_ranks].max

      attr_contrib = (creature.attribute_value(driving_attr).to_f /
                      Config.attribute_contribution_divisor).floor

      [effective_ranks + attr_contrib, effective_ranks.positive?]
    end

    def floor_lift(key, entry, creature)
      return 0 if entry.nil?
      return 0 if Config.restricted_skills.include?(key)
      floor_ability_ranks(creature)
    end

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

  def compute(key:, creature:, attribute_override: nil)
    Compute.roll_inputs(key: key, creature: creature, attribute_override: attribute_override)
  end

  def list_skills
    Proficiencies.skills.dup
  end
end
