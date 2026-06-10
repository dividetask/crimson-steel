require_relative 'support'

# The Common Goblin's spawn-time loadout is the live `common_goblin_loadout`
# Loot Table in loot_tables.yaml. These specs use the real catalog + loot
# tables so a typo in the YAML (an item that doesn't resolve, a malformed
# row) is caught here.
RSpec.describe 'common_goblin_loadout Loot Table' do
  let(:catalog) { Equipment::Catalog.load }

  def instance(rng)
    Equipment::Instance.new(catalog: catalog, loot: Equipment::LootTables.load, rng: rng)
  end

  it 'is defined and rolls without error across many seeds' do
    100.times do |seed|
      out = instance(SequenceRng.new).roll_loot_table('common_goblin_loadout', seed: seed)
      expect(out).not_to equal(Equipment::ERROR)
      # Every produced Stack resolves to a real Item Type (Get Item Details
      # raises / returns ERROR for an unknown item).
      out.each do |stack|
        expect(catalog.item_type(stack.item_type)).to be_truthy,
               "unknown item #{stack.item_type.inspect}"
      end
    end
  end

  it 'always equips exactly one melee weapon (dagger / short sword / spear)' do
    melee = %w[Dagger Short\ sword Spear]
    20.times do |seed|
      out = instance(SequenceRng.new).roll_loot_table('common_goblin_loadout', seed: seed)
      equipped_melee = out.select { |s| s.equipped && melee.include?(s.item_type) }
      expect(equipped_melee.size).to eq(1)
    end
  end

  it 'never gives a shield alongside a spear (two-handed)' do
    50.times do |seed|
      out = instance(SequenceRng.new).roll_loot_table('common_goblin_loadout', seed: seed)
      has_spear = out.any? { |s| s.item_type == 'Spear' }
      has_shield = out.any? { |s| s.item_type == 'Light wooden shield' }
      expect(has_spear && has_shield).to be(false)
    end
  end

  it 'Short bow and Humanoid skull resolve in the catalog' do
    expect(catalog.item_type('Short bow')).to be_truthy
    expect(catalog.item_type('Humanoid skull')).to be_truthy
  end
end
