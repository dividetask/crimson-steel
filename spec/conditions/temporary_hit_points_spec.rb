RSpec.describe 'Apply Temporary Hit Points' do
  it 'accepts a first grant on an empty slot' do
    inst = build_instance
    r = inst.apply_temporary_hit_points(amount: 6, source_id: 'spell:aid:42')
    expect(r).to eq(accepted: true, displaced_source_id: nil)
    expect(inst.state.temporary_hit_points[:amount]).to eq(6)
  end

  it 'replaces a strictly smaller grant and reports the displaced source' do
    state = build_state(temporary_hit_points: { amount: 4, source_id: 'spell:aid:7' })
    inst  = build_instance(state: state)
    r = inst.apply_temporary_hit_points(amount: 6, source_id: 'spell:aid:42')
    expect(r).to eq(accepted: true, displaced_source_id: 'spell:aid:7')
    expect(inst.state.temporary_hit_points[:amount]).to eq(6)
    expect(inst.state.temporary_hit_points[:source_id]).to eq('spell:aid:42')
  end

  it 'rejects an equal grant' do
    state = build_state(temporary_hit_points: { amount: 4, source_id: 'spell:aid:7' })
    inst  = build_instance(state: state)
    r = inst.apply_temporary_hit_points(amount: 4, source_id: 'spell:aid:42')
    expect(r).to eq(accepted: false, displaced_source_id: nil)
    expect(inst.state.temporary_hit_points[:source_id]).to eq('spell:aid:7')
  end

  it 'rejects a strictly smaller grant' do
    state = build_state(temporary_hit_points: { amount: 4, source_id: 's1' })
    inst  = build_instance(state: state)
    r = inst.apply_temporary_hit_points(amount: 3, source_id: 's2')
    expect(r).to eq(accepted: false, displaced_source_id: nil)
    expect(inst.state.temporary_hit_points[:amount]).to eq(4)
  end

  it 'clears the slot on a zero-or-negative grant' do
    state = build_state(temporary_hit_points: { amount: 4, source_id: 's1' })
    inst  = build_instance(state: state)
    r = inst.apply_temporary_hit_points(amount: 0, source_id: 's2')
    expect(r).to eq(accepted: true, displaced_source_id: 's1')
    expect(inst.state.temporary_hit_points).to be_nil
  end
end
