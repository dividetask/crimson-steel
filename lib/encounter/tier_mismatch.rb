module Encounter
  # Tier Mismatch modifiers (encounter_design.md -> Tier Mismatch).
  #
  # When two Creatures of different Tiers oppose each other, the
  # higher-Tier Creature gains advantages scaled by the Tier difference
  # `delta = higher.tier - lower.tier`. Tier 0 counts as 0.5 per project
  # convention; magnitudes are floored to integers.
  #
  #   - Inherent damage reduction: 5 * delta against a lower-Tier
  #     attacker (an Inherent Bonus).
  #   - Ascendancy: +/- 2 * delta on opposed checks (Bonus for the
  #     higher Creature, Penalty for the lower).
  #
  # An ability may raise a Creature's *effective* Tier for a single
  # resolution (the Glory Channel Divinity Glorious Charge adds +1);
  # callers fold that into the tier they pass.
  module TierMismatch
    INHERENT_DR_PER_TIER = 5
    ASCENDANCY_PER_TIER  = 2
    ASCENDANCY_TYPE      = 'Ascendancy'.freeze

    module_function

    # Tier 0 -> 0.5 per project convention.
    def effective_tier(tier)
      t = tier.to_f
      t.zero? ? 0.5 : t
    end

    # Signed Tier difference actor - opponent (using the 0 -> 0.5 rule).
    def delta(actor_tier, opponent_tier)
      effective_tier(actor_tier) - effective_tier(opponent_tier)
    end

    # `per_tier * |delta|`, floored, carrying delta's sign.
    def scaled(per_tier, actor_tier, opponent_tier)
      d = delta(actor_tier, opponent_tier)
      mag = (per_tier * d.abs).floor
      d.negative? ? -mag : mag
    end

    # Ascendancy modifier for an opposed check the actor makes against the
    # opponent: a Bonus when the actor is higher Tier, a Penalty when
    # lower, nil when equal (or when the floored magnitude is 0). Returns
    # a [type, amount] bonus_penalty pair.
    def ascendancy_modifier(actor_tier, opponent_tier)
      amount = scaled(ASCENDANCY_PER_TIER, actor_tier, opponent_tier)
      return nil if amount.zero?
      [ASCENDANCY_TYPE, amount]
    end

    # Inherent damage reduction the defender gets against a lower-Tier
    # attacker's hit: 5 per Tier the defender is above the attacker, else 0.
    def inherent_damage_reduction(defender_tier, attacker_tier)
      d = delta(defender_tier, attacker_tier)
      return 0 unless d.positive?
      (INHERENT_DR_PER_TIER * d).floor
    end
  end
end
