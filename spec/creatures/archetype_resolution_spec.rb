require 'spec_helper'
require 'creatures'

RSpec.describe 'Creatures::Advancement Archetype Resolution', type: :model do
  it 'top-level Class returns its own entry verbatim' do
    cls = Creatures::Advancement.look_up_class('cleric')
    expect(cls['martial_advancement']).to eq('unaligned')
    expect(cls['parent_class']).to be_nil
  end

  it 'Archetype merges with its parent' do
    cls = Creatures::Advancement.look_up_class('arcane_trickster')
    # parent rogue's martial_advancement (Archetype doesn't override).
    expect(cls['martial_advancement']).to eq('unaligned')
    expect(cls['parent_class']).to eq('rogue')
    # Archetype overrides mana_per_level.
    expect(cls['mana_per_level']).to eq(2)
    # Archetype adds arcana to aligned, and removes it from rogue's unaligned.
    expect(cls['aligned_proficiencies']).to include('arcana')
    expect(cls['unaligned_proficiencies']).not_to include('arcana')
  end

  it 'Archetype ability_progression appends to parent at each level' do
    cls = Creatures::Advancement.look_up_class('arcane_trickster')
    # rogue level 1 = [trapfinding, sneak_attack, thieves_cant]
    # arcane_trickster level 1 = [arcane_spellcasting]
    expect(cls['ability_progression']['1']).to eq(
      %w[trapfinding sneak_attack thieves_cant arcane_spellcasting]
    )
    # rogue level 2 = [danger_sense]
    # arcane_trickster level 2 = [combat_trickery, mage_hand_legerdemain]
    expect(cls['ability_progression']['2']).to eq(
      %w[danger_sense combat_trickery mage_hand_legerdemain]
    )
  end

  it 'unknown Class key returns nil' do
    expect(Creatures::Advancement.look_up_class('homebrew_class')).to be_nil
  end
end
