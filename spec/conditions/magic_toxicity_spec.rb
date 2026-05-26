RSpec.describe 'Apply Magic Toxicity' do
  it 'applies a positive effect below threshold without damage' do
    inst = build_instance(state: build_state(magic_toxicity: 4))
    r = inst.apply_magic_toxicity(amount: 3, kind: :positive, charisma: 5, tier: 2)
    expect(r).to eq(accepted: true, charisma_damage: 0)
    expect(inst.state.magic_toxicity).to eq(7)
    expect(inst.state.ability_damage).to be_empty
  end

  it 'deals damage for the overshoot when crossing threshold' do
    inst = build_instance(state: build_state(magic_toxicity: 8))
    r = inst.apply_magic_toxicity(amount: 5, kind: :positive, charisma: 5, tier: 2)
    expect(r).to eq(accepted: true, charisma_damage: 3)
    expect(inst.state.magic_toxicity).to eq(13)
    expect(inst.state.ability_damage[:major][:cha]).to eq(3)
  end

  it 'blocks positive effects when current strictly exceeds threshold' do
    inst = build_instance(state: build_state(magic_toxicity: 11))
    r = inst.apply_magic_toxicity(amount: 4, kind: :positive, charisma: 5, tier: 2)
    expect(r).to eq(accepted: false, charisma_damage: 0)
    expect(inst.state.magic_toxicity).to eq(11)
  end

  it 'allows positive at exactly threshold' do
    inst = build_instance(state: build_state(magic_toxicity: 10))
    r = inst.apply_magic_toxicity(amount: 1, kind: :positive, charisma: 5, tier: 2)
    expect(r).to eq(accepted: true, charisma_damage: 1)
    expect(inst.state.magic_toxicity).to eq(11)
  end

  it 'never blocks forced toxicity' do
    inst = build_instance(state: build_state(magic_toxicity: 25))
    r = inst.apply_magic_toxicity(amount: 4, kind: :forced, charisma: 5, tier: 2)
    expect(r).to eq(accepted: true, charisma_damage: 4)
    expect(inst.state.magic_toxicity).to eq(29)
  end

  it 'honors Tier Scaled false' do
    catalog = build_catalog
    catalog.config['Toxicity Threshold'] = { 'Attribute' => 'cha', 'Tier Scaled' => false }
    inst = build_instance(catalog: catalog)
    expect(inst.toxicity_threshold(9, 3)).to eq(9)
  end

  it 'uses the 0.5 substitution for Tier 0' do
    inst = build_instance
    expect(inst.toxicity_threshold(8, 0)).to eq(4)
  end

  it 'is structurally a no-op for amount = 0' do
    inst = build_instance(state: build_state(magic_toxicity: 2))
    r = inst.apply_magic_toxicity(amount: 0, kind: :positive, charisma: 10, tier: 1)
    expect(r).to eq(accepted: true, charisma_damage: 0)
    expect(inst.state.magic_toxicity).to eq(2)
  end
end
