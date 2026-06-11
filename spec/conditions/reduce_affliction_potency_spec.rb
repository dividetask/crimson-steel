RSpec.describe 'Reduce Affliction Potency' do
  it 'drains Potency by the amount and reports how much was removed' do
    state = build_state(afflictions: { 'bleeding' => { potency: 5, inflicting_tier: 2, next_resolution_round: 47 } })
    inst  = build_instance(state: state)
    removed = inst.reduce_affliction_potency('bleeding', 3)
    expect(removed).to eq(3)
    expect(inst.state.afflictions['bleeding']).to include(potency: 2)
  end

  it 'removes the Affliction when Potency reaches zero' do
    state = build_state(afflictions: { 'bleeding' => { potency: 2, inflicting_tier: 1 } })
    inst  = build_instance(state: state)
    removed = inst.reduce_affliction_potency('bleeding', 5) # more than present
    expect(removed).to eq(2)                                 # only what was there
    expect(inst.state.afflictions).not_to have_key('bleeding')
  end

  it 'is a no-op for an inactive Affliction or a non-positive amount' do
    inst = build_instance
    expect(inst.reduce_affliction_potency('bleeding', 4)).to eq(0)
    state = build_state(afflictions: { 'bleeding' => { potency: 3, inflicting_tier: 1 } })
    inst2 = build_instance(state: state)
    expect(inst2.reduce_affliction_potency('bleeding', 0)).to eq(0)
    expect(inst2.state.afflictions['bleeding'][:potency]).to eq(3) # unchanged
  end
end
