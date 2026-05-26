RSpec.describe 'Clear Expired Effects' do
  it 'removes Active Effects past their inclusive expiry' do
    inst = build_instance
    [3, 5, nil, 10].each_with_index do |ends, i|
      inst.apply_effect(
        target_key: 'str', bonus_type: 'Enhancement', amount: i + 1,
        source_id: "e#{i}", ends_on_round: ends
      )
    end
    inst.clear_expired_effects(5)
    expect(inst.state.effects.map { |e| e[:source_id] }).to eq(%w[e2 e3])
  end

  it 'clears expired Temporary HP and discards the absorbed pool' do
    state = build_state(temporary_hit_points: { amount: 6, source_id: 's', ends_on_round: 4 })
    inst  = build_instance(state: state)
    inst.clear_expired_effects(4)
    expect(inst.state.temporary_hit_points).to be_nil
  end

  it 'leaves permanent entries alone' do
    inst = build_instance
    inst.apply_effect(target_key: 'str', bonus_type: 'E', amount: 1, source_id: 'p')
    inst.clear_expired_effects(9999)
    expect(inst.state.effects.size).to eq(1)
  end
end
