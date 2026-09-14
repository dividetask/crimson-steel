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
