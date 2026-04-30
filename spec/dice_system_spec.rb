require_relative '../lib/dice_system'

class ScriptedRandomSource
  def initialize(values)
    @values = values.dup
  end

  def rand_int(_low, _high)
    @values.shift
  end
end

CONFIG_PATH = File.expand_path('../data/dice_resolution.yaml', __dir__)

RSpec.describe DiceSystem do
  let(:dice_system) { DiceSystem.new(CONFIG_PATH) }

  describe '#rand_roll_dice' do
    it 'returns dice_count values inside the die range' do
      dice = dice_system.rand_roll_dice(10)
      expect(dice.length).to eq(10)
      expect(dice).to all(be_between(1, 10))
    end

    it 'uses the injected random source in order' do
      scripted = DiceSystem.new(CONFIG_PATH, random_source: ScriptedRandomSource.new([3, 7, 10]))
      expect(scripted.rand_roll_dice(3)).to eq([3, 7, 10])
    end

    it 'rejects dice_count < 1' do
      expect { dice_system.rand_roll_dice(0) }.to raise_error(ArgumentError)
    end
  end

  describe '#compute_results' do
    it 'counts crits as 2, successes as 1, and fumbles as -1' do
      result = dice_system.compute_results([10, 7, 6, 1, 2], 6, 0)
      expect(result['degree_of_individual_success']).to eq(2 + 1 + 1 - 1 + 0)
      expect(result['critical_count']).to eq(1)
    end

    it 'applies the starting_value' do
      result = dice_system.compute_results([5, 5, 5], 6, 2)
      expect(result['degree_of_individual_success']).to eq(2)
    end
  end

  describe '#compute_check_details' do
    # Min Dice Count = 6, Max Dice Count = 10, Bonus Cap = 3 in the
    # checked-in config.

    it 'with zero prowess fills the minimum dice and nothing else' do
      expect(dice_system.compute_check_details(0)).to eq(
        'dice_count' => 6, 'competency_bonus' => 0, 'competency_penalty' => 0, 'starting_value' => 0
      )
    end

    it 'spends prowess on dice up to the maximum first' do
      expect(dice_system.compute_check_details(4)).to eq(
        'dice_count' => 10, 'competency_bonus' => 0, 'competency_penalty' => 0, 'starting_value' => 0
      )
    end

    it 'spills positive prowess past the dice cap into Competency Bonus (no cap)' do
      expect(dice_system.compute_check_details(5)).to eq(
        'dice_count' => 10, 'competency_bonus' => 1, 'competency_penalty' => 0, 'starting_value' => 0
      )
      # 12 prowess = 4 dice (filling 6→10) + 8 leftover Bonus. No cap
      # at this layer; downstream overflow handles TN-floor breaches.
      expect(dice_system.compute_check_details(12)).to eq(
        'dice_count' => 10, 'competency_bonus' => 8, 'competency_penalty' => 0, 'starting_value' => 0
      )
    end

    it 'clamps negative prowess to the minimum dice and routes the deficit to Competency Penalty' do
      expect(dice_system.compute_check_details(-2)).to eq(
        'dice_count' => 6, 'competency_bonus' => 0, 'competency_penalty' => 2, 'starting_value' => 0
      )
    end
  end

  describe '#compute_roll_parameters' do
    it 'reduces TN by bonus and increases by penalty' do
      params = dice_system.compute_roll_parameters('Competency Bonus' => 2, 'Morale Penalty' => 1)
      expect(params['tn']).to eq(6 - 2 + 1)
      expect(params['starting_value']).to eq(0)
    end

    it 'converts TN overflow below minimum into starting successes' do
      params = dice_system.compute_roll_parameters('Competency Bonus' => 10)
      expect(params['tn']).to eq(3)
      expect(params['starting_value']).to eq(7)
    end

    it 'raises on unrecognized modifier keys' do
      expect { dice_system.compute_roll_parameters('Bogus Bonus' => 1) }.to raise_error(ArgumentError)
    end
  end

  describe '#rand_reroll_some_dice' do
    it 'positive reroll_count targets the lowest non-successes' do
      scripted = DiceSystem.new(CONFIG_PATH, random_source: ScriptedRandomSource.new([9, 9]))
      changes = scripted.rand_reroll_some_dice([1, 2, 7, 6], 2, 6)
      expect(changes).to eq([9, 9, nil, nil])
    end

    it 'negative reroll_count targets the highest successes' do
      scripted = DiceSystem.new(CONFIG_PATH, random_source: ScriptedRandomSource.new([2, 2]))
      changes = scripted.rand_reroll_some_dice([1, 6, 9, 10], -2, 6)
      expect(changes).to eq([nil, nil, 2, 2])
    end

    it 'returns an all-nil list when reroll_count is zero' do
      expect(dice_system.rand_reroll_some_dice([1, 6, 10], 0, 6)).to eq([nil, nil, nil])
    end
  end

  describe '#apply_nudge' do
    it 'picks the die whose contribution delta is largest for a positive nudge' do
      # TN=6. Die at index 2 (value 5) becomes a success with +1 nudge (delta +1);
      # every other die has delta 0.
      changes = dice_system.apply_nudge([3, 4, 5, 7, 10], 1, 6)
      expect(changes).to eq([nil, nil, 6, nil, nil])
    end

    it 'returns all-nil when nudge_amount is zero' do
      expect(dice_system.apply_nudge([1, 5, 10], 0, 6)).to eq([nil, nil, nil])
    end
  end
end
