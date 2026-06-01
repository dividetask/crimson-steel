require 'equipment'

RSpec.describe Equipment::DisplayName do
  let(:catalog) { Equipment::Catalog.load }

  def name(catalog, **fields)
    described_class.call(Equipment::Stack.normalize(fields), catalog)
  end

  it 'omits the prefix at Tier 0' do
    expect(name(catalog, item_type: 'Long sword', tier: 0)).to eq('Long sword')
  end

  it 'renders a tier prefix from the format string at Tier >= 1' do
    expect(name(catalog, item_type: 'Long sword', tier: 2)).to eq('+2 Long sword')
  end

  it 'hides the Tier prefix for a Consumable Category' do
    expect(name(catalog, item_type: "Alchemist's fire", tier: 2)).to eq("Alchemist's fire")
  end

  it 'sits a Property prefix between the Tier prefix and the Item Type' do
    n = name(catalog, item_type: 'Long sword', tier: 1,
                      properties: [{ name: 'Elemental', subtype: 'Fire' }])
    expect(n).to eq('+1 Flaming Long sword')
  end

  it 'applies Properties in order' do
    keen = { 'Keen' => { 'min_tier' => 1, 'cost' => 500, 'display' => { 'word' => 'Keen' } } }
    custom = Equipment::Catalog.new(catalog.data.merge('Weapon Properties' => catalog.data['Weapon Properties'].merge(keen)))
    n = name(custom, item_type: 'Long sword', tier: 1,
                     properties: [{ name: 'Elemental', subtype: 'Fire' }, { name: 'Keen' }])
    expect(n).to eq('+1 Flaming Keen Long sword')
  end

  it 'places a suffix-position Property after the Item Type' do
    demon = { 'Of Demonslaying' => { 'min_tier' => 1, 'cost' => 0,
                                     'display' => { 'word' => 'of Demonslaying', 'position' => 'suffix' } } }
    custom = Equipment::Catalog.new(catalog.data.merge('Weapon Properties' => catalog.data['Weapon Properties'].merge(demon)))
    n = name(custom, item_type: 'Long sword', tier: 1, properties: [{ name: 'Of Demonslaying' }])
    expect(n).to eq('+1 Long sword of Demonslaying')
  end

  it 'lets a Name Override replace the whole Generated Display Name' do
    n = name(catalog, item_type: 'Lute', tier: 1, name: 'Lute of the Wandering Bard')
    expect(n).to eq('Lute of the Wandering Bard')
  end

  context 'Guidance Items' do
    it 'uses the Guidance Bonus (not the Tier) for the +N prefix' do
      # A +2 Belt of Strength is Tier 1 per the catalog array, but the
      # player-facing prefix is the Bonus.
      expect(name(catalog, item_type: 'Belt of Strength', tier: 1, guidance_bonus: 2))
        .to eq('+2 Belt of Strength')
    end

    it 'shows the Bonus prefix even when it differs from the Tier' do
      # +6 Belt of Strength is Tier 3; the name still reads +6.
      expect(name(catalog, item_type: 'Belt of Strength', tier: 3, guidance_bonus: 6))
        .to eq('+6 Belt of Strength')
    end

    it 'matches Bonus and Tier for a one-to-one Guidance Item' do
      expect(name(catalog, item_type: 'Cloak of Resistance', tier: 5, guidance_bonus: 5))
        .to eq('+5 Cloak of Resistance')
    end
  end
end
