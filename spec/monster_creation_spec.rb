require 'spec_helper'
require 'tmpdir'
require 'monster_creation'
require 'live_roster'

RSpec.describe MonsterCreation, type: :model do
  describe '.races' do
    it 'offers monster races (orc, goblin, ogre) unlike the PC playable list' do
      keys = MonsterCreation.races.map { |r| r[:key] }
      expect(keys).to include('orc', 'goblin', 'ogre', 'kobold')
    end
  end

  describe '.classes' do
    it 'offers the game classes' do
      keys = MonsterCreation.classes.map { |c| c[:key] }
      expect(keys).to include('fighter', 'rogue')
    end
  end

  describe '.create!' do
    around do |example|
      Dir.mktmpdir do |dir|
        # reset! clears @data_dir, so it must run BEFORE pointing the dataset at
        # the tmpdir — otherwise create! leaks test monsters into the live file.
        Creatures::Dataset.reset!
        Creatures::Dataset.data_dir = dir
        example.run
      ensure
        Creatures::Dataset.reset!
        Creatures::Dataset.data_dir = nil
      end
    end

    it 'builds and persists a stub enemy tagged as a custom template' do
      id = MonsterCreation.create!(
        'name' => 'Bridge Troll', 'race' => 'ogre', 'class' => 'fighter', 'level' => '5',
        'attributes' => { 'str' => 19, 'dex' => 8, 'con' => 17, 'int' => 6, 'wis' => 9, 'cha' => 7 },
        'skills' => %w[athletics intimidate]
      )
      a = Creatures.lookup(id)
      expect(a.name).to eq('Bridge Troll')
      expect(a.tags).to include('enemy_template', 'category:custom')
      expect(a.group).to eq('enemy')
      expect(a.class_summary).to eq([['fighter', 5]])
      expect(a.base_attribute_value(:str)).to eq(19)
    end

    it 'lands in the Roster enemy templates under the custom category' do
      id = MonsterCreation.create!('name' => 'Gutter Rat', 'race' => 'goblin',
                                   'attributes' => { 'str' => 8 })
      templates = LiveRoster.creatures_with_tag('enemy_template')
      rec = templates.find { |r| r[:id] == id }
      expect(rec).not_to be_nil
      expect(LiveRoster.category_of(rec)).to eq('custom')
    end

    it 'defaults missing attributes to 10 and works without a class' do
      id = MonsterCreation.create!('name' => 'Zombie', 'race' => 'undead',
                                   'attributes' => { 'str' => 14 })
      a = Creatures.lookup(id)
      expect(a.base_attribute_value(:str)).to eq(14)
      expect(a.base_attribute_value(:dex)).to eq(10)
      expect(a.class_summary).to eq([])
    end

    it 'stores an explicit Tier and the hide_tier flag' do
      id = MonsterCreation.create!('name' => 'Mystery', 'race' => 'human', 'tier' => '4',
                                   'hide_tier' => '1', 'attributes' => {})
      rec = Creatures::Dataset.get(id)
      expect(rec[:tier]).to eq(4)
      expect(rec[:hide_tier]).to be(true)
    end

    it 'rejects a monster with no name' do
      expect { MonsterCreation.create!('race' => 'orc', 'attributes' => {}) }
        .to raise_error(ArgumentError, /name is required/)
    end

    it 'rejects an unknown race' do
      expect { MonsterCreation.create!('name' => 'X', 'race' => 'dragonborn', 'attributes' => {}) }
        .to raise_error(ArgumentError, /not a known race/)
    end
  end
end
