require 'spec_helper'
require 'spell_list'

# The Compendium Spell List rows (docs/common/ui/abilities_spell_list_stub.md):
# every Spell expanded into its individual Variants, sorted by Tier.
RSpec.describe SpellList do
  subject(:rows) { described_class.rows }

  def names
    rows.map { |r| r[:name] }
  end

  def find(name)
    rows.find { |r| r[:name] == name }
  end

  it 'is sorted by Tier, lowest first' do
    tiers = rows.map { |r| r[:tier] }
    expect(tiers).to eq(tiers.sort)
    expect(tiers.first).to eq(0)
  end

  it 'expands a Tier-axis Spell into one row per Tier (not a single group row)' do
    expect(names).to include('Heal Petty Wounds', 'Heal Lesser Wounds')
    expect(names).not_to include('Heal')            # the group name is not listed
    expect(find('Heal Petty Wounds')[:tier]).to eq(0)
    expect(find('Heal Lesser Wounds')[:tier]).to eq(1)
  end

  it 'expands an aspect-axis Spell into one row per aspect (same Tier)' do
    darts = names.grep(/Dart\z/).sort
    expect(darts).to include('Acid Dart', 'Cold Dart', 'Electricity Dart', 'Fire Dart')
    expect(find('Fire Dart')[:tier]).to eq(0)
    expect(find('Acid Dart')[:tier]).to eq(0)
    expect(names).not_to include('Elemental Dart')  # the group name is not listed
  end

  it 'lists a single-Variant Spell exactly once' do
    expect(names.count('Vicious Mockery')).to eq(1)
    expect(find('Vicious Mockery')[:tier]).to eq(0)
  end

  it 'never lists Evocation among a Spell\'s Casting Skills' do
    rows.each do |r|
      expect(r[:skills]).not_to include('evocation')
      expect(r[:skills_label].downcase).not_to include('evocation')
    end
  end

  describe '.school_description' do
    it 'returns the description text for a School' do
      expect(described_class.school_description('resonance')).to match(/Creation magic/)
      expect(described_class.school_description('pneumancy')).to match(/Soul magic/)
    end

    it 'returns nil for an unknown School' do
      expect(described_class.school_description('nope')).to be_nil
    end
  end
end
