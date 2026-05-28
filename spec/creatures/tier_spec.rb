require 'spec_helper'
require_relative 'fixtures'

RSpec.describe 'Creatures Get Tier', type: :model do
  include CreaturesFixtures

  it 'tier override bypasses computation' do
    a = Creatures::Accessor.new(record(tier: 4, tags: [], classes: { fighter: { level: 1 } }))
    expect(a.tier).to eq(4)
  end

  it 'player_character tag at total level 4 → Tier 2' do
    a = Creatures::Accessor.new(record(
      tags: ['player_character'], classes: { cleric: { level: 4 } }, tier: nil
    ))
    # player_character breakpoints [0,1,4,8,16,30], level 4 → index 2.
    expect(a.tier).to eq(2)
  end

  it 'animal tag at total level 6 → Tier 1' do
    a = Creatures::Accessor.new(record(
      race: 'beast', tags: ['animal'],
      classes: { commoner: { level: 6 } }, tier: nil
    ))
    # animal breakpoints [0,4,8,12,16,20]; level 6, highest ≤ 6 is index 1 (=4).
    expect(a.tier).to eq(1)
  end

  it 'multiple matching tags take the maximum' do
    a = Creatures::Accessor.new(record(
      tags: %w[player_character noble], classes: { fighter: { level: 5 } }, tier: nil
    ))
    # player_character at 5 → index 3 (breakpoint 4, next is 8). Actually:
    # player_character [0,1,4,8,16,30] at level 5: largest i with bp ≤ 5 is index 2 (=4).
    # noble [0,2,5,9,12,20] at level 5: largest i with bp ≤ 5 is index 2 (=5).
    # max = 2.
    expect(a.tier).to eq(2)
  end

  it 'no matching tag falls back to the minimum tier across every list' do
    a = Creatures::Accessor.new(record(
      tags: ['unrelated'], classes: { commoner: { level: 1 } }, tier: nil
    ))
    # Every list gets some Tier at level 1; the lowest list (commoner) gives 0.
    expect(a.tier).to eq(0)
  end

  it 'tier 0 when total level is 0' do
    a = Creatures::Accessor.new(record(
      tags: ['player_character'], classes: {}, tier: nil
    ))
    expect(a.tier).to eq(0)
  end
end
