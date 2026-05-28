require 'equipment'

RSpec.describe Equipment::Details do
  let(:catalog) { Equipment::Catalog.load }

  def stack(**fields) ; Equipment::Stack.normalize(fields) ; end

  describe 'Get Item Details' do
    it 'returns the generic fields' do
      d = described_class.item_details(
        stack(item_type: 'Long sword', tier: 1,
              properties: [{ name: 'Elemental', subtype: 'Fire', cost: 500 }], equipped: true),
        catalog
      )
      expect(d[:category]).to eq('Weapon')
      expect(d[:tier]).to eq(1)
      expect(d[:equipped]).to be true
      expect(d[:display_name]).to eq('+1 Flaming Long sword')
      expect(d[:unit_price]).to eq(785)
      expect(d[:durability_damage]).to eq(0)
      expect(d[:slot]).to be_nil
    end
  end

  describe 'Get Weapon Details' do
    it 'adds weapon-specific fields' do
      d = described_class.weapon_details(
        stack(item_type: 'Long sword', tier: 1,
              properties: [{ name: 'Elemental', subtype: 'Fire', cost: 500 }]),
        catalog
      )
      expect(d[:damage_formula]).to eq('str / 4 - 2')
      expect(d[:damage_types]).to eq(%w[Slashing Piercing])
      expect(d[:bleed]).to eq(7)
      expect(d[:threshold]).to eq(4)
      expect(d[:tags]).to eq([])
      expect(d[:ammo_type]).to be_nil
    end

    it 'lets a Tag damage_formula override the Category default' do
      d = described_class.weapon_details(stack(item_type: 'Great sword', tier: 0), catalog)
      expect(d[:damage_formula]).to eq('str / 2 + 2')
    end

    it 'lets a per-Weapon base_damage override Tag and Category' do
      d = described_class.weapon_details(stack(item_type: 'Whip', tier: 0), catalog)
      expect(d[:damage_formula]).to eq(0)
    end

    it 'propagates a per-Weapon threshold: null' do
      d = described_class.weapon_details(stack(item_type: 'Whip', tier: 0), catalog)
      expect(d[:threshold]).to be_nil
    end
  end

  describe 'Get Armor Details' do
    it 'computes Effective Hardness and Resilience' do
      d = described_class.armor_details(stack(item_type: 'Chain mail', tier: 2), catalog)
      expect(d[:material]).to eq('Metal')
      expect(d[:base_hardness]).to eq(10)
      expect(d[:effective_hardness]).to eq(14)
      expect(d[:damage_reduction]).to eq(3)
      expect(d[:resilience_increment]).to eq(2)
      expect(d[:resilience]).to eq(4)
      expect(d[:hit_points_formula]).to eq('30 * thickness')
      expect(d[:thickness]).to eq(2)
      expect(d[:is_metal_armor]).to be true
    end

    it 'reads the per-Item Metal flag and null-guards Shields' do
      tower = described_class.armor_details(stack(item_type: 'Tower shield', tier: 3), catalog)
      expect(tower[:damage_reduction]).to be_nil
      expect(tower[:resilience_increment]).to be_nil
      expect(tower[:resilience]).to eq(0)
      expect(tower[:is_metal_armor]).to be true

      wooden = described_class.armor_details(stack(item_type: 'Light wooden shield', tier: 0), catalog)
      expect(wooden[:is_metal_armor]).to be false
    end

    it 'defaults metal to false when omitted' do
      expect(described_class.armor_details(stack(item_type: 'Leather armor', tier: 0), catalog)[:is_metal_armor]).to be false
      expect(described_class.armor_details(stack(item_type: 'Hide armor', tier: 0), catalog)[:is_metal_armor]).to be false
    end

    it 'has zero Resilience for non-magical armor' do
      expect(described_class.armor_details(stack(item_type: 'Chain mail', tier: 0), catalog)[:resilience]).to eq(0)
    end
  end
end
