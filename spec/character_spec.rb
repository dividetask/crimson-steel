require 'tmpdir'
require_relative '../lib/character'

RSpec.describe Character do
  describe '#attribute' do
    it 'returns the base score when no advancement is provided' do
      c = Character.new(
        id:         1,
        name:       'Test',
        player:     'P',
        race:       'Human',
        attributes: { str: 10, dex: 12, con: 14, int: 11, wis: 13, cha: 15 }
      )
      expect(c.attribute(:str)).to eq(10)
      expect(c.attribute(:cha)).to eq(15)
    end

    it 'adds the advancement bonus on top of the base score' do
      adv = Advancement.new(tier: 2, attribute_bonus_per_tier: 1)
      c = Character.new(
        id:          1,
        name:        'Test',
        player:      'P',
        race:        'Human',
        attributes:  { str: 10 },
        advancement: adv
      )
      expect(c.attribute(:str)).to eq(12)
    end

    it 'stacks the racial adjustment on top of base + advancement' do
      adv  = Advancement.new(tier: 1, attribute_bonus_per_tier: 1)
      race = Race.new(
        key: 'mountain_dwarf',
        race_definitions: {
          'mountain_dwarf' => { 'ability_score_adjustments' => { 'str' => 2, 'con' => 2 } }
        }
      )
      c = Character.new(
        id:          1,
        name:        'Test',
        player:      'P',
        race:        race,
        attributes:  { str: 10, con: 10 },
        advancement: adv
      )
      expect(c.attribute(:str)).to eq(13) # 10 base + 1 tier + 2 race
      expect(c.attribute(:con)).to eq(13)
      expect(c.attribute(:dex)).to eq(1)  # 0 base + 1 tier + 0 race
    end
  end

  describe '.load_yaml' do
    it 'wires each character to an Advancement built from the combined config' do
      Dir.mktmpdir do |dir|
        chars_path = File.join(dir, 'characters.yaml')
        adv_path   = File.join(dir, 'advancement.yaml')

        File.write(chars_path, <<~YAML)
          characters:
            - id: 1
              name: Hero
              player: P
              race: Human
              attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 }
              advancement:
                tier: 2
                classes:
                  rogue: 3
                  wizard: 2
        YAML

        File.write(adv_path, <<~YAML)
          attribute_bonus_per_tier: 1
          classes:
            rogue:
              abilities:
                - name: trapfinding
                - name: sneak_attack
                  scales_with_level: true
            wizard:
              abilities: []
        YAML

        chars = Character.load_yaml(chars_path, advancement_path: adv_path)
        expect(chars.size).to eq(1)
        c = chars.first

        expect(c.attribute(:str)).to eq(12)
        expect(c.advancement.tier).to eq(2)
        expect(c.advancement.class_level('rogue')).to eq(3)
        expect(c.advancement.class_level('wizard')).to eq(2)

        sneak = c.advancement.abilities.find { |a| a.name == 'sneak_attack' }
        expect(sneak.level).to eq(3)
        expect(c.advancement.abilities.map(&:name)).to include('trapfinding')
      end
    end

    it 'wires the race YAML into Character#race and Character#attribute' do
      Dir.mktmpdir do |dir|
        chars_path = File.join(dir, 'characters.yaml')
        races_path = File.join(dir, 'races.yaml')

        File.write(chars_path, <<~YAML)
          characters:
            - id: 1
              name: Hero
              player: P
              race: hill_dwarf
              attributes: { str: 10, con: 10, wis: 10 }
              advancement:
                classes:
                  fighter: 1
        YAML

        File.write(races_path, <<~YAML)
          races:
            dwarf:
              speed: 25
              abilities:
                - name: low_light_vision
            hill_dwarf:
              parent_race: dwarf
              ability_score_adjustments:
                con: 2
                wis: 2
        YAML

        c = Character.load_yaml(chars_path, races_path: races_path).first
        expect(c.race).to be_a(Race)
        expect(c.race.key).to eq('hill_dwarf')
        expect(c.race.speed).to eq(25)
        expect(c.attribute(:con)).to eq(12) # 10 base + 0 tier + 2 race
        expect(c.attribute(:wis)).to eq(12)
        expect(c.race.abilities.map(&:name)).to include('low_light_vision')
      end
    end

    it 'still loads characters when the advancement section is absent' do
      Dir.mktmpdir do |dir|
        chars_path = File.join(dir, 'characters.yaml')
        File.write(chars_path, <<~YAML)
          characters:
            - id: 9
              name: Plain
              player: P
              race: Human
              attributes: { str: 10 }
        YAML
        c = Character.load_yaml(chars_path).first
        expect(c.attribute(:str)).to eq(10)
        expect(c.advancement.tier).to eq(0)
        expect(c.advancement.class_levels).to eq({})
      end
    end
  end
end
