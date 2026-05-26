RSpec.describe 'Dead?' do
  it 'triggers death on the HP track at the threshold' do
    state = build_state(hp_damage: { minor: 10, moderate: 15, major: 15 })
    inst  = build_instance(state: state)
    expect(inst.dead?(max_hit_points: 20, attribute_scores: {}, toxicity_threshold: 100)).to eq(true)

    state = build_state(hp_damage: { minor: 10, moderate: 15, major: 14 })
    inst  = build_instance(state: state)
    expect(inst.dead?(max_hit_points: 20, attribute_scores: {}, toxicity_threshold: 100)).to eq(false)
  end

  it 'scales by fractional Death Multiplier' do
    catalog = build_catalog
    catalog.config['Death Multiplier'] = 1.5
    state = build_state(hp_damage: { minor: 30 })
    inst  = build_instance(state: state, catalog: catalog)
    expect(inst.dead?(max_hit_points: 20, attribute_scores: {}, toxicity_threshold: 100)).to eq(true)
    state2 = build_state(hp_damage: { minor: 29 })
    inst2  = build_instance(state: state2, catalog: catalog)
    expect(inst2.dead?(max_hit_points: 20, attribute_scores: {}, toxicity_threshold: 100)).to eq(false)
  end

  it 'triggers on any single attribute crossing its threshold' do
    state = build_state(ability_damage: { minor: { str: 5 }, moderate: { str: 5 } })
    inst  = build_instance(state: state)
    expect(inst.dead?(max_hit_points: 100, attribute_scores: { str: 5, dex: 100 }, toxicity_threshold: 100)).to eq(true)
  end

  it 'triggers on the Toxicity track at the threshold' do
    inst = build_instance(state: build_state(magic_toxicity: 8))
    expect(inst.dead?(max_hit_points: 100, attribute_scores: {}, toxicity_threshold: 4)).to eq(true)
    inst2 = build_instance(state: build_state(magic_toxicity: 7))
    expect(inst2.dead?(max_hit_points: 100, attribute_scores: {}, toxicity_threshold: 4)).to eq(false)
  end

  it 'is a disjunction over the three tracks' do
    state = build_state(hp_damage: { minor: 35 }, magic_toxicity: 8)
    inst  = build_instance(state: state)
    expect(inst.dead?(max_hit_points: 20, attribute_scores: {}, toxicity_threshold: 4)).to eq(true)
  end
end
