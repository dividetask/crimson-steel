require 'spec_helper'
require_relative 'fixtures'

RSpec.describe 'Creatures ranks_for', type: :model do
  include CreaturesFixtures

  describe 'skills' do
    it 'aligned skill (inclusion form): Korth Cleric 4 healing' do
      # Cleric has `aligned_proficiencies` including `healing`. Aligned = floor(5*4/3) = 6.
      a = Creatures::Accessor.new(korth)
      expect(a.ranks_for('healing')).to eq(6)
    end

    it 'untrained skill returns 0' do
      a = Creatures::Accessor.new(korth)
      expect(a.ranks_for('stealth')).to eq(0)
    end

    it 'inclusion-form default (unaligned) for trained skill not in aligned list' do
      # Cleric inclusion form; intimidate is not in cleric.aligned_proficiencies.
      # Unaligned = level = 4.
      a = Creatures::Accessor.new(korth)
      expect(a.ranks_for('intimidate')).to eq(4)
    end

    it 'inverse form: Birch Bard 4 perform_sing → aligned via inverse default' do
      # Bard `unaligned_proficiencies: [restricted_magic, survival]`. perform_ not in list.
      # Inverse default = aligned = floor(5*4/3) = 6.
      a = Creatures::Accessor.new(birch)
      expect(a.ranks_for('perform_sing')).to eq(6)
    end

    it 'inverse form: a Bard trained in survival → unaligned via the listed override' do
      rec = birch
      rec[:classes]['bard'][:skills] << 'survival'
      a = Creatures::Accessor.new(rec)
      expect(a.ranks_for('survival')).to eq(4)
    end

    it 'Set Skill prefix match: cleric craft_blacksmith via craft_ → aligned' do
      rec = korth
      rec[:classes]['cleric'][:skills] << 'craft_blacksmith'
      a = Creatures::Accessor.new(rec)
      expect(a.ranks_for('craft_blacksmith')).to eq(6)
    end

    it 'archetype-merged aligned list: Vex arcana → aligned' do
      # Arcane Trickster adds `arcana` to aligned. Aligned at level 4 = 6.
      a = Creatures::Accessor.new(vex)
      expect(a.ranks_for('arcana')).to eq(6)
    end

    it 'archetype default (now inclusion form) for trained but unlisted: Vex stealth → unaligned' do
      # The merged Arcane Trickster effective aligned list = [arcana].
      # stealth is not in it → unaligned default = level = 4.
      a = Creatures::Accessor.new(vex)
      expect(a.ranks_for('stealth')).to eq(4)
    end

    it 'multi-class summation: Fighter 3 + Rogue 2 trained in athletics on both' do
      rec = record(
        id: 99, name: 'Multi', race: 'human',
        classes: {
          fighter: { level: 3, skills: %w[athletics] },
          rogue:   { level: 2, skills: %w[athletics] }
        }
      )
      # Fighter has athletics aligned (5×3/3 = 5). Rogue has unaligned_proficiencies
      # not containing athletics, so inverse default = aligned (5×2/3 = 3).
      expect(Creatures::Accessor.new(rec).ranks_for('athletics')).to eq(5 + 3)
    end

    it 'unknown key returns zero' do
      a = Creatures::Accessor.new(korth)
      expect(a.ranks_for('homebrew_skill')).to eq(0)
    end
  end

  describe 'saves' do
    it 'a save in neither list uses the Unaligned (medium) rate' do
      # saves.aligned is now empty for every Class; cleric's saves.opposed is
      # [str, dex, con, int], so wis is in neither list → Unaligned = level = 4.
      a = Creatures::Accessor.new(korth)
      expect(a.ranks_for('wis_save')).to eq(4)
    end

    it 'an explicitly opposed save uses the opposed rate' do
      # str is in cleric's saves.opposed → opposed = floor(2*4/3) = 2.
      a = Creatures::Accessor.new(korth)
      expect(a.ranks_for('str_save')).to eq(2)
    end

    it 'every Class contributes to every Save' do
      rec = record(
        id: 99, name: 'Multi', race: 'human',
        classes: { fighter: { level: 3 }, rogue: { level: 2 } }
      )
      # saves.aligned is now empty for every Class.
      # Fighter: dex is in saves.opposed → opposed = floor(2*3/3) = 2.
      # Rogue: dex is in neither list → Unaligned = level = 2.
      # Sum = 4.
      expect(Creatures::Accessor.new(rec).ranks_for('dex_save')).to eq(2 + 2)
    end
  end

  describe 'martial' do
    it 'cleric martial_advancement = unaligned' do
      a = Creatures::Accessor.new(korth)
      expect(a.ranks_for('martial')).to eq(4)
    end

    it 'barbarian martial_advancement = aligned' do
      a = Creatures::Accessor.new(brenna)
      expect(a.ranks_for('martial')).to eq(6) # floor(5*4/3)
    end
  end
end
