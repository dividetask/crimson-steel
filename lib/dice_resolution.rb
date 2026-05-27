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
end

require_relative 'dice_resolution/config'
require_relative 'dice_resolution/roll'
