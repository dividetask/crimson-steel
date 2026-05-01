require_relative '../lib/magical_item_generator'
require 'tmpdir'

# rand_int returns the next scripted value, ignoring the bounds.
# Lets specs assert which branch the cumulative-probability sample
# actually picks.
class ScriptedRng
  def initialize(values)
    @values = values.dup
  end

  def rand_int(_low, _high)
    raise 'random source exhausted' if @values.empty?
    @values.shift
  end
end

RSpec.describe MagicalItemGenerator do
  let(:config) do
    {
      'Weapons' => {
        'Long sword'  => { 'category' => 'One Handed' },
        'Mace'        => { 'category' => 'One Handed' },
        'Great sword' => { 'category' => 'Two Handed' },
        'Longbow'     => { 'category' => 'Ranged' },
        'Shortbow'    => { 'category' => 'Ranged' }
      },
      'Ammunition' => {
        'Arrow' => { 'base_price' => 5 },
        'Bolt'  => { 'base_price' => 5 }
      },
      'Armor' => {
        'Leather armor' => { 'category' => 'Light' },
        'Chain shirt'   => { 'category' => 'Light' },
        'Plate mail'    => { 'category' => 'Heavy' },
        'Tower shield'  => { 'category' => 'Shield' }
      },
      'Weapon Properties' => {
        'Elemental' => {
          'min_tier'    => 1,
          'applies_to'  => %w[melee ranged ammo],
          'has_subtype' => true,
          'subtypes'    => %w[Fire Acid Electricity Cold]
        },
        'Subdual' => {
          'min_tier'    => 1,
          'applies_to'  => %w[melee ranged ammo],
          'has_subtype' => false
        },
        'Vicious' => {
          'min_tier'    => 2,
          'applies_to'  => %w[melee],
          'has_subtype' => false
        }
      },
      'Armor Properties' => {
        'Fortification' => {
          'min_tier'    => 1,
          'applies_to'  => %w[all_body],
          'has_subtype' => false
        },
        'Spell Storing 1' => {
          'min_tier'    => 1,
          'applies_to'  => %w[all_armor],
          'has_subtype' => false
        }
      }
    }
  end

  def gen(rng)
    described_class.new(config: config, random_source: rng)
  end

  describe 'category → item pool' do
    it 'melee picks from One Handed + Two Handed weapons' do
      # tier index 0, item index 0 (Long sword), property index 0 (Elemental @ pos 0)
      rng = ScriptedRng.new([0, 0, 0, 0])  # tier-pick, item-pick, weighted-property, subtype
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1],
        'properties_weighted' => { 'Elemental' => 1 }
      })
      expect(stack['item_type']).to eq('Long sword')
      expect(stack['tier']).to eq(1)
      expect(stack['properties']).to eq([{ 'name' => 'Elemental', 'subtype' => 'Fire' }])
      expect(stack['quantity']).to eq(1)
    end

    it 'ranged picks only Ranged weapons' do
      rng = ScriptedRng.new([0, 1, 0])  # tier, item index 1 = Shortbow, property
      stack = gen(rng).generate({
        'category'            => 'ranged',
        'tier'                => [1],
        'properties_weighted' => { 'Subdual' => 1 }
      })
      expect(stack['item_type']).to eq('Shortbow')
    end

    it 'ammo picks from the Ammunition catalog' do
      rng = ScriptedRng.new([0, 0, 0])
      stack = gen(rng).generate({
        'category'            => 'ammo',
        'tier'                => [1],
        'properties_weighted' => { 'Subdual' => 1 }
      })
      expect(stack['item_type']).to eq('Arrow')
    end

    it 'all_body excludes shields' do
      # all_body eligibles in iteration order: Leather armor, Chain shirt, Plate mail.
      rng = ScriptedRng.new([0, 2, 0])  # picks Plate mail at index 2
      stack = gen(rng).generate({
        'category'            => 'all_body',
        'tier'                => [1],
        'properties_weighted' => { 'Fortification' => 1 }
      })
      expect(stack['item_type']).to eq('Plate mail')
    end

    it 'all_armor includes shields' do
      # all four armors are eligible; pick index 3 = Tower shield
      rng = ScriptedRng.new([0, 3, 0])
      stack = gen(rng).generate({
        'category'            => 'all_armor',
        'tier'                => [1],
        'properties_weighted' => { 'Spell Storing 1' => 1 }
      })
      expect(stack['item_type']).to eq('Tower shield')
    end

    it 'raises on an unknown category' do
      rng = ScriptedRng.new([])
      expect {
        gen(rng).generate({
          'category'            => 'foo',
          'tier'                => [1],
          'properties_weighted' => { 'Subdual' => 1 }
        })
      }.to raise_error(ArgumentError, /Unknown magical-item category/)
    end
  end

  describe 'tier picking' do
    it 'uniform from tier list' do
      rng = ScriptedRng.new([1, 0, 0])  # picks tier index 1 → tier 2
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1, 2],
        'properties_weighted' => { 'Subdual' => 1 }
      })
      expect(stack['tier']).to eq(2)
    end

    it 'honors tier_weights when present' do
      # 3:1 weighting tier 1 vs tier 2; threshold > 0.75 of total → tier 2.
      # With weights {1: 3, 2: 1} (total = 4), threshold = 8000/10000 * 4 = 3.2 → tier 2.
      rng = ScriptedRng.new([8000, 0, 0])
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1, 2],
        'tier_weights'        => { 1 => 3, 2 => 1 },
        'properties_weighted' => { 'Subdual' => 1 }
      })
      expect(stack['tier']).to eq(2)
    end

    it 'raises when tier_weights covers nothing in the tier list' do
      rng = ScriptedRng.new([])
      expect {
        gen(rng).generate({
          'category'            => 'melee',
          'tier'                => [1],
          'tier_weights'        => { 2 => 1 },
          'properties_weighted' => { 'Subdual' => 1 }
        })
      }.to raise_error(ArgumentError, /tier_weights does not cover/)
    end

    it 'raises on an empty tier list' do
      rng = ScriptedRng.new([])
      expect {
        gen(rng).generate({
          'category'            => 'melee',
          'tier'                => [],
          'properties_weighted' => { 'Subdual' => 1 }
        })
      }.to raise_error(ArgumentError, /missing tier list/)
    end
  end

  describe 'item picking' do
    it 'uniform when items_weighted not provided' do
      rng = ScriptedRng.new([0, 1, 0])  # melee eligibles: Long sword, Mace, Great sword → index 1 = Mace
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1],
        'properties_weighted' => { 'Subdual' => 1 }
      })
      expect(stack['item_type']).to eq('Mace')
    end

    it 'honors items_weighted, restricted to the eligible set' do
      # weights {Mace: 1, Great sword: 3}; total = 4. threshold = 0 → first key (Mace).
      rng = ScriptedRng.new([0, 0, 0])
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1],
        'items_weighted'      => { 'Mace' => 1, 'Great sword' => 3 },
        'properties_weighted' => { 'Subdual' => 1 }
      })
      expect(%w[Mace Great\ sword]).to include(stack['item_type'])
    end

    it 'raises when items_weighted covers nothing eligible' do
      rng = ScriptedRng.new([0])  # tier-pick consumed before item-pick raises
      expect {
        gen(rng).generate({
          'category'            => 'melee',
          'tier'                => [1],
          'items_weighted'      => { 'Longbow' => 1 },  # ranged, not melee
          'properties_weighted' => { 'Subdual' => 1 }
        })
      }.to raise_error(ArgumentError, /items_weighted does not cover/)
    end
  end

  describe 'property picking' do
    it 'filters out properties whose min_tier is above picked tier' do
      # tier 1; Vicious requires tier 2 so it's excluded. Weights: {Subdual: 1}.
      rng = ScriptedRng.new([0, 0, 0])
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1],
        'properties_weighted' => { 'Subdual' => 1, 'Vicious' => 1 }
      })
      expect(stack['properties']).to eq([{ 'name' => 'Subdual' }])
    end

    it 'filters out properties whose applies_to does not include the category' do
      # Vicious only applies to melee; ranged constraint should drop it.
      # Tier 2 picked; only Elemental remains.
      rng = ScriptedRng.new([0, 0, 0, 0])
      stack = gen(rng).generate({
        'category'            => 'ranged',
        'tier'                => [2],
        'properties_weighted' => { 'Elemental' => 1, 'Vicious' => 1 }
      })
      expect(stack['properties'].first['name']).to eq('Elemental')
    end

    it 'reserved `none` weight produces a propertyless stack' do
      # weights {none: 1, Elemental: 0}; only `none` is eligible (well, both,
      # but Elemental's weight is 0 so it can never win).
      rng = ScriptedRng.new([0, 0, 0])  # tier, item, property -> first key = none
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1],
        'properties_weighted' => { 'none' => 1 }
      })
      expect(stack['properties']).to eq([])
    end

    it 'subtype is sampled uniformly from declared subtypes' do
      # Pick Cold (index 3). Subtype-pick is the 4th rand_int call.
      rng = ScriptedRng.new([0, 0, 0, 3])
      stack = gen(rng).generate({
        'category'            => 'melee',
        'tier'                => [1],
        'properties_weighted' => { 'Elemental' => 1 }
      })
      expect(stack['properties']).to eq([{ 'name' => 'Elemental', 'subtype' => 'Cold' }])
    end

    it 'raises when no eligible properties remain' do
      rng = ScriptedRng.new([0, 0])  # tier + item picks consumed
      expect {
        gen(rng).generate({
          'category'            => 'melee',
          'tier'                => [1],
          'properties_weighted' => { 'Vicious' => 1 }  # min_tier 2
        })
      }.to raise_error(ArgumentError, /No properties eligible/)
    end
  end

  describe 'constraint validation' do
    it 'requires category' do
      rng = ScriptedRng.new([])
      expect { gen(rng).generate({ 'tier' => [1], 'properties_weighted' => { 'Subdual' => 1 } }) }
        .to raise_error(ArgumentError, /missing category/)
    end

    it 'requires properties_weighted' do
      rng = ScriptedRng.new([])
      expect { gen(rng).generate({ 'category' => 'melee', 'tier' => [1] }) }
        .to raise_error(ArgumentError, /missing properties_weighted/)
    end
  end

  describe 'integration with LootTables' do
    it 'wires in via `to_proc` so inline magical rows resolve through the generator' do
      require_relative '../lib/loot_tables'
      yaml = <<~YAML
        loot_tables:
          chest:
            rolls:
              - item:
                  magical:
                    category: melee
                    tier: [1]
                    properties_weighted:
                      Subdual: 1
      YAML
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'loot_tables.yaml')
        File.write(path, yaml)
        # Two RNG streams interleave: LootTables for its row picks
        # (none in this guaranteed-row table) and the generator for
        # tier/item/property/subtype. The Guaranteed row needs no rolls.
        rng = ScriptedRng.new([0, 0, 0])  # tier index 0, item index 0, property pick
        magical = described_class.new(config: config, random_source: rng)
        lt = LootTables.new(config_path: path, random_source: rng, magical_item_generator: magical.to_proc)
        stacks = lt.roll('chest')
        expect(stacks.length).to eq(1)
        expect(stacks.first['item_type']).to eq('Long sword')
        expect(stacks.first['properties']).to eq([{ 'name' => 'Subdual' }])
      end
    end
  end
end
