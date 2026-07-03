module Encounter
  # Spell Cast assembly (encounter_design.md → Attack / Cast / Use Item;
  # turn_action_stub.md → Cast). Parallel to Encounter::Attack: a pure helper
  # module — no state, no dice. Resolution is client-side (the JS Dice/Check
  # engine rolls the casting check and each target's Save); the resolved
  # Successes come back to Encounter::State#resolve_cast_payload, which spends
  # Combat Pool, debits Mana, applies Magic Toxicity, and routes each resolved
  # Effect to Conditions / Combat.
  #
  # The spell itself is interpreted by the Abilities domain
  # (`Abilities.resolve_spell`) — Combat never reads spell YAML. The payload
  # carries already-evaluated Effects, exactly as the Attack flow carries an
  # already-evaluated weapon (`resolve_attack_payload`).
  module Cast
    # Default casting skill when a spell names none (abilities_design.md →
    # `skills`, turn_action_stub.md → Cast step 3).
    DEFAULT_CAST_SKILL = 'arcana'.freeze

    # Sustain kinds Combat tracks for a cast (encounter_design.md → Begin
    # Concentration / Begin Long Cast).
    SUSTAIN_KINDS = %w[concentration long_cast].freeze

    module_function

    # Can the caster pay a spell's per-Tier Mana Cost out of what remains?
    def mana_affordable?(remaining:, cost:)
      cost.to_i <= remaining.to_i
    end

    # The Combat-Pool cost of a cast: the casting time's flat Speed plus one
    # per die rolled — `Speed + dice` (mirrors a weapon Attack). Speed is a
    # flat surcharge, not a per-die multiplier.
    def pool_cost(speed:, dice:)
      speed.to_i + dice.to_i
    end

    # Halved Effect (abilities_design.md): on a successful Save whose
    # `on_success` is `halved`, each Severity's count is floor-halved
    # independently. Zero results are dropped.
    def halve_severity_map(map)
      (map || {}).each_with_object({}) do |(sev, n), h|
        half = n.to_i / 2
        h[sev] = half if half.positive?
      end
    end

    def halve_amount(value)
      value.to_i / 2
    end

    # Default damage for a damage-dealing Spell that declares no explicit damage
    # Effect: floor(casting stat / 4) + Spell Tier + casting-skill Competency +
    # Successes rolled. The casting stat is the attribute backing the Spell's
    # casting skill; the Competency is that skill's Competency Modifier (which
    # also rides the casting-check Roll — Competency applies to both the roll
    # and the damage). Tier 0 is treated as 0.5 (project formula convention);
    # the total is floored. A Spell that states its own damage formula overrides
    # this default.
    def default_spell_damage(casting_stat:, tier:, successes:, competency: 0)
      tier_value = tier.to_i.zero? ? 0.5 : tier.to_i
      (casting_stat.to_i / 4 + tier_value + competency.to_i + successes.to_i).floor
    end

    # Floor-halve a single resolved Effect for the Halved rule. Damage /
    # heal Severity maps halve per Severity; scalar amounts (`amount`)
    # floor-halve. Non-numeric Effects (a bare named Active Effect) are
    # returned unchanged.
    def halve_effect(effect)
      e = effect.dup
      case e[:kind].to_s
      when 'damage'
        if e.key?(:severity_map) then e[:severity_map] = halve_severity_map(e[:severity_map])
        elsif e.key?(:amount)    then e[:amount] = halve_amount(e[:amount]) end
      when 'heal'
        e[:severity_map] = halve_severity_map(e[:severity_map])
      when 'mana', 'temp_hp'
        e[:amount] = halve_amount(e[:amount])
      when 'effect'
        e[:amount] = halve_amount(e[:amount]) if e.key?(:amount)
      end
      e
    end

    # Resolve one target's Save against the caster's casting-check Successes
    # and return [outcome, effects]. With no Save the full Effects always
    # land. With a Save, the cast is an opposed Check (mirrors the Attack
    # flow's Supporting − Opposing): when the caster's Successes beat the
    # target's Save Successes the target *fails* its Save and takes the full
    # Effects; otherwise the Save succeeds and `on_success` decides the
    # reduction — `halved` floor-halves every Effect, `none`/`0` negates them,
    # anything else swaps in the Save's `success_effects`.
    def resolve_save(effects:, caster_successes:, save:)
      effects = Array(effects)
      return ['hit', effects] unless save

      net = caster_successes.to_i - save[:successes].to_i
      return ['failed_save', effects] if net.positive?

      case (save[:on_success] || 'none').to_s
      when 'halved'
        ['saved_halved', effects.map { |e| halve_effect(e) }]
      when 'none', '0', ''
        ['saved_negated', []]
      else
        ['saved_alternate', Array(save[:success_effects])]
      end
    end

    # Classify a spell's sustain from its Channel / Reservoir / casting-time
    # metadata into the Encounter bookkeeping it needs:
    #   nil                                   — instantaneous, single-turn cast.
    #   { kind: :concentration, mode:, ... }  — a Channeled spell (Begin Concentration).
    #   { kind: :long_cast, turns_required: } — a multi-turn cast (Begin Long Cast).
    # A single-turn (`turns_required <= 1`), non-channeled cast needs no entry.
    def sustain_spec(channel: nil, reservoir: nil, turns_required: 1)
      if channel
        reset = (reservoir && (reservoir[:reset] || reservoir['reset'])) || 'per_turn'
        { kind: :concentration,
          mode: (channel[:mode] || channel['mode'] || 'maintain').to_s,
          reservoir_reset: reset.to_s }
      elsif turns_required.to_i > 1
        { kind: :long_cast, turns_required: turns_required.to_i }
      end
    end
  end
end
