RSpec.describe 'Acid Counter' do
  it 'adds to the counter on Apply Acid Damage' do
    inst = build_instance
    expect(inst.apply_acid_damage(7)).to eq(7)
    expect(inst.state.acid_counter).to eq(7)
  end

  it 'is a no-op for zero or negative amounts' do
    inst = build_instance(state: build_state(acid_counter: 5))
    expect(inst.apply_acid_damage(0)).to eq(5)
    expect(inst.apply_acid_damage(-3)).to eq(5)
    expect(inst.state.acid_counter).to eq(5)
  end

  it 'halves then deals on Resolve Acid Turn Start' do
    inst = build_instance(state: build_state(acid_counter: 7))
    expect(inst.resolve_acid_turn_start).to eq(3)
    expect(inst.state.acid_counter).to eq(3)
    expect(inst.state.hp_damage[:minor]).to eq(3)
  end

  it 'clears the counter when it drops to zero' do
    inst = build_instance(state: build_state(acid_counter: 1))
    expect(inst.resolve_acid_turn_start).to eq(0)
    expect(inst.state.acid_counter).to eq(0)
    expect(inst.state.hp_damage).to be_empty
  end
end
