RSpec.describe 'Inflict Affliction' do
  it 'creates a new entry at potency 1 with scheduling' do
    inst = build_instance
    r = inst.inflict_affliction('bleeding', inflicter_tier: 2, current_round: 100)
    expect(r).to include(potency: 1, inflicting_tier: 2, next_resolution_round: 101)
    expect(inst.state.afflictions['bleeding']).to include(potency: 1)
  end

  it 'leaves the schedule null without current_round' do
    inst = build_instance
    inst.inflict_affliction('bleeding', inflicter_tier: 2)
    expect(inst.state.afflictions['bleeding'][:next_resolution_round]).to be_nil
  end

  it 'accumulates Potency without rescheduling' do
    state = build_state(afflictions: { 'bleeding' => { potency: 3, inflicting_tier: 1, next_resolution_round: 47 } })
    inst  = build_instance(state: state)
    inst.inflict_affliction('bleeding', inflicter_tier: 2, delta: 2, current_round: 80)
    expect(inst.state.afflictions['bleeding']).to eq(
      potency: 5, inflicting_tier: 2, next_resolution_round: 47
    )
  end

  it 'never decreases Inflicter Tier' do
    state = build_state(afflictions: { 'bleeding' => { potency: 1, inflicting_tier: 4 } })
    inst  = build_instance(state: state)
    inst.inflict_affliction('bleeding', inflicter_tier: 1)
    expect(inst.state.afflictions['bleeding'][:inflicting_tier]).to eq(4)
    expect(inst.state.afflictions['bleeding'][:potency]).to eq(2)
  end

  it 'raises on unknown Affliction names' do
    inst = build_instance
    expect { inst.inflict_affliction('not_a_real', inflicter_tier: 0) }
      .to raise_error(ArgumentError)
  end

  it 'uses the day frequency for sleeping_sickness' do
    inst = build_instance
    r = inst.inflict_affliction('sleeping_sickness', inflicter_tier: 1, current_round: 100)
    expect(r[:next_resolution_round]).to eq(14500)
  end

  it 're-inflicts after decay at the end of the order with fresh scheduling' do
    state = build_state(afflictions: {
      'bleeding'    => { potency: 1, inflicting_tier: 1, next_resolution_round: 90 },
      'common_venom' => { potency: 2, inflicting_tier: 1, next_resolution_round: 100 }
    })
    inst = build_instance(state: state)
    # Decay bleeding to zero via a successful save at high Tier.
    inst.resolve_affliction('bleeding', { dice_count: 5 }, dois: 5, creature_tier: 3, current_round: 90)
    expect(inst.state.afflictions.keys).to eq(['common_venom'])
    inst.inflict_affliction('bleeding', inflicter_tier: 1, current_round: 200)
    expect(inst.state.afflictions.keys).to eq(['common_venom', 'bleeding'])
    expect(inst.state.afflictions['bleeding'][:next_resolution_round]).to eq(201)
  end
end
