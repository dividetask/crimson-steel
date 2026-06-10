require_relative 'support'

RSpec.describe 'Shops' do
  let(:catalog) { Equipment::Catalog.load }

  describe 'Visit Generic Shop (population model)' do
    let(:generic) do
      { 'alch' => {
        'name' => 'Alchemist', 'base_gold' => 80, 'gold_per_sqrt_pop' => 18,
        'stock' => [
          { 'item' => 'Potion of Heal', 'tier' => 0, 'min_pop' => 5, 'qty_base' => 2, 'qty_per_kpop' => 4 },
          { 'item' => "Acid jar", 'min_pop' => 200, 'qty_base' => 1, 'qty_per_kpop' => 1 }
        ]
      } }
    end

    def inst(game_day: 5)
      Equipment::Instance.new(catalog: catalog, generic_shops: generic, game_day: game_day)
    end

    it 'scales item Quantity with population and records the Game Day' do
      i = inst
      owner = i.visit_generic_shop('alch', population: 1000)
      expect(owner).to eq('generic_shop:alch')
      expect(i.active_generic_day('alch')).to eq(5)
      potion = i.get_inventory(owner).find { |s| s.item_type == 'Potion of Heal' }
      expect(potion.quantity).to eq(6) # 2 + floor(4 * 1000 / 1000)
    end

    it 'gates items below their min_pop' do
      i = inst
      i.visit_generic_shop('alch', population: 100)
      types = i.get_inventory('generic_shop:alch').map(&:item_type)
      expect(types).to include('Potion of Heal')
      expect(types).not_to include('Acid jar')
    end

    it 'gives the shop a finite, population-scaled Gold budget' do
      i = inst
      i.visit_generic_shop('alch', population: 1000)
      # 80 + floor(18 * sqrt(1000)) = 80 + 569 = 649
      expect(i.get_total_wealth('generic_shop:alch')).to eq(649)
      expect(i.shop_can_buy?('generic_shop:alch', 700)).to be false
      expect(i.shop_can_buy?('generic_shop:alch', 600)).to be true
    end

    it 'returns the existing Active Generic Shop on a same-day re-visit without re-rolling' do
      i = inst
      i.visit_generic_shop('alch', population: 1000)
      i.adjust_stack_quantity('generic_shop:alch', 0, 99)
      i.visit_generic_shop('alch', population: 50_000) # ignored same day
      expect(i.get_inventory('generic_shop:alch')[0].quantity).to eq(99)
    end

    it 'errors for an unknown Generic Shop' do
      expect(inst.visit_generic_shop('nope', population: 100)).to be(Equipment::ERROR)
    end

    it 'loads the real shops.yaml catalog by default' do
      i = Equipment::Instance.new(catalog: catalog, game_day: 1)
      owner = i.visit_generic_shop('alchemist_shop', population: 1000)
      potion = i.get_inventory(owner).find { |s| s.item_type == 'Potion of Heal' && s.tier == 0 }
      expect(potion.quantity).to eq(6)
      expect(i.get_total_wealth(owner)).to eq(649)
    end

    it 'stocks a magical weapon with its Property and prices it from the catalog' do
      generic_magic = { 'magic' => {
        'name' => 'Arcane Armory', 'base_gold' => 0, 'gold_per_sqrt_pop' => 0,
        'stock' => [
          { 'item' => 'Long sword', 'tier' => 1, 'min_pop' => 5, 'qty_base' => 1, 'qty_per_kpop' => 0,
            'properties' => [{ 'name' => 'Elemental', 'subtype' => 'Fire' }] }
        ]
      } }
      i = Equipment::Instance.new(catalog: catalog, generic_shops: generic_magic, game_day: 1)
      owner = i.visit_generic_shop('magic', population: 100)
      sword = i.get_inventory(owner).find { |s| s.item_type == 'Long sword' }
      expect(sword.properties).to eq([{ name: 'Elemental', subtype: 'Fire', cost: nil }])
      # Base 35 + Tier 1 surcharge 250 + Elemental cost 500 = 785.
      expect(Equipment::Pricing.unit_price(sword, catalog)).to eq(785)
    end
  end

  describe 'Advance Time' do
    let(:generic) { { 'alch' => { 'base_gold' => 0, 'gold_per_sqrt_pop' => 0, 'stock' => [{ 'item' => 'Potion of Heal', 'tier' => 0, 'min_pop' => 5, 'qty_base' => 1, 'qty_per_kpop' => 0 }] } } }

    it 'expires yesterday Active Generic Shops; a later visit re-rolls' do
      i = Equipment::Instance.new(catalog: catalog, generic_shops: generic, game_day: 5)
      i.visit_generic_shop('alch', population: 100)
      expect(i.advance_time).to eq(6)
      expect(i.store.exists?('generic_shop:alch')).to be false
      i.visit_generic_shop('alch', population: 100)
      expect(i.active_generic_day('alch')).to eq(6)
    end
  end

  describe 'Refresh Specific Shop' do
    let(:loot) do
      Equipment::LootTables.new(tables: {
        'stock' => { 'rolls' => [{ 'item' => { 'item' => 'Dagger', 'quantity' => 2 } }] }
      })
    end

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
      expect(inv).to eq([['Spear', 5]]) # 1 + floor(0.4 * 10) = 5
    end

    it 'merges Template rolls back in via Stack Identity' do
      inst = Equipment::Instance.new(catalog: catalog, loot: loot,
                                     rng: SequenceRng.new([0.6, 0.0]),
                                     shops: { 'smith' => { template: 'stock' } })
      inst.add_item('shop:smith', item: 'Dagger', quantity: 4)
      inst.refresh_specific_shop('smith')
      dagger = inst.get_inventory('shop:smith').find { |s| s.item_type == 'Dagger' }
      expect(dagger.quantity).to be >= 3
    end

    it 'refuses a buy a Specific Shop cannot afford' do
      inst = Equipment::Instance.new(catalog: catalog, shops: { 'smith' => { template: nil } })
      inst.add_item('shop:smith', item: 'Gold', quantity: 5)
      expect(inst.shop_can_buy?('shop:smith', 10)).to be false
    end
  end
end
