require_relative 'support'

RSpec.describe 'Item Consumption' do
  let(:base) { Equipment::Catalog.load }

  # Catalog with named Potion / Scroll / Wand variants carrying a spell.
  def catalog_with(extra_consumables: {}, extra_items: {})
    data = base.data.dup
    data['Consumables'] = base.data['Consumables'].merge(extra_consumables)
    data['Items'] = base.data['Items'].merge(extra_items)
    Equipment::Catalog.new(data)
  end

  let(:conditions) { RecordingConditions.new }
  let(:combat)     { RecordingCombat.new }

  describe 'routing and decrement' do
    it 'routes a cure spell through Apply Heal, imposes toxicity, decrements, and cleans up' do
      catalog = catalog_with(extra_consumables: {
        'Potion of Cure Light Wounds' => { 'category' => 'Consumable', 'base_price' => 50, 'innately_usable' => true,
                                            'spell' => 'cure_light_wounds', 'form' => 'potion' }
      })
      abilities = RecordingAbilities.new(spells: { 'cure_light_wounds' => { effects: [{ 'minor_damage' => -10 }], polarity: :positive } })
      accessor = FakeCreatureAccessor.new('1' => [{ item: 'Potion of Cure Light Wounds', quantity: 2, tier: 1 }])
      inst = Equipment::Instance.new(catalog: catalog, creature_accessor: accessor,
                                     conditions: conditions, abilities: abilities)

      result = inst.consume_item('creature:1', 0, target_creature_id: 'creature:1', toxicity_threshold: 6)
      expect(conditions.heals).to eq([{ minor: 10 }])
      expect(conditions.toxicities.size).to eq(1)
      expect(inst.get_inventory('creature:1')[0].quantity).to eq(1)
      expect(result.spell).to eq('cure_light_wounds')
    end

    it 'routes an explicit damage Effect through Combat and decrements to zero' do
      abilities = RecordingAbilities.new(spells: { 'alchemy_fire' => { effects: [{ 'damage' => { 'amount' => 6, 'type' => 'fire' } }], polarity: :forced } })
      catalog = catalog_with(extra_consumables: {
        "Alchemist's fire" => base.data['Consumables']["Alchemist's fire"].merge('spell' => 'alchemy_fire')
      })
      accessor = FakeCreatureAccessor.new('1' => [{ item: "Alchemist's fire", quantity: 1 }])
      inst = Equipment::Instance.new(catalog: catalog, creature_accessor: accessor,
                                     conditions: conditions, combat: combat, abilities: abilities)
      inst.consume_item('creature:1', 0, target_creature_id: 'creature:2', toxicity_threshold: nil)
      expect(combat.damages.size).to eq(1)
      expect(inst.get_inventory('creature:1')).to be_empty
    end

    it 'does not decrement a non-Consumable (Wand)' do
      catalog = catalog_with(extra_items: {
        'Wand of Sparks' => { 'category' => 'Item', 'slot' => 'bag', 'base_price' => 100, 'spell' => 'sparks', 'form' => 'wand' }
      })
      abilities = RecordingAbilities.new(spells: { 'sparks' => { effects: [{ 'damage' => { 'amount' => 2 } }], polarity: :forced } })
      accessor = FakeCreatureAccessor.new('1' => [{ item: 'Wand of Sparks', quantity: 1, tier: 1 }])
      inst = Equipment::Instance.new(catalog: catalog, creature_accessor: accessor,
                                     conditions: conditions, combat: combat, abilities: abilities)
      result = inst.consume_item('creature:1', 0, target_creature_id: 'creature:2', toxicity_threshold: nil)
      expect(inst.get_inventory('creature:1')[0].quantity).to eq(1)
      expect(result.toxicity_cost).to eq(0)
      expect(conditions.toxicities).to be_empty
    end
  end

  describe 'Saturation Gate' do
    let(:catalog) do
      catalog_with(extra_consumables: {
        'Potion of Cure' => { 'category' => 'Consumable', 'base_price' => 50, 'spell' => 'cure', 'form' => 'potion' },
        'Potion of Aid'  => { 'category' => 'Consumable', 'base_price' => 50, 'spell' => 'aid', 'form' => 'potion' }
      })
    end

    it 'skips Cure effects when the target is at or above the threshold, but still imposes saturation' do
      conditions = RecordingConditions.new(magic_toxicity: 7)
      abilities = RecordingAbilities.new(spells: { 'cure' => { effects: [{ 'minor_damage' => -10 }], polarity: :positive } })
      accessor = FakeCreatureAccessor.new('1' => [{ item: 'Potion of Cure', quantity: 1, tier: 1 }])
      inst = Equipment::Instance.new(catalog: catalog, creature_accessor: accessor, conditions: conditions, abilities: abilities)
      inst.consume_item('creature:1', 0, target_creature_id: 'creature:1', toxicity_threshold: 6)
      expect(conditions.heals).to be_empty
      expect(conditions.toxicities.size).to eq(1)
    end

    it 'applies Ward (Temporary HP) regardless of the gate' do
      conditions = RecordingConditions.new(magic_toxicity: 99)
      abilities = RecordingAbilities.new(spells: { 'aid' => { effects: [{ 'temp_hp' => 8 }], polarity: :positive } })
      accessor = FakeCreatureAccessor.new('1' => [{ item: 'Potion of Aid', quantity: 1, tier: 1 }])
      inst = Equipment::Instance.new(catalog: catalog, creature_accessor: accessor, conditions: conditions, abilities: abilities)
      inst.consume_item('creature:1', 0, target_creature_id: 'creature:1', toxicity_threshold: 6)
      expect(conditions.temp_hps.size).to eq(1)
    end
  end

  describe 'Item-Only' do
    it 'delegates Is Item-Only? to Abilities' do
      abilities = RecordingAbilities.new(item_only: ['dragon_breath'])
      inst = Equipment::Instance.new(catalog: base, abilities: abilities)
      expect(inst.is_item_only?('dragon_breath')).to be true
      expect(inst.is_item_only?('magic_missile')).to be false
    end
  end

  describe 'Item-Form Toxicity' do
    let(:inst) { Equipment::Instance.new(catalog: base) }

    it 'uses Base[item_tier] at or above tier' do
      expect(inst.item_form_toxicity(item_tier: 2, target_tier: 2)).to eq(6)
    end

    it 'floors at Minimum[item_tier] under a large reducer' do
      expect(inst.item_form_toxicity(item_tier: 2, target_tier: 2, saturation_reducer: 5)).to eq(3)
      expect(inst.item_form_toxicity(item_tier: 2, target_tier: 2, saturation_reducer: 10)).to eq(3)
    end

    it 'multiplies Base and Minimum for a below-tier target' do
      expect(inst.item_form_toxicity(item_tier: 2, target_tier: 1)).to eq(12)
      expect(inst.item_form_toxicity(item_tier: 2, target_tier: 1, saturation_reducer: 4)).to eq(8)
      expect(inst.item_form_toxicity(item_tier: 2, target_tier: 1, saturation_reducer: 10)).to eq(6)
    end

    it 'handles a Tier 0 Potion' do
      expect(inst.item_form_toxicity(item_tier: 0, target_tier: 0)).to eq(2)
    end
  end
end
