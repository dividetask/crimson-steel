module Equipment
  # Loot Table Dice Expression evaluator. Handles integer constants and
  # `NdM` with an optional `± K`:
  #   "3"        → 3
  #   "2d6"      → 2..12
  #   "3d10 + 10"→ 13..40
  #   "1d4 - 1"  → 0..3
  # A Random instance is supplied so rolls are reproducible from a seed.
  # Distinct from the Dice Resolution domain's success-counting dice.
  module DiceExpression
    DICE_RE = /\A\s*(?:(\d+)|(\d+)d(\d+)\s*(?:([+\-])\s*(\d+))?)\s*\z/

    module_function

    def eval(expr, rng = Random.new)
      return expr if expr.is_a?(Integer)
      m = expr.to_s.match(DICE_RE)
      raise ArgumentError, "invalid dice expression #{expr.inspect}" unless m

      return Integer(m[1]) if m[1]

      count = Integer(m[2])
      sides = Integer(m[3])
      total = count.times.sum { rng.rand(1..sides) }
      if m[4]
        adj = Integer(m[5])
        total += (m[4] == '+' ? adj : -adj)
      end
      total
    end
  end
end
