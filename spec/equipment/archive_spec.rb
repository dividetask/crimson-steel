require_relative 'support'

RSpec.describe 'Loot Archive' do
  let(:catalog)  { Equipment::Catalog.load }
  let(:accessor) { FakeCreatureAccessor.new('pc_1' => []) }
  let(:inst)     { Equipment::Instance.new(catalog: catalog, creature_accessor: accessor) }

  before do
    inst.add_item('ground:combat_42', item: 'Rapier', tier: 1)
    inst.add_item('ground:combat_42', item: 'Gold', quantity: 30)
  end

  it 'snapshots the Ground Pile on Open, leaving the pile in place' do
    id = inst.open_loot_archive('ground:combat_42', label: 'Goblin hoard')
    entry = inst.loot_archive(id)
    expect(entry[:items].size).to eq(2)
    expect(entry[:items].map { |r| r[:claimed_by] }).to eq([nil, nil])
    expect(inst.get_inventory('ground:combat_42').size).to eq(2)
  end

  it 'transitions one item on Claim and moves it out of the pile' do
    id = inst.open_loot_archive('ground:combat_42')
    dest = inst.claim_from_loot_archive(id, 0, 'creature:pc_1')
    expect(dest.item_type).to eq('Rapier')
    expect(inst.loot_archive(id)[:items][0][:claimed_by]).to eq('creature:pc_1')
    expect(inst.get_inventory('creature:pc_1').map(&:item_type)).to eq(['Rapier'])
  end

  it 'refuses a previously claimed item' do
    id = inst.open_loot_archive('ground:combat_42')
    inst.claim_from_loot_archive(id, 0, 'creature:pc_1')
    expect(inst.claim_from_loot_archive(id, 0, 'creature:pc_1')).to be(Equipment::ERROR)
  end

  it 'marks the Entry closed and removes the Ground Pile on Close' do
    id = inst.open_loot_archive('ground:combat_42')
    inst.close_loot_archive(id)
    expect(inst.loot_archive(id)[:closed]).to be true
    expect(inst.store.exists?('ground:combat_42')).to be false
  end
end
