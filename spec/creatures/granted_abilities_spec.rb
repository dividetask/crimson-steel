require 'spec_helper'
require_relative 'fixtures'

RSpec.describe 'Creatures granted_abilities', type: :model do
  include CreaturesFixtures

  it 'class progression collects abilities up to Class Level' do
    a = Creatures::Accessor.new(korth)
    names = a.granted_abilities.map { |g| g[:name] }
    # Cleric levels 1-2 abilities (Cleric 4 reaches both):
    %w[see_injury improved_healing combat_healing domain
       channel_divinity turn_undead casting_feat].each do |ab|
      expect(names).to include(ab)
    end
  end

  it 'cleric `granted_spells` appear in the list' do
    a = Creatures::Accessor.new(korth)
    names = a.granted_abilities.map { |g| g[:name] }
    expect(names).to include('Heal', 'Ward', 'Standard Surgery')
  end

  it 'cleric deity+domain resolves through deities.yaml' do
    a = Creatures::Accessor.new(korth)
    names = a.granted_abilities.map { |g| g[:name] }
    # Karthak / War: Divine Favor, Shield of Faith, Spiritual Hammer, Silence
    expect(names).to include('Divine Favor', 'Shield of Faith', 'Spiritual Hammer', 'Silence')
  end

  it 'source filter narrows to race only' do
    a = Creatures::Accessor.new(korth)
    sources = a.granted_abilities(source: 'race').map { |g| g[:source] }.uniq
    expect(sources).to eq(['race']).or eq([])
  end

  it 'source filter "class" narrows to class:* sources' do
    a = Creatures::Accessor.new(korth)
    expect(a.granted_abilities(source: 'class')).to all(
      satisfy { |g| g[:source].start_with?('class:') }
    )
  end

  it 'archetype emits source = class:<archetype_key>' do
    a = Creatures::Accessor.new(vex)
    arcane_spellcasting = a.granted_abilities.find { |g| g[:name] == 'arcane_spellcasting' }
    expect(arcane_spellcasting[:source]).to eq('class:arcane_trickster')
  end

  it 'level_for_ability returns Class Level for class-sourced abilities' do
    a = Creatures::Accessor.new(korth)
    expect(a.level_for_ability('see_injury')).to eq(4) # cleric level
    expect(a.level_for_ability('nonexistent')).to eq(0)
  end

  it 'has_ability is true for granted, false otherwise' do
    a = Creatures::Accessor.new(korth)
    expect(a.has_ability('channel_divinity')).to be true
    expect(a.has_ability('nonexistent')).to be false
  end

  it 'choices.spellcasting picks contribute only when a Spellcasting ability is granted' do
    # Barbarian has no Spellcasting-type ability; choices.spellcasting is ignored.
    rec = record(
      id: 88, name: 'Spurious', race: 'human',
      classes: { barbarian: { level: 4, choices: { 'spellcasting' => ['fire_dart'] } } }
    )
    a = Creatures::Accessor.new(rec)
    expect(a.granted_abilities.map { |g| g[:name] }).not_to include('fire_dart')
  end

  it 'choices.spellcasting picks contribute when a Spellcasting ability is in progression' do
    # Bard at level 1 gets `bardic_spellcasting`; spellcasting picks then count.
    rec = record(
      id: 88, name: 'Caster', race: 'human',
      classes: { bard: { level: 1, choices: { 'spellcasting' => ['charm_person'] } } }
    )
    a = Creatures::Accessor.new(rec)
    expect(a.granted_abilities.map { |g| g[:name] }).to include('charm_person')
  end

  context 'borrowed class entry (Borrowed Talent persona)' do
    # A doppelganger-style persona: a borrowed wizard 4 layered on a
    # paragon 8. It should grant the wizard's abilities/spells but add no
    # Character Levels.
    def borrower
      record(
        id: 89, name: 'Borrower', race: 'human',
        classes: {
          paragon: { level: 8, skills: %w[arcana perception] },
          wizard:  { level: 4, borrowed: true,
                     choices: { 'spellcasting' => ['Charm Person'] } }
        }
      )
    end

    it 'grants the borrowed class abilities and spells' do
      names = Creatures::Accessor.new(borrower).granted_abilities.map { |g| g[:name] }
      expect(names).to include('arcane_spellcasting', 'Charm Person')
    end

    it 'contributes no Character Levels (excluded from total_level)' do
      expect(Creatures::Accessor.new(borrower).total_level).to eq(8)
    end

    it 'does not advance Martial / Saves / Skill ranks off the borrowed level' do
      borrowed = Creatures::Accessor.new(borrower)
      paragon_only = Creatures::Accessor.new(
        record(id: 90, name: 'Plain', race: 'human',
               classes: { paragon: { level: 8, skills: %w[arcana perception] } })
      )
      expect(borrowed.ranks_for('martial')).to eq(paragon_only.ranks_for('martial'))
      expect(borrowed.ranks_for('str_save')).to eq(paragon_only.ranks_for('str_save'))
      expect(borrowed.ranks_for('arcana')).to eq(paragon_only.ranks_for('arcana'))
    end
  end
end
