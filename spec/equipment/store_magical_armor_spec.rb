require 'store_magical_armor'
require 'equipment'

RSpec.describe StoreMagicalArmor do
  let(:catalog) { Equipment::Catalog.load }

  describe '.builder' do
    it 'lists buyable armor (incl. Shields) with base prices, plus the tier surcharges' do
      b = described_class.builder(catalog)
      names = b[:armor].map { |a| a[:name] }
      expect(names).to include('Leather armor', 'Plate mail', 'Tower shield')
      leather = b[:armor].find { |a| a[:name] == 'Leather armor' }
      expect(leather[:base_price]).to eq(10)
      expect(b[:tiers].first).to eq(tier: 1, surcharge: 250)
      expect(b[:tiers].map { |t| t[:tier] }).to eq([1, 2, 3, 4, 5])
    end

    it 'carries no Property dimension (Tier only)' do
      b = described_class.builder(catalog)
      expect(b).not_to have_key(:properties)
    end
  end

  describe '.fields' do
    it 'builds a priced, named Stack for a valid tiered armor (no properties)' do
      out = described_class.fields('Leather armor', 2, catalog)
      expect(out[:error]).to be_nil
      expect(out[:label]).to eq('+2 Leather armor')
      stack = Equipment::Stack.normalize(out[:fields])
      expect(stack.tier).to eq(2)
      expect(stack.properties).to eq([])
      expect(Equipment::Pricing.unit_price(stack, catalog)).to eq(1010) # 10 + 1000
    end

    it 'rejects a non-armor item' do
      expect(described_class.fields('Long sword', 1, catalog)[:error]).to eq('not armor')
    end

    it 'rejects a Tier below 1' do
      expect(described_class.fields('Leather armor', 0, catalog)[:error]).to eq('invalid tier')
      expect(described_class.fields('Leather armor', 'x', catalog)[:error]).to eq('invalid tier')
    end
  end
end
