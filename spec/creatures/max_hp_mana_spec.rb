require 'spec_helper'
require_relative 'fixtures'

RSpec.describe 'Creatures Max HP / Max Mana', type: :model do
  include CreaturesFixtures

  it 'Tier 2 HP uses 2*con against Effective Constitution' do
    # Korth: base con 17, hill_dwarf chain contributes +2 con, per-tier 2
    # = 2, chosen +2 (con). Effective Con = 17 + 2 + 2 + 2 = 23. Tier 2 HP
    # formula = "2 * con". Asserted dynamically against Effective Con.
    a = Creatures::Accessor.new(korth)
    expect(a.max_hit_points).to eq(2 * a.effective_attributes[:con])
  end

  it 'Tier 1 HP uses "con"' do
    a = Creatures::Accessor.new(ghoul)
    expect(a.max_hit_points).to eq(a.effective_attributes[:con])
  end

  it 'Tier 0 HP uses "con / 2" (floor)' do
    a = Creatures::Accessor.new(record(
      tier: 0, attributes: { str: 10, dex: 10, con: 17, int: 10, wis: 10, cha: 10 }
    ))
    # effective con = 17 + 0 (per-tier 0) = 17. floor(17/2) = 8.
    expect(a.max_hit_points).to eq(8)
  end

  it 'Tier 2 cleric Max Mana adds class mana_per_level contribution' do
    a = Creatures::Accessor.new(korth)
    # Mana Base Formula[2] = "int". cleric mana_per_level (4) × level (4) = 16.
    base = a.effective_attributes[:int]
    expect(a.max_mana).to eq(base + 16)
  end

  it 'multi-class Max Mana sums per-class contributions' do
    rec = record(
      id: 99, name: 'Multi', race: 'humanoid', tier: 2,
      attributes: { str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10 },
      classes: { fighter: { level: 3 }, rogue: { level: 2 } }
    )
    # Effective int = 14 + 2 (per-tier) = 16. Mana[2] = "int" = 16.
    # fighter mana_per_level (1) × 3 = 3. rogue (1) × 2 = 2. Total = 21.
    expect(Creatures::Accessor.new(rec).max_mana).to eq(16 + 3 + 2)
  end
end
