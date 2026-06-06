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

    # Attacker Bonuses (encounter_config.yaml). Flatfooted applies whenever
    # the defender is not actively Dodging — so no defence and Block / Parry
    # all leave the target Flatfooted; only a Dodge sheds it. Unaware applies
    # when the defender has not yet acted in the Combat, but declaring any
    # Defensive Action proves awareness, so the caller passes `unaware: false`
    # for a declared defence. The caller decides each flag per branch.
    # Returns a bonus_penalty_list of [type, amount] pairs.
    def attacker_bonuses(flatfooted:, unaware:)
      list = []
      list << bonus_pair(Config.data['Flatfooted Bonus'], 'flatfooted') if flatfooted
      list << bonus_pair(Config.data['Unaware Bonus'],     'unaware')    if unaware
      list.compact
    end

    # A [type, amount] (or [type, amount, source]) Bonus/Penalty entry. The
    # optional `source` is a display label (e.g. "flatfooted") the TN-breakdown
    # tooltip shows in parentheses; TN computation ignores it (it destructures
    # only type + amount), so per-Type stacking is unaffected.
    def bonus_pair(cfg, source = nil)
      return nil unless cfg
      pair = [cfg['type'] || cfg[:type], cfg['amount'] || cfg[:amount]]
      source ? pair + [source] : pair
    end

    # ---- Tier modifiers on the attack check (Inherent / Ascendancy) ----
    #
    # Every Creature's Inherent Bonus (Creatures' Tier Minimum Inherent Bonus
    # table) applies to its checks, not only its Attributes. On a weapon attack
    # both sides carry their Inherent Bonus, and the Tier-gap effect — the
    # Ascendancy — is produced by Check Resolution's cross-side propagation:
    # when a Roll's Inherent crosses to the opposing Roll it is inverted *and
    # relabeled Ascendancy* (see propagation.js → CROSS_SIDE_RELABEL), so a
    # higher-Tier defender's Inherent lands on the attacker's TN as an
    # Ascendancy Penalty. When the defender declares no Defensive Action it does
    # not roll — nothing propagates — so Combat supplies the same Ascendancy
    # explicitly: the defender's Inherent, negated. A weapon's Glory Property
    # (`tier_advantage`) treats the wielder as that many Tiers higher when
    # fighting up, lifting its Inherent Bonus and shrinking the gap. Magnitudes
    # come entirely from the Inherent table — Ascendancy invents no new number.

    # The wielder's effective Tier for the attack: raised by a Glory weapon's
    # `tier_advantage`, but only when the defender outranks the attacker.
    def effective_attacker_tier(attacker_tier, defender_tier, tier_advantage)
      bump = (tier_advantage.to_i.positive? && defender_tier.to_i > attacker_tier.to_i) ? tier_advantage.to_i : 0
      attacker_tier.to_i + bump
    end

    # Inherent Bonus amount for a Tier from the Tier Minimum Inherent Bonus
    # table (clamped to the table's range; 0 when empty).
    def inherent_amount(inherent_table, tier)
      t = Array(inherent_table)
      return 0 if t.empty?
      idx = tier.to_i.clamp(0, t.length - 1)
      (t[idx] || 0).to_i
    end

    # The attacker roll's Tier modifiers: its (Glory-adjusted) Inherent Bonus,
    # plus — only against an undefended target — an Ascendancy penalty equal to
    # the defender's Inherent (the advantage that would otherwise propagate).
    # Returns a bonus_penalty_list of [type, amount] pairs.
    def attacker_tier_bonuses(attacker_tier:, defender_tier:, tier_advantage:, inherent_table:, no_defense:)
      eff = effective_attacker_tier(attacker_tier, defender_tier, tier_advantage)
      list = []
      inh = inherent_amount(inherent_table, eff)
      list << ['Inherent', inh] unless inh.zero?
      if no_defense
        asc = -inherent_amount(inherent_table, defender_tier)
        list << ['Ascendancy', asc] unless asc.zero?
      end
      list
    end

    # The defender roll's Tier modifier: its Inherent Bonus (which propagates
    # onto the attacker's TN per Check Resolution). [] when zero.
    def defender_tier_bonuses(defender_tier:, inherent_table:)
      inh = inherent_amount(inherent_table, defender_tier)
      inh.zero? ? [] : [['Inherent', inh]]
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
