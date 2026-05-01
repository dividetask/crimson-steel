require_relative '../lib/loot_tables'
require 'tempfile'
require 'tmpdir'

# Drives the random source deterministically. rand_int returns the
# next value in @values; useful for asserting which weighted-choice
# branch fires.
class ScriptedRng
  def initialize(values)
    @values = values.dup
  end

  def rand_int(_low, _high)
    raise 'random source exhausted' if @values.empty?
    @values.shift
  end
end

RSpec.describe LootTables do
  def with_table_yaml(yaml_text)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'loot_tables.yaml')
      File.write(path, yaml_text)
      yield path
    end
  end

  describe 'Guaranteed rows' do
    it 'always emits the listed item' do
      with_table_yaml(<<~YAML) do |path|
        loot_tables:
          guard:
            rolls:
              - item: { item: Long sword }
              - item: { item: Gold, quantity: 5 }
      YAML
        rng = ScriptedRng.new([])  # no rolls needed
        lt = LootTables.new(config_path: path, random_source: rng)
        stacks = lt.roll('guard')
        expect(stacks.length).to eq(2)
        expect(stacks[0]).to include('item_type' => 'Long sword', 'quantity' => 1)
        expect(stacks[1]).to include('item_type' => 'Gold', 'quantity' => 5)
      end
    end

    it 'expands `items:` list rows into multiple stacks' do
      with_table_yaml(<<~YAML) do |path|
        loot_tables:
          archer:
            rolls:
              - items:
                  - { item: Shortbow }
                  - { item: Arrow, quantity: 10 }
      YAML
        lt = LootTables.new(config_path: path, random_source: ScriptedRng.new([]))
        stacks = lt.roll('archer')
        expect(stacks.length).to eq(2)
        expect(stacks.map { |s| s['item_type'] }).to eq(%w[Shortbow Arrow])
      end
    end

    it 'tags every stack as equipped when the row has equipped: true' do
      with_table_yaml(<<~YAML) do |path|
        loot_tables:
          guard:
            rolls:
              - equipped: true
                items:
                  - { item: Chain shirt }
                  - { item: Long sword }
      YAML
        lt = LootTables.new(config_path: path, random_source: ScriptedRng.new([]))
        stacks = lt.roll('guard')
        expect(stacks).to all(include('equipped' => true))
      end
    end
  end

  describe 'Independent Chance rows' do
    it 'drops when the roll lands inside the chance window' do
      with_table_yaml(<<~YAML) do |path|
        loot_tables:
          chest:
            rolls:
              - chance: 0.50
                item: { item: Healing potion }
      YAML
        # rand_int(0, 9999) / 10000 < 0.5 → drops
        lt = LootTables.new(config_path: path, random_source: ScriptedRng.new([4999]))
        expect(lt.roll('chest').length).to eq(1)
      end
    end

    it 'drops nothing when the roll lands outside' do
      with_table_yaml(<<~YAML) do |path|
        loot_tables:
          chest:
            rolls:
              - chance: 0.50
                item: { item: Healing potion }
      YAML
        lt = LootTables.new(config_path: path, random_source: ScriptedRng.new([5001]))
        expect(lt.roll('chest')).to eq([])
      end
    end
  end

  describe 'Weighted Choice rows' do
    let(:weighted_yaml) do
      <<~YAML
        loot_tables:
          guard:
            rolls:
              - options:
                  - { chance: 0.40, key: short_sword, item: { item: Short sword } }
                  - { chance: 0.30, key: spear,       item: { item: Spear } }
                  - { chance: 0.20, key: mace,        item: { item: Mace } }
                  # remainder 0.10 = nothing
      YAML
    end

    it 'picks the first option when the threshold lands in its band' do
      # threshold = 1000/10000 = 0.10 < 0.40 → first option
      lt = LootTables.new(config_path: write_yaml(weighted_yaml), random_source: ScriptedRng.new([1000]))
      stacks = lt.roll('guard')
      expect(stacks.first['item_type']).to eq('Short sword')
    end

    it 'picks a later option when earlier bands miss' do
      # threshold = 5000/10000 = 0.50 → past short_sword (0.4) and into spear (0.4 + 0.3 = 0.7)
      lt = LootTables.new(config_path: write_yaml(weighted_yaml), random_source: ScriptedRng.new([5000]))
      stacks = lt.roll('guard')
      expect(stacks.first['item_type']).to eq('Spear')
    end

    it 'falls into the remainder (nothing drops) when threshold exceeds total' do
      # threshold = 9500/10000 = 0.95 > 0.9 → remainder
      lt = LootTables.new(config_path: write_yaml(weighted_yaml), random_source: ScriptedRng.new([9500]))
      expect(lt.roll('guard')).to eq([])
    end

    def write_yaml(yaml_text)
      f = Tempfile.new(['loot_tables', '.yaml'])
      f.write(yaml_text)
      f.flush
      f.path
    end
  end

  describe 'Gated Weighted Choice rows' do
    let(:yaml) do
      <<~YAML
        loot_tables:
          chest:
            rolls:
              - chance: 0.30
                options:
                  - { chance: 0.50, item: { item: Wand } }
                  - { chance: 0.50, item: { item: Scroll } }
      YAML
    end

    it 'fires the gate first; on failure no weighted roll happens' do
      # First roll = 5000 (gate threshold 0.5 > chance 0.3 → gate fails)
      lt = LootTables.new(config_path: write(yaml), random_source: ScriptedRng.new([5000]))
      expect(lt.roll('chest')).to eq([])
    end

    it 'fires the weighted roll when the gate passes' do
      # First roll = 1000 (0.10 < 0.30 → gate passes)
      # Second roll = 2000 (0.20 < 0.50 → first option)
      lt = LootTables.new(config_path: write(yaml), random_source: ScriptedRng.new([1000, 2000]))
      stacks = lt.roll('chest')
      expect(stacks.first['item_type']).to eq('Wand')
    end

    def write(yaml_text)
      f = Tempfile.new(['loot_tables', '.yaml'])
      f.write(yaml_text)
      f.flush
      f.path
    end
  end

  describe 'Roll Variables' do
    let(:yaml) do
      <<~YAML
        loot_tables:
          guard:
            rolls:
              - as: hand
                options:
                  - { chance: 0.50, key: one_handed, item: { item: Short sword } }
                  - { chance: 0.50, key: two_handed, item: { item: Spear } }

              - when: { hand: one_handed }
                item: { item: Light wooden shield }
      YAML
    end

    it 'gates a row by a previously-published variable' do
      # First roll picks one_handed (0.10 < 0.50). Second row's
      # when: hand: one_handed matches → shield drops.
      lt = LootTables.new(config_path: write(yaml), random_source: ScriptedRng.new([1000]))
      stacks = lt.roll('guard')
      expect(stacks.map { |s| s['item_type'] }).to eq(['Short sword', 'Light wooden shield'])
    end

    it 'skips a gated row when the variable does not match' do
      # First roll picks two_handed (0.70 > 0.50 → second option).
      # Second row's when: hand: one_handed does not match → skipped.
      lt = LootTables.new(config_path: write(yaml), random_source: ScriptedRng.new([7000]))
      stacks = lt.roll('guard')
      expect(stacks.map { |s| s['item_type'] }).to eq(['Spear'])
    end

    it 'records null for a row that drops nothing' do
      with_var_yaml = <<~YAML
        loot_tables:
          chest:
            rolls:
              - as: tier
                chance: 0.50
                key: hit
                item: { item: Wand }
              - when: { tier: hit }
                item: { item: Bonus }
      YAML
      # Roll 9000 → chance 0.50 fails → tier = null → second row skipped.
      lt = LootTables.new(config_path: write(with_var_yaml), random_source: ScriptedRng.new([9000]))
      expect(lt.roll('chest')).to eq([])
    end

    def write(yaml_text)
      f = Tempfile.new(['loot_tables', '.yaml'])
      f.write(yaml_text)
      f.flush
      f.path
    end
  end

  describe 'Option Lists' do
    let(:yaml) do
      <<~YAML
        loot_tables:
          chest:
            rolls:
              - options: tier_one_potions

        option_lists:
          tier_one_potions:
            - { chance: 0.60, item: { item: Healing potion } }
            - { chance: 0.40, item: { item: Mana potion } }
      YAML
    end

    it 'pulls options from a named list' do
      # 1000 → 0.10 → first option (Healing potion)
      lt = LootTables.new(config_path: write(yaml), random_source: ScriptedRng.new([1000]))
      stacks = lt.roll('chest')
      expect(stacks.first['item_type']).to eq('Healing potion')
    end

    it 'recurses into another list via `from`' do
      with_recursive_yaml = <<~YAML
        loot_tables:
          chest:
            rolls:
              - options: outer

        option_lists:
          outer:
            - { chance: 1.0, from: inner }
          inner:
            - { chance: 1.0, item: { item: Recursed scroll } }
      YAML
      # Two rolls: outer picks the only option (any threshold works);
      # inner picks its only option.
      lt = LootTables.new(config_path: write(with_recursive_yaml), random_source: ScriptedRng.new([0, 0]))
      stacks = lt.roll('chest')
      expect(stacks.first['item_type']).to eq('Recursed scroll')
    end

    def write(yaml_text)
      f = Tempfile.new(['loot_tables', '.yaml'])
      f.write(yaml_text)
      f.flush
      f.path
    end
  end

  describe '#evaluate_dice_expression' do
    let(:lt) do
      Tempfile.create(['lt', '.yaml']) do |f|
        f.write("loot_tables: {}\n")
        f.flush
        return LootTables.new(config_path: f.path, random_source: ScriptedRng.new([3, 5, 1]))
      end
    end

    it 'evaluates NdM + K with the random source' do
      # 3d6 + 2 with rolls 3, 5, 1 → 9 + 2 = 11
      expect(lt.evaluate_dice_expression('3d6 + 2')).to eq(11)
    end
  end

  describe 'inline magical rows' do
    it 'invokes the magical_item_generator callback when supplied' do
      yaml = <<~YAML
        loot_tables:
          chest:
            rolls:
              - item:
                  magical:
                    category: melee
                    tier: [1]
                    properties_weighted: { Elemental: 1 }
      YAML
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'loot_tables.yaml')
        File.write(path, yaml)
        gen = ->(constraint) {
          { 'item_type' => 'Long sword', 'quantity' => 1, 'tier' => constraint['tier'].first, 'properties' => ['Elemental'] }
        }
        lt = LootTables.new(config_path: path, random_source: ScriptedRng.new([]), magical_item_generator: gen)
        stacks = lt.roll('chest')
        expect(stacks.first['item_type']).to eq('Long sword')
        expect(stacks.first['tier']).to eq(1)
        expect(stacks.first['properties']).to eq(['Elemental'])
      end
    end

    it 'raises when no generator is configured' do
      yaml = <<~YAML
        loot_tables:
          chest:
            rolls:
              - item: { magical: { category: melee, tier: [1] } }
      YAML
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'loot_tables.yaml')
        File.write(path, yaml)
        lt = LootTables.new(config_path: path, random_source: ScriptedRng.new([]))
        expect { lt.roll('chest') }.to raise_error(NotImplementedError, /magical_item_generator/)
      end
    end
  end

  describe 'multi-file loading' do
    it 'merges loot_tables-*.yaml siblings into one registry' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'loot_tables.yaml'), <<~YAML)
          loot_tables:
            chest_a:
              rolls:
                - item: { item: Item A }
        YAML
        File.write(File.join(dir, 'loot_tables-extra.yaml'), <<~YAML)
          loot_tables:
            chest_b:
              rolls:
                - item: { item: Item B }
        YAML
        lt = LootTables.new(config_path: File.join(dir, 'loot_tables.yaml'),
                            random_source: ScriptedRng.new([]))
        expect(lt.tables.keys).to contain_exactly('chest_a', 'chest_b')
      end
    end

    it 'raises on duplicate ids across files' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'loot_tables.yaml'), "loot_tables:\n  dup: { rolls: [] }\n")
        File.write(File.join(dir, 'loot_tables-2.yaml'), "loot_tables:\n  dup: { rolls: [] }\n")
        expect {
          LootTables.new(config_path: File.join(dir, 'loot_tables.yaml'),
                         random_source: ScriptedRng.new([]))
        }.to raise_error(ArgumentError, /Duplicate loot table/)
      end
    end
  end
end
