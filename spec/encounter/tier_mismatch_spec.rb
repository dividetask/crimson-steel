require 'spec_helper'
require 'encounter'

RSpec.describe Encounter::TierMismatch do
  describe '.ascendancy_modifier' do
    it 'is a Bonus when the actor out-Tiers the opponent' do
      expect(described_class.ascendancy_modifier(3, 1)).to eq(['Ascendancy', 4])
    end

    it 'is a Penalty when the actor is out-Tiered' do
      expect(described_class.ascendancy_modifier(1, 3)).to eq(['Ascendancy', -4])
    end

    it 'is nil at equal Tier' do
      expect(described_class.ascendancy_modifier(2, 2)).to be_nil
    end

    it 'treats Tier 0 as 0.5 and floors the magnitude' do
      # delta = 1 - 0.5 = 0.5 -> 2 * 0.5 = 1
      expect(described_class.ascendancy_modifier(1, 0)).to eq(['Ascendancy', 1])
      expect(described_class.ascendancy_modifier(0, 1)).to eq(['Ascendancy', -1])
    end
  end

  describe '.inherent_damage_reduction' do
    it 'is 5 per Tier the defender stands above the attacker' do
      expect(described_class.inherent_damage_reduction(3, 1)).to eq(10)
    end

    it 'is 0 when the defender is equal or lower Tier' do
      expect(described_class.inherent_damage_reduction(1, 1)).to eq(0)
      expect(described_class.inherent_damage_reduction(1, 3)).to eq(0)
    end

    it 'treats Tier 0 as 0.5 and floors' do
      # delta = 1 - 0.5 = 0.5 -> 5 * 0.5 = 2.5 -> floor 2
      expect(described_class.inherent_damage_reduction(1, 0)).to eq(2)
    end
  end
end
