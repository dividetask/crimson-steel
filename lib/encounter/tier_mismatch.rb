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
  #
  # This Ruby module owns the *Inherent damage reduction* half, applied
  # server-side when damage is resolved. The *Ascendancy* check modifier
  # is computed client-side in the JS Check Resolution engine
  # (public/js/tierMismatch.js), since Rolls resolve there.
  module TierMismatch
    INHERENT_DR_PER_TIER = 5

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

    # Inherent damage reduction the defender gets against a lower-Tier
    # attacker's hit: 5 per Tier the defender is above the attacker, else 0.
    def inherent_damage_reduction(defender_tier, attacker_tier)
      d = delta(defender_tier, attacker_tier)
      return 0 unless d.positive?
      (INHERENT_DR_PER_TIER * d).floor
    end

    # --- Combat builder seam ---------------------------------------------
    # How the combat builders (attack + cast) pass each Roll its Creature's
    # Tier down to Check Resolution, where the JS engine applies Ascendancy.
    # Centralized here so the attack and cast builders wire it identically;
    # skill-check builders simply never call this, which is what scopes
    # Ascendancy to combat.

    # The Tier a seed / actor Roll should carry, or nil when unknown.
    def roll_tier(accessor)
      accessor.tier
    rescue StandardError
      nil
    end

    # The builder-step patch that stamps a Roll's Tier when its Creature is
    # chosen (the defender/target Roll, resolved at Target-selection time).
    def set_tier_patch(roll_id, tier)
      { set_tier: [{ id: roll_id, tier: tier }] }
    end
  end
end
