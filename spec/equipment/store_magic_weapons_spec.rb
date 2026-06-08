require 'store_magic_weapons'
require 'equipment'

RSpec.describe StoreMagicWeapons do
  let(:catalog) { Equipment::Catalog.load }

  describe '.builder' do
    it 'lists buyable weapons (no natural attacks), flattened properties, and tiers' do
      b = described_class.builder(catalog)
      names = b[:weapons].map { |w| w[:name] }
      expect(names).to include('Long sword', 'Great sword', 'Longbow')
      expect(names).not_to include('Unarmed') # natural attack
      long = b[:weapons].find { |w| w[:name] == 'Long sword' }
      expect(long).to include(category: 'melee', base_price: 35)
      bow = b[:weapons].find { |w| w[:name] == 'Longbow' }
      expect(bow[:category]).to eq('ranged')

      # Elemental is flattened into one entry per Subtype; Vicious is single.
      elem = b[:properties].select { |p| p[:name] == 'Elemental' }
      expect(elem.map { |p| p[:subtype] }).to contain_exactly('Fire', 'Acid', 'Electricity', 'Cold')
      vicious = b[:properties].find { |p| p[:name] == 'Vicious' }
      expect(vicious).to include(subtype: nil, min_tier: 2, applies_to: ['melee'])

      expect(b[:tiers].first).to eq(tier: 1, surcharge: 250)
    end
  end

  describe '.fields' do
    it 'builds a priced, named Stack for a valid magical weapon' do
      out = described_class.fields('Long sword', [{ 'name' => 'Elemental', 'subtype' => 'Fire' }], 1, catalog)
      expect(out[:error]).to be_nil
      expect(out[:label]).to eq('+1 Flaming Long sword')
      stack = Equipment::Stack.normalize(out[:fields])
      expect(stack.properties).to eq([{ name: 'Elemental', subtype: 'Fire', cost: 500 }])
      expect(Equipment::Pricing.unit_price(stack, catalog)).to eq(785) # 35 + 250 + 500
    end

    it 'rejects a Property below its minimum Tier' do
      out = described_class.fields('Great sword', [{ 'name' => 'Vicious' }], 1, catalog)
      expect(out[:error]).to match(/Vicious needs tier 2/)
    end

    it 'rejects a melee-only Property on a ranged weapon' do
      out = described_class.fields('Longbow', [{ 'name' => 'Vicious' }], 2, catalog)
      expect(out[:error]).to match(/can't go on a ranged weapon/)
    end

    it 'rejects a subtyped Property with no subtype' do
      out = described_class.fields('Long sword', [{ 'name' => 'Elemental' }], 1, catalog)
      expect(out[:error]).to match(/needs a subtype/)
    end

    it 'rejects an unknown property and a non-weapon item' do
      expect(described_class.fields('Long sword', [{ 'name' => 'Nope' }], 1, catalog)[:error]).to match(/unknown property/)
      expect(described_class.fields('Leather armor', [{ 'name' => 'Glory' }], 1, catalog)[:error]).to eq('not a weapon')
    end

    it 'allows Glory on a ranged weapon (applies_to melee + ranged)' do
      out = described_class.fields('Longbow', [{ 'name' => 'Glory' }], 1, catalog)
      expect(out[:error]).to be_nil
      expect(out[:label]).to eq('+1 Glorious Longbow')
    end
  end
end
