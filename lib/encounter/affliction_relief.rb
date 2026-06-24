require 'dice_resolution'

module Encounter
  # Out-of-combat Affliction relief simulator. Fast-forwards a single
  # round-based Affliction 
  module AfflictionRelief
    module_function

    CHANNELS_PER_ROUND = 2
    DEFAULT_MAX_ROUNDS = 60
    CRIT_MODIFIER = 2
    FAIL_MODIFIER = -1

    def run(instance:, affliction_name:, creature_tier:, save:, aiders: [],
            creature_name: 'Creature', death_threshold: nil, rng: Random.new,
            max_rounds: DEFAULT_MAX_ROUNDS)
      name   = affliction_name.to_s
      before = hp_damage_snapshot(instance)
      mana   = {}
      channeled = {}
      log    = []
      rounds = 0
      died   = false

      while instance.state.afflictions.key?(name) && rounds < max_rounds
        rounds += 1
        entry = { round: rounds, rolls: [] }

        pot_before = instance.state.afflictions[name][:potency]
        sv = roll_check(dice: save[:save_dice], die_size: save[:die_size], rng: rng,
                        modifiers: save_modifier_list(save, pot_before))
        result = instance.resolve_affliction(name, {}, dois: sv[:dois],
                                             current_round: rounds, creature_tier: creature_tier.to_i)
        entry[:rolls] << { actor: creature_name, kind: 'save', successes: [sv[:dois], 0].max,
                           potency_before: pot_before, potency_after: result[:new_potency].to_i,
                           damage: result[:net_magnitude].to_i, roll: roll_view(sv) }

        if death_threshold && total_hp_damage(instance) >= death_threshold.to_i
          died = true
          log << entry
          break
        end

        aiders.each do |a|
          CHANNELS_PER_ROUND.times do
            break unless instance.state.afflictions.key?(name)
            channeled[a[:id]] = true
            hb     = instance.state.afflictions[name][:potency]
            hv     = roll_check(dice: a[:heal_dice], die_size: a[:die_size] || save[:die_size],
                                rng: rng, modifiers: Array(a[:heal_modifiers]))
            succ   = [hv[:dois], 0].max
            tier_value = a[:spell_tier].to_i.zero? ? 0.5 : a[:spell_tier].to_i
            amount = (succ * tier_value * 2).floor
            instance.reduce_affliction_potency(name, amount) if amount.positive?
            ha = instance.state.afflictions.key?(name) ? instance.state.afflictions[name][:potency] : 0
            entry[:rolls] << { actor: a[:name], kind: 'heal', successes: succ,
                               potency_before: hb, potency_after: ha, roll: roll_view(hv) }
          end
        end
        log << entry
      end

      aiders.each { |a| mana[a[:id]] = a[:mana_cost].to_i if channeled[a[:id]] }

      after = hp_damage_snapshot(instance)
      { rounds:     rounds,
        cleared:    !instance.state.afflictions.key?(name),
        died:       died,
        hp_damage:  hp_damage_diff(before, after),
        aider_mana: mana,
        log:        log }
    end

    def roll_check(dice:, die_size:, modifiers:, rng:)
      die = die_size.to_i
      die = 6 if die <= 0
      calc = DiceResolution.compute_target_number(normalize_modifiers(modifiers))
      tn   = calc[:tn]
      values = Array.new([dice.to_i, 0].max) { rng.rand(1..die) }
      dois = calc[:starting_value] + values.sum do |v|
        if    v == die then CRIT_MODIFIER
        elsif v == 1   then FAIL_MODIFIER
        elsif v >= tn  then 1
        else 0
        end
      end
      { dois: dois, values: values, tn: tn, die_size: die, starting: calc[:starting_value] }
    end

    def roll_dois(dice:, die_size:, modifiers:, rng:)
      roll_check(dice: dice, die_size: die_size, modifiers: modifiers, rng: rng)[:dois]
    end

    def roll_view(check)
      { values: check[:values], tn: check[:tn], die_size: check[:die_size], starting: check[:starting] }
    end

    def save_modifier_list(save, potency)
      divisor = save[:potency_divisor].to_i
      penalty = divisor.positive? ? potency.to_i / divisor : 0
      list = normalize_modifiers(save[:save_modifiers])
      list << ['Inherent', save[:creature_tier].to_i] if save[:creature_tier].to_i.positive?
      list << ['Competency', -penalty] if penalty.positive?
      list << ['Inherent', -save[:inflicter_tier].to_i]
      list
    end

    def normalize_modifiers(modifiers)
      Array(modifiers).map { |m| m.is_a?(Array) ? m : [m[:type] || m['type'], m[:amount] || m['amount']] }
    end

    def hp_damage_snapshot(instance)
      { minor:    instance.state.hp_damage[:minor].to_i,
        moderate: instance.state.hp_damage[:moderate].to_i,
        major:    instance.state.hp_damage[:major].to_i }
    end

    # Total HP damage across all Severities — compared to the death threshold.
    def total_hp_damage(instance)
      instance.state.hp_damage.values.sum
    end

    def hp_damage_diff(before, after)
      { minor:    after[:minor]    - before[:minor],
        moderate: after[:moderate] - before[:moderate],
        major:    after[:major]    - before[:major] }
    end
  end
end
