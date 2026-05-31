require_relative 'support'

RSpec.describe 'Restock' do
  let(:catalog) { Equipment::Catalog.load }
  let(:inst)    { Equipment::Instance.new(catalog: catalog) }

  it 'sums understocked deltas, ignoring fully-stocked and target-less Stacks' do
    inst.add_item('shop:smith', item: 'Arrow', tier: 0, quantity: 5, restock_target: 20)
    inst.add_item('shop:smith', item: 'Bolt', tier: 0, quantity: 20, restock_target: 20)
    inst.add_item('shop:smith', item: 'Dagger', quantity: 1)
    inst.add_item('shop:smith', item: 'Gold', quantity: 50)
    cost = inst.restock('shop:smith')
    expect(cost).to be_within(1e-9).of(3.75)
    arrow = inst.get_inventory('shop:smith').find { |s| s.item_type == 'Arrow' }
    expect(arrow.quantity).to eq(20)
  end

  it 'fails atomically when Total Wealth is insufficient' do
    inst.add_item('shop:smith', item: 'Arrow', tier: 0, quantity: 5, restock_target: 20)
    inst.add_item('shop:smith', item: 'Gold', quantity: 1)
    expect(inst.restock('shop:smith')).to be(Equipment::ERROR)
    arrow = inst.get_inventory('shop:smith').find { |s| s.item_type == 'Arrow' }
    expect(arrow.quantity).to eq(5)
  end
end
