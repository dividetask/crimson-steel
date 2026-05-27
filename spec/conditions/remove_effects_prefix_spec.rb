RSpec.describe 'Remove Effects by Prefix' do
  it 'removes every Effect whose source_id starts with the prefix' do
    inst = build_instance
    %w[equipment:char_42:belt:body equipment:char_42:ring:hand
       equipment:char_99:cloak:body spell:aid:7].each_with_index do |id, i|
      inst.apply_effect(target_key: 'str', bonus_type: 'Enhancement', amount: i + 1, source_id: id)
    end
    removed = inst.remove_effects_by_prefix('equipment:char_42:')
    expect(removed.map { |e| e[:source_id] }).to eq(%w[equipment:char_42:belt:body equipment:char_42:ring:hand])
    expect(inst.state.effects.map { |e| e[:source_id] }).to eq(%w[equipment:char_99:cloak:body spell:aid:7])
  end

  it 'matches literally — no globbing' do
    inst = build_instance
    inst.apply_effect(target_key: 's', bonus_type: 'E', amount: 1, source_id: 'equipment:char_42')
    inst.apply_effect(target_key: 's', bonus_type: 'E', amount: 1, source_id: 'equipment:char_42:belt')
    removed = inst.remove_effects_by_prefix('equipment:char_42:')
    expect(removed.map { |e| e[:source_id] }).to eq(['equipment:char_42:belt'])
  end

  it 'returns an empty list when nothing matches' do
    inst = build_instance
    inst.apply_effect(target_key: 's', bonus_type: 'E', amount: 1, source_id: 'spell:aid:7')
    expect(inst.remove_effects_by_prefix('equipment:')).to eq([])
    expect(inst.state.effects.size).to eq(1)
  end
end
