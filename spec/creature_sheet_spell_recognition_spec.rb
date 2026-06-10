require 'spec_helper'
require 'creature_sheet'
require 'abilities'

# A Creature can know a Tier-axis spell by one of its per-Tier variant names
# (e.g. "Create Illusionary Sound" is the Tier-0 name of the "Create Illusion"
# spell). Such names must be recognized as spells so they list under Spells —
# and NOT under Abilities.
RSpec.describe 'CreatureSheet spell recognition' do
  describe '.spell_info' do
    it 'recognizes a Tier-axis spell by its per-Tier variant name' do
      expect(CreatureSheet.spell_info('Create Illusionary Sound')).to include(tier: 0, name: 'Create Illusionary Sound')
      expect(CreatureSheet.spell_info('create_illusionary_sound')).to include(tier: 0, name: 'Create Illusionary Sound')
      expect(CreatureSheet.spell_info('Create Minor Illusion')).to include(tier: 2, name: 'Create Minor Illusion')
    end

    it 'still resolves a spell by its primary catalog key' do
      expect(CreatureSheet.spell_info('Create Illusion')).to include(name: 'Create Illusion')
    end

    it 'recognizes a snake_case spell name with small words (case-insensitive)' do
      # "shield_of_faith" must match the catalog key "Shield of Faith" — naive
      # Title-Casing would yield "Shield Of Faith" and miss it.
      expect(CreatureSheet.spell_info('shield_of_faith')).to include(tier: 1, name: 'Shield of Faith')
      expect(CreatureSheet.spell_info('Shield of Faith')).to include(tier: 1, name: 'Shield of Faith')
    end

    it 'recognizes per-Tier variant names built from prefix / suffix arrays' do
      # "Ward" has prefix [Trivial, Lesser, Standard, …]; "Heal" has a `suffix`.
      expect(CreatureSheet.spell_info('Lesser Ward')).to include(tier: 1, name: 'Lesser Ward')
      expect(CreatureSheet.spell_info('Standard Ward')).to include(tier: 2, name: 'Standard Ward')
      expect(CreatureSheet.spell_info('Heal Petty Wounds')).to include(tier: 0, name: 'Heal Petty Wounds')
      expect(CreatureSheet.spell_info('heal_lesser_wounds')).to include(tier: 1, name: 'Heal Lesser Wounds')
    end

    it 'maps a constructed variant name back to its base catalog key + Tier axis' do
      # So the Abilities domain (which keys only by catalog name) can resolve it.
      expect(CreatureSheet.spell_info('Standard Shield')).to include(base: 'Shield', axis: 1)
      expect(CreatureSheet.spell_info('Lesser Shield')).to include(base: 'Shield', axis: 0)
      expect(CreatureSheet.spell_info('Shield of Faith')).to include(base: 'Shield of Faith', axis: 0)
    end

    it 'returns nil for non-spell Talents (they stay under Abilities)' do
      expect(CreatureSheet.spell_info('Rage')).to be_nil
      expect(CreatureSheet.spell_info('Turn Undead')).to be_nil
    end
  end

  describe '.abilities' do
    it 'excludes a known spell variant (it belongs under Spells, not Abilities)' do
      acc = Object.new
      acc.define_singleton_method(:granted_abilities) do |source: nil|
        [{ name: 'Create Illusionary Sound', source: 'class:bard' },
         { name: 'Rage', source: 'class:bard' }]
      end
      names = CreatureSheet.abilities(acc).map { |a| a[:name] }
      expect(names).to include('Rage')
      expect(names).not_to include('Create Illusionary Sound')
    end
  end
end
