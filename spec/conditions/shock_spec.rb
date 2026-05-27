RSpec.describe 'Consume Shock' do
  it 'returns the smaller of shock and max_consume' do
    inst = build_instance(state: build_state(shock: 3))
    expect(inst.consume_shock(5)).to eq(3)
    expect(inst.state.shock).to eq(0)
  end

  it 'persists Shock past max_consume' do
    inst = build_instance(state: build_state(shock: 7))
    expect(inst.consume_shock(4)).to eq(4)
    expect(inst.state.shock).to eq(3)
  end

  it 'is a no-op when shock is zero' do
    inst = build_instance
    expect(inst.consume_shock(10)).to eq(0)
    expect(inst.state.shock).to eq(0)
  end

  it 'is a no-op when max_consume is zero' do
    inst = build_instance(state: build_state(shock: 5))
    expect(inst.consume_shock(0)).to eq(0)
    expect(inst.state.shock).to eq(5)
  end
end
