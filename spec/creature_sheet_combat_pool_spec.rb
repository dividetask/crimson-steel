require 'spec_helper'
require 'creature_sheet'
require 'encounter'
require_relative 'creatures/fixtures'

# The Character Sheet shows a Creature's Combat Pool — its maximum spendable
# dice on one of its turns — in the Initiative · Combat Pool · Perception ·
# Speed row, with a popup spelling out the two stages behind it
# (creatures_minimal_stub.md § 3; encounter_design.md → "Combat Pool
# computation"). CreatureSheet#vitals supplies both.
RSpec.describe 'CreatureSheet Combat Pool' do
  include CreaturesFixtures

  let(:fighter) do
    Creatures::Accessor.new(
      record(attributes: { str: 16, dex: 12, con: 14, int: 10, wis: 14, cha: 10 },
             classes: { 'fighter' => { level: 4, skills: %w[athletics] } })
    )
  end

  subject(:breakdown) { CreatureSheet.build(fighter)[:vitals][:combat_pool_breakdown] }

  it 'reports the size Encounter computes — the sheet never derives its own' do
    expect(breakdown[:size]).to eq(Encounter::CombatPool.size_for(fighter))
    expect(CreatureSheet.build(fighter)[:vitals][:combat_pool]).to eq(breakdown[:size])
  end

  it 'carries the Budget stage inputs: martial ranks, the Combat Pool Attribute, Turns Per Round' do
    tier = fighter.tier
    expect(breakdown[:martial_ranks]).to eq(fighter.ranks_for('martial'))
    expect(breakdown[:attribute_key]).to eq(Encounter::Config.combat_pool_attribute)
    expect(breakdown[:attribute]).to eq(fighter.attribute_value(Encounter::Config.combat_pool_attribute))
    expect(breakdown[:turns]).to eq(Encounter::Config.turns_for_tier(tier))
    expect(breakdown[:budget]).to eq(
      Encounter::CombatPool.budget(martial_ranks: breakdown[:martial_ranks],
                                   attribute: breakdown[:attribute], tier: tier)
    )
  end

  it 'carries the Buy stage values: the Step and what the size cost' do
    expect(breakdown[:step]).to eq(Encounter::Config.combat_pool_step)
    expect(breakdown[:cost]).to eq(Encounter::CombatPool.cost_to_buy(breakdown[:size], breakdown[:step]))
  end

  it 'carries the sum before the division, so the Budget can split over two lines' do
    expect(breakdown[:before_turns]).to eq((breakdown[:martial_ranks] * 2) + breakdown[:attribute])
    expect(breakdown[:budget]).to eq(breakdown[:before_turns] / breakdown[:turns])
  end

  describe 'the Buy stage price blocks' do
    subject(:blocks) { breakdown[:blocks] }

    it 'covers every die exactly once, in Step-sized blocks' do
      expect(blocks.first[:from]).to eq(1)
      expect(blocks.last[:to]).to eq(breakdown[:size])
      blocks.each_cons(2) { |a, b| expect(b[:from]).to eq(a[:to] + 1) }
      expect(blocks.sum { |b| b[:count] }).to eq(breakdown[:size])
    end

    it 'prices the first block free and each later block one point dearer' do
      expect(blocks.first[:cost_each]).to eq(0)
      blocks.each_with_index { |b, i| expect(b[:cost_each]).to eq(i) }
    end

    it 'spends exactly what Encounter says the Pool costs' do
      expect(blocks.sum { |b| b[:spent] }).to eq(breakdown[:cost])
      blocks.each { |b| expect(b[:spent]).to eq(b[:count] * b[:cost_each]) }
    end

    it 'leaves the final block partial when the Pool stops mid-block' do
      # Pool 13 at Step 4 stops one die into the 13-16 block.
      brk = CreatureSheet.build(
        Creatures::Accessor.new(
          record(attributes: { str: 10, dex: 10, con: 10, int: 10, wis: 12, cha: 10 },
                 tier: 3, classes: { 'fighter' => { level: 5, skills: [] } })
        )
      )[:vitals][:combat_pool_breakdown]
      expect(brk[:size] % brk[:step]).not_to eq(0)
      expect(brk[:blocks].last[:count]).to eq(brk[:size] % brk[:step])
      expect(brk[:blocks].sum { |b| b[:spent] }).to eq(brk[:cost])
    end
  end

  describe 'why the Buy stopped' do
    it 'reports the next die price and the leftover Budget' do
      expect(breakdown[:next_die_cost]).to eq(
        Encounter::CombatPool.cost_to_buy(breakdown[:size] + 1, breakdown[:step]) - breakdown[:cost]
      )
      expect(breakdown[:remaining]).to eq(breakdown[:budget] - breakdown[:cost])
    end

    it 'leaves too little Budget to afford that next die' do
      expect(breakdown[:remaining]).to be < breakdown[:next_die_cost]
      expect(breakdown[:remaining]).to be >= 0
    end
  end

  describe 'the guaranteed minimum' do
    # Points 1..Step are free, so a Creature with no martial ranks and a
    # minimal Combat Pool Attribute still buys the Step floor at zero cost —
    # the popup's Buy line covers the guarantee without a special case.
    let(:commoner) do
      Creatures::Accessor.new(
        record(attributes: { str: 8, dex: 8, con: 8, int: 8, wis: 3, cha: 8 },
               classes: { 'commoner' => { level: 1, skills: [] } })
      )
    end

    it 'never reports a Pool below the Step, and never a cost above the Budget' do
      brk = CreatureSheet.build(commoner)[:vitals][:combat_pool_breakdown]
      expect(brk[:size]).to be >= brk[:step]
      expect(brk[:cost]).to be <= brk[:budget]
    end

    it 'costs nothing for the first Step points' do
      expect(Encounter::CombatPool.cost_to_buy(Encounter::Config.combat_pool_step,
                                               Encounter::Config.combat_pool_step)).to eq(0)
    end
  end
end
