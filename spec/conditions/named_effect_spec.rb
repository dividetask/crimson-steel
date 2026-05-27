RSpec.describe 'Apply Named Effect' do
  it 'stores modifier mechanics as Active Effects with per-mechanic source IDs' do
    inst = build_instance
    ids = inst.apply_named_effect('dazzled', source_id: 'spell:glitterdust:7', ends_on_round: 12)
    expect(ids).to eq(['spell:glitterdust:7:0'])
    effect = inst.state.effects.first
    expect(effect[:bonus_type]).to eq('Circumstance')
    expect(effect[:amount]).to eq(-1)
    expect(effect[:source_id]).to eq('spell:glitterdust:7:0')
    expect(effect[:target_key]).to include('dex_checks')
  end

  it 'raises on unknown Effect Names' do
    inst = build_instance
    expect { inst.apply_named_effect('not_a_real', source_id: 'x') }.to raise_error(ArgumentError)
    expect(inst.state.effects).to be_empty
  end

  it 're-applying the same Effect Name overwrites every Mechanic slot' do
    inst = build_instance
    inst.apply_named_effect('paralyzed', source_id: 'x')
    inst.apply_named_effect('paralyzed', source_id: 'x')
    source_ids = inst.state.effects.map { |e| e[:source_id] } +
                 inst.state.named_effect_mechanics.map { |m| m[:source_id] }
    expect(source_ids).to contain_exactly(*source_ids.uniq)
  end

  it 'dispatches affliction-triggered Named Effects with a deterministic Source ID' do
    state = build_state(afflictions: { 'ghoul_paralysis' => { potency: 1, inflicting_tier: 1 } })
    inst  = build_instance(state: state)
    inst.resolve_affliction('ghoul_paralysis', { dice_count: 1 }, dois: 0, creature_tier: 0, current_round: 50)
    source_ids = inst.state.named_effect_mechanics.map { |m| m[:source_id] }
    expect(source_ids).to all(start_with('affliction:ghoul_paralysis:'))
  end
end
