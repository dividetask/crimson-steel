require_relative 'support'
require 'tmpdir'

RSpec.describe Equipment::Dataset do
  let(:example) { Equipment::Dataset::EXAMPLE_PATH }

  around do |ex|
    Dir.mktmpdir { |dir| @data_path = File.join(dir, 'equipment_data.yaml'); ex.run }
  end

  def load
    described_class.load(data_path: @data_path, example_path: example)
  end

  it 'loads Party, Character, and Ground Pile Owners from the example file' do
    ds = load
    expect(ds.exists?('party')).to be true
    expect(ds.exists?('character:1')).to be true
    expect(ds.exists?('ground:Goblin cave — entrance')).to be true
    expect(ds.inventory('character:1')).to all(be_a(Equipment::Stack))
  end

  it 'persists a mutation and reloads it from the data path' do
    ds = load
    # Read the example's starting Party Gold so the assertion isn't coupled to
    # the exact campaign value (which the DM may tune).
    base_gold = ds.inventory('party').find { |s| s.item_type == 'Gold' }.quantity
    inst = Equipment::Instance.new(
      catalog: Equipment::Catalog.load,
      store: Equipment::Dataset::StoreAdapter.new(ds),
      creature_accessor: Equipment::Dataset::CreatureAdapter.new(ds)
    )
    inst.add_item('party', item: 'Gold', quantity: 100)
    inst.add_item('creature:1', item: 'Potion of Heal', tier: 0, quantity: 1)

    expect(File.exist?(@data_path)).to be true
    reloaded = load
    party_gold = reloaded.inventory('party').find { |s| s.item_type == 'Gold' }
    expect(party_gold.quantity).to eq(base_gold + 100)
    expect(reloaded.inventory('character:1').count { |s| s.item_type == 'Potion of Heal' }).to be >= 1
  end

  it 'round-trips Ground Piles by location' do
    ds = load
    Equipment::Dataset::StoreAdapter.new(ds).set_inventory(
      'ground:tavern', [Equipment::Stack.normalize(item: 'Dagger', quantity: 2)], nil
    )
    reloaded = load
    expect(reloaded.inventory('ground:tavern').map { |s| [s.item_type, s.quantity] }).to eq([['Dagger', 2]])
  end
end

RSpec.describe 'Equipment.instance wiring' do
  after { Equipment.reset! }

  it 'builds a persistence-backed singleton that reads the example data' do
    # No data/ overlay in a fresh checkout, so it reads the example.
    expect(Equipment.instance).to be_a(Equipment::Instance)
    expect(Equipment.instance.get_total_wealth('party')).to be_a(Numeric)
  end
end
