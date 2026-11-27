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

    it 'resolves the Item Type catalog description for a generic item' do
      d = described_class.item_details(stack(item_type: 'Cloak of Resistance', tier: 1), catalog)
      expect(d[:description]).to eq("Grants a Guidance Bonus to the wearer's saving throws.")
    end

    it 'lets a Stack description override the catalog description' do
      d = described_class.item_details(
        stack(item_type: 'Lute', tier: 1, name: 'Lute of the Wandering Bard',
              description: 'Once per scene, grant Bardic Inspiration without spending the action.'),
        catalog
      )
      expect(d[:description]).to eq('Once per scene, grant Bardic Inspiration without spending the action.')
    end

    it 'is nil when neither the Stack nor the Item Type carries a description' do
      expect(described_class.item_details(stack(item_type: 'Lute'), catalog)[:description]).to be_nil
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

  describe 'Get Weapon Details — Enhancement and Enchantment' do
    it "reports the weapon's +X from its Tier, and 0 for a natural weapon" do
      expect(described_class.weapon_details(stack(item_type: 'Long sword', tier: 2), catalog)[:enhancement]).to eq(2)
      expect(described_class.weapon_details(Equipment::Stack.from_catalog('Bite (Jaws)', catalog), catalog)[:enhancement]).to eq(0)
    end

    it 'resolves a Flaming enchantment, expanding from_subtype' do
      d = described_class.weapon_details(
        stack(item_type: 'Long sword', tier: 1, properties: [{ name: 'Elemental', subtype: 'Fire' }]), catalog)
      expect(d[:enchantment]).to eq(property: 'Elemental', subtype: 'Fire', label: 'Flaming',
                                    damage_type: 'fire', multiplier: 1)
    end

    it 'resolves Vicious: demonic, forced Major, 1 minor to the wielder per 1' do
      d = described_class.weapon_details(stack(item_type: 'Great sword', tier: 2, properties: [{ name: 'Vicious' }]), catalog)
      e = d[:enchantment]
      expect(e[:damage_type]).to eq('demonic')
      expect(e[:severity]).to eq('major')
      expect(e[:self_damage_per_one]).to eq(severity: 'minor', amount: 1)
    end

    it 'resolves Merciful as 2 Shock and keeps its threshold_delta' do
      d = described_class.weapon_details(stack(item_type: 'Mace', tier: 1, properties: [{ name: 'Subdual' }]), catalog)
      expect(d[:enchantment]).to include(effect: 'shock', amount: 2)
      expect(d[:threshold]).to eq(8) # Bludgeoning Threshold 3 + Subdual threshold_delta 5
    end

    it "resolves Glorious as double damage of the weapon's own type, only against higher Tiers" do
      d = described_class.weapon_details(stack(item_type: 'Long sword', tier: 1, properties: [{ name: 'Glory' }]), catalog)
      expect(d[:enchantment]).to include(damage_type: 'slashing', multiplier: 2, only_vs_higher_tier: true)
    end

    it 'has no enchantment on a mundane weapon' do
      expect(described_class.weapon_details(stack(item_type: 'Long sword', tier: 0), catalog)[:enchantment]).to be_nil
    end

    it 'keeps only the newest enchantment when a weapon carries two' do
      d = described_class.weapon_details(
        stack(item_type: 'Long sword', tier: 2,
              properties: [{ name: 'Elemental', subtype: 'Fire' }, { name: 'Radiant' }]), catalog)
      expect(d[:enchantment][:damage_type]).to eq('radiant')
    end

    it "hydrates a natural weapon's intrinsic Corrosive property into an acid enchantment" do
      bite = Equipment::Stack.from_catalog('Bite (Acid)', catalog)
      d = described_class.weapon_details(bite, catalog)
      expect(d[:display_name]).to eq('Corrosive Bite (Acid)')
      expect(d[:enchantment]).to include(label: 'Corrosive', damage_type: 'acid')
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
