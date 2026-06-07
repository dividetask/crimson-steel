require 'abilities'
require 'proficiencies'

module Encounter
  # Special Actions (turn_action_stub.md → Special). The Special pane lets
  # the DM use a Combatant's non-Spell Abilities that do not require a
  # Reaction — most prominently a Bard's Bardic Performance, but any such
  # Talent qualifies.
  #
  # This module owns only the *classification* rules: which of a Creature's
  # Granted Abilities are usable from the Special pane, and the per-Ability
  # costs the action economy charges. The resource mutation (spend Mana /
  # Combat Pool, begin or continue a Bardic Performance, apply a self
  # Active Effect) lives in Encounter::State#use_special_payload, mirroring
  # how Encounter::Attack pairs with #resolve_attack_payload.
  module Special
    REACTION = 'reaction'.freeze

    module_function

    # A Granted Ability is usable as a Special action when it is a Talent
    # (Spells belong to the Cast pane) that declares an *explicit*
    # activation_time resolving to a non-Reaction action category.
    #
    # Requiring an explicit activation_time is deliberate: it admits active
    # Talents (Rage, Turn Undead, Bardic Inspiration, Magical Performance,
    # Better Lucky Than Good) while excluding the two shapes that share the
    # `talent` type but are not actively "used" here —
    #   - Trigger riders (Sneak Attack, Halfling Luck, monster bites): a
    #     `trigger` and no activation_time. They fire during another action.
    #   - Passive / enabler Talents (Trapfinding, Thieves Cant, the
    #     *_Spellcasting feats): no activation_time at all.
    # Reactions (Primal Tenacity, Danger Sense) are excluded by the alias.
    #
    # `raw` is the un-defaulted Catalog entry; `activation` is the result of
    # Abilities' *Resolve a Catalog Ability's activation time*.
    def usable?(raw, activation)
      return false unless raw.is_a?(Hash)
      return false unless raw['type'] == 'talent'
      return false if raw['activation_time'].nil?
      return false unless activation.is_a?(Hash) && activation[:kind] == :action
      activation[:alias].to_s != REACTION
    end

    # Combat Pool dice the action economy charges to take this action — the
    # Action Minimum for the action's category (encounter_config.yaml). A
    # Free action costs nothing; Bonus / Main cost their respective minima.
    def action_cost(activation_alias)
      case activation_alias.to_s
      when 'free'  then Config.free_action_minimum
      when 'bonus' then Config.bonus_action_minimum
      else Config.main_action_minimum
      end
    end

    # Whether a Channeled Ability's Reservoir fills from **check successes**
    # (a real skill Check, which obeys the skill's Dice Cap — Bardic
    # Inspiration) rather than `channel_dice` / fire (which pour dice straight
    # into the effect and ignore the Dice Cap, per abilities_design.md).
    def check_channel?(raw)
      !!(raw && raw.dig('reservoir', 'fill', 'source').to_s == 'check_successes')
    end

    # The Creature's trained skills usable for a check-based channel's Check,
    # each with its Dice Cap + Competency. The Ability's `skills` list may name
    # a skill **family** (a trailing-underscore prefix like `perform_`, matched
    # by every trained `perform_<type>`) or an exact skill key. Returns
    # [{ key:, label:, dice_cap:, competency: }] in the Creature's trained order
    # (empty when the Creature trains none, or has no class records).
    def check_skills(accessor, raw)
      return [] unless accessor.respond_to?(:record)
      trained  = (accessor.record[:classes] || {}).values
                      .flat_map { |e| Array(e[:skills]) }.map(&:to_s).uniq
      families = Array(raw && raw['skills']).map(&:to_s)
      trained.select { |k| families.any? { |f| f.end_with?('_') ? (k.start_with?(f) && k != f) : k == f } }
             .map do |k|
        ri = (Proficiencies::Compute.roll_inputs(key: k, creature: accessor) rescue {})
        { key: k, label: pretty_skill(k), dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier] }
      end
    rescue StandardError
      []
    end

    # Render a skill key for display: a Set-Skill (`perform_dance`) reads
    # `Perform (Dance)`; a plain key (`sleight_of_hand`) Title-Cases.
    def pretty_skill(key)
      k = key.to_s
      if k.include?('_') && (Proficiencies.skills.key?("#{k.split('_').first}_") rescue false)
        family, *rest = k.split('_')
        return "#{family.capitalize} (#{rest.map(&:capitalize).join(' ')})"
      end
      k.split('_').map(&:capitalize).join(' ')
    end

    # The Ability's unconditional named Effects (Conditions Effect Names),
    # for self-target application. Damage expressions and "0"/"none" are
    # dropped — only Effect Names (e.g. `rage`) are returned.
    def named_effects(effects, context: {})
      Array(effects).filter_map do |str|
        cls = Abilities.classify_effect(str.to_s, context: context)
        cls[:name] if cls[:kind] == :effect
      end
    end
  end
end
