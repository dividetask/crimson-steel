require 'spec_helper'
require 'encounter'

RSpec.describe Encounter::TierMismatch do
  # The Ascendancy check modifier lives in the JS Check Resolution engine
  # (public/js/tierMismatch.js); this Ruby module owns the server-side
  # Inherent damage reduction half.
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
