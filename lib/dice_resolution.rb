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
end

require_relative 'dice_resolution/config'
require_relative 'dice_resolution/roll'
require_relative 'dice_resolution/translate'
