require 'spec_helper'
require 'creatures'

RSpec.describe 'Creatures::Races chain walk', type: :model do
  it 'leaf race with single ancestor returns merged size/speed' do
    # human: parent humanoid (size: medium, speed: 30).
    r = Creatures::Races.look_up('human')
    expect(r[:size]).to eq('medium')
    expect(r[:speed]).to eq(30)
  end

  it 'chain leaf speed wins over root' do
    # dwarf overrides humanoid speed to 20. hill_dwarf doesn't redeclare.
    r = Creatures::Races.look_up('hill_dwarf')
    expect(r[:speed]).to eq(20)
  end

  it 'unknown race returns nil' do
    expect(Creatures::Races.look_up('merfolk')).to be_nil
  end

  it 'chain_summary returns root → leaf names' do
    expect(Creatures::Races.chain_summary('hill_dwarf'))
      .to eq('Humanoid → Dwarf → Hill Dwarf')
  end

  it 'attribute_adjustments accumulate across the chain' do
    # The shipped catalog has no per-race adjustments — verify the
    # zero-baseline before downstream content fills it in.
    r = Creatures::Races.look_up('hill_dwarf')
    expect(r[:attribute_adjustments]).to eq(
      str: 0, dex: 0, con: 0, int: 0, wis: 0, cha: 0
    )
  end
end
