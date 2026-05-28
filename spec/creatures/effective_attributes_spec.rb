require 'spec_helper'
require_relative 'fixtures'

RSpec.describe 'Creatures Get Effective Attributes', type: :model do
  include CreaturesFixtures

  it 'Tier 0 adds zero per-Tier Inherent Bonus' do
    a = Creatures::Accessor.new(record(
      tier: 0,
      attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 }
    ))
    expect(a.effective_attributes).to include(str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10)
  end

  it 'Tier 1 adds the flat per-Tier Inherent Bonus only (no chosen)' do
    a = Creatures::Accessor.new(record(
      tier: 1,
      attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 }
    ))
    expect(a.effective_attributes[:str]).to eq(11)
  end

  it 'Tier 2 chunk consumes the first 2 tier_attribute_advancement entries' do
    a = Creatures::Accessor.new(record(
      tier: 2,
      attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 },
      tier_attribute_advancement: %i[con wis]
    ))
    # Per-tier 2 = 2 across all attrs. Chosen: con +2, wis +2.
    ea = a.effective_attributes
    expect(ea[:str]).to eq(12)
    expect(ea[:con]).to eq(14)
    expect(ea[:wis]).to eq(14)
    expect(ea[:cha]).to eq(12)
  end

  it 'Tier 3 chunks Tier 2 (2 picks) then Tier 3 (2 picks)' do
    a = Creatures::Accessor.new(record(
      tier: 3,
      attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 },
      tier_attribute_advancement: %i[con wis int dex]
    ))
    # Per-tier 3 = 3 across all attrs. Chosen: con +2 wis +2 int +2 dex +2.
    ea = a.effective_attributes
    expect(ea[:con]).to eq(15)
    expect(ea[:wis]).to eq(15)
    expect(ea[:int]).to eq(15)
    expect(ea[:dex]).to eq(15)
    expect(ea[:str]).to eq(13)  # no chosen, just +3 per-tier
  end

  it 'short list forgoes trailing tier chosen bonuses' do
    a = Creatures::Accessor.new(record(
      tier: 3,
      attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 },
      tier_attribute_advancement: %i[con wis]
    ))
    # Tier 2 picks [con, wis] apply; Tier 3 chunk has nothing → no extra chosen.
    ea = a.effective_attributes
    expect(ea[:con]).to eq(15) # 10 + 3 per-tier + 2 chosen
    expect(ea[:int]).to eq(13) # 10 + 3 per-tier
  end

  it 'duplicate chosen-bonus picks stack' do
    a = Creatures::Accessor.new(record(
      tier: 2,
      attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 },
      tier_attribute_advancement: %i[str str]
    ))
    # Tier-2 chunk = [str, str] → +2 +2 = +4 on str.
    expect(a.effective_attributes[:str]).to eq(16)
  end
end
