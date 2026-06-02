require 'abilities'

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
