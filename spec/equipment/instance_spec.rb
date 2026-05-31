require_relative 'support'

RSpec.describe Equipment::Instance do
  let(:catalog)  { Equipment::Catalog.load }
  let(:accessor) { FakeCreatureAccessor.new }
  let(:inst)     { described_class.new(catalog: catalog, creature_accessor: accessor) }

  def s(**fields) ; fields ; end

  describe 'Add Item' do
    it 'appends to an empty Inventory' do
      inst.add_item('party', s(item: 'Long sword', quantity: 1, tier: 0))
      inv = inst.get_inventory('party')
      expect(inv.size).to eq(1)
      expect(inv[0].item_type).to eq('Long sword')
    end

    it 'merges two Stacks with identical identity' do
      inst.add_item('party', s(item: 'Long sword', tier: 0))
      inst.add_item('party', s(item: 'Long sword', tier: 0))
      inv = inst.get_inventory('party')
      expect(inv.size).to eq(1)
      expect(inv[0].quantity).to eq(2)
    end

    it 'keeps Stacks that differ on tier separate, new one last' do
      inst.add_item('party', s(item: 'Long sword', tier: 0))
      inst.add_item('party', s(item: 'Long sword', tier: 1))
      inv = inst.get_inventory('party')
      expect(inv.map(&:tier)).to eq([0, 1])
    end

    it 'does not merge equipped and unequipped copies' do
      inst.add_item('party', s(item: 'Long sword', tier: 1, equipped: false))
      inst.add_item('party', s(item: 'Long sword', tier: 1, equipped: true))
      expect(inst.get_inventory('party').size).to eq(2)
    end
  end

  describe 'Remove / Adjust' do
    it 'decrements without deleting' do
      inst.add_item('party', s(item: "Alchemist's fire", quantity: 2))
      expect(inst.remove_item('party', 0, quantity: 1)).to eq(1)
      expect(inst.get_inventory('party')[0].quantity).to eq(1)
    end

    it 'removes the whole Stack with no quantity argument' do
      inst.add_item('party', s(item: "Alchemist's fire", quantity: 2))
      expect(inst.remove_item('party', 0)).to eq(0)
      expect(inst.get_inventory('party')[0].quantity).to eq(0)
    end

    it 'refuses to go negative and refuses a negative quantity' do
      inst.add_item('party', s(item: "Alchemist's fire", quantity: 2))
      expect(inst.remove_item('party', 0, quantity: 5)).to be(Equipment::ERROR)
      expect(inst.remove_item('party', 0, quantity: -1)).to be(Equipment::ERROR)
      expect(inst.get_inventory('party')[0].quantity).to eq(2)
    end

    it 'Adjust sets the value directly' do
      inst.add_item('party', s(item: 'Gold', quantity: 12))
      expect(inst.adjust_stack_quantity('party', 0, 0)).to eq(0)
      expect(inst.get_inventory('party')[0].quantity).to eq(0)
    end
  end

  describe 'Transfer Stack' do
    it 'moves a Quantity between Owners and empties the source after Cleanup' do
      accessor.set_inventory('1', [Equipment::Stack.normalize(item: 'Long sword', quantity: 1)])
      inst.transfer_stack('creature:1', 'party', 0)
      expect(inst.get_inventory('party').map(&:item_type)).to eq(['Long sword'])
      inst.cleanup('creature:1')
      expect(inst.get_inventory('creature:1')).to be_empty
    end
  end

  describe 'Cleanup' do
    it 'removes zero-Quantity Stacks without a Restock Target but keeps those with one' do
      inst.add_item('party', s(item: 'Long sword', quantity: 0))
      inst.add_item('party', s(item: 'Arrow', quantity: 0, restock_target: 20))
      inst.cleanup('party')
      inv = inst.get_inventory('party')
      expect(inv.map(&:item_type)).to eq(['Arrow'])
    end

    it 'deletes an emptied Ground Pile Owner' do
      inst.add_item('ground:x', s(item: 'Dagger', quantity: 1))
      inst.remove_item('ground:x', 0)
      inst.cleanup('ground:x')
      expect(inst.get_inventory('ground:x')).to be_empty
      expect(inst.store.exists?('ground:x')).to be false
    end
  end

  describe 'Total Wealth and Debit Wealth' do
    it 'sums Currencies and Gems, ignoring other Categories' do
      inst.add_item('party', s(item: 'Gold', quantity: 5))
      inst.add_item('party', s(item: 'Silver', quantity: 12))
      inst.add_item('party', s(item: 'Gem', value_in_gold: 50, quantity: 1))
      inst.add_item('party', s(item: 'Long sword'))
      expect(inst.get_total_wealth('party')).to be_within(1e-9).of(56.2)
    end

    it 'spends coins cheapest-first' do
      inst.add_item('party', s(item: 'Copper', quantity: 50))
      inst.add_item('party', s(item: 'Silver', quantity: 5))
      inst.add_item('party', s(item: 'Gold', quantity: 1))
      inst.debit_wealth('party', 0.7)
      inv = inst.get_inventory('party').reject { |x| x.quantity <= 0 }
      by_type = inv.to_h { |x| [x.item_type, x.quantity] }
      expect(by_type['Copper']).to be_nil
      expect(by_type['Silver']).to eq(3)
      expect(by_type['Gold']).to eq(1)
    end

    it 'consumes Gems cheapest-first when coins run out and refunds Gold change' do
      inst.add_item('party', s(item: 'Copper', quantity: 5))
      inst.add_item('party', s(item: 'Gem', value_in_gold: 10, quantity: 1))
      inst.add_item('party', s(item: 'Gem', value_in_gold: 50, quantity: 1))
      refund = inst.debit_wealth('party', 30)
      expect(refund).to be_within(1e-9).of(30.05)
      gold = inst.get_inventory('party').find { |x| x.item_type == 'Gold' }
      expect(gold.quantity).to be_within(1e-9).of(30.05)
    end

    it 'fails atomically when amount exceeds Total Wealth' do
      inst.add_item('party', s(item: 'Gold', quantity: 5))
      expect(inst.debit_wealth('party', 100)).to be(Equipment::ERROR)
      expect(inst.get_inventory('party')[0].quantity).to eq(5)
    end

    it 'treats zero amount as a no-op' do
      inst.add_item('party', s(item: 'Gold', quantity: 5))
      expect(inst.debit_wealth('party', 0)).to eq(0)
      expect(inst.get_inventory('party')[0].quantity).to eq(5)
    end
  end
end
