RSpec.describe 'Apply Heal' do
  it 'heals at one Severity without cascading' do
    inst = build_instance(state: build_state(hp_damage: { minor: 3, moderate: 2, major: 1 }))
    healed = inst.apply_heal(minor: 2, moderate: 0, major: 0)
    expect(inst.state.hp_damage).to eq(minor: 1, moderate: 2, major: 1)
    expect(healed).to eq(minor: 2, moderate: 0, major: 0)
  end

  it 'flows worst -> best when cascading' do
    inst = build_instance(state: build_state(hp_damage: { minor: 1, major: 1 }))
    healed = inst.apply_heal(minor: 0, moderate: 0, major: 3)
    expect(inst.state.hp_damage).to be_empty
    expect(healed).to eq(major: 1, moderate: 0, minor: 1)
  end

  it 'wastes excess past Minor' do
    inst = build_instance(state: build_state(hp_damage: { minor: 1 }))
    healed = inst.apply_heal(minor: 5, moderate: 0, major: 0)
    expect(inst.state.hp_damage).to be_empty
    expect(healed).to eq(minor: 1, moderate: 0, major: 0)
  end

  it 'does not touch Temporary HP' do
    state = build_state(hp_damage: { minor: 2 }, temporary_hit_points: { amount: 4, source_id: 's' })
    inst  = build_instance(state: state)
    inst.apply_heal(minor: 2)
    expect(inst.state.hp_damage).to be_empty
    expect(inst.state.temporary_hit_points[:amount]).to eq(4)
  end

  it 'does not impose Magic Toxicity' do
    inst = build_instance
    inst.apply_heal(minor: 4, moderate: 4, major: 4)
    expect(inst.state.magic_toxicity).to eq(0)
  end
end
