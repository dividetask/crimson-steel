module Encounter
  # Weapon Attack + Defensive Action assembly (encounter_design.md →
  # Attack / Cast / Use Item, Defensive Actions). This covers weapon
  # Attacks; the Cast counterpart lives in Encounter::Cast +
  # Encounter::State#resolve_cast_payload. Use Item is still deferred
  # (needs the Equipment-consumable wiring).
  #
  # Resolution is client-side (the JS Dice/Check engine): this module
  # builds the *Roll specs* — dice caps, critical_modifier, the
  # Attacker Bonuses, and the eligible Defensive Actions with their
  # costs — that the turn-action UI resolves. The resolved successes
  # come back to Encounter::State#resolve_attack_payload, which spends
  # Combat Pool and applies damage.
  module Attack
    # Defensive Action eligibility + cost, per the design's table.
    #   parry — Martial; melee only; costs a Reaction + Combat-Pool dice.
    #   block — Martial; melee/ranged/spell; costs a Reaction + dice.
    #   dodge — uses the `dex_save` proficiency for its Dice Cap + Modifiers,
    #           but is NOT a Saving Throw: it is a Defensive Action that costs
    #           a Reaction + Combat-Pool dice (Speed 0), like Parry/Block.
    DEFENSES = {
      'parry' => { proficiency: 'martial',   attribute_override: nil,  applies: %w[melee],              pool_cost: true  },
      'block' => { proficiency: 'martial',   attribute_override: nil,  applies: %w[melee ranged spell], pool_cost: true  },
      'dodge' => { proficiency: 'dex_save',  attribute_override: :dex, applies: %w[melee ranged spell], pool_cost: true  }
    }.freeze

    ATTACK_KINDS = %w[melee ranged spell].freeze

    module_function

    def defense_spec(defense_type)
      DEFENSES[defense_type.to_s]
    end

    def defense_eligible?(defense_type, attack_kind)
      spec = DEFENSES[defense_type.to_s]
      spec && spec[:applies].include?(attack_kind.to_s)
    end

    # The eligible Defensive Actions against an attack of `attack_kind`.
    def eligible_defenses(attack_kind)
      DEFENSES.keys.select { |d| defense_eligible?(d, attack_kind) }
    end

    # Attacker Bonuses (encounter_config.yaml). Flatfooted applies when
    # the defender declares no Defensive Action against this attack.
    # Unaware applies when the defender has not yet acted in the Combat —
    # but declaring a Defensive Action proves awareness, so a declared
    # defence (no_defense: false) suppresses Unaware too. Both bonuses
    # therefore require no_defense; when present they can apply together.
    # Returns a bonus_penalty_list of [type, amount] pairs.
    def attacker_bonuses(no_defense:, unaware:)
      list = []
      if no_defense
        list << bonus_pair(Config.data['Flatfooted Bonus'])
        list << bonus_pair(Config.data['Unaware Bonus']) if unaware
      end
      list.compact
    end

    def bonus_pair(cfg)
      return nil unless cfg
      [cfg['type'] || cfg[:type], cfg['amount'] || cfg[:amount]]
    end

    # Assemble the client-resolvable attack spec.
    #
    #   attacker / target — Combatant hashes from the State.
    #   attack_kind       — 'melee' | 'ranged' | 'spell'.
    #   weapon            — { damage_types:, threshold:, bleed:, speed:,
    #                         base_damage: } (Equipment details, formula
    #                         already evaluated by the caller).
    #   attacker_dice_cap / attacker_competency — Proficiencies *Compute
    #                         Roll inputs* for the attack proficiency.
    #   attacker_modifiers — extra [type, amount] pairs (Conditions /
    #                         Abilities aggregation); defaults to none.
    #   unaware           — defender has not acted, or attacker Hidden.
    #   declared_defense  — nil | 'parry' | 'block' | 'dodge'.
    #   defender_inputs   — { dice_cap:, competency:, modifiers:,
    #                         pool_remaining: } for the declared defense.
    def build_spec(attacker:, target:, attack_kind:, weapon:,
                   attacker_dice_cap:, attacker_competency: nil, attacker_modifiers: [],
                   unaware: false, declared_defense: nil, defender_inputs: {})
      raise ArgumentError, "unknown attack kind #{attack_kind.inspect}" unless ATTACK_KINDS.include?(attack_kind.to_s)
      if declared_defense && !defense_eligible?(declared_defense, attack_kind)
        raise ArgumentError, "#{declared_defense} is not eligible against a #{attack_kind} attack"
      end

      crit = Severity.critical_modifier_for(Array(weapon[:damage_types]).first || 'physical')
      bonuses = []
      bonuses << attacker_competency if attacker_competency
      bonuses.concat(Array(attacker_modifiers))
      bonuses.concat(attacker_bonuses(no_defense: declared_defense.nil?, unaware: unaware))

      spec = {
        attacker: {
          combatant_id:      attacker[:id],
          dice_cap:          attacker_dice_cap,
          critical_modifier: crit,
          speed:             weapon[:speed],
          bonus_penalty_list: bonuses.compact,
          weapon: {
            damage_types: Array(weapon[:damage_types]),
            threshold:    weapon[:threshold],
            bleed:        weapon[:bleed],
            base_damage:  weapon[:base_damage]
          }
        },
        target: {
          combatant_id: target[:id],
          unaware:      unaware,
          flatfooted:   declared_defense.nil?
        },
        eligible_defenses: eligible_defenses(attack_kind)
      }

      if declared_defense
        d = DEFENSES[declared_defense.to_s]
        dbonus = []
        dbonus << defender_inputs[:competency] if defender_inputs[:competency]
        dbonus.concat(Array(defender_inputs[:modifiers]))
        spec[:defense] = {
          combatant_id:       target[:id],
          choice:             declared_defense.to_s,
          proficiency:        d[:proficiency],
          attribute_override: d[:attribute_override],
          pool_cost:          d[:pool_cost],
          # Parry/Block/Dodge all cost pool: the defender chooses dice from the
          # Reaction Action Minimum up to remaining pool (Dice Cap still caps
          # the roll). A true Saving Throw (a Save spell) is handled elsewhere.
          min_dice:           d[:pool_cost] ? Config.reaction_action_minimum : defender_inputs[:dice_cap],
          max_dice:           d[:pool_cost] ? [defender_inputs[:dice_cap], defender_inputs[:pool_remaining]].compact.min : defender_inputs[:dice_cap],
          dice_cap:           defender_inputs[:dice_cap],
          bonus_penalty_list: dbonus.compact
        }
      end

      spec
    end
  end
end
