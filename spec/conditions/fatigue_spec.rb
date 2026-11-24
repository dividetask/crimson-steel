# Fatigue track and Unconscious (conditions_effect_names.yaml).
RSpec.describe 'Fatigue track' do
  def fatigue(inst, stage = 'winded')
    inst.apply_named_effect(stage, source_id: "test:1:x:#{stage}", ends_on_round: 50)
  end

  it 'moves up one stage each time fatigue is gained' do
    inst = build_instance
    fatigue(inst)
    expect(inst.fatigue_stage).to eq('winded')
    fatigue(inst)
    expect(inst.fatigue_stage).to eq('tired')
    expect(inst.active_effect_names).to eq(['tired'])
  end

  it 'goes straight to a higher stage, and adds unconscious when already exhausted' do
    inst = build_instance
    fatigue(inst)
    fatigue(inst, 'exhausted')
    expect(inst.fatigue_stage).to eq('exhausted')
    fatigue(inst)
    expect(inst.active_effect_names).to contain_exactly('exhausted', 'unconscious')
    expect(inst.cannot_act_effect?).to be(true)
  end

  it 'reduces Strength, Combat Pool and speed by 25/50/75%, rounding the reduction down' do
    inst = build_instance
    fatigue(inst)
    expect(inst.adjusted_value(:str, 15)).to eq(12)
    expect(inst.adjusted_value(:speed, 30)).to eq(23)
    fatigue(inst)
    expect(inst.adjusted_value(:combat_pool, 15)).to eq(8)
    fatigue(inst)
    expect(inst.adjusted_value(:str, 21)).to eq(6)
    expect(inst.adjusted_value(:dex, 14)).to eq(14)
  end

  it 'sets Strength, Dexterity, Wisdom, Intelligence and the Combat Pool to 0 while unconscious' do
    inst = build_instance
    inst.apply_named_effect('unconscious', source_id: 'test:1:x:unconscious')
    expect(%i[str dex wis int con cha].map { |a| inst.adjusted_value(a, 14) }).to eq([0, 0, 0, 0, 14, 14])
    fatigue(inst, 'exhausted')
    expect(inst.adjusted_value(:combat_pool, 16)).to eq(0)
  end
end
