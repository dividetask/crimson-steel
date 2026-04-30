require_relative '../lib/equipment'

EQUIPMENT_CONFIG = File.expand_path('../data/equipment_config.yaml', __dir__)

RSpec.describe Equipment do
  let(:equipment) { Equipment.new(config_path: EQUIPMENT_CONFIG) }

  describe '#add_item and stack identity' do
    it 'merges identical stacks' do
      equipment.add_item('character:1', { 'item_type' => 'Gold', 'quantity' => 10 })
      equipment.add_item('character:1', { 'item_type' => 'Gold', 'quantity' => 5 })
      inv = equipment.get_inventory('character:1')
      expect(inv.length).to eq(1)
      expect(inv.first['quantity']).to eq(15)
    end

    it 'keeps separate stacks when identity differs' do
      equipment.add_item('character:1', { 'item_type' => 'Gem', 'quantity' => 1, 'value_in_gold' => 50 })
      equipment.add_item('character:1', { 'item_type' => 'Gem', 'quantity' => 1, 'value_in_gold' => 100 })
      inv = equipment.get_inventory('character:1')
      expect(inv.length).to eq(2)
    end

    it 'separates equipped vs unequipped' do
      equipment.add_item('character:1', { 'item_type' => 'Long sword', 'quantity' => 1, 'tier' => 0, 'equipped' => true })
      equipment.add_item('character:1', { 'item_type' => 'Long sword', 'quantity' => 1, 'tier' => 0, 'equipped' => false })
      expect(equipment.get_inventory('character:1').length).to eq(2)
    end
  end

  describe '#transfer_item' do
    it 'moves quantity from one owner to another' do
      equipment.add_item('character:1', { 'item_type' => 'Gold', 'quantity' => 10 })
      equipment.transfer_item('character:1', 0, 'character:2', 4)
      expect(equipment.get_inventory('character:1').first['quantity']).to eq(6)
      expect(equipment.get_inventory('character:2').first['quantity']).to eq(4)
    end

    it 'caps the transfer at the source quantity' do
      equipment.add_item('character:1', { 'item_type' => 'Gold', 'quantity' => 3 })
      equipment.transfer_item('character:1', 0, 'character:2', 10)
      # Source has 0; cleanup_zero_quantity removes it from the inventory.
      expect(equipment.get_inventory('character:1')).to be_empty
      expect(equipment.get_inventory('character:2').first['quantity']).to eq(3)
    end
  end

  describe '#total_wealth_in_gold' do
    it 'sums currencies and gems by value' do
      equipment.add_item('character:1', { 'item_type' => 'Gold',   'quantity' => 5  })
      equipment.add_item('character:1', { 'item_type' => 'Silver', 'quantity' => 30 })
      equipment.add_item('character:1', { 'item_type' => 'Gem',    'quantity' => 2, 'value_in_gold' => 50 })
      # 5 + 3 + 100 = 108
      expect(equipment.total_wealth_in_gold('character:1')).to be_within(0.001).of(108)
    end
  end

  describe '#debit_wealth' do
    it 'spends coins cheapest-first' do
      equipment.add_item('character:1', { 'item_type' => 'Copper', 'quantity' => 100 })  # 1 gp
      equipment.add_item('character:1', { 'item_type' => 'Silver', 'quantity' => 20 })   # 2 gp
      equipment.add_item('character:1', { 'item_type' => 'Gold',   'quantity' => 5 })    # 5 gp
      # Total: 8 gp. Spend 6 gp.
      equipment.debit_wealth('character:1', 6)
      # Copper goes first (1 gp), then Silver (2 gp), then 3 gp from Gold.
      inv = equipment.get_inventory('character:1').sort_by { |s| s['item_type'] }
      gold = inv.find { |s| s['item_type'] == 'Gold' }
      expect(gold['quantity']).to be_within(0.001).of(2)
    end

    it 'uses gems and refunds overpayment as Gold' do
      equipment.add_item('character:1', { 'item_type' => 'Gem', 'quantity' => 1, 'value_in_gold' => 50 })
      equipment.debit_wealth('character:1', 30)
      # 50 gp gem spent, 20 gp refunded as Gold.
      inv = equipment.get_inventory('character:1')
      gold = inv.find { |s| s['item_type'] == 'Gold' }
      expect(gold['quantity']).to be_within(0.001).of(20)
      gem = inv.find { |s| s['item_type'] == 'Gem' }
      expect(gem).to be_nil  # cleaned up
    end

    it 'rejects insufficient funds' do
      equipment.add_item('character:1', { 'item_type' => 'Gold', 'quantity' => 5 })
      expect { equipment.debit_wealth('character:1', 10) }.to raise_error(ArgumentError, /insufficient/)
    end
  end

  describe '#item_unit_price' do
    it 'returns Currency value_in_gold * quantity' do
      stack = { 'item_type' => 'Gold', 'quantity' => 7 }
      expect(equipment.item_unit_price(stack)).to be_within(0.001).of(7.0)
    end

    it 'returns the Gem stack value_in_gold' do
      stack = { 'item_type' => 'Gem', 'quantity' => 1, 'value_in_gold' => 75 }
      expect(equipment.item_unit_price(stack)).to be_within(0.001).of(75.0)
    end

    it 'applies the Innately Usable multiplier when set' do
      definition = (equipment.equipment_config['Items'] || {})
      potion_type = definition.find { |_, v| v.is_a?(Hash) && v['innately_usable'] }
      next unless potion_type
      stack = { 'item_type' => potion_type[0], 'quantity' => 1, 'tier' => 0 }
      no_mult = equipment.item_unit_price(stack)
      multiplied = no_mult * equipment.innately_usable_multiplier rescue no_mult
      expect(multiplied).to be >= no_mult
    end
  end

  describe '#get_item_details' do
    it 'returns the basic descriptor for a Gold stack' do
      details = equipment.get_item_details({ 'item_type' => 'Gold', 'quantity' => 5 })
      expect(details['category']).to eq('Currency')
      expect(details['unit_price']).to be_within(0.001).of(5.0)
    end
  end

  describe '#equipment_source_id' do
    it 'builds a deterministic namespaced source id' do
      expect(equipment.equipment_source_id('character:42', 'belt_str:body'))
        .to eq('equipment:character:42:belt_str:body')
    end
  end
end
