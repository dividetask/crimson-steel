require_relative 'support'

RSpec.describe 'Equip and Reconcile Loadout' do
  let(:catalog)    { Equipment::Catalog.load }
  let(:accessor)   { FakeCreatureAccessor.new }
  let(:conditions) { RecordingConditions.new }
  let(:inst) do
    Equipment::Instance.new(catalog: catalog, creature_accessor: accessor, conditions: conditions)
  end

  describe 'Equip Stack' do
    it 'peels off a Quantity-1 equipped copy' do
      accessor.set_inventory('1', [Equipment::Stack.normalize(item: 'Long sword', quantity: 2, equipped: false)])
      inst.equip_stack('creature:1', 0)
      inv = inst.get_inventory('creature:1')
      expect(inv.size).to eq(2)
      expect(inv[0]).to have_attributes(quantity: 1, equipped: false)
      expect(inv[1]).to have_attributes(quantity: 1, equipped: true)
    end

    it 'reverses the split on Unequip by merging back' do
      accessor.set_inventory('1', [Equipment::Stack.normalize(item: 'Long sword', quantity: 2, equipped: false)])
      inst.equip_stack('creature:1', 0)
      equipped_idx = inst.get_inventory('creature:1').find_index(&:equipped)
      inst.unequip_stack('creature:1', equipped_idx)
      inv = inst.get_inventory('creature:1')
      expect(inv.size).to eq(1)
      expect(inv[0]).to have_attributes(quantity: 2, equipped: false)
    end

    it 'refuses to equip a Consumable' do
      accessor.set_inventory('1', [Equipment::Stack.normalize(item: "Alchemist's fire", quantity: 1)])
      expect(inst.equip_stack('creature:1', 0)).to be(Equipment::ERROR)
    end
  end

  describe 'Reconcile Loadout' do
    it 'clears the equipment namespace before any Apply Effect' do
      accessor.set_inventory('3', [Equipment::Stack.normalize(
        item: 'Belt of Strength', tier: 1, guidance_bonus: 2, equipped: true
      )])
      inst.reconcile_loadout('creature:3')
      expect(conditions.removed_prefixes).to eq(['equipment:creature:3:'])
    end

    it 'posts each equipped Stack Guidance Bonus with the Stable Stack Key Source ID' do
      accessor.set_inventory('3', [Equipment::Stack.normalize(
        item: 'Belt of Strength', tier: 1, guidance_bonus: 2, equipped: true
      )])
      inst.reconcile_loadout('creature:3')
      expect(conditions.applied).to eq([{
        target_key: 'str', bonus_type: 'Guidance', amount: 2,
        source_id: 'equipment:creature:3:Belt of Strength:belt'
      }])
    end

    it 'indexes Source IDs when a Stack posts more than one Effect' do
      dual = { 'Dual Ward' => { 'min_tier' => 1, 'cost' => 0, 'applies_to' => ['melee'],
                                'display' => { 'word' => 'Warded' },
                                'effects' => [
                                  { 'target_key' => 'str', 'bonus_type' => 'Guidance', 'amount' => 1 },
                                  { 'target_key' => 'dex', 'bonus_type' => 'Guidance', 'amount' => 1 }
                                ] } }
      custom = Equipment::Catalog.new(catalog.data.merge('Weapon Properties' => catalog.data['Weapon Properties'].merge(dual)))
      i = Equipment::Instance.new(catalog: custom, creature_accessor: accessor, conditions: conditions)
      accessor.set_inventory('3', [Equipment::Stack.normalize(
        item: 'Long sword', tier: 1, equipped: true, properties: [{ name: 'Dual Ward' }]
      )])
      i.reconcile_loadout('creature:3')
      expect(conditions.applied.map { |e| e[:source_id] }).to eq([
        'equipment:creature:3:Long sword:hand:0:0',
        'equipment:creature:3:Long sword:hand:0:1'
      ])
    end

    it 'is idempotent — re-running clears and re-posts the same Effects' do
      accessor.set_inventory('3', [Equipment::Stack.normalize(
        item: 'Belt of Strength', tier: 1, guidance_bonus: 2, equipped: true
      )])
      first = inst.reconcile_loadout('creature:3')
      second = inst.reconcile_loadout('creature:3')
      expect(first).to eq(second)
      expect(conditions.removed_prefixes.size).to eq(2)
    end

    it 'clears the namespace but posts nothing when no Stack is equipped' do
      accessor.set_inventory('3', [Equipment::Stack.normalize(item: 'Long sword', equipped: false)])
      inst.reconcile_loadout('creature:3')
      expect(conditions.removed_prefixes).to eq(['equipment:creature:3:'])
      expect(conditions.applied).to be_empty
    end

    it 'uses hand:<index> keys for multiple equipped Weapons' do
      ench = { 'Sharp' => { 'min_tier' => 1, 'cost' => 0, 'applies_to' => ['melee'],
                            'display' => { 'word' => 'Sharp' },
                            'effects' => [{ 'target_key' => 'str', 'bonus_type' => 'Guidance', 'amount' => 1 }] } }
      custom = Equipment::Catalog.new(catalog.data.merge('Weapon Properties' => catalog.data['Weapon Properties'].merge(ench)))
      i = Equipment::Instance.new(catalog: custom, creature_accessor: accessor, conditions: conditions)
      accessor.set_inventory('3', [
        Equipment::Stack.normalize(item: 'Long sword', tier: 1, equipped: true, properties: [{ name: 'Sharp' }]),
        Equipment::Stack.normalize(item: 'Long sword', tier: 2, equipped: true, properties: [{ name: 'Sharp' }])
      ])
      i.reconcile_loadout('creature:3')
      expect(conditions.applied.map { |e| e[:source_id] }).to eq([
        'equipment:creature:3:Long sword:hand:0',
        'equipment:creature:3:Long sword:hand:1'
      ])
    end
  end

  # A Tattoo is permanent: it is never (un)equippable, so it posts its
  # effects regardless of the `equipped` flag.
  describe 'Tattoos are always borne' do
    it 'posts a Tattoo Guidance Bonus without the equipped flag' do
      accessor.set_inventory('3', [Equipment::Stack.normalize(
        item: 'Tattoo of the Fox', tier: 1, guidance_bonus: 1
      )])
      inst.reconcile_loadout('creature:3')
      expect(conditions.applied).to eq([{
        target_key: 'int', bonus_type: 'Guidance', amount: 1,
        source_id: 'equipment:creature:3:Tattoo of the Fox:face'
      }])
    end

    it 'surfaces the Tattoo effect via equipped_effects without the flag' do
      accessor.set_inventory('3', [Equipment::Stack.normalize(
        item: 'Tattoo of the Fox', tier: 1, guidance_bonus: 1
      )])
      expect(inst.equipped_effects('creature:3')).to eq([
        { target_key: 'int', bonus_type: 'Guidance', amount: 1 }
      ])
    end

    it 'refuses to (un)equip a Tattoo through the toggle' do
      accessor.set_inventory('3', [Equipment::Stack.normalize(
        item: 'Tattoo of the Fox', guidance_bonus: 1
      )])
      expect(inst.equip_stack('creature:3', 0)).to be(Equipment::ERROR)
    end
  end
end
