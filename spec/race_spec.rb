require 'tmpdir'
require_relative '../lib/race'

RSpec.describe Race do
  let(:definitions) do
    {
      'human' => {
        'name'   => 'Human',
        'speed'  => 30,
        'size'   => 'Medium',
        'ability_score_adjustments' => { 'str' => 1, 'dex' => 1, 'con' => 1, 'int' => 1, 'wis' => 1, 'cha' => 1 },
        'abilities' => Advancement.normalize_abilities_list([
          { 'name' => 'bonus_feat' }
        ])
      },
      'dwarf' => {
        'name'  => 'Dwarf',
        'speed' => 25,
        'size'  => 'Medium',
        'abilities' => Advancement.normalize_abilities_list([
          { 'name' => 'low_light_vision' },
          { 'name' => 'poison_resistance' }
        ])
      },
      'hill_dwarf' => {
        'name'        => 'Hill Dwarf',
        'parent_race' => 'dwarf',
        'ability_score_adjustments' => { 'con' => 2, 'wis' => 2 }
      }
    }
  end

  describe '#name / #speed / #size' do
    it 'reads the race fields directly when present' do
      race = Race.new(key: 'human', race_definitions: definitions)
      expect(race.name).to eq('Human')
      expect(race.speed).to eq(30)
      expect(race.size).to eq('Medium')
    end

    it 'falls back to the key when the name is omitted' do
      race = Race.new(key: 'mystery', race_definitions: { 'mystery' => {} })
      expect(race.name).to eq('mystery')
    end

    it 'inherits unset fields from the parent race' do
      race = Race.new(key: 'hill_dwarf', race_definitions: definitions)
      expect(race.name).to eq('Hill Dwarf')
      expect(race.speed).to eq(25)
      expect(race.size).to eq('Medium')
    end
  end

  describe '#ability_score_adjustments' do
    it 'returns the race-only adjustments when there is no parent' do
      race = Race.new(key: 'human', race_definitions: definitions)
      expect(race.ability_score_adjustments).to eq(
        'str' => 1, 'dex' => 1, 'con' => 1, 'int' => 1, 'wis' => 1, 'cha' => 1
      )
    end

    it 'sums adjustments across the parent_race chain' do
      race = Race.new(key: 'hill_dwarf', race_definitions: definitions)
      # Dwarf provides nothing here; Hill Dwarf adds con/wis.
      expect(race.adjustment_for(:con)).to eq(2)
      expect(race.adjustment_for(:wis)).to eq(2)
      expect(race.adjustment_for(:str)).to eq(0)
    end

    it 'stacks parent and sub-race adjustments when both are set' do
      definitions['dwarf']['ability_score_adjustments'] = { 'con' => 1 }
      race = Race.new(key: 'hill_dwarf', race_definitions: definitions)
      expect(race.adjustment_for(:con)).to eq(3)
      expect(race.adjustment_for(:wis)).to eq(2)
    end
  end

  describe '#abilities' do
    it 'returns abilities from the chain whose min_level the character meets' do
      defs = definitions.dup
      defs['dwarf']['abilities'] = Advancement.normalize_abilities_list([
        { 'name' => 'low_light_vision' },
        { 'min_level' => 5 },
        { 'name' => 'stonecunning' }
      ])
      race = Race.new(key: 'hill_dwarf', race_definitions: defs, character_level: 3)
      expect(race.abilities.map(&:name)).to contain_exactly('low_light_vision')
    end

    it 'unlocks min_level abilities once the character is high enough level' do
      defs = definitions.dup
      defs['dwarf']['abilities'] = Advancement.normalize_abilities_list([
        { 'name' => 'low_light_vision' },
        { 'min_level' => 5 },
        { 'name' => 'stonecunning' }
      ])
      race = Race.new(key: 'hill_dwarf', race_definitions: defs, character_level: 5)
      expect(race.abilities.map(&:name)).to contain_exactly('low_light_vision', 'stonecunning')
    end

    it 'reports the character level for scaling racial abilities' do
      defs = {
        'dragonborn' => {
          'abilities' => Advancement.normalize_abilities_list([
            { 'name' => 'breath_weapon', 'scales_with_level' => true }
          ])
        }
      }
      race = Race.new(key: 'dragonborn', race_definitions: defs, character_level: 4)
      breath = race.abilities.find { |a| a.name == 'breath_weapon' }
      expect(breath.level).to eq(4)
    end
  end

  describe '.load_yaml' do
    it 'returns {} for a missing path' do
      expect(Race.load_yaml(nil)).to eq({})
      expect(Race.load_yaml('/no/such/file.yaml')).to eq({})
    end

    it 'normalizes ability lists with sticky min_level' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'races.yaml')
        File.write(path, <<~YAML)
          races:
            human:
              speed: 30
              abilities:
                - name: bonus_feat
                - min_level: 3
                - name: extra_proficiency
        YAML
        races = Race.load_yaml(path)
        expect(races['human']['abilities']).to eq([
          { 'name' => 'bonus_feat' },
          { 'name' => 'extra_proficiency', 'min_level' => 3 }
        ])
      end
    end
  end
end
