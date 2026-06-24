require 'spec_helper'
require 'encounter/affliction_relief'

RSpec.describe Encounter::AfflictionRelief do
  # A standard round-based bleed save blob (5 dice, d6), divisor 10.
  def bleed_save(creature_tier:, inflicter_tier: 1)
    { save_dice: 5, die_size: 6, save_modifiers: [],
      potency_divisor: 10, creature_tier: creature_tier, inflicter_tier: inflicter_tier }
  end

  def with_bleed(potency:, inflicter_tier: 1)
    inst = build_instance
    inst.inflict_affliction('bleeding', inflicter_tier: inflicter_tier, delta: potency, current_round: 0)
    inst
  end

  it 'fast-forwards a Tier-2 bleed to zero and reports rounds + HP taken' do
    inst = with_bleed(potency: 6)
    out = described_class.run(
      instance: inst, affliction_name: 'bleeding', creature_tier: 2,
      save: bleed_save(creature_tier: 2), rng: Random.new(1)
    )
    expect(out[:cleared]).to be(true)
    expect(inst.state.afflictions).not_to have_key('bleeding')
    expect(out[:rounds]).to be > 0
    # The bleed dealt some Minor HP damage along the way (never moderate/major).
    expect(out[:hp_damage][:minor]).to be >= 0
    expect(out[:hp_damage][:moderate]).to eq(0)
    expect(out[:hp_damage][:major]).to eq(0)
    expect(out[:log].size).to eq(out[:rounds])
  end

  it 'an aider channeling Heal twice per round clots faster and spends its cast mana once' do
    aided = described_class.run(
      instance: with_bleed(potency: 12), affliction_name: 'bleeding', creature_tier: 1,
      save: bleed_save(creature_tier: 1), rng: Random.new(7),
      aiders: [{ id: 99, name: 'Cleric', spell_tier: 2, heal_dice: 5, die_size: 6,
                 heal_modifiers: [], mana_cost: 6 }]
    )
    solo = described_class.run(
      instance: with_bleed(potency: 12), affliction_name: 'bleeding', creature_tier: 1,
      save: bleed_save(creature_tier: 1), rng: Random.new(7)
    )
    expect(aided[:cleared]).to be(true)
    expect(aided[:rounds]).to be <= solo[:rounds]
    # Mana is the one-time Tier-2 Heal cast cost (6), no matter how many
    # rounds/channels the relief took.
    expect(aided[:aider_mana][99]).to eq(6)
  end

  it 'is deterministic for a given RNG seed' do
    a = described_class.run(instance: with_bleed(potency: 8), affliction_name: 'bleeding',
                            creature_tier: 2, save: bleed_save(creature_tier: 2), rng: Random.new(42))
    b = described_class.run(instance: with_bleed(potency: 8), affliction_name: 'bleeding',
                            creature_tier: 2, save: bleed_save(creature_tier: 2), rng: Random.new(42))
    expect(a[:rounds]).to eq(b[:rounds])
    expect(a[:hp_damage]).to eq(b[:hp_damage])
  end

  it 'a Tier-0 Heal still reduces potency (Tier 0 counts as 0.5, so 1 per success)' do
    # Pin the heal roll high: many dice at a low TN guarantee successes, and a
    # Tier-0 channel must still drain Potency (0.5 * 2 * successes, floored).
    inst = with_bleed(potency: 30)
    out = described_class.run(
      instance: inst, affliction_name: 'bleeding', creature_tier: 1,
      save: bleed_save(creature_tier: 1), rng: Random.new(2),
      aiders: [{ id: 5, name: 'Acolyte', spell_tier: 0, heal_dice: 6, die_size: 6,
                 heal_modifiers: [], mana_cost: 1 }]
    )
    heal_drops = out[:log].flat_map { |e| e[:rolls] }
                          .select { |r| r[:kind] == 'heal' && r[:successes].positive? }
    expect(heal_drops).not_to be_empty
    expect(heal_drops).to all(satisfy { |r| r[:potency_after] < r[:potency_before] })
  end

  it 'stops when the bleed would kill the Creature (death threshold)' do
    inst = with_bleed(potency: 40, inflicter_tier: 3)
    out = described_class.run(
      instance: inst, affliction_name: 'bleeding', creature_tier: 0,
      save: bleed_save(creature_tier: 0, inflicter_tier: 3),
      death_threshold: 6, rng: Random.new(1), max_rounds: 50
    )
    expect(out[:died]).to be(true)
    expect(out[:cleared]).to be(false)
    expect(out[:hp_damage].values.sum).to be >= 6
    # It halts at death, well short of the safety cap.
    expect(out[:rounds]).to be < 50
  end

  it 'stops at the safety cap when a Tier-0 bleed can never clot unaided' do
    inst = with_bleed(potency: 5)
    out = described_class.run(
      instance: inst, affliction_name: 'bleeding', creature_tier: 0,
      save: bleed_save(creature_tier: 0), rng: Random.new(3), max_rounds: 12
    )
    # Tier 0 clots by 0.5/success (floors to 0), so the save never reduces it;
    # with no aid the loop bottoms out at the cap rather than spinning forever.
    expect(out[:rounds]).to eq(12)
    expect(out[:cleared]).to be(false)
  end
end
