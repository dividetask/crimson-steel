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

  it 'Archetype ability_progression merges with the parent (archetype features at level 3)' do
    cls = Creatures::Advancement.look_up_class('arcane_trickster')
    # Parent Rogue levels are inherited unchanged...
    expect(cls['ability_progression']['1']).to eq(%w[trapfinding sneak_attack thieves_cant])
    expect(cls['ability_progression']['2']).to eq(%w[danger_sense])
    # ...and the archetype's own features are added at level 3 (chosen then).
    expect(cls['ability_progression']['3']).to eq(
      %w[arcane_spellcasting combat_trickery mage_hand_legerdemain]
    )
  end

  it 'merge appends when parent and archetype share a level (Berserker keeps its own)' do
    # Berserker adds level 3/4 on top of the base Barbarian (levels 1-2), so the
    # merged progression carries both.
    prog = Creatures::Advancement.look_up_class('berserker')['ability_progression']
    expect(prog['1']).to eq(%w[rage fast_movement])
    expect(prog['3']).to eq(%w[reckless_attacks])
  end

  it 'unknown Class key returns nil' do
    expect(Creatures::Advancement.look_up_class('homebrew_class')).to be_nil
  end
end
