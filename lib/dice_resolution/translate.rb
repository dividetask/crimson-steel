module DiceResolution
  module_function

  # Translate Skill Prowess into Roll inputs. Per
  # docs/common/dice_resolution/dice_resolution_design.md:
  #   bonus_penalty = floor(prowess / Dice Count Range)
  #   remainder     = prowess - (bonus_penalty * Dice Count Range)
  #   dice_count    = Minimum Dice Count + remainder
  #
  # Floor toward negative infinity is required so that negative
  # prowess wraps to the maximum dice count with a negative
  # bonus_penalty (see the spec's worked examples).
  def translate_prowess(prowess, config = DiceResolution.config)
    range     = config.dice_count_range
    min_dice  = config.minimum_dice_count

    bonus_penalty = (prowess.to_f / range).floor
    remainder     = prowess - (bonus_penalty * range)
    dice_count    = min_dice + remainder
    [dice_count, bonus_penalty]
  end
end
