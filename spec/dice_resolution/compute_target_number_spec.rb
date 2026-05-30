require 'dice_resolution'

# Mirrors the JS TnComputation behaviour the Check stub relies on, so the
# Ruby side (used to build attack-roll Check data) stays in lock-step.
RSpec.describe 'DiceResolution.compute_target_number' do
  # Defaults from dice_resolution_config.yaml: Base 6, Minimum 3, Maximum 9.
  it 'returns the Base Target Number with no modifiers' do
    expect(DiceResolution.compute_target_number([])).to eq(tn: 6, starting_value: 0)
  end

  it 'lowers the TN by a net Bonus (Base - net)' do
    expect(DiceResolution.compute_target_number([['Competency', 2]])).to eq(tn: 4, starting_value: 0)
  end

  it 'raises the TN by a net Penalty' do
    expect(DiceResolution.compute_target_number([['Competency', -1]])).to eq(tn: 7, starting_value: 0)
  end

  it 'keeps only the highest positive and lowest negative per Type' do
    # Two Circumstance bonuses (+1, +2) -> only +2; plus a Competency +1 -> net +3 -> TN 3.
    list = [['Circumstance', 1], ['Circumstance', 2], ['Competency', 1]]
    expect(DiceResolution.compute_target_number(list)).to eq(tn: 3, starting_value: 0)
  end

  it 'sums across distinct Types' do
    list = [['Competency', 1], ['Circumstance', 1]]
    expect(DiceResolution.compute_target_number(list)).to eq(tn: 4, starting_value: 0)
  end

  it 'clamps a large Bonus to the Minimum TN and banks the overflow as Starting Successes' do
    # net +5 -> candidate 1 -> clamp to 3, starting_value = 3 - 1 = 2.
    expect(DiceResolution.compute_target_number([['Competency', 5]])).to eq(tn: 3, starting_value: 2)
  end

  it 'clamps a large Penalty to the Maximum TN and banks the overflow as Starting Failures' do
    # net -5 -> candidate 11 -> clamp to 9, starting_value = -(11 - 9) = -2.
    expect(DiceResolution.compute_target_number([['Competency', -5]])).to eq(tn: 9, starting_value: -2)
  end
end
