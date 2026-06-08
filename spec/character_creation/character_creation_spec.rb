require 'spec_helper'
require 'tmpdir'
require 'character_creation'

RSpec.describe CharacterCreation, type: :model do
  describe '.attribute_allocation' do
    it 'exposes the Point Buy rules from character_creation.yaml' do
      a = CharacterCreation.attribute_allocation
      expect(a[:starting]).to eq(10)
      expect(a[:pool]).to eq(15)
      expect(a[:min]).to eq(7)
      expect(a[:max]).to eq(16)
      # Cumulative cost table, keyed by integer attribute value.
      expect(a[:cost][7]).to eq(-3)
      expect(a[:cost][10]).to eq(0)
      expect(a[:cost][16]).to eq(12)
    end
  end

  describe '.races' do
    it 'offers only the configured playable sub-races, in order' do
      keys = CharacterCreation.races.map { |r| r[:key] }
      expect(keys).to eq(%w[human hill_dwarf mountain_dwarf high_elf wood_elf
                            forest_gnome rock_gnome halfling satyr])
    end

    it 'never offers abstract parent races or the half-races' do
      keys = CharacterCreation.races.map { |r| r[:key] }
      expect(keys).not_to include('humanoid', 'fey', 'animal', 'dwarf', 'elf', 'gnome',
                                  'half_orc', 'half_elf')
    end

    it 'resolves each race’s accumulated attribute modifiers' do
      by_key = CharacterCreation.races.each_with_object({}) { |r, h| h[r[:key]] = r }
      expect(by_key['human'][:adjustments]).to eq(
        'str' => 1, 'dex' => 1, 'con' => 1, 'int' => 1, 'wis' => 1, 'cha' => 1
      )
      expect(by_key['hill_dwarf'][:adjustments].select { |_, v| v != 0 }).to eq('con' => 2, 'wis' => 2)
      expect(by_key['mountain_dwarf'][:adjustments].select { |_, v| v != 0 }).to eq('str' => 2, 'con' => 2)
      expect(by_key['high_elf'][:adjustments].select { |_, v| v != 0 }).to eq('dex' => 2, 'int' => 2)
      expect(by_key['wood_elf'][:adjustments].select { |_, v| v != 0 }).to eq('dex' => 2, 'wis' => 2)
      expect(by_key['forest_gnome'][:adjustments].select { |_, v| v != 0 }).to eq('dex' => 2, 'int' => 2)
      expect(by_key['rock_gnome'][:adjustments].select { |_, v| v != 0 }).to eq('con' => 2, 'int' => 2)
      expect(by_key['halfling'][:adjustments].select { |_, v| v != 0 }).to eq('cha' => 2, 'dex' => 2)
      expect(by_key['satyr'][:adjustments].select { |_, v| v != 0 }).to eq('dex' => 2, 'cha' => 2)
    end
  end

  describe '.blob classes' do
    let(:by_key) { CharacterCreation.classes.each_with_object({}) { |c, h| h[c[:key]] = c } }

    it 'drops the deleted Ranger class and includes the new Sorcerer' do
      expect(by_key).not_to have_key('ranger')
      expect(by_key).to have_key('sorcerer')
    end

    it 'categorizes every Skill into aligned / unaligned / opposed for a class' do
      groups = by_key['fighter'][:skill_groups]
      total = groups[:aligned].length + groups[:unaligned].length + groups[:opposed].length
      expect(total).to eq(Proficiencies.skills.length)
      expect(groups[:aligned]).to include('athletics')
    end

    it 'surfaces level-1 abilities for the class' do
      expect(by_key['fighter'][:abilities]).to include('Weapon Training', 'Armor Training')
    end
  end

  describe '.blob spell_selection' do
    let(:by_key) { CharacterCreation.classes.each_with_object({}) { |c, h| h[c[:key]] = c } }

    it 'gives Wizards a 5 + level^2 point pool with 1 + tier costs' do
      sel = by_key['wizard'][:spell_selection]
      expect(sel[:mode]).to eq('points')
      expect(sel[:budget]).to eq(6) # 5 + 1*1 at level 1
      tier0 = sel[:spells].find { |s| s[:tier].zero? }
      expect(tier0[:cost]).to eq(1) # 1 + tier, floored: a Tier 0 spell costs 1
      tier1 = sel[:spells].find { |s| s[:tier] == 1 }
      expect(tier1[:cost]).to eq(2) if tier1
    end

    it 'gives Sorcerers 4 * level spells of any kind' do
      sel = by_key['sorcerer'][:spell_selection]
      expect(sel[:mode]).to eq('count')
      expect(sel[:budget]).to eq(4)
    end

    it 'limits Bards to Performance spells, 2 * level of them' do
      sel = by_key['bard'][:spell_selection]
      expect(sel[:mode]).to eq('count')
      expect(sel[:budget]).to eq(2)
      # Every offered spell must be castable with a perform_ skill.
      every_perform = sel[:spells].all? do |sp|
        entry = Abilities.catalog.ability(sp[:key])
        skills = Array(entry['skills'])
        skills = ['arcana'] if skills.empty?
        skills.any? { |s| s.start_with?('perform') }
      end
      expect(every_perform).to be(true)
    end

    it 'gives Arcane Tricksters a 9 + level point pool' do
      sel = by_key['arcane_trickster'][:spell_selection]
      expect(sel[:mode]).to eq('points')
      expect(sel[:budget]).to eq(10)
    end

    it 'has the Cleric pick a deity and domains instead of spells' do
      sel = by_key['cleric'][:spell_selection]
      expect(sel[:mode]).to eq('domain')
      expect(sel[:max_domains]).to eq(3)
      karthak = sel[:deities].find { |d| d[:name] == 'Karthak' }
      expect(karthak).not_to be_nil
      war = karthak[:domains].find { |dom| dom[:name] == 'War' }
      expect(war[:spells]).to include('Spiritual Hammer')
    end

    it 'skips the step for auto casters (Druid) and non-casters (Fighter)' do
      expect(by_key['druid'][:spell_selection]).to be_nil
      expect(by_key['fighter'][:spell_selection]).to be_nil
    end
  end

  describe '.create!' do
    around do |example|
      Dir.mktmpdir do |dir|
        Creatures::Dataset.data_dir = dir
        Creatures::Dataset.reset!
        example.run
      ensure
        Creatures::Dataset.reset!
        Creatures::Dataset.data_dir = nil
      end
    end

    it 'builds and persists a level-1 Player Character' do
      id = CharacterCreation.create!(
        'name' => 'Mira', 'player' => 'Sam', 'race' => 'human', 'class' => 'wizard',
        'attributes' => { 'str' => 8, 'dex' => 14, 'con' => 12, 'int' => 16, 'wis' => 10, 'cha' => 10 },
        'skills' => %w[arcana history], 'spells' => ['Mage Hand', 'Charm Person']
      )
      a = Creatures.lookup(id)
      expect(a.name).to eq('Mira')
      expect(a.player).to eq('Sam')
      expect(a.tags).to include('player_character')
      expect(a.class_summary).to eq([['wizard', 1]])
      expect(a.base_attribute_value(:int)).to eq(16)
      # Effective Int = base 16 + Human all:+1 racial + Tier-1 inherent +1.
      expect(a.attribute_value(:int)).to eq(18)
      names = a.granted_abilities.map { |g| g[:name] }
      expect(names).to include('Mage Hand', 'Charm Person')
    end

    it 'records a deity / domains for the Cleric domain flow' do
      id = CharacterCreation.create!(
        'name' => 'Brother Vael', 'race' => 'hill_dwarf', 'class' => 'cleric',
        'attributes' => { 'str' => 12, 'dex' => 10, 'con' => 14, 'int' => 10, 'wis' => 15, 'cha' => 13 },
        'skills' => %w[healing religion], 'deity' => 'Karthak', 'domains' => %w[War Fire Glory]
      )
      names = Creatures.lookup(id).granted_abilities.map { |g| g[:name] }
      expect(names).to include('Heal')             # class-level granted spell
      expect(names).to include('Spiritual Hammer') # War-domain spell
    end

    it 'rejects a character with no name' do
      expect do
        CharacterCreation.create!('race' => 'human', 'class' => 'fighter', 'attributes' => {})
      end.to raise_error(ArgumentError, /name is required/)
    end

    it 'rejects a non-playable race (e.g. an abstract parent)' do
      expect do
        CharacterCreation.create!(
          'name' => 'Y', 'race' => 'humanoid', 'class' => 'fighter', 'attributes' => {}
        )
      end.to raise_error(ArgumentError, /not a playable race/)
    end

    it 'rejects a bare Set Skill key (instance suffix required)' do
      expect do
        CharacterCreation.create!(
          'name' => 'X', 'race' => 'human', 'class' => 'fighter',
          'attributes' => {}, 'skills' => ['craft_']
        )
      end.to raise_error(ArgumentError, /Set Skill/)
    end
  end
end
