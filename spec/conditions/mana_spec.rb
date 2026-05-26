RSpec.describe 'Mana operations' do
  it 'increments mana_spent up to Mana Max' do
    inst = build_instance
    expect(inst.apply_mana_cost(amount: 3, mana_max: 10)).to eq(3)
    expect(inst.state.mana_spent).to eq(3)
  end

  it 'returns the actual spend when amount exceeds available' do
    inst = build_instance(state: build_state(mana_spent: 8))
    expect(inst.apply_mana_cost(amount: 5, mana_max: 10)).to eq(2)
    expect(inst.state.mana_spent).to eq(10)
  end

  it 'restores Mana toward zero' do
    inst = build_instance(state: build_state(mana_spent: 5))
    expect(inst.restore_mana(3)).to eq(3)
    expect(inst.state.mana_spent).to eq(2)
  end

  it 'floors Restore Mana at zero' do
    inst = build_instance(state: build_state(mana_spent: 2))
    expect(inst.restore_mana(5)).to eq(2)
    expect(inst.state.mana_spent).to eq(0)
  end

  it 'clamps Set Mana Spent into [0, mana_max]' do
    inst = build_instance(state: build_state(mana_spent: 5))
    inst.set_mana_spent(amount: 100, mana_max: 12)
    expect(inst.state.mana_spent).to eq(12)
    inst.set_mana_spent(amount: -3, mana_max: 12)
    expect(inst.state.mana_spent).to eq(0)
  end
end
