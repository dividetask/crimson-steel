RSpec.describe 'Conditions::State serialization' do
  it 'round-trips a populated State' do
    state = build_state(
      hp_damage: { minor: 3, major: 1 },
      ability_damage: { minor: { str: 1 } },
      temporary_hit_points: { amount: 4, source_id: 'spell:s', ends_on_round: 50 },
      mana_spent: 2,
      magic_toxicity: 5,
      shock: 1,
      acid_counter: 7,
      afflictions: {
        'bleeding'    => { potency: 2, inflicting_tier: 1, next_resolution_round: 50 },
        'common_venom' => { potency: 1, inflicting_tier: 2 }
      },
      effects: [
        { target_key: 'str', bonus_type: 'Enhancement', amount: 2, source_id: 'a' },
        { target_key: 'dex', bonus_type: 'Circumstance', amount: -1, source_id: 'b' }
      ]
    )
    h = state.to_h
    loaded = Conditions::State.load(h)
    expect(loaded.to_h).to eq(h)
    expect(loaded.afflictions.keys).to eq(state.afflictions.keys)
    expect(loaded.effects.map { |e| e[:source_id] }).to eq(%w[a b])
  end

  it 'rejects malformed input' do
    expect { Conditions::State.load('hp_damage' => { 'minor' => -1 }) }
      .to raise_error(ArgumentError)
    expect { Conditions::State.load('hp_damage' => { 'wat' => 1 }) }
      .to raise_error(ArgumentError)
  end

  it 'accepts a missing next_resolution_round' do
    state = Conditions::State.load(
      'afflictions' => { 'bleeding' => { 'potency' => 1, 'inflicting_tier' => 1 } }
    )
    expect(state.afflictions['bleeding'][:next_resolution_round]).to be_nil
  end

  it 'fills defaults for an empty input dict' do
    state = Conditions::State.load({})
    expect(state.hp_damage).to be_empty
    expect(state.ability_damage).to be_empty
    expect(state.temporary_hit_points).to be_nil
    expect(state.mana_spent).to eq(0)
    expect(state.magic_toxicity).to eq(0)
    expect(state.shock).to eq(0)
    expect(state.acid_counter).to eq(0)
    expect(state.afflictions).to be_empty
    expect(state.effects).to be_empty
  end

  it 'fills defaults for omitted Active Effect fields' do
    state = Conditions::State.load(
      'effects' => [{ 'target_key' => 'str', 'bonus_type' => 'E', 'amount' => 1, 'source_id' => 'a' }]
    )
    expect(state.effects.first[:ends_on_round]).to be_nil
    expect(state.effects.first[:metadata]).to eq({})
  end

  it 'fills defaults for omitted Temporary HP fields' do
    state = Conditions::State.load(
      'temporary_hit_points' => { 'amount' => 4, 'source_id' => 's' }
    )
    expect(state.temporary_hit_points[:ends_on_round]).to be_nil
  end
end
