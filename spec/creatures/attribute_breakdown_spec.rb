require 'spec_helper'
require 'creature_modifiers'
require_relative 'fixtures'

RSpec.describe 'Creatures Attribute Breakdown', type: :model do
  include CreaturesFixtures

  it 'is base-only at Tier 0 with no racial adjustment or bonuses' do
    a = Creatures::Accessor.new(record(
      tier: 0, attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 }
    ))
    expect(a.attribute_breakdown(:str)).to eq([{ label: 'base', amount: 10 }])
  end

  it 'adds the flat per-Tier minimum as an inherent term' do
    a = Creatures::Accessor.new(record(
      tier: 1, attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 }
    ))
    expect(a.attribute_breakdown(:str)).to eq([
      { label: 'base', amount: 10 }, { label: 'inherent', amount: 1 }
    ])
  end

  it 'folds chosen Tier advancements into the inherent term' do
    a = Creatures::Accessor.new(record(
      tier: 2, attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 },
      tier_attribute_advancement: %i[con wis]
    ))
    # Per-tier 2 = 2; con also takes a +2 chosen pick → inherent 4.
    expect(a.attribute_breakdown(:con)).to eq([
      { label: 'base', amount: 10 }, { label: 'inherent', amount: 4 }
    ])
    expect(a.attribute_breakdown(:str)).to eq([
      { label: 'base', amount: 10 }, { label: 'inherent', amount: 2 }
    ])
  end

  it 'breaks out Always-On Modifiers per Bonus Type after base/racial/inherent' do
    a = Creatures::Accessor.new(record(
      tier: 0, attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 }
    ))
    allow(CreatureModifiers).to receive(:attribute_bonus_tokens) do |_acc, attr|
      attr == :str ? [{ amount: 2, type: 'Guidance' }] : []
    end
    expect(a.attribute_breakdown(:str)).to eq([
      { label: 'base', amount: 10 }, { label: 'Guidance', amount: 2 }
    ])
  end

  it 'has components that sum to the Effective Attribute (racial included)' do
    a = Creatures::Accessor.new(korth) # hill_dwarf, Tier 2, chosen con/wis
    %i[str dex con int wis cha].each do |k|
      sum = a.attribute_breakdown(k).sum { |c| c[:amount] }
      expect(sum).to eq(a.attribute_value(k))
    end
  end
end
