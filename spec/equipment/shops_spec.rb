require_relative 'support'

RSpec.describe 'Shops' do
  let(:catalog) { Equipment::Catalog.load }
  let(:loot) do
    Equipment::LootTables.new(tables: {
      'stock' => { 'rolls' => [{ 'item' => { 'item' => 'Dagger', 'quantity' => 2 } }] }
    })
  end

  describe 'Visit Generic Shop' do
    it 'rolls the Template on first visit and records the Game Day' do
      inst = Equipment::Instance.new(catalog: catalog, loot: loot, game_day: 5,
                                     shops: { 'alch' => { template: 'stock' } })
      owner = inst.visit_generic_shop('alch')
      expect(owner).to eq('generic_shop:alch')
      expect(inst.active_generic_day('alch')).to eq(5)
      expect(inst.get_inventory(owner).map(&:item_type)).to eq(['Dagger'])
    end

    it 'returns the existing Active Generic Shop on a same-day re-visit without re-rolling' do
      inst = Equipment::Instance.new(catalog: catalog, loot: loot, game_day: 5,
                                     shops: { 'alch' => { template: 'stock' } })
      inst.visit_generic_shop('alch')
      inst.adjust_stack_quantity('generic_shop:alch', 0, 99) # mutate to detect a re-roll
      inst.visit_generic_shop('alch')
      expect(inst.get_inventory('generic_shop:alch')[0].quantity).to eq(99)
    end

    it 'has unlimited Wealth' do
      inst = Equipment::Instance.new(catalog: catalog, loot: loot, shops: { 'alch' => { template: 'stock' } })
      expect(inst.get_total_wealth('generic_shop:alch')).to eq(Float::INFINITY)
      expect(inst.shop_can_buy?('generic_shop:alch', 10_000)).to be true
    end
  end

  describe 'Advance Time' do
    it 'expires yesterday Active Generic Shops; a later visit re-rolls' do
      inst = Equipment::Instance.new(catalog: catalog, loot: loot, game_day: 5,
                                     shops: { 'alch' => { template: 'stock' } })
      inst.visit_generic_shop('alch')
      expect(inst.advance_time).to eq(6)
      expect(inst.store.exists?('generic_shop:alch')).to be false
      inst.visit_generic_shop('alch')
      expect(inst.active_generic_day('alch')).to eq(6)
    end
  end

  describe 'Refresh Specific Shop' do
    it 'flips a d2 per Stack, then rolls and merges the Template' do
      # d2 draws: stack0 -> 1 (remove), stack1 -> 2 (keep) + reroll, stack2 -> 1 (remove).
      rng = SequenceRng.new([0.0, 0.6, 0.4, 0.0])
      inst = Equipment::Instance.new(catalog: catalog, loot: loot, rng: rng,
                                     shops: { 'smith' => { template: nil } })
      inst.add_item('shop:smith', item: 'Mace', quantity: 1)
      inst.add_item('shop:smith', item: 'Spear', quantity: 10)
      inst.add_item('shop:smith', item: 'Rapier', quantity: 1)
      inst.refresh_specific_shop('smith')
      inv = inst.get_inventory('shop:smith').map { |s| [s.item_type, s.quantity] }
      expect(inv).to eq([['Spear', 5]]) # 1 + floor(0.4*10) = 5
    end

    it 'merges Template rolls back in via Stack Identity' do
      inst = Equipment::Instance.new(catalog: catalog, loot: loot,
                                     rng: SequenceRng.new([0.6, 0.0]), # keep the lone stack, reroll
                                     shops: { 'smith' => { template: 'stock' } })
      inst.add_item('shop:smith', item: 'Dagger', quantity: 4)
      inst.refresh_specific_shop('smith')
      dagger = inst.get_inventory('shop:smith').find { |s| s.item_type == 'Dagger' }
      # surviving rerolled quantity (>=1) plus the 2 rolled from the template
      expect(dagger.quantity).to be >= 3
    end

    it 'refuses a buy a Specific Shop cannot afford' do
      inst = Equipment::Instance.new(catalog: catalog, shops: { 'smith' => { template: nil } })
      inst.add_item('shop:smith', item: 'Gold', quantity: 5)
      expect(inst.shop_can_buy?('shop:smith', 10)).to be false
    end
  end
end
