require 'dice_resolution'
require_relative 'config'

module Proficiencies
  module Compute
    module_function

    def roll_inputs(key:, creature:, attribute_override: nil)
      b = breakdown(key: key, creature: creature, attribute_override: attribute_override)
      bonus_penalty = b[:bonus] + b[:penalty]
      modifier = bonus_penalty.zero? ? nil : ['Competency', bonus_penalty]
      out = { dice_cap: b[:dice_cap], competency_modifier: modifier }
      skill_mods = skill_modifiers_for(creature, b[:key])
      out[:skill_modifiers] = skill_mods unless skill_mods.empty?
      out
    end

    # Every step behind roll_inputs, for showing the math: the winning Prowess
    # source's ranks and attribute, then the translation into dice and bonus.
    # `source_key` differs from `key` when the Substitution Ability's source
    # won. `penalty` (the Non-Proficiency Penalty, or 0) is kept apart from
    # `bonus`; roll_inputs' Competency Modifier is their sum.
    def breakdown(key:, creature:, attribute_override: nil)
      key = key.to_s
      raise ArgumentError, "bare Set Skill key #{key.inspect}" if key.end_with?('_')

      entry = Proficiencies.look_up(key)
      if entry.nil? && attribute_override.nil?
        raise ArgumentError, "unknown key #{key.inspect} requires attribute_override"
      end

      driving_attr = (attribute_override || entry['attribute']).to_sym
      direct = direct_prowess(key, entry, driving_attr, creature)
      substituted = substituted_prowess(key, creature)
      used = substituted && substituted[:prowess] > direct[:prowess] ? substituted : direct

      dice_cap, bonus = DiceResolution.translate_prowess(used[:prowess])
      penalty = !used[:trained] && !key.end_with?('_save') ? Config.non_proficiency_penalty : 0
      used.merge(key: key, dice_cap: dice_cap, bonus: bonus, penalty: penalty)
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
      base_ranks  = creature.ranks_for(key)
      floor_ranks = floor_lift(key, entry, creature)
      prowess_parts(key, driving_attr, creature, ranks: [base_ranks, floor_ranks].max,
                                                 base_ranks: base_ranks, floor_ranks: floor_ranks)
    end

    # One Prowess source: its ranks plus the attribute's contribution.
    def prowess_parts(source_key, attr, creature, ranks:, base_ranks:, floor_ranks:)
      value   = creature.attribute_value(attr)
      contrib = (value.to_f / Config.attribute_contribution_divisor).floor
      { source_key: source_key, attribute: attr, attribute_value: value, attribute_contribution: contrib,
        base_ranks: base_ranks, floor_ranks: floor_ranks, ranks: ranks,
        prowess: ranks + contrib, trained: ranks.positive? }
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
        prowess_parts(source_key, source_entry['attribute'].to_sym, creature,
                      ranks: source_ranks, base_ranks: source_ranks, floor_ranks: 0)
      end.max_by { |p| p[:prowess] }
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
