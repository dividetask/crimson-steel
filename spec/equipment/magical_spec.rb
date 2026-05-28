require_relative 'support'

RSpec.describe 'Generate Magical Item' do
  let(:catalog) { Equipment::Catalog.load }

  def inst(rng)
    Equipment::Instance.new(catalog: catalog, rng: rng)
  end

  it 'produces a propertyless tiered item for the none pool' do
    item = inst(SequenceRng.new).generate_magical_item(
      'category' => 'melee', 'tier' => [1], 'properties_weighted' => { 'none' => 1 }
    )
    expect(item.tier).to eq(1)
    expect(item.properties).to be_empty
    expect(catalog.category_of(item.item_type)).to eq('Weapon')
  end

  it 'applies the min_tier / applies_to Property filter' do
    # ammo constraint filters out Vicious (melee-only); only Elemental
    # remains, so the generated Stack carries Elemental + a Subtype.
    item = inst(SequenceRng.new([0.0, 0.0, 0.0, 0.0])).generate_magical_item(
      'category' => 'ammo', 'tier' => [1],
      'properties_weighted' => { 'Elemental' => 1, 'Vicious' => 1 }
    )
    expect(item.properties.map { |p| p[:name] }).to eq(['Elemental'])
    expect(%w[Fire Acid Electricity Cold]).to include(item.properties.first[:subtype])
  end

  it 'picks a Subtype uniformly across the quartiles' do
    subtypes = [0.1, 0.35, 0.6, 0.85].map do |q|
      # floats: tier, item, property(=Elemental), subtype quartile
      item = inst(SequenceRng.new([0.0, 0.0, 0.0, q])).generate_magical_item(
        'category' => 'ammo', 'tier' => [1], 'properties_weighted' => { 'Elemental' => 1 }
      )
      item.properties.first[:subtype]
    end
    expect(subtypes).to eq(%w[Fire Acid Electricity Cold])
  end

  it 'honors items_weighted probabilities' do
    constraint = { 'category' => 'melee', 'tier' => [1],
                   'properties_weighted' => { 'none' => 1 },
                   'items_weighted' => { 'Long sword' => 3, 'Mace' => 1 } }
    # Weighted entries follow catalog order (Mace precedes Long sword),
    # so Mace occupies u in [0, 0.25) and Long sword [0.25, 1).
    # floats: tier, item(weighted), property
    long = inst(SequenceRng.new([0.0, 0.5, 0.0])).generate_magical_item(constraint)
    mace = inst(SequenceRng.new([0.0, 0.1, 0.0])).generate_magical_item(constraint)
    expect(long.item_type).to eq('Long sword')
    expect(mace.item_type).to eq('Mace')
  end

  it 'weights the Tier draw' do
    constraint = { 'tier' => [1, 2], 'tier_weights' => { 1 => 3, 2 => 1 },
                   'category' => 'melee', 'properties_weighted' => { 'none' => 1 } }
    t1 = inst(SequenceRng.new([0.5, 0.0, 0.0])).generate_magical_item(constraint)
    t2 = inst(SequenceRng.new([0.9, 0.0, 0.0])).generate_magical_item(constraint)
    expect(t1.tier).to eq(1)
    expect(t2.tier).to eq(2)
  end

  it 'falls back to none when no Property passes the filter' do
    item = inst(SequenceRng.new).generate_magical_item(
      'category' => 'melee', 'tier' => [1], 'properties_weighted' => { 'Vicious' => 1 }
    )
    expect(item.properties).to be_empty
  end
end
