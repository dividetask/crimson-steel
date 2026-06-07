require 'spec_helper'
require 'creatures'
require 'creatures/advancement'
require 'tmpdir'
require_relative 'fixtures'

RSpec.describe 'Enemy templates: races, clamp, NPC class, loadout', type: :model do
  include CreaturesFixtures

  describe 'enemy racial benefits' do
    it 'goblin: -4 Str/Con/Int/Cha, -2 Wis, +4 Dex (small, low-light, fast movement)' do
      a = accessor(race: 'goblin', tier: 0,
                   attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 })
      expect(a.effective_attributes).to include(str: 6, con: 6, int: 6, cha: 6, wis: 8, dex: 14)
      expect(a.has_ability('low_light_vision')).to be(true)
      expect(a.has_ability('fast_movement')).to be(true)
    end

    it 'orc: +4 Str/Con, -2 Int/Wis/Cha (low-light, ferocity)' do
      a = accessor(race: 'orc', tier: 0,
                   attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 })
      expect(a.effective_attributes).to include(str: 14, con: 14, int: 8, wis: 8, cha: 8, dex: 10)
      expect(a.has_ability('ferocity')).to be(true)
      expect(a.has_ability('low_light_vision')).to be(true)
    end

    it 'kobold: -4 Str, -2 Con/Wis, +2 Dex/Int (scaled hide, light sensitivity, trapfinding)' do
      a = accessor(race: 'kobold', tier: 0,
                   attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 })
      expect(a.effective_attributes).to include(str: 6, con: 8, wis: 8, dex: 12, int: 12, cha: 10)
      %w[low_light_vision scaled_hide light_sensitivity Trapfinding].each do |ab|
        expect(a.has_ability(ab)).to be(true), "expected kobold to have #{ab}"
      end
    end

    it 'large beast: +4 Str/Con, -4 Wis/Cha, -8 Int, +2 natural armor' do
      a = accessor(race: 'large_beast', tier: 0,
                   attributes: { str: 12, dex: 10, con: 12, int: 10, wis: 12, cha: 10 })
      expect(a.effective_attributes).to include(str: 16, con: 16, wis: 8, cha: 6)
      expect(a.has_ability('natural_armor_2')).to be(true)
    end
  end

  describe 'fey races removed' do
    it 'fey/sprite/pixie/dryad/brownie are no longer known races' do
      %w[fey sprite pixie dryad brownie].each do |r|
        expect(Creatures::Races.known?(r)).to be(false), "expected #{r} to be removed"
      end
    end
  end

  describe 'minimum-1 attribute clamp' do
    it 'a beast -8 Int never drops below 1' do
      # spider is a medium_beast: -8 Int. Base 5 would land at -3 without the clamp.
      a = accessor(race: 'spider', tier: 0,
                   attributes: { str: 9, dex: 12, con: 11, int: 5, wis: 10, cha: 2 })
      expect(a.effective_attributes[:int]).to eq(1)
    end

    it 'clamps every attribute, not just Int' do
      a = accessor(race: 'tiny_beast', tier: 0,
                   attributes: { str: 1, dex: 10, con: 1, int: 1, wis: 1, cha: 1 })
      ea = a.effective_attributes
      expect(ea[:str]).to eq(1) # 1 - 6 -> clamped
      expect(ea[:con]).to eq(1)
      expect(ea[:wis]).to eq(1)
    end
  end

  describe 'warrior NPC class' do
    it 'is flagged npc_class and excluded from the PC class picker (with commoner)' do
      expect(Creatures::Advancement.npc_class?('warrior')).to be(true)
      expect(Creatures::Advancement.npc_class?('commoner')).to be(true)
      expect(Creatures::Advancement.npc_class?('fighter')).to be(false)
      expect(Creatures::Advancement.pc_class_keys).not_to include('warrior', 'commoner')
      expect(Creatures::Advancement.pc_class_keys).to include('fighter')
    end

    it 'mirrors fighter saves/martial but grants no class abilities' do
      w = Creatures::Advancement.look_up_class('warrior')
      f = Creatures::Advancement.look_up_class('fighter')
      expect(w['martial_advancement']).to eq(f['martial_advancement'])
      expect(w['saves']).to eq(f['saves'])
      expect(w['aligned_proficiencies']).to eq(f['aligned_proficiencies'])
      expect(w['ability_progression']).to be_nil
    end
  end

  describe 'equipment_table round-trip' do
    it 'normalize/serialize preserve equipment_table' do
      raw = {
        'id' => 9500, 'name' => 'Gob', 'race' => 'goblin',
        'attributes' => { 'str' => 10, 'dex' => 10, 'con' => 10,
                          'int' => 10, 'wis' => 10, 'cha' => 10 },
        'advancement' => { 'classes' => { 'warrior' => 1 } },
        'equipment_table' => 'common_goblin_loadout'
      }
      rec = Creatures::Record.normalize(raw)
      expect(rec[:equipment_table]).to eq('common_goblin_loadout')
      expect(Creatures::Record.serialize(rec)['equipment_table']).to eq('common_goblin_loadout')
    end
  end

  describe 'Common templates (dataset)' do
    around(:each) do |ex|
      Dir.mktmpdir('creatures-data') do |dir|
        Creatures::Dataset.data_dir = dir
        ex.run
      ensure
        Creatures::Dataset.reset!
      end
    end
    before(:each) { Creatures::Dataset.load! }

    it 'Common Goblin: tier 0, goblin, spawns carrying its equipment_table' do
      a = Creatures.lookup(306)
      expect(a.name).to eq('Common Goblin')
      expect(a.race).to eq('goblin')
      expect(a.tier).to eq(0)
      expect(a.equipment_table).to eq('common_goblin_loadout')

      new_id = Creatures.spawn_from_template(306)
      expect(Creatures.lookup(new_id).equipment_table).to eq('common_goblin_loadout')
    end

    it 'Common Orc: tier 0, orc, orc-adjusted stats, spawns carrying its equipment_table' do
      a = Creatures.lookup(307)
      expect(a.name).to eq('Common Orc')
      expect(a.race).to eq('orc')
      expect(a.tier).to eq(0)
      expect(a.equipment_table).to eq('common_orc_loadout')
      expect(a.effective_attributes).to include(str: 14, con: 14, int: 8, wis: 8, cha: 8)

      new_id = Creatures.spawn_from_template(307)
      expect(Creatures.lookup(new_id).equipment_table).to eq('common_orc_loadout')
    end

    it 'Slaver: tier 1, race + class rolled at spawn, equipment_table slaver_loadout' do
      a = Creatures.lookup(355)
      expect(a.name).to eq('Slaver')
      expect(a.tier).to eq(1)
      expect(a.equipment_table).to eq('slaver_loadout')
      expect(a.record[:race_table].map { |e| e[:race] }).to eq(%w[orc human elf dwarf])
      expect(a.record[:class_table].map { |e| e[:class] }).to eq(%w[warrior fighter cleric rogue])

      spawn = Creatures.lookup(Creatures.spawn_from_template(355))
      # The spawn has a concrete race + single class drawn from the tables.
      expect(%w[orc human elf dwarf]).to include(spawn.race)
      expect(spawn.record[:race_table]).to be_empty
      expect(spawn.class_summary.size).to eq(1)
      expect(%w[warrior fighter cleric rogue]).to include(spawn.class_summary.first.first)
      expect(spawn.record[:class_table]).to be_empty
    end

    it 'Slaver race + class rolls are weighted ~50% and honor the seeded rng' do
      races = Hash.new(0)
      classes = Hash.new(0)
      400.times do |seed|
        a = Creatures.lookup(Creatures.spawn_from_template(355, rng: Random.new(seed)))
        races[a.race] += 1
        classes[a.class_summary.first.first] += 1
      end
      expect(races.keys).to match_array(%w[orc human elf dwarf])
      expect(classes.keys).to match_array(%w[warrior fighter cleric rogue])
      expect(races['orc'].to_f / 400).to be_within(0.08).of(0.5)
      expect(classes['warrior'].to_f / 400).to be_within(0.08).of(0.5)
    end

    it 'the cleric Slaver variant carries Mortheth as its deity' do
      # Find a seed that rolls the cleric variant, then assert its choices.
      cleric = nil
      (0..120).each do |s|
        a = Creatures.lookup(Creatures.spawn_from_template(355, rng: Random.new(s)))
        if a.class_summary.first.first == 'cleric'
          cleric = a
          break
        end
      end
      expect(cleric).not_to be_nil
      expect(cleric.record[:classes]['cleric'][:choices]).to include('deity' => 'Mortheth')
    end

    it 'Slaver spawns get random trained skills sized by class + Effective Intelligence' do
      pool = %w[athletics perception religion restricted_magic sense_motive healing]
      20.times do |seed|
        a = Creatures.lookup(Creatures.spawn_from_template(355, rng: Random.new(seed)))
        cls_key, = a.class_summary.first
        skills = a.record[:classes][cls_key][:skills]
        bonus = Creatures::Advancement.look_up_class(cls_key)['bonus_skills'] || 0
        budget = ((a.attribute_value(:int) / 4) + bonus) # level 1
        expect(skills).to all(satisfy { |s| pool.include?(s) })
        expect(skills.uniq.size).to eq(skills.size)
        expect(skills.size).to eq([budget, pool.size].min)
      end
    end

    it 'Slaver Lieutenant: tier 2, barbarian/fighter/cleric/rogue, rolls 2 Str/Con/Cha/Dex picks' do
      a = Creatures.lookup(356)
      expect(a.name).to eq('Slaver Lieutenant')
      expect(a.tier).to eq(2)
      expect(a.record[:class_table].map { |e| e[:class] }).to eq(%w[barbarian fighter cleric rogue])
      expect(a.record[:tier_advancement_table]).to eq(count: 2, from: %i[str con cha dex])

      pool = %w[athletics perception religion restricted_magic sense_motive healing]
      10.times do |seed|
        s = Creatures.lookup(Creatures.spawn_from_template(356, rng: Random.new(seed)))
        cls_key, level = s.class_summary.first
        expect(%w[barbarian fighter cleric rogue]).to include(cls_key)
        expect(level).to eq(4)
        adv = s.tier_attribute_advancement
        expect(adv.size).to eq(2)
        expect(adv).to all(satisfy { |x| %i[str con cha dex].include?(x) })

        # Skill COUNT does not scale with Class Level: it is the level-1
        # budget floor(int/4)+bonus_skills, capped at the pool size.
        bonus = Creatures::Advancement.look_up_class(cls_key)['bonus_skills'] || 0
        expected = [(s.attribute_value(:int) / 4) + bonus, pool.size].min
        expect(s.record[:classes][cls_key][:skills].size).to eq(expected)
      end
    end

    it 'cleric Slaver rolls 3 distinct domains (2 from Mortheth, 1 from the wider pool)' do
      pool_a = %w[Artifice Death Earth Greed Ruin]
      pool_b = %w[Plague Travel Vengeance Secrets Tempest Cunning Despair Knowledge]
      checked = 0
      (0..200).each do |s|
        a = Creatures.lookup(Creatures.spawn_from_template(355, rng: Random.new(s)))
        next unless a.class_summary.first.first == 'cleric'
        domains = a.record[:classes]['cleric'][:choices]['domains']
        expect(domains.uniq.size).to eq(3)
        expect((domains & pool_a).size).to eq(2)
        expect((domains & pool_b).size).to eq(1)
        checked += 1
        break if checked >= 5
      end
      expect(checked).to be >= 1
    end
  end
end
