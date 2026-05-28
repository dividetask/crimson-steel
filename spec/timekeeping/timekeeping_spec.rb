require 'timekeeping'

RSpec.describe Timekeeping do
  let(:cfg) { Timekeeping::Config.load }

  describe '.calendar_date' do
    it 'maps day_index 0 to first Day of Default Starting Year' do
      expect(described_class.calendar_date(0, cfg)).to eq(
        year: 4710, month: 1, day_of_month: 1, day_of_week: 'Restday'
      )
    end

    it 'advances Day of Week with day_index 1' do
      expect(described_class.calendar_date(1, cfg)).to eq(
        year: 4710, month: 1, day_of_month: 2, day_of_week: 'Toilday'
      )
    end

    it 'crosses Month boundary at day_index 31' do
      expect(described_class.calendar_date(31, cfg)).to eq(
        year: 4710, month: 2, day_of_month: 1, day_of_week: 'Marketday'
      )
    end

    it 'inserts Brindle 29 in a Leap Year' do
      expect(described_class.calendar_date(789, cfg)).to eq(
        year: 4712, month: 2, day_of_month: 29, day_of_week: 'Feastday'
      )
    end

    it 'skips Brindle 29 in a non-Leap Year' do
      expect(described_class.calendar_date(424, cfg)).to eq(
        year: 4711, month: 3, day_of_month: 1, day_of_week: 'Tradeday'
      )
    end

    it 'maps day_index -1 to the last Day of the prior Year' do
      expect(described_class.calendar_date(-1, cfg)).to eq(
        year: 4709, month: 12, day_of_month: 31, day_of_week: 'Templeday'
      )
    end

    it 'crosses Year boundary at day_index 365' do
      d = described_class.calendar_date(365, cfg)
      expect(d[:year]).to eq(4711)
      expect(d[:month]).to eq(1)
      expect(d[:day_of_month]).to eq(1)
    end

    it 'spans a Leap Year with day_index 366' do
      d = described_class.calendar_date(366, cfg)
      expect(d[:year]).to eq(4711)
      expect(d[:month]).to eq(1)
      expect(d[:day_of_month]).to eq(2)
    end

    it 'wraps Day of Week back to Restday after a full cycle' do
      expect(described_class.calendar_date(7, cfg)[:day_of_week]).to eq('Restday')
    end

    it 'disables Leap Years when Leap Year Interval is 0' do
      raw = cfg.data.merge('Leap Year Interval' => 0)
      override = Timekeeping::Config.new(raw)
      # In default config 4712 has Brindle 29 at day_index 789. With
      # leap years disabled, day_index 789 is Thawmoon 1 of 4712.
      d = described_class.calendar_date(789, override)
      expect(d[:year]).to eq(4712)
      expect(d[:month]).to eq(3)
      expect(d[:day_of_month]).to eq(1)
    end
  end

  describe '.time_of_day' do
    it 'returns 00:00:00 for round 0' do
      expect(described_class.time_of_day(0, cfg)).to eq('00:00:00')
    end

    it 'returns 01:00:00 for round 600' do
      expect(described_class.time_of_day(600, cfg)).to eq('01:00:00')
    end

    it 'returns 23:59:54 for the last Round of the Day' do
      expect(described_class.time_of_day(14399, cfg)).to eq('23:59:54')
    end

    it 'returns 12:05:00 for round 7250' do
      expect(described_class.time_of_day(7250, cfg)).to eq('12:05:00')
    end

    it 'rejects round_of_day at or beyond Rounds Per Day' do
      expect { described_class.time_of_day(14400, cfg) }.to raise_error(ArgumentError)
    end
  end

  describe '.advance' do
    it 'adds Rounds within a Day' do
      ts = { day_index: 100, round_of_day: 0 }
      expect(described_class.advance(ts, rounds: 600, cfg: cfg)).to eq(
        day_index: 100, round_of_day: 600
      )
    end

    it 'rolls Rounds into the next Day' do
      ts = { day_index: 100, round_of_day: 14000 }
      expect(described_class.advance(ts, rounds: 1000, cfg: cfg)).to eq(
        day_index: 101, round_of_day: 600
      )
    end

    it 'handles multi-Day rollover from Rounds' do
      ts = { day_index: 0, round_of_day: 0 }
      expect(described_class.advance(ts, rounds: 30000, cfg: cfg)).to eq(
        day_index: 2, round_of_day: 1200
      )
    end

    it 'adds Days only, leaving round_of_day untouched' do
      ts = { day_index: 100, round_of_day: 5000 }
      expect(described_class.advance(ts, days: 7, cfg: cfg)).to eq(
        day_index: 107, round_of_day: 5000
      )
    end

    it 'combines Round rollover with Day delta' do
      ts = { day_index: 50, round_of_day: 13000 }
      expect(described_class.advance(ts, rounds: 2000, days: 3, cfg: cfg)).to eq(
        day_index: 54, round_of_day: 600
      )
    end

    it 'subtracts Rounds across a Day boundary' do
      ts = { day_index: 100, round_of_day: 100 }
      expect(described_class.advance(ts, rounds: -200, cfg: cfg)).to eq(
        day_index: 99, round_of_day: 14300
      )
    end

    it 'allows negative day_index' do
      ts = { day_index: 5, round_of_day: 7000 }
      expect(described_class.advance(ts, days: -10, cfg: cfg)).to eq(
        day_index: -5, round_of_day: 7000
      )
    end

    it 'accepts string-keyed Timestamps (from JSON)' do
      ts = { 'day_index' => 100, 'round_of_day' => 0 }
      expect(described_class.advance(ts, rounds: 600, cfg: cfg)).to eq(
        day_index: 100, round_of_day: 600
      )
    end
  end
end
