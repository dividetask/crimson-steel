module Encounter
  module Attack
    # Defensive Action eligibility + cost, per the design's table.
    DEFENSES = {
      'parry' => { proficiency: 'martial',   attribute_override: nil,  applies: %w[melee],              pool_cost: true  },
      'block' => { proficiency: 'martial',   attribute_override: nil,  applies: %w[melee ranged spell], pool_cost: true  },
      'dodge' => { proficiency: 'dex_save',  attribute_override: :dex, applies: %w[melee ranged spell], pool_cost: true  },
      'ringparry' => { proficiency: 'martial', attribute_override: nil, applies: %w[melee], pool_cost: false, conditional: true }
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

    def eligible_defenses(attack_kind)
      DEFENSES.reject { |_d, spec| spec[:conditional] }.keys
              .select { |d| defense_eligible?(d, attack_kind) }
    end

    def attacker_bonuses(flatfooted:, unaware:, helpless: false)
      list = []
      if helpless
        list << bonus_pair(Config.data['Helpless Bonus'], 'helpless')
      else
        list << bonus_pair(Config.data['Flatfooted Bonus'], 'flatfooted') if flatfooted
        list << bonus_pair(Config.data['Unaware Bonus'],     'unaware')    if unaware
      end
      list.compact
    end

    def bonus_pair(cfg, source = nil)
      return nil unless cfg
      pair = [cfg['type'] || cfg[:type], cfg['amount'] || cfg[:amount]]
      source ? pair + [source] : pair
    end

    def effective_attacker_tier(attacker_tier, defender_tier, tier_advantage)
      bump = (tier_advantage.to_i.positive? && defender_tier.to_i > attacker_tier.to_i) ? tier_advantage.to_i : 0
      attacker_tier.to_i + bump
    end

    def inherent_amount(inherent_table, tier)
      t = Array(inherent_table)
      return 0 if t.empty?
      idx = tier.to_i.clamp(0, t.length - 1)
      (t[idx] || 0).to_i
    end

    def attacker_tier_bonuses(attacker_tier:, defender_tier:, tier_advantage:, inherent_table:, no_defense:)
      eff = effective_attacker_tier(attacker_tier, defender_tier, tier_advantage)
      list = [['Inherent', inherent_amount(inherent_table, eff)]]
      list << ['Inherent', -inherent_amount(inherent_table, defender_tier)] if no_defense
      list
    end

    def defender_tier_bonuses(defender_tier:, inherent_table:)
      [['Inherent', inherent_amount(inherent_table, defender_tier)]]
    end

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
      no_def = declared_defense.nil?
      bonuses.concat(attacker_bonuses(flatfooted: (no_def || declared_defense.to_s != 'dodge'),
                                      unaware: (no_def && unaware)))

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
