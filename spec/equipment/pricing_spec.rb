require 'equipment'

RSpec.describe Equipment::Pricing do
  let(:catalog) { Equipment::Catalog.load }

  def price(catalog, **fields)
    described_class.unit_price(Equipment::Stack.normalize(fields), catalog)
  end

  it 'prices a Tier 0 Weapon as its Base Price' do
    expect(price(catalog, item_type: 'Long sword', tier: 0)).to eq(35)
  end

  it 'adds the Default Tier Surcharge for a Tier 1 Weapon' do
    expect(price(catalog, item_type: 'Long sword', tier: 1)).to eq(285)
  end

  it 'stacks Property cost into Unit Price' do
    p = price(catalog, item_type: 'Long sword', tier: 1,
                       properties: [{ name: 'Elemental', subtype: 'Fire', cost: 500 }])
    expect(p).to eq(785)
  end

  it 'lets a Per-Item Tier Surcharge override the Default' do
    data = catalog.data.dup
    data['Weapons'] = data['Weapons'].merge(
      'Long sword' => data['Weapons']['Long sword'].merge('tier_surcharge' => { 1 => 100 })
    )
    custom = Equipment::Catalog.new(data)
    expect(price(custom, item_type: 'Long sword', tier: 1)).to eq(135)
  end

  it 'prices Guidance Items from Tier + Bonus Surcharge, ignoring Base Price' do
    expect(price(catalog, item_type: 'Belt of Strength', tier: 1, guidance_bonus: 2)).to eq(1250)
  end

  it 'prices a Tier 0 Guidance Item at the Bonus Surcharge alone' do
    expect(price(catalog, item_type: 'Belt of Strength', tier: 0, guidance_bonus: 2)).to eq(1000)
  end

  it 'divides Ammunition magical cost by the Magical Ammunition Divisor' do
    p = price(catalog, item_type: 'Arrow', tier: 1,
                       properties: [{ name: 'Elemental', subtype: 'Fire', cost: 500 }])
    expect(p).to be_within(1e-9).of(7.75)
  end

  it 'divides non-ammo Consumable magical cost by the Consumable Surcharge Divisor and doubles for Innately Usable' do
    # Alchemist's fire is innately_usable. Tier 1: (25 + 250/10) * 2 = 100.
    expect(price(catalog, item_type: "Alchemist's fire", tier: 1)).to eq(100)
    # Tier 0: 25 * 2 = 50.
    expect(price(catalog, item_type: "Alchemist's fire", tier: 0)).to eq(50)
  end

  it 'prices Currency at value_in_gold' do
    expect(price(catalog, item_type: 'Gold', quantity: 1)).to eq(1.0)
    expect(price(catalog, item_type: 'Silver', quantity: 1)).to eq(0.1)
    expect(price(catalog, item_type: 'Copper', quantity: 1)).to eq(0.01)
  end

  it "prices a Gem at the Stack's own value_in_gold" do
    expect(price(catalog, item_type: 'Gem', value_in_gold: 250, tier: 0)).to eq(250)
  end
end
