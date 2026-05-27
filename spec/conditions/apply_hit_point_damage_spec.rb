RSpec.describe 'Apply Hit Point Damage' do
  it 'lands directly on counters when no Temporary HP grant exists' do
    inst = build_instance
    inst.apply_hit_point_damage(minor: 2, moderate: 1, major: 0)
    expect(inst.state.hp_damage).to eq(minor: 2, moderate: 1)
    expect(inst.state.temporary_hit_points).to be_nil
  end

  it 'absorbs worst-first against Temporary HP' do
    state = build_state(temporary_hit_points: { amount: 5, source_id: 'spell:aid:42' })
    inst  = build_instance(state: state)
    result = inst.apply_hit_point_damage(minor: 0, moderate: 0, major: 3)
    expect(inst.state.hp_damage).to be_empty
    expect(inst.state.temporary_hit_points[:amount]).to eq(2)
    expect(result[:displaced_source_id]).to be_nil
  end

  it 'clears the grant when the pool is depleted exactly' do
    state = build_state(temporary_hit_points: { amount: 5, source_id: 'spell:aid:42' })
    inst  = build_instance(state: state)
    result = inst.apply_hit_point_damage(minor: 0, moderate: 0, major: 5)
    expect(inst.state.hp_damage).to be_empty
    expect(inst.state.temporary_hit_points).to be_nil
    expect(result[:displaced_source_id]).to eq('spell:aid:42')
  end

  it 'consumes the pool worst-first; per-category absorption does not redistribute' do
    state = build_state(temporary_hit_points: { amount: 3, source_id: 's' })
    inst  = build_instance(state: state)
    inst.apply_hit_point_damage(minor: 0, moderate: 5, major: 1)
    expect(inst.state.hp_damage).to eq(moderate: 3)
    expect(inst.state.temporary_hit_points).to be_nil
  end

  it 'splits damage exceeding the pool across categories' do
    state = build_state(temporary_hit_points: { amount: 2, source_id: 's' })
    inst  = build_instance(state: state)
    inst.apply_hit_point_damage(minor: 1, moderate: 0, major: 4)
    expect(inst.state.hp_damage).to eq(minor: 1, major: 2)
    expect(inst.state.temporary_hit_points).to be_nil
  end

  it 'is a no-op for zero damage' do
    state = build_state(temporary_hit_points: { amount: 4, source_id: 's' })
    inst  = build_instance(state: state)
    inst.apply_hit_point_damage(minor: 0, moderate: 0, major: 0)
    expect(inst.state.hp_damage).to be_empty
    expect(inst.state.temporary_hit_points[:amount]).to eq(4)
  end
end
