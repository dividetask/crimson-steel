require 'spec_helper'
require 'store_spell_items'
require 'equipment'

# The Store's Scrolls / Potions / Oils builder: pick a Form (which filters the
# Spell list), then a Spell and Tier. Every Spell can be a Scroll; potion- /
# oil-capable Spells also offer those forms. Pricing: a Potion/Oil costs the
# full Consumable price, a Scroll half; Tier 0 (no surcharge) is priced as half
# the Tier-1 price rather than zero.
RSpec.describe StoreSpellItems do
  let(:catalog) { Equipment.catalog }

  describe '.builder' do
    subject(:data) { described_class.builder(catalog) }

    it 'flags each form a spell offers' do
      heal = data[:spells].find { |r| r[:name] == 'Heal' }
      expect(heal).to include(scroll: true, potion: true, oil: true)   # Heal: potion + oil
      vm = data[:spells].find { |r| r[:name] == 'Vicious Mockery' }
      expect(vm).to include(scroll: true, potion: false, oil: false)   # scroll-only
    end

    it 'prices a Scroll at half the Potion/Oil price, and Tier 0 above zero' do
      heal = data[:spells].find { |r| r[:name] == 'Heal' }
      t0 = heal[:tiers].find { |t| t[:tier] == 0 }
      t1 = heal[:tiers].find { |t| t[:tier] == 1 }
      expect(t0[:potion]).to be > 0                 # Tier 0 is not free
      expect(t0[:scroll]).to eq(t0[:potion] / 2.0)  # scroll = half
      expect(t1[:scroll]).to eq(t1[:potion] / 2.0)
      expect(t1[:oil]).to eq(t1[:potion])           # oil = full
      expect(t0[:potion]).to eq(t1[:potion] / 2.0)  # Tier 0 = half Tier 1
    end

    it 'omits the potion/oil prices for a scroll-only spell' do
      vm = data[:spells].find { |r| r[:name] == 'Vicious Mockery' }
      expect(vm[:tiers].first[:potion]).to be_nil
      expect(vm[:tiers].first[:oil]).to be_nil
      expect(vm[:tiers].first[:scroll]).to be > 0
    end

    it 'is sorted by spell name with no leading/trailing whitespace' do
      names = data[:spells].map { |r| r[:name] }
      expect(names).to eq(names.sort)
      expect(names).to all(satisfy { |n| n == n.strip })
    end
  end

  describe '.fields' do
    it 'builds a Scroll / Potion / Oil stack at a valid tier' do
      expect(described_class.fields('Heal', 'scroll', 2, catalog)[:fields]).to include('item' => 'Scroll of Heal', 'tier' => 2)
      expect(described_class.fields('Heal', 'potion', 2, catalog)[:fields]).to include('item' => 'Potion of Heal')
      expect(described_class.fields('Heal', 'oil', 2, catalog)[:fields]).to include('item' => 'Oil of Heal')
    end

    it 'rejects a potion/oil for a scroll-only spell' do
      expect(described_class.fields('Vicious Mockery', 'potion', 0, catalog)[:error]).not_to be_nil
      expect(described_class.fields('Vicious Mockery', 'oil', 0, catalog)[:error]).not_to be_nil
    end

    it 'rejects a tier the spell does not offer and an unknown form' do
      expect(described_class.fields('Heal', 'scroll', 9, catalog)[:error]).to eq('invalid tier')
      expect(described_class.fields('Heal', 'wand', 0, catalog)[:error]).to eq('unknown form')
    end
  end

  describe '.line_price' do
    it 'matches the builder prices (so the charge equals the shown price)' do
      expect(described_class.line_price('Scroll of Heal', 1, catalog)).to eq(25.0)
      expect(described_class.line_price('Potion of Heal', 1, catalog)).to eq(50.0)
      expect(described_class.line_price('Oil of Heal', 1, catalog)).to eq(50.0)
      expect(described_class.line_price('Scroll of Heal', 0, catalog)).to eq(12.5)
    end
  end

  describe '.spell_form_item?' do
    it 'recognizes generated Scroll/Potion/Oil consumables' do
      expect(described_class.spell_form_item?('Scroll of Heal', catalog)).to be_truthy
      expect(described_class.spell_form_item?('Potion of Heal', catalog)).to be_truthy
      expect(described_class.spell_form_item?('Oil of Heal', catalog)).to be_truthy
    end

    it 'rejects ordinary items and wands' do
      expect(described_class.spell_form_item?('Leather armor', catalog)).to be_falsey
      expect(described_class.spell_form_item?('Wand of Heal', catalog)).to be_falsey
    end
  end
end
