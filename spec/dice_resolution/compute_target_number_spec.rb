require 'dice_resolution'

# Mirrors the JS TnComputation behaviour the Check stub relies on, so the
# Ruby side (used to build attack-roll Check data) stays in lock-step.
RSpec.describe 'DiceResolution.compute_target_number' do
  # Defaults from dice_resolution_config.yaml: Base 8, Minimum 3, Maximum 9.
  it 'returns the Base Target Number with no modifiers' do
    expect(DiceResolution.compute_target_number([])).to eq(tn: 8, starting_value: 0)
  end

  it 'lowers the TN by a net Bonus (Base - net)' do
    expect(DiceResolution.compute_target_number([['Competency', 2]])).to eq(tn: 6, starting_value: 0)
  end

  it 'raises the TN by a net Penalty' do
    expect(DiceResolution.compute_target_number([['Competency', -1]])).to eq(tn: 9, starting_value: 0)
  end

  it 'keeps only the highest positive and lowest negative per Type' do
    # Two Circumstance bonuses (+1, +2) -> only +2; plus a Competency +1 -> net +3 -> TN 5.
    list = [['Circumstance', 1], ['Circumstance', 2], ['Competency', 1]]
    expect(DiceResolution.compute_target_number(list)).to eq(tn: 5, starting_value: 0)
  end

  it 'sums across distinct Types' do
    list = [['Competency', 1], ['Circumstance', 1]]
    expect(DiceResolution.compute_target_number(list)).to eq(tn: 6, starting_value: 0)
  end

  it 'clamps a large Bonus to the Minimum TN and banks the overflow as Starting Successes' do
    # net +7 -> candidate 1 -> clamp to 3, starting_value = 3 - 1 = 2.
    expect(DiceResolution.compute_target_number([['Competency', 7]])).to eq(tn: 3, starting_value: 2)
  end

  it 'clamps a large Penalty to the Maximum TN and banks the overflow as Starting Failures' do
    # net -5 -> candidate 13 -> clamp to 9, starting_value = -(13 - 9) = -4.
    expect(DiceResolution.compute_target_number([['Competency', -5]])).to eq(tn: 9, starting_value: -4)
  end

  # Tier-mismatch Ascendancy is derived here (Roll Resolution), the Ruby twin
  # of ascendancy.js. It folds a derived `['Ascendancy', 2 × gap]` into the
  # net before stacking, but only when an Inherent Penalty (value <= 0, a 0
  # counts) is present.
  describe 'Ascendancy derivation' do
    it 'amplifies an Inherent imbalance into the TN' do
      # Inherent +2 and -1: net Inherent +1, plus derived Ascendancy +2 -> net
      # +3 -> TN 8 - 3 = 5.
      expect(DiceResolution.compute_target_number([['Inherent', 2], ['Inherent', -1]]))
        .to eq(tn: 5, starting_value: 0)
    end

    it 'derives a Penalty when the Inherent deficit is the stronger side' do
      # +1 vs -3: net Inherent -2, derived Ascendancy -4 -> net -6 -> candidate
      # 14 -> clamp 9, starting_value = -(14 - 9) = -5.
      expect(DiceResolution.compute_target_number([['Inherent', 1], ['Inherent', -3]]))
        .to eq(tn: 9, starting_value: -5)
    end

    it 'derives nothing from a lone Inherent Bonus (no opposing creature)' do
      expect(DiceResolution.compute_target_number([['Inherent', 2]])).to eq(tn: 6, starting_value: 0)
    end

    it 'fires on a +0 Inherent Penalty (Tier-0 opponent), reading the 0 as 0.5' do
      # Tier 2 vs Tier 0: the 0 Penalty does not move the TN itself (net_modifier
      # drops 0s), but the gate fires and the gap 2 - 0.5 = 1.5 -> +3 Ascendancy.
      # net = Inherent +2 + Ascendancy +3 = +5 -> TN 8 - 5 = 3.
      expect(DiceResolution.compute_target_number([['Inherent', 2], ['Inherent', 0]]))
        .to eq(tn: 3, starting_value: 0)
    end

    it 'derives nothing when the Inherents balance' do
      expect(DiceResolution.compute_target_number([['Inherent', 2], ['Inherent', -2]]))
        .to eq(tn: 8, starting_value: 0)
    end
  end
end
