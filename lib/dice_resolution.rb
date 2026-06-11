require 'yaml'

# Dice Resolution validation. The Roll Resolution Stub calls into
# DiceResolution::Roll.validate! before rendering each Roll so that
# data violating the rules in dice_resolution_design.md (out-of-bounds
# TN, wrong die size, malformed modifier, …) is rejected at render
# time rather than producing a quietly wrong display.
module DiceResolution
  module_function

  def config
    @config ||= Config.load
  end

  # Compute a Dice Result String — an ASCII encoding of a list of dice
  # sorted descending, monotonic so a lexical compare reproduces the
  # die-by-die comparison. Per dice_resolution_design.md → "Compute a
  # Dice Result String": values 1-9 emit '1'-'9'; higher values emit
  # encoding[value-10]. The configured encoding falls back to 'A'..'Z'
  # when it is shorter than Die Size - 9.
  def dice_result_string(dice, cfg = config)
    encoding = cfg.dice_result_string_encoding.to_s
    encoding = ('A'..'Z').to_a.join if encoding.length < (cfg.die_size - 9)
    dice.sort.reverse.map do |v|
      v.between?(1, 9) ? v.to_s : encoding[v - 10]
    end.join
  end

  # Compute a Roll's Target Number and Starting Value from a Bonus /
  # Penalty list — the Ruby twin of the JS `TnComputation` the Check
  # stub uses. The Tier-mismatch Ascendancy entry is derived here first
  # (the Ruby twin of `ascendancy.js`), so any Roll computed server-side —
  # an Affliction save composes the saver's Inherent Bonus and the
  # inflicter's Inherent Penalty — picks it up. Per-Type stacking: for each
  # Bonus/Penalty Type only the highest positive and the lowest negative
  # entry contribute. The TN candidate is `Base TN - Net Modifier`, clamped
  # to [Minimum, Maximum]; whatever the clamp discards becomes Starting Value
  # (Bonuses below the Minimum become Starting Successes, Penalties above the
  # Maximum become Starting Failures). `list` is an Array of `[type, amount]`
  # pairs. Returns `{ tn:, starting_value: }`.
  def compute_target_number(list, cfg = config)
    candidate = cfg.base_target_number - net_modifier(with_ascendancy(list))
    min = cfg.minimum_target_number
    max = cfg.maximum_target_number
    if candidate < min
      { tn: min, starting_value: min - candidate }
    elsif candidate > max
      { tn: max, starting_value: -(candidate - max) }
    else
      { tn: candidate, starting_value: 0 }
    end
  end

  def net_modifier(list)
    highest = {}
    lowest  = {}
    Array(list).each do |type, amount|
      next if amount.nil? || amount.zero?
      if amount.positive?
        highest[type] = amount if !highest.key?(type) || amount > highest[type]
      else
        lowest[type] = amount if !lowest.key?(type) || amount < lowest[type]
      end
    end
    highest.values.sum + lowest.values.sum
  end

  ASCENDANCY_PER_POINT = 2

  # The list with its derived Ascendancy entry appended (or unchanged when no
  # Inherent imbalance is present).
  def with_ascendancy(list)
    mod = ascendancy_modifier(list)
    mod ? Array(list) + [mod] : Array(list)
  end

  # The Ascendancy `[type, amount]` pair for a Bonus/Penalty list, or nil.
  # Derived only when an Inherent *Penalty* (value <= 0; 0 counts — the
  # injected Tier-0 opponent) is present, so a Roll with an Inherent Bonus but
  # no opposing creature derives nothing. Magnitude is
  # `floor(PER_POINT x gap)`, the gap measured on effective (0 -> 0.5) values.
  # The Ruby twin of `ascendancy.js`.
  def ascendancy_modifier(list)
    bonus = 0.0
    penalty = 0.0
    penalty_present = false
    Array(list).each do |type, amount|
      next unless type.to_s == 'Inherent'
      v = amount.to_f
      bonus = v if v > bonus
      if v <= 0
        penalty_present = true
        penalty = v if v < penalty
      end
    end
    return nil unless penalty_present
    gap = ascendancy_effective(bonus) - ascendancy_effective(-penalty)
    return nil if gap.zero?
    magnitude = (ASCENDANCY_PER_POINT * gap.abs).floor
    return nil if magnitude.zero?
    ['Ascendancy', gap.negative? ? -magnitude : magnitude]
  end

  # Tier 0 -> 0.5: a zero side of the comparison reads as the Tier-0 value.
  def ascendancy_effective(value)
    value.zero? ? 0.5 : value
  end
end

require_relative 'dice_resolution/config'
require_relative 'dice_resolution/roll'
require_relative 'dice_resolution/translate'
