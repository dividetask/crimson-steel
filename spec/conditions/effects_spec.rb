RSpec.describe 'Apply Effect / Get Modifiers' do
  it 'appends a new entry on Apply Effect' do
    inst = build_instance
    inst.apply_effect(
      target_key: 'str', bonus_type: 'Enhancement', amount: 2,
      source_id: 'spell:bull_strength:7'
    )
    expect(inst.state.effects.size).to eq(1)
    expect(inst.state.effects.first[:ends_on_round]).to be_nil
    expect(inst.state.effects.first[:metadata]).to eq({})
  end

  it 'overwrites in place when the Source ID matches' do
    inst = build_instance
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 2, source_id: 's')
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 4, source_id: 's')
    expect(inst.state.effects.size).to eq(1)
    expect(inst.state.effects.first[:amount]).to eq(4)
  end

  it 'returns the largest positive and most-negative per Bonus Type' do
    inst = build_instance
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement',  amount:  2, source_id: 'a')
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement',  amount:  4, source_id: 'b')
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement',  amount: -1, source_id: 'c')
    inst.apply_effect(target_key: 'str', bonus_type: 'Circumstance', amount:  1, source_id: 'd')
    mods = inst.get_modifiers('str')
    expect(mods).to contain_exactly(
      ['Enhancement', 4], ['Enhancement', -1], ['Circumstance', 1]
    )
  end

  it 'filters by target_key' do
    inst = build_instance
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 2, source_id: 'a')
    inst.apply_effect(target_key: 'dex', bonus_type: 'Enhancement', amount: 1, source_id: 'b')
    expect(inst.get_modifiers('dex')).to eq([['Enhancement', 1]])
  end

  it 'respects expiry inclusively when current_round is supplied' do
    inst = build_instance
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 2, source_id: 'a', ends_on_round: 5)
    expect(inst.get_modifiers('str', current_round: 4)).to eq([['Enhancement', 2]])
    expect(inst.get_modifiers('str', current_round: 5)).to eq([])
    expect(inst.get_modifiers('str')).to eq([['Enhancement', 2]])
  end

  it 'promotes a survivor at lookup time when the stronger is removed' do
    inst = build_instance
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 4, source_id: 'big')
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 2, source_id: 'small')
    expect(inst.get_modifiers('str')).to eq([['Enhancement', 4]])
    inst.remove_effects_by_prefix('big')
    expect(inst.get_modifiers('str')).to eq([['Enhancement', 2]])
  end

  it 'promotes a survivor when the stronger is re-applied at amount 0' do
    inst = build_instance
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 4, source_id: 'big')
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 2, source_id: 'small')
    expect(inst.get_modifiers('str')).to eq([['Enhancement', 4]])
    # Re-applying the same Source ID at amount 0 overwrites in place; an
    # amount of 0 is neither positive nor negative, so it stops contributing.
    inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: 0, source_id: 'big')
    expect(inst.get_modifiers('str')).to eq([['Enhancement', 2]])
  end
end
