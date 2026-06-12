module Encounter
  # Combat Pool computation per encounter_design.md → Operations →
  # "Combat Pool computation". Two stages: a Budget derived from
  # martial ranks + a scaled attribute, then a tiered Buy where each
  # successive block of `Step` points costs one more Budget point each.
  module CombatPool
    module_function

    # Stage 1 — Budget.
    #   budget = floor((martial_ranks*2 + attribute) / Turns Per Round[tier])
    def budget(martial_ranks:, attribute:, tier:)
      turns = Config.turns_for_tier(tier)
      raw = (martial_ranks * 2) + attribute
      raw / turns
    end

    # Stage 2 — Buy. Points 1..Step are free; points (k·Step)+1..(k+1)·Step
    # cost k each. Return the largest count P whose total cost fits the
    # Budget. Every Combatant is guaranteed at least `Step` points.
    def buy(budget, step: Config.combat_pool_step)
      p = 0
      p += 1 while cost_to_buy(p + 1, step) <= budget
      [p, step].max
    end

    # Closed-form total cost of P points: with T = floor(P/Step) and
    # R = P mod Step, total = Step · T·(T-1)/2 + R · T.
    def cost_to_buy(p, step)
      t = p / step
      r = p % step
      step * (t * (t - 1) / 2) + r * t
    end

    # Full computation from a Creature Accessor: martial ranks, the
    # Combat Pool attribute's effective value, and the Tier.
    def size_for(creature)
      martial   = creature.ranks_for('martial')
      attribute = creature.attribute_value(Config.combat_pool_attribute)
      tier      = creature.tier
      buy(budget(martial_ranks: martial, attribute: attribute, tier: tier))
    end
  end
end
