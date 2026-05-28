require 'dice_resolution'

module Encounter
  # Initiative-specific Roll handling. Initiative has no Target Number,
  # so Dice Resolution's generic Reroll/Value-Adjustment (which classify
  # against a TN) don't apply — Combat owns these variants. See
  # encounter_design.md → Operations.
  module Initiative
    module_function

    def die_size
      DiceResolution.config.die_size
    end

    # Valid Dice Result String characters for the current die: '1'..'9'
    # plus the encoding chars for values 10..Die Size (monotonic, so a
    # plain descending sort orders them high-to-low).
    def valid_chars
      cfg = DiceResolution.config
      enc = cfg.dice_result_string_encoding.to_s
      enc = ('A'..'Z').to_a.join if enc.length < (cfg.die_size - 9)
      highs = (10..cfg.die_size).map { |v| enc[v - 10] }.compact
      ('1'..'9').to_a + highs
    end

    # Parse a raw user-typed Initiative String: drop every character
    # that isn't a valid die value, then sort the survivors descending.
    def normalize_string(raw)
      allowed = valid_chars
      raw.to_s.upcase.chars.select { |c| allowed.include?(c) }.sort.reverse.join
    end

    # Dice count = floor(Initiative Attribute / Initiative Divisor).
    def dice_count_for(creature)
      attr = creature.attribute_value(Config.initiative_attribute)
      attr / Config.initiative_divisor
    end

    # Roll a fresh set of `count` dice. Overridable for tests via the
    # injected `roller`.
    def roll(count, roller: method(:default_roll))
      roller.call(count)
    end

    def default_roll(count)
      Array.new(count) { rand(1..die_size) }
    end

    # Apply Initiative Luck, then Initiative Insight, then encode the
    # final dice as a Dice Result String. `roller` rerolls dice during
    # Luck. Returns the Dice Result String.
    def resolve(dice, luck: 0, insight: 0, roller: method(:default_roll))
      dice = apply_luck(dice, luck, roller)
      dice = apply_insight(dice, insight)
      DiceResolution.dice_result_string(dice)
    end

    # Positive Luck: reroll up to |luck| of the lowest values, skipping
    # any die already at Critical (Die Size). Negative Luck: reroll up
    # to |luck| of the highest values, skipping any at Failure (1).
    # Each die rerolled at most once.
    def apply_luck(dice, luck, roller)
      return dice if luck.zero?
      dice = dice.dup
      order = (0...dice.length).to_a
      if luck.positive?
        order.sort_by! { |i| dice[i] } # ascending
        skip = die_size
      else
        order.sort_by! { |i| -dice[i] } # descending
        skip = 1
      end
      rerolled = 0
      order.each do |i|
        break if rerolled >= luck.abs
        next if dice[i] == skip
        dice[i] = roller.call(1).first
        rerolled += 1
      end
      dice
    end

    # Positive Insight: among non-Critical dice, prefer one whose value
    # + insight would meet/exceed Die Size (crit-capable); pick the
    # lowest such, else the highest non-Critical die; raise it by
    # `insight` (capped at Die Size). Negative Insight: lower the single
    # highest die by |insight| (clamped at 1). Single operation — the
    # repeated-iteration variant is an unresolved edge case in the
    # design (see *Unassigned → Initiative reroll edge cases*).
    def apply_insight(dice, insight)
      return dice if insight.zero?
      dice = dice.dup

      if insight.positive?
        non_crit = dice.each_index.select { |i| dice[i] < die_size }
        return dice if non_crit.empty?
        crit_capable = non_crit.select { |i| dice[i] + insight >= die_size }
        idx = crit_capable.any? ? crit_capable.min_by { |i| dice[i] } : non_crit.max_by { |i| dice[i] }
        dice[idx] = [dice[idx] + insight, die_size].min
      else
        idx = dice.each_index.max_by { |i| dice[i] }
        dice[idx] = [dice[idx] + insight, 1].max
      end
      dice
    end
  end
end
