module Creatures
  # Tiny dice-expression evaluator for the `count` field on
  # Encounter Row Spawn Refs. Supports integer literals and
  # XdY-style expressions with an optional ±N modifier:
  #   "3"        → 3
  #   "2d4"      → 2..8
  #   "1d4 + 1"  → 2..5
  #   "2d6 - 1"  → 1..11
  # The caller supplies a Random instance so encounter rolls are
  # reproducible from a seed.
  module DiceExpression
    DICE_RE = /\A\s*(?:(\d+)|(\d+)d(\d+)\s*(?:([+\-])\s*(\d+))?)\s*\z/

    module_function

    def eval(expr, rng = Random.new)
      s = expr.to_s
      m = s.match(DICE_RE)
      raise ArgumentError, "invalid dice expression #{expr.inspect}" unless m

      if m[1]
        Integer(m[1])
      else
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
end
