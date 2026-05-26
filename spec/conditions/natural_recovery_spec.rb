RSpec.describe 'Apply Natural Recovery' do
  it 'heals Minor at the configured Slow rate at Tier 1' do
    inst = build_instance(state: build_state(hp_damage: { minor: 5, moderate: 5, major: 1 }))
    inst.apply_natural_recovery(
      recovery_ticks: 1, mode: :slow, character_tier: 1,
      mana_max: 8, magic_toxicity_attribute_score: 4
    )
    expect(inst.state.hp_damage).to eq(minor: 4, moderate: 5, major: 1)
  end

  it 'doubles in Fast mode' do
    inst = build_instance(state: build_state(hp_damage: { minor: 5, moderate: 5, major: 1 }))
    inst.apply_natural_recovery(
      recovery_ticks: 1, mode: :fast, character_tier: 1,
      mana_max: 8, magic_toxicity_attribute_score: 4
    )
    expect(inst.state.hp_damage).to eq(minor: 3, moderate: 5, major: 1)
  end

  it 'accumulates across multiple Recovery Ticks' do
    inst = build_instance(state: build_state(hp_damage: { minor: 10 }))
    inst.apply_natural_recovery(
      recovery_ticks: 7, mode: :slow, character_tier: 1,
      mana_max: 0, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.hp_damage[:minor]).to eq(3)
  end

  it 'heals zero when Recovery Ticks < tick_length' do
    inst = build_instance(state: build_state(hp_damage: { minor: 5 }))
    inst.apply_natural_recovery(
      recovery_ticks: 6, mode: :slow, character_tier: 0,
      mana_max: 0, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.hp_damage[:minor]).to eq(5)
  end

  it 'heals one when Recovery Ticks == tick_length' do
    inst = build_instance(state: build_state(hp_damage: { minor: 5 }))
    inst.apply_natural_recovery(
      recovery_ticks: 7, mode: :slow, character_tier: 0,
      mana_max: 0, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.hp_damage[:minor]).to eq(4)
  end

  it 'heals zero Major at Tier 0 in both modes' do
    inst = build_instance(state: build_state(hp_damage: { major: 5 }))
    inst.apply_natural_recovery(
      recovery_ticks: 365, mode: :fast, character_tier: 0,
      mana_max: 0, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.hp_damage[:major]).to eq(5)
  end

  it 'caps healing at the current counter' do
    inst = build_instance(state: build_state(hp_damage: { minor: 2 }))
    inst.apply_natural_recovery(
      recovery_ticks: 1, mode: :fast, character_tier: 5,
      mana_max: 0, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.hp_damage).to be_empty
  end

  it 'restores Mana by floor(mana_max / divisor) per Recovery Tick' do
    inst = build_instance(state: build_state(mana_spent: 8))
    inst.apply_natural_recovery(
      recovery_ticks: 2, mode: :slow, character_tier: 1,
      mana_max: 12, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.mana_spent).to eq(2)
  end

  it 'decays Magic Toxicity by floor(attr / divisor) per Recovery Tick' do
    inst = build_instance(state: build_state(magic_toxicity: 10))
    inst.apply_natural_recovery(
      recovery_ticks: 3, mode: :slow, character_tier: 1,
      mana_max: 0, magic_toxicity_attribute_score: 9
    )
    expect(inst.state.magic_toxicity).to eq(4)
  end

  it 'clears Temporary HP regardless of duration' do
    state = build_state(temporary_hit_points: { amount: 8, source_id: 's' })
    inst  = build_instance(state: state)
    inst.apply_natural_recovery(
      recovery_ticks: 1, mode: :slow, character_tier: 0,
      mana_max: 0, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.temporary_hit_points).to be_nil
  end

  it 'heals Ability Damage FIFO across attributes' do
    state = build_state(ability_damage: { minor: { str: 2, dex: 1 } })
    inst  = build_instance(state: state)
    inst.apply_natural_recovery(
      recovery_ticks: 7, mode: :slow, character_tier: 0,
      mana_max: 0, magic_toxicity_attribute_score: 0
    )
    expect(inst.state.ability_damage[:minor]).to eq(str: 1, dex: 1)
  end
end
