require 'equipment'

RSpec.describe Equipment::Stack do
  def stack(**fields)
    described_class.normalize(fields)
  end

  describe 'Stack Identity' do
    it 'two Stacks with identical identity match' do
      a = stack(item_type: 'Long sword', tier: 0, properties: [])
      b = stack(item_type: 'Long sword', tier: 0, properties: [])
      expect(a.same_identity?(b)).to be true
    end

    it 'differing tier does not match' do
      a = stack(item_type: 'Long sword', tier: 0)
      b = stack(item_type: 'Long sword', tier: 1)
      expect(a.same_identity?(b)).to be false
    end

    it 'Property order is part of identity' do
      a = stack(item_type: 'Long sword', tier: 1,
                properties: [{ name: 'Elemental', subtype: 'Fire' }, { name: 'Keen' }])
      b = stack(item_type: 'Long sword', tier: 1,
                properties: [{ name: 'Keen' }, { name: 'Elemental', subtype: 'Fire' }])
      expect(a.same_identity?(b)).to be false
    end

    it 'equipped and unequipped copies do not match' do
      a = stack(item_type: 'Long sword', tier: 1, equipped: false)
      b = stack(item_type: 'Long sword', tier: 1, equipped: true)
      expect(a.same_identity?(b)).to be false
    end

    it 'Inscribed Spells are order-sensitive identity' do
      a = stack(item_type: 'Ritual book', inscribed_spells: %w[mending light])
      b = stack(item_type: 'Ritual book', inscribed_spells: %w[light mending])
      c = stack(item_type: 'Ritual book', inscribed_spells: %w[mending light])
      expect(a.same_identity?(b)).to be false
      expect(a.same_identity?(c)).to be true
    end

    it 'Gem identity requires value_in_gold and gem_name to match' do
      ruby     = stack(item_type: 'Gem', value_in_gold: 50, gem_name: 'ruby')
      sapphire = stack(item_type: 'Gem', value_in_gold: 50, gem_name: 'sapphire')
      bare_a   = stack(item_type: 'Gem', value_in_gold: 50)
      bare_b   = stack(item_type: 'Gem', value_in_gold: 50)
      expect(ruby.same_identity?(sapphire)).to be false
      expect(bare_a.same_identity?(bare_b)).to be true
    end

    it 'Guidance Bonus is an identity field' do
      a = stack(item_type: 'Belt of Strength', tier: 1, guidance_bonus: 2)
      b = stack(item_type: 'Belt of Strength', tier: 1, guidance_bonus: 4)
      expect(a.same_identity?(b)).to be false
    end
  end

  describe 'Stack Merge' do
    it 'sums Quantity on a matching identity' do
      a = stack(item_type: 'Long sword', quantity: 1)
      b = stack(item_type: 'Long sword', quantity: 1)
      a.merge!(b)
      expect(a.quantity).to eq(2)
    end

    it 'restock_target conflict keeps the earlier value and warns' do
      a = stack(item_type: 'Arrow', tier: 0, quantity: 20, restock_target: 20)
      b = stack(item_type: 'Arrow', tier: 0, quantity: 5, restock_target: 50)
      expect(a.same_identity?(b)).to be true
      expect { a.merge!(b) }.to output(/restock_target conflict/).to_stderr
      expect(a.quantity).to eq(25)
      expect(a.restock_target).to eq(20)
    end

    it 'restock_target is not part of identity' do
      a = stack(item_type: 'Arrow', restock_target: 20)
      b = stack(item_type: 'Arrow', restock_target: 50)
      expect(a.same_identity?(b)).to be true
    end
  end

  describe 'normalization shorthand' do
    it 'accepts the YAML data-file shape (item:/name:)' do
      s = described_class.normalize('item' => 'Lute', 'tier' => 1, 'name' => 'Lute of the Wandering Bard')
      expect(s.item_type).to eq('Lute')
      expect(s.tier).to eq(1)
      expect(s.name_override).to eq('Lute of the Wandering Bard')
    end

    it 'routes a Gem name: to gem_name' do
      s = described_class.normalize('item' => 'Gem', 'name' => 'Uncut Sapphire', 'value_in_gold' => 200)
      expect(s.gem_name).to eq('Uncut Sapphire')
      expect(s.name_override).to be_nil
    end
  end
end
