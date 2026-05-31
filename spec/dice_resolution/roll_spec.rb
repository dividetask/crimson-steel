require 'dice_resolution'

RSpec.describe DiceResolution::Roll do
  let(:config) { DiceResolution::Config.load }

  def valid_roll
    {
      creature_name: 'Bryn Ironvein',
      roll_name:     'Attack',
      dice_count:    8,
      tn:            6,
      starting_value: 0,
      die_size:      10,
      reroll:        nil,
      mass_reroll:   nil,
      nudge:         nil
    }
  end

  describe '.validate!' do
    it 'accepts a well-formed Roll' do
      expect { described_class.validate!(valid_roll, config) }.not_to raise_error
    end

    it 'rejects a non-Hash Roll' do
      expect { described_class.validate!('nope', config) }.to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'rejects a TN below Minimum Target Number' do
      bad = valid_roll.merge(tn: config.minimum_target_number - 1)
      expect { described_class.validate!(bad, config) }.to raise_error(ArgumentError, /tn=/)
    end

    it 'rejects a TN above Maximum Target Number' do
      bad = valid_roll.merge(tn: config.maximum_target_number + 1)
      expect { described_class.validate!(bad, config) }.to raise_error(ArgumentError, /tn=/)
    end

    it 'accepts a TN exactly at Minimum Target Number' do
      good = valid_roll.merge(tn: config.minimum_target_number)
      expect { described_class.validate!(good, config) }.not_to raise_error
    end

    it 'accepts a TN exactly at Maximum Target Number' do
      good = valid_roll.merge(tn: config.maximum_target_number)
      expect { described_class.validate!(good, config) }.not_to raise_error
    end

    it 'rejects a missing TN' do
      bad = valid_roll.reject { |k, _| k == :tn }
      expect { described_class.validate!(bad, config) }.to raise_error(ArgumentError, /missing tn/)
    end

    it 'rejects a non-integer TN' do
      bad = valid_roll.merge(tn: 5.5)
      expect { described_class.validate!(bad, config) }.to raise_error(ArgumentError, /tn=/)
    end

    it 'rejects a die_size other than the configured Die Size' do
      bad = valid_roll.merge(die_size: 8)
      expect { described_class.validate!(bad, config) }
        .to raise_error(ArgumentError, /die_size=8/)
    end

    it 'rejects a dice_count above the Maximum Dice Count' do
      bad = valid_roll.merge(dice_count: config.maximum_dice_count + 1)
      expect { described_class.validate!(bad, config) }
        .to raise_error(ArgumentError, /exceeds the Maximum Dice Count/)
    end

    it 'accepts a dice_count exactly at the Maximum Dice Count' do
      good = valid_roll.merge(dice_count: config.maximum_dice_count)
      expect { described_class.validate!(good, config) }.not_to raise_error
    end

    it 'rejects a missing die_size' do
      bad = valid_roll.reject { |k, _| k == :die_size }
      expect { described_class.validate!(bad, config) }
        .to raise_error(ArgumentError, /missing die_size/)
    end

    it 'rejects a negative dice_count' do
      bad = valid_roll.merge(dice_count: -1)
      expect { described_class.validate!(bad, config) }
        .to raise_error(ArgumentError, /dice_count=/)
    end

    it 'rejects a non-integer dice_count' do
      bad = valid_roll.merge(dice_count: 4.5)
      expect { described_class.validate!(bad, config) }
        .to raise_error(ArgumentError, /dice_count=/)
    end

    it 'rejects a non-integer starting_value' do
      bad = valid_roll.merge(starting_value: 'three')
      expect { described_class.validate!(bad, config) }
        .to raise_error(ArgumentError, /starting_value=/)
    end

    it 'accepts a missing starting_value' do
      good = valid_roll.reject { |k, _| k == :starting_value }
      expect { described_class.validate!(good, config) }.not_to raise_error
    end

    context 'reroll modifier' do
      it 'accepts a well-formed reroll' do
        good = valid_roll.merge(reroll: { sign: :pos, amount: 2, max: false, label: 'X' })
        expect { described_class.validate!(good, config) }.not_to raise_error
      end

      it 'rejects an unknown sign' do
        bad = valid_roll.merge(reroll: { sign: :weird, amount: 2 })
        expect { described_class.validate!(bad, config) }
          .to raise_error(ArgumentError, /reroll sign=/)
      end

      it 'rejects a negative amount' do
        bad = valid_roll.merge(reroll: { sign: :pos, amount: -1 })
        expect { described_class.validate!(bad, config) }
          .to raise_error(ArgumentError, /reroll amount=/)
      end

      it 'rejects a non-integer amount' do
        bad = valid_roll.merge(reroll: { sign: :pos, amount: 'two' })
        expect { described_class.validate!(bad, config) }
          .to raise_error(ArgumentError, /reroll amount=/)
      end
    end

    context 'mass_reroll modifier' do
      it 'accepts a well-formed mass_reroll (no amount)' do
        good = valid_roll.merge(mass_reroll: { sign: :neg, label: 'Curse' })
        expect { described_class.validate!(good, config) }.not_to raise_error
      end

      it 'rejects an unknown sign' do
        bad = valid_roll.merge(mass_reroll: { sign: :weird })
        expect { described_class.validate!(bad, config) }
          .to raise_error(ArgumentError, /mass_reroll sign=/)
      end
    end

    context 'nudge modifier' do
      it 'accepts a well-formed nudge' do
        good = valid_roll.merge(nudge: { sign: :pos, amount: 1, label: 'Guidance' })
        expect { described_class.validate!(good, config) }.not_to raise_error
      end

      it 'rejects an unknown sign' do
        bad = valid_roll.merge(nudge: { sign: :weird, amount: 1 })
        expect { described_class.validate!(bad, config) }
          .to raise_error(ArgumentError, /nudge sign=/)
      end

      it 'rejects a negative amount' do
        bad = valid_roll.merge(nudge: { sign: :pos, amount: -1 })
        expect { described_class.validate!(bad, config) }
          .to raise_error(ArgumentError, /nudge amount=/)
      end
    end

    it 'accepts string keys as well as symbol keys' do
      good = {
        'dice_count' => 8, 'tn' => 6, 'die_size' => 10,
        'reroll' => { 'sign' => 'neg', 'amount' => 2 }
      }
      expect { described_class.validate!(good, config) }.not_to raise_error
    end
  end

  describe 'every Roll the project actually feeds to the stub' do
    it 'passes validation for every Status::SampleRolls.rolls entry' do
      require_relative '../../lib/status/sample_rolls'
      Status::SampleRolls.rolls.each do |roll|
        expect { described_class.validate!(roll, config) }
          .not_to raise_error,
            "Expected SampleRolls entry #{roll[:roll_name].inspect} to validate"
      end
    end

    it 'passes validation for every roll in Status::SampleCheck.check (supporting + opposing)' do
      require_relative '../../lib/status/sample_check'
      (Status::SampleCheck.check[:supporting] + Status::SampleCheck.check[:opposing]).each do |roll|
        expect { described_class.validate!(roll, config) }
          .not_to raise_error,
            "Expected SampleCheck roll #{roll[:roll_name].inspect} to validate"
      end
    end
  end
end

RSpec.describe DiceResolution::Config do
  let(:config) { described_class.load }

  it 'reads the project Die Size' do
    expect(config.die_size).to eq(10)
  end

  it 'reads TN bounds' do
    expect(config.minimum_target_number).to eq(3)
    expect(config.maximum_target_number).to eq(9)
  end
end
