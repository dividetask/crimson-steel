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
      expect(CreatureSheet.spell_info('Create Illusionary Sound')).to eq(tier: 0, name: 'Create Illusionary Sound')
      expect(CreatureSheet.spell_info('create_illusionary_sound')).to eq(tier: 0, name: 'Create Illusionary Sound')
      expect(CreatureSheet.spell_info('Create Minor Illusion')).to eq(tier: 2, name: 'Create Minor Illusion')
    end

    it 'still resolves a spell by its primary catalog key' do
      expect(CreatureSheet.spell_info('Create Illusion')).to include(name: 'Create Illusion')
    end

    it 'recognizes a snake_case spell name with small words (case-insensitive)' do
      # "shield_of_faith" must match the catalog key "Shield of Faith" — naive
      # Title-Casing would yield "Shield Of Faith" and miss it.
      expect(CreatureSheet.spell_info('shield_of_faith')).to eq(tier: 1, name: 'Shield of Faith')
      expect(CreatureSheet.spell_info('Shield of Faith')).to eq(tier: 1, name: 'Shield of Faith')
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
