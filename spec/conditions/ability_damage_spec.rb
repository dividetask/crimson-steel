RSpec.describe 'Ability Damage and Ability Heal' do
  it 'preserves attribute insertion order' do
    inst = build_instance
    inst.apply_ability_damage(:str, minor: 2)
    inst.apply_ability_damage(:dex, minor: 1)
    expect(inst.state.ability_damage[:minor].keys).to eq([:str, :dex])
    inst.apply_ability_damage(:str, minor: 1)
    expect(inst.state.ability_damage[:minor]).to eq(str: 3, dex: 1)
    expect(inst.state.ability_damage[:minor].keys).to eq([:str, :dex])
  end

  it 'heals FIFO within a Severity' do
    inst = build_instance(state: build_state(ability_damage: { minor: { str: 2, dex: 1 } }))
    healed = inst.apply_ability_heal(minor: 2)
    expect(inst.state.ability_damage).to eq(minor: { dex: 1 })
    expect(healed[:minor]).to eq(2)
  end

  it 'cascades worst -> best across Severities' do
    state = build_state(ability_damage: {
      minor: { wis: 2 },
      major: { con: 1 }
    })
    inst = build_instance(state: state)
    healed = inst.apply_ability_heal(minor: 0, moderate: 0, major: 3)
    expect(inst.state.ability_damage).to be_empty
    expect(healed).to eq(major: 1, moderate: 0, minor: 2)
  end

  it 'preserves order of survivors after pruning' do
    state = build_state(ability_damage: { minor: { str: 1, dex: 1, con: 1 } })
    inst  = build_instance(state: state)
    inst.apply_ability_heal(minor: 1)
    expect(inst.state.ability_damage[:minor].keys).to eq([:dex, :con])
  end
end
