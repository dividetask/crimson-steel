require 'spec_helper'
require 'encounter'

RSpec.describe 'Encounter combat-mode operations' do
  describe Encounter::CombatPool do
    it 'computes the Budget' do
      # martial 4, attribute 12, tier 0 (Turns Per Round[0] = 1):
      # floor((4 + floor(12/2)) / 1) = 10
      expect(described_class.budget(martial_ranks: 4, attribute: 12, tier: 0)).to eq(10)
    end

    it 'buys the largest pool whose tiered cost fits the Budget' do
      # Per the design's closed form, cost(11)=10 <= 10 < cost(12)=12.
      expect(described_class.buy(10)).to eq(11)
    end

    it 'guarantees at least Combat Pool Step points' do
      expect(described_class.buy(0)).to eq(Encounter::Config.combat_pool_step)
    end
  end

  describe Encounter::TimeTicks do
    it 'sets Time Ticks Per Round to the highest tier' do
      expect(described_class.ticks_per_round([1, 3, 4])).to eq(4)
    end

    it 'computes the floored-midpoint schedule' do
      expect(described_class.schedule(1, 4)).to eq([2])
      expect(described_class.schedule(3, 4)).to eq([1, 3])
      expect(described_class.schedule(4, 4)).to eq([1, 2, 3, 4])
    end
  end

  describe Encounter::Initiative do
    it 'encodes rolled dice as a descending Dice Result String' do
      expect(described_class.resolve([8, 6, 5, 3])).to eq('8653')
    end

    it 'encodes a 10 as the configured Critical label' do
      expect(described_class.resolve([10, 9, 7])).to eq('X97')
    end

    it 'positive Luck rerolls the lowest non-Critical dice' do
      queue = [7, 9]
      roller = ->(_n) { [queue.shift] }
      # [10,6,5,2] luck 2: reroll the 5 and 2 (lowest non-crit), 10 skipped.
      result = described_class.resolve([10, 6, 5, 2], luck: 2, roller: roller)
      expect(result).to eq('X976') # {10,6,9,7} sorted desc
    end

    it 'negative Luck rerolls the highest non-Failure dice' do
      queue = [4, 3]
      roller = ->(_n) { [queue.shift] }
      result = described_class.resolve([9, 8, 1], luck: -2, roller: roller)
      expect(result).to eq('431') # {4,3,1}
    end

    it 'positive Insight prefers the lowest crit-capable die' do
      expect(described_class.resolve([6, 4], insight: 4)).to eq('X4') # 6 -> 10
    end

    it 'positive Insight falls back to the highest non-Critical die' do
      expect(described_class.resolve([10, 5, 3], insight: 1)).to eq('X63') # 5 -> 6
    end

    it 'negative Insight lowers the highest die, clamped at 1' do
      expect(described_class.resolve([7, 4], insight: -3)).to eq('44')
      expect(described_class.resolve([7, 4], insight: -8)).to eq('41')
    end
  end

  describe Encounter::Severity do
    it 'uses the catalog severity for non-physical damage (+damage_per_hit)' do
      out = described_class.compute(raw: 5, type: 'fire')
      expect(out[:severity_map]).to eq(moderate: 6)
    end

    it 'inherits runtime bucketing from the physical parent' do
      out = described_class.compute(raw: 7, type: 'slashing', threshold: 2, damage_resilience: 1)
      expect(out[:severity_map]).to eq(minor: 3, moderate: 3, major: 1)
    end

    it 'routes acid to the Acid Counter' do
      out = described_class.compute(raw: 6, type: 'acid')
      expect(out[:severity_map]).to eq(moderate: 6)
      expect(out[:side_effects]).to include(hash_including(kind: 'acid', amount: 6))
    end

    it 'inflicts Shock for cold' do
      out = described_class.compute(raw: 4, type: 'cold')
      expect(out[:severity_map]).to eq(minor: 4)
      expect(out[:side_effects]).to include(hash_including(kind: 'inflict', effect: 'shock', amount: 4))
    end

    it 'upgrades radiant severity against undead' do
      expect(described_class.compute(raw: 5, type: 'radiant', target_tags: ['undead'])[:severity_map]).to eq(major: 5)
      expect(described_class.compute(raw: 5, type: 'radiant')[:severity_map]).to eq(moderate: 5)
    end
  end
end
