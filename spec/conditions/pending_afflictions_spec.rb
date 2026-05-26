RSpec.describe 'List / Resolve Due Afflictions' do
  let(:starting_state) do
    build_state(afflictions: {
      'bleeding'     => { potency: 1, inflicting_tier: 1, next_resolution_round: 100 },
      'common_venom' => { potency: 1, inflicting_tier: 1, next_resolution_round: 105 },
      'sleep_venom'  => { potency: 1, inflicting_tier: 1, next_resolution_round: 100 }
    })
  end

  it 'returns due Afflictions in insertion order' do
    inst = build_instance(state: starting_state)
    expect(inst.list_pending_afflictions(100)).to eq(%w[bleeding sleep_venom])
  end

  it 'filters out Afflictions with null scheduling' do
    state = build_state(afflictions: {
      'bleeding'     => { potency: 1, inflicting_tier: 1, next_resolution_round: nil },
      'common_venom' => { potency: 1, inflicting_tier: 1, next_resolution_round: 50 }
    })
    inst = build_instance(state: state)
    expect(inst.list_pending_afflictions(100)).to eq(['common_venom'])
  end

  it 'dispatches per-Affliction Save Inputs and reschedules survivors' do
    state = build_state(afflictions: {
      'bleeding'     => { potency: 5, inflicting_tier: 1, next_resolution_round: 100 },
      'common_venom' => { potency: 5, inflicting_tier: 1, next_resolution_round: 100 }
    })
    inst = build_instance(state: state)
    results = inst.resolve_due_afflictions(current_round: 100, creature_tier: 0) do |name|
      { save_input: { dice_count: 1, name: name }, dois: 0 }
    end
    expect(results.size).to eq(2)
    inst.state.afflictions.each_value do |a|
      expect(a[:next_resolution_round]).to eq(101)
    end
  end

  it 'sees Afflictions inflicted mid-call' do
    state = build_state(afflictions: { 'bleeding' => { potency: 1, inflicting_tier: 1, next_resolution_round: 100 } })
    inst  = build_instance(state: state)
    seen = []
    inst.resolve_due_afflictions(current_round: 100, creature_tier: 0) do |name|
      seen << name
      if name == 'bleeding'
        inst.inflict_affliction('common_venom', inflicter_tier: 1, current_round: 99)
      end
      { save_input: { dice_count: 1 }, dois: 0 }
    end
    expect(seen).to eq(['bleeding', 'common_venom'])
  end

  it 'returns an empty list when nothing is due' do
    inst = build_instance(state: starting_state)
    expect(inst.list_pending_afflictions(50)).to eq([])
    expect(inst.resolve_due_afflictions(current_round: 50) { { save_input: {}, dois: 0 } }).to eq([])
  end
end
