RSpec.describe 'Resolve Affliction' do
  it 'decays Potency by the default tier-based decay on a clean save' do
    state = build_state(afflictions: { 'bleeding' => { potency: 3, inflicting_tier: 1, next_resolution_round: 47 } })
    inst  = build_instance(state: state)
    inst.resolve_affliction('bleeding', { dice_count: 1 }, dois: 0, creature_tier: 3)
    expect(inst.state.afflictions).not_to have_key('bleeding')
  end

  it 'raises Potency on a failure within the global defaults' do
    state = build_state(afflictions: { 'common_venom' => { potency: 2, inflicting_tier: 1 } })
    inst  = build_instance(state: state)
    r = inst.resolve_affliction('common_venom', { dice_count: 1 }, dois: -1, creature_tier: 1)
    # default decay = "tier" → 1; per_failure = 1. Net delta = 0.
    expect(inst.state.afflictions['common_venom'][:potency]).to eq(2)
    expect(r[:net_magnitude]).to eq(1)
  end

  it 'reduces Potency and the effect Net Magnitude on a success' do
    state = build_state(afflictions: { 'bleeding' => { potency: 12, inflicting_tier: 1 } })
    inst  = build_instance(state: state)
    r = inst.resolve_affliction('bleeding', { dice_count: 1 }, dois: 1, creature_tier: 2)
    # bleeding: per_success = "tier" → 2; per_failure = 0; decay = "tier" → 2.
    # delta = -2 - floor(1*2) - 0 = -4. New potency = 8.
    expect(inst.state.afflictions['bleeding'][:potency]).to eq(8)
    expect(r[:magnitude]).to eq(2)
    expect(r[:net_magnitude]).to eq(1)
  end

  it 'is a no-op for the effect on a fully-saved resolution' do
    state = build_state(afflictions: { 'common_venom' => { potency: 1, inflicting_tier: 0 } })
    inst  = build_instance(state: state)
    r = inst.resolve_affliction('common_venom', { dice_count: 1 }, dois: 3, creature_tier: 0)
    expect(r[:net_magnitude]).to eq(0)
    expect(inst.state.hp_damage).to be_empty
  end

  it 'appends the Potency Save Penalty as a Competency entry alongside any existing entry' do
    state = build_state(afflictions: { 'bleeding' => { potency: 25, inflicting_tier: 0 } })
    inst  = build_instance(state: state)
    r = inst.resolve_affliction(
      'bleeding',
      { dice_count: 1, modifiers: [['Competency', -1]] },
      dois: 0, creature_tier: 0
    )
    competency = r[:modified_input][:modifiers].select { |t, _| t == 'Competency' }
    expect(competency).to eq([['Competency', -1], ['Competency', -2]])
  end

  it 'reschedules a survivor when current_round is supplied' do
    state = build_state(afflictions: { 'common_venom' => { potency: 5, inflicting_tier: 1, next_resolution_round: 100 } })
    inst  = build_instance(state: state)
    r = inst.resolve_affliction('common_venom', { dice_count: 1 }, dois: -1, creature_tier: 1, current_round: 100)
    expect(r[:next_resolution_round]).to eq(101)
    expect(inst.state.afflictions['common_venom'][:next_resolution_round]).to eq(101)
  end

  it 'does not reschedule when current_round is omitted' do
    state = build_state(afflictions: { 'common_venom' => { potency: 5, inflicting_tier: 1, next_resolution_round: 100 } })
    inst  = build_instance(state: state)
    inst.resolve_affliction('common_venom', { dice_count: 1 }, dois: -1, creature_tier: 1)
    expect(inst.state.afflictions['common_venom'][:next_resolution_round]).to eq(100)
  end

  it 'discards scheduling on a removed Affliction' do
    state = build_state(afflictions: { 'bleeding' => { potency: 1, inflicting_tier: 0, next_resolution_round: 47 } })
    inst  = build_instance(state: state)
    inst.resolve_affliction('bleeding', { dice_count: 1 }, dois: 0, creature_tier: 3)
    expect(inst.state.afflictions).not_to have_key('bleeding')
  end

  it 'applies floor to Tier 0 substitutions' do
    state = build_state(afflictions: { 'bleeding' => { potency: 1, inflicting_tier: 0 } })
    inst  = build_instance(state: state)
    inst.resolve_affliction('bleeding', { dice_count: 1 }, dois: 1, creature_tier: 0)
    expect(inst.state.afflictions['bleeding'][:potency]).to eq(1)
  end
end
