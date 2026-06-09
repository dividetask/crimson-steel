require_relative 'support'

# The Common Orc's spawn-time loadout is the live `common_orc_loadout`
# Loot Table. Uses the real catalog + loot tables so a typo (unknown
# item, malformed row) is caught here.
RSpec.describe 'common_orc_loadout Loot Table' do
  let(:catalog) { Equipment::Catalog.load }

  def instance(rng)
    Equipment::Instance.new(catalog: catalog, loot: Equipment::LootTables.load, rng: rng)
  end

  MELEE = ['Falchion', 'Great axe', 'Long sword', 'Dagger', 'Short sword', 'Spear'].freeze
  TWO_HANDED = ['Great axe', 'Spear'].freeze

  it 'rolls without error and every Stack resolves to a real Item Type' do
    100.times do |seed|
      out = instance(SequenceRng.new).roll_loot_table('common_orc_loadout', seed: seed)
      expect(out).not_to equal(Equipment::ERROR)
      out.each do |stack|
        expect(catalog.item_type(stack.item_type)).to be_truthy,
               "unknown item #{stack.item_type.inspect}"
      end
    end
  end

  it 'always equips exactly one melee weapon' do
    20.times do |seed|
      out = instance(SequenceRng.new).roll_loot_table('common_orc_loadout', seed: seed)
      equipped_melee = out.select { |s| s.equipped && MELEE.include?(s.item_type) }
      expect(equipped_melee.size).to eq(1)
    end
  end

  it 'never gives a shield alongside a two-handed weapon' do
    50.times do |seed|
      out = instance(SequenceRng.new).roll_loot_table('common_orc_loadout', seed: seed)
      two_handed = out.any? { |s| TWO_HANDED.include?(s.item_type) }
      shield = out.any? { |s| s.item_type == 'Light metal shield' }
      expect(two_handed && shield).to be(false)
    end
  end

  it 'new catalog items all resolve' do
    %w[Falchion].each { |w| expect(catalog.item_type(w)).to be_truthy }
    expect(catalog.item_type('Great axe')).to be_truthy
    expect(catalog.item_type('Breastplate')).to be_truthy
    expect(catalog.item_type('Light metal shield')).to be_truthy
    expect(catalog.item_type('Necklace of animal fangs')).to be_truthy
  end
end
