require_relative 'support'

RSpec.describe 'End-of-Combat loot' do
  let(:catalog) { Equipment::Catalog.load }

  describe 'Collect Combat Loot' do
    let(:accessor) do
      FakeCreatureAccessor.new(
        'goblin_a' => [{ item: 'Short sword', quantity: 1, equipped: true }, { item: 'Gold', quantity: 3 }],
        'goblin_b' => [{ item: 'Dagger', quantity: 1, equipped: true }, { item: 'Silver', quantity: 10 }],
        'pc_1'     => [{ item: 'Long sword', equipped: true }]
      )
    end
    let(:inst) { Equipment::Instance.new(catalog: catalog, creature_accessor: accessor) }
    let(:entries) do
      [{ combatant_id: 1, creature_id: 'pc_1', ally: true },
       { combatant_id: 2, creature_id: 'goblin_a', ally: false },
       { combatant_id: 3, creature_id: 'goblin_b', ally: false }]
    end

    it 'moves non-ally Inventory and Currency into the Ground Pile' do
      pile = inst.collect_combat_loot(entries, combat_id: 7)
      expect(pile).to eq('ground:combat_7')
      contents = inst.get_inventory(pile).map { |s| [s.item_type, s.quantity] }
      expect(contents).to eq([['Short sword', 1], ['Gold', 3], ['Dagger', 1], ['Silver', 10]])
      expect(inst.get_inventory('creature:goblin_a')).to be_empty
      expect(inst.get_inventory('creature:goblin_b')).to be_empty
    end

    it 'leaves ally Inventories untouched' do
      inst.collect_combat_loot(entries, combat_id: 7)
      expect(inst.get_inventory('creature:pc_1').map(&:item_type)).to eq(['Long sword'])
    end

    it 'resets equipped on moved Stacks' do
      pile = inst.collect_combat_loot(entries, combat_id: 7)
      expect(inst.get_inventory(pile).map(&:equipped)).to all(be false)
    end

    it 'rolls a Loot Table Reference in addition to Inventory' do
      loot = Equipment::LootTables.new(tables: {
        'goblin_pocket_change' => { 'rolls' => [{ 'item' => { 'item' => 'Copper', 'quantity' => 5 } }] }
      })
      i = Equipment::Instance.new(catalog: catalog, creature_accessor: accessor, loot: loot)
      pile = i.collect_combat_loot(
        [{ combatant_id: 2, creature_id: 'goblin_a', ally: false, loot_table: 'goblin_pocket_change' }],
        combat_id: 9
      )
      expect(i.get_inventory(pile).map(&:item_type)).to include('Copper')
    end

    it 'produces no Ground Pile for an all-ally hand-off' do
      expect(inst.collect_combat_loot([{ combatant_id: 1, creature_id: 'pc_1', ally: true }], combat_id: 1)).to be_nil
    end
  end

  describe 'Distribute Loot Pile' do
    let(:accessor) { FakeCreatureAccessor.new('1' => [], '2' => []) }
    let(:inst) { Equipment::Instance.new(catalog: catalog, creature_accessor: accessor) }

    def seed_pile(id, stacks)
      stacks.each { |st| inst.add_item(id, st) }
    end

    it 'transfers each Stack to its assigned target and empties the pile' do
      seed_pile('ground:c7', [{ item: 'Rapier', quantity: 1 }, { item: 'Healing Draught', quantity: 2 }, { item: 'Gold', quantity: 30 }])
      results = inst.distribute_loot_pile('ground:c7', [
        { stack_ref: 0, target_owner_id: 'character:1' },
        { stack_ref: 1, target_owner_id: 'party' },
        { stack_ref: 2, target_owner_id: 'party' }
      ])
      expect(results.compact.size).to eq(3)
      expect(inst.get_inventory('creature:1').map(&:item_type)).to eq(['Rapier'])
      expect(inst.get_inventory('party').map { |s| [s.item_type, s.quantity] }).to eq([['Healing Draught', 2], ['Gold', 30]])
      expect(inst.get_inventory('ground:c7')).to be_empty
      expect(inst.store.exists?('ground:c7')).to be false
    end

    it 'leaves skip / nil assignments on the pile and keeps the pile' do
      seed_pile('ground:c7', [{ item: 'A' }, { item: 'B' }, { item: 'C' }])
      results = inst.distribute_loot_pile('ground:c7', [
        { stack_ref: 0, target_owner_id: 'party' },
        { stack_ref: 1, target_owner_id: 'skip' },
        { stack_ref: 2, target_owner_id: nil }
      ])
      expect(results).to eq([results[0], nil, nil])
      expect(inst.get_inventory('ground:c7').map(&:item_type)).to eq(['B', 'C'])
    end

    it 'merges into a PC who already owns a matching Stack' do
      accessor.set_inventory('1', [Equipment::Stack.normalize(item: 'Healing Draught', quantity: 1, innately_usable: true)])
      seed_pile('ground:c7', [{ item: 'Healing Draught', quantity: 2 }])
      inst.distribute_loot_pile('ground:c7', [{ stack_ref: 0, target_owner_id: 'character:1' }])
      hp = inst.get_inventory('creature:1').find { |s| s.item_type == 'Healing Draught' }
      expect(hp.quantity).to eq(3)
    end

    it 'rejects an unknown Creature target without mutating the pile' do
      seed_pile('ground:c7', [{ item: 'Rapier' }])
      expect(inst.distribute_loot_pile('ground:c7', [{ stack_ref: 0, target_owner_id: 'character:99999' }])).to be(Equipment::ERROR)
      expect(inst.get_inventory('ground:c7').map(&:item_type)).to eq(['Rapier'])
    end

    it 'rejects a non-existent pile' do
      expect(inst.distribute_loot_pile('ground:never', [{ stack_ref: 0, target_owner_id: 'party' }])).to be(Equipment::ERROR)
    end

    it 'rejects an out-of-range stack_ref without mutating the pile' do
      seed_pile('ground:c7', [{ item: 'A' }, { item: 'B' }])
      expect(inst.distribute_loot_pile('ground:c7', [{ stack_ref: 5, target_owner_id: 'party' }])).to be(Equipment::ERROR)
      expect(inst.get_inventory('ground:c7').size).to eq(2)
    end
  end

  describe 'Drop Stack' do
    it 'transfers onto a Ground Pile at a location' do
      accessor = FakeCreatureAccessor.new('1' => [{ item: 'Dagger', quantity: 2 }])
      inst = Equipment::Instance.new(catalog: catalog, creature_accessor: accessor)
      inst.drop_stack('creature:1', 0, 'tavern floor', quantity: 1)
      expect(inst.get_inventory('ground:tavern floor').map { |s| [s.item_type, s.quantity] }).to eq([['Dagger', 1]])
    end
  end
end
