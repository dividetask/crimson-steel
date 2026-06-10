require_relative 'support'

# The Slaver's spawn-time loadout is the live `slaver_loadout` Loot Table.
# Its melee branch keys off the `race` roll variable the spawn flow seeds.
RSpec.describe 'slaver_loadout Loot Table' do
  let(:catalog) { Equipment::Catalog.load }

  def instance(rng = SequenceRng.new)
    Equipment::Instance.new(catalog: catalog, loot: Equipment::LootTables.load, rng: rng)
  end

  MELEE = ['Falchion', 'Great axe', 'Long sword', 'Dagger', 'Short sword', 'Spear'].freeze
  TWO_HANDED = ['Great axe', 'Spear'].freeze

  %w[orc human elf dwarf].each do |race|
    it "rolls cleanly for a #{race} slaver: one melee weapon + a whip, valid items" do
      20.times do |seed|
        out = instance.roll_loot_table('slaver_loadout', seed: seed, vars: { 'race' => race })
        expect(out).not_to equal(Equipment::ERROR)
        out.each do |s|
          expect(catalog.item_type(s.item_type)).to be_truthy, "unknown item #{s.item_type.inspect}"
        end
        expect(out.count { |s| s.equipped && MELEE.include?(s.item_type) }).to eq(1)
        expect(out.any? { |s| s.item_type == 'Whip' }).to be(true)
      end
    end
  end

  it 'orc slavers pick the falchion far more often than non-orc slavers' do
    orc = 0
    other = 0
    300.times do |seed|
      orc   += 1 if instance.roll_loot_table('slaver_loadout', seed: seed, vars: { 'race' => 'orc' }).any?  { |s| s.item_type == 'Falchion' }
      other += 1 if instance.roll_loot_table('slaver_loadout', seed: seed, vars: { 'race' => 'human' }).any? { |s| s.item_type == 'Falchion' }
    end
    expect(orc).to be > other
  end

  it 'never gives a shield alongside a two-handed weapon' do
    %w[orc human].each do |race|
      50.times do |seed|
        out = instance.roll_loot_table('slaver_loadout', seed: seed, vars: { 'race' => race })
        two_handed = out.any? { |s| TWO_HANDED.include?(s.item_type) }
        shield = out.any? { |s| s.item_type == 'Light metal shield' }
        expect(two_handed && shield).to be(false)
      end
    end
  end

  it 'new catalog items resolve' do
    %w[Bola Net Manacles Whip].each { |i| expect(catalog.item_type(i)).to be_truthy }
  end
end
