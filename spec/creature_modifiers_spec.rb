require 'spec_helper'
require 'creatures'
require 'abilities'
require 'creature_modifiers'
require_relative 'creatures/fixtures'

RSpec.describe CreatureModifiers do
  include CreaturesFixtures

  # Korth is a hill_dwarf (→ poison_resistance), Vex a high_elf and Birch
  # a satyr (→ enchantment_resistance). A plain human carries none.
  let(:human) { Creatures::Accessor.new(record) }
  let(:dwarf) { Creatures::Accessor.new(korth) }
  let(:elf)   { Creatures::Accessor.new(vex) }
  let(:satyr) { Creatures::Accessor.new(birch) }

  describe '.attribute_bonus (equipment Guidance)' do
    it 'returns the net Guidance bonus for the matching attribute only' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'str', bonus_type: 'Guidance', amount: 3 },
         { target_key: 'dex', bonus_type: 'Guidance', amount: 2 }]
      )
      expect(described_class.attribute_bonus(human, :str)).to eq(3)
      expect(described_class.attribute_bonus(human, :dex)).to eq(2)
      expect(described_class.attribute_bonus(human, :con)).to eq(0)
    end

    it 'keeps only the highest of two same-Type bonuses (per-Type stacking)' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'str', bonus_type: 'Guidance', amount: 2 },
         { target_key: 'str', bonus_type: 'Guidance', amount: 5 }]
      )
      expect(described_class.attribute_bonus(human, :str)).to eq(5)
    end
  end

  describe 'active abilities are not Always-On' do
    it 'classifies an action (has activation_time) vs a passive Modifier ability' do
      # Strength Devotion is a Channel Divinity action (activation_time: main).
      expect(described_class.active_ability?('Strength Devotion')).to be true
      expect(described_class.active_ability?('Weapon Training')).to be false
    end

    it "excludes an action ability's Modifiers from the Always-On aggregate" do
      acc = Object.new
      acc.define_singleton_method(:granted_abilities) { |source: nil| [{ name: 'Strength Devotion', source: 'class:cleric' }] }
      # Strength Devotion grants +2 str/con, but only when used — never Always-On.
      expect(described_class.ability_modifier_entries(acc)).to eq([])
    end
  end

  describe '.skill_modifiers (equipment Guidance to a named skill)' do
    it 'returns the Guidance only for the exact skill key, not other skills or saves' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'stealth',           bonus_type: 'Guidance', amount: 1 },
         { target_key: 'perform_percussion', bonus_type: 'Guidance', amount: 1 },
         { target_key: 'saves',             bonus_type: 'Guidance', amount: 2 }]
      )
      expect(described_class.skill_modifiers(human, 'stealth')).to eq([['Guidance', 1]])
      expect(described_class.skill_bonus(human, 'perform_percussion')).to eq(1)
      # An unrelated skill, and the 'saves' Guidance, never leak in.
      expect(described_class.skill_modifiers(human, 'perception')).to eq([])
      expect(described_class.skill_bonus(human, 'wis_save')).to eq(0)
    end

    it 'per-Type stacks (keeps the highest of two same-Type bonuses)' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'stealth', bonus_type: 'Guidance', amount: 1 },
         { target_key: 'stealth', bonus_type: 'Guidance', amount: 3 }]
      )
      expect(described_class.skill_bonus(human, 'stealth')).to eq(3)
    end
  end

  describe '.save_modifiers' do
    it 'includes the Cloak (Guidance to saves) on every save, unconditionally' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'saves', bonus_type: 'Guidance', amount: 2 }]
      )
      expect(described_class.save_modifiers(human, :wis)).to eq([['Guidance', 2]])
      expect(described_class.unconditional_save_bonus(human, :con)).to eq(2)
    end

    it "applies a Dwarf's +1 racial poison resistance only against poison" do
      allow(described_class).to receive(:equipped_effects).and_return([])
      expect(described_class.save_modifiers(dwarf, :con, descriptors: ['poison'])).to eq([['Racial', 1]])
      expect(described_class.save_modifiers(dwarf, :con, descriptors: [])).to eq([])
      expect(described_class.save_modifiers(dwarf, :con, descriptors: ['enchantment'])).to eq([])
      # Conditional → never part of the unconditional sheet bonus.
      expect(described_class.unconditional_save_bonus(dwarf, :con)).to eq(0)
    end

    it "applies an Elf's / Satyr's +1 enchantment resistance only against enchantment" do
      allow(described_class).to receive(:equipped_effects).and_return([])
      expect(described_class.save_modifiers(elf,   :wis, descriptors: ['enchantment'])).to eq([['Racial', 1]])
      expect(described_class.save_modifiers(satyr, :wis, descriptors: ['enchantment'])).to eq([['Racial', 1]])
      expect(described_class.save_modifiers(elf,   :wis, descriptors: ['poison'])).to eq([])
    end

    it 'stacks the Cloak (Guidance) and a racial resistance (Racial) as separate Types' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'saves', bonus_type: 'Guidance', amount: 3 }]
      )
      expect(described_class.save_modifiers(dwarf, :con, descriptors: ['poison']))
        .to contain_exactly(['Guidance', 3], ['Racial', 1])
    end
  end

  describe '.attribute_bonus_tokens (sheet breakdown)' do
    it 'breaks out a Bonus Type (per-Type stacked), summing to attribute_bonus' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'str', bonus_type: 'Guidance', amount: 2 },
         { target_key: 'str', bonus_type: 'Guidance', amount: 5 }]
      )
      tokens = described_class.attribute_bonus_tokens(human, :str)
      expect(tokens).to eq([{ amount: 5, type: 'Guidance' }])
      expect(tokens.sum { |t| t[:amount] }).to eq(described_class.attribute_bonus(human, :str))
    end

    it 'returns no tokens for an attribute with no Always-On bonus' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'str', bonus_type: 'Guidance', amount: 2 }]
      )
      expect(described_class.attribute_bonus_tokens(human, :con)).to eq([])
    end
  end

  describe '.save_bonus_tokens (sheet display)' do
    it 'returns the Cloak as an unconditional token' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'saves', bonus_type: 'Guidance', amount: 1 }]
      )
      expect(described_class.save_bonus_tokens(human, :wis)).to eq([{ amount: 1, conditional: false, type: 'Guidance' }])
    end

    it 'marks a racial resistance token conditional, ordered after unconditional ones' do
      allow(described_class).to receive(:equipped_effects).and_return(
        [{ target_key: 'saves', bonus_type: 'Guidance', amount: 1 }]
      )
      tokens = described_class.save_bonus_tokens(dwarf, :con)
      expect(tokens).to eq([
        { amount: 1, conditional: false, type: 'Guidance' },
        { amount: 1, conditional: true,  type: 'Racial' }
      ])
    end

    it 'shows the conditional token even with no equipment' do
      allow(described_class).to receive(:equipped_effects).and_return([])
      expect(described_class.save_bonus_tokens(elf, :wis)).to eq([{ amount: 1, conditional: true, type: 'Racial' }])
    end
  end
end

RSpec.describe 'CreatureSheet.defense_breakdown' do
  require 'creature_sheet'
  cond = Struct.new(:mods) { def get_modifiers(key) = mods[key] || [] }

  it 'splits the Armor base from broken-out active-effect tokens' do
    c = cond.new({ 'damage_reduction' => [['Circumstance', 2]] })
    b = CreatureSheet.defense_breakdown(3, c, 'damage_reduction')
    expect(b).to eq(base: 3, tokens: [{ amount: 2, conditional: false }], total: 5)
  end

  it 'folds Inherent Modifiers into the base (kept baked in)' do
    c = cond.new({ 'damage_resilience' => [['Inherent', 1], ['Morale', 2]] })
    b = CreatureSheet.defense_breakdown(3, c, 'damage_resilience')
    expect(b[:base]).to eq(4)
    expect(b[:tokens]).to eq([{ amount: 2, conditional: false }])
    expect(b[:total]).to eq(6)
  end

  it 'returns base-only when there is no Conditions record' do
    expect(CreatureSheet.defense_breakdown(3, nil, 'damage_reduction')).to eq(base: 3, tokens: [], total: 3)
  end
end

RSpec.describe 'Racial resistance abilities are granted' do
  include CreaturesFixtures

  it 'grants poison_resistance to dwarves' do
    names = Creatures::Accessor.new(korth).granted_abilities.map { |g| g[:name] }
    expect(names).to include('poison_resistance')
  end

  it 'grants enchantment_resistance to elves and satyrs' do
    expect(Creatures::Accessor.new(vex).granted_abilities.map { |g| g[:name] }).to include('enchantment_resistance')
    expect(Creatures::Accessor.new(birch).granted_abilities.map { |g| g[:name] }).to include('enchantment_resistance')
  end

  it 'does not grant either resistance to a human' do
    names = Creatures::Accessor.new(record).granted_abilities.map { |g| g[:name] }
    expect(names).not_to include('poison_resistance', 'enchantment_resistance')
  end
end

RSpec.describe 'Effective Attributes fold in item bonuses' do
  include CreaturesFixtures

  it 'adds the CreatureModifiers attribute bonus to attribute_value' do
    allow(CreatureModifiers).to receive(:attribute_bonus).and_return(0)
    intrinsic = Creatures::Accessor.new(korth).attribute_value(:str)

    # A Belt of Strength +4 worth of Guidance on str only.
    allow(CreatureModifiers).to receive(:attribute_bonus) { |_acc, attr| attr == :str ? 4 : 0 }
    boosted = Creatures::Accessor.new(korth)
    expect(boosted.attribute_value(:str)).to eq(intrinsic + 4)
    expect(boosted.attribute_value(:con)).to eq(Creatures::Accessor.new(korth).attribute_value(:con))
  end
end
