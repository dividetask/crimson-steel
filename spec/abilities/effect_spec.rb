require_relative 'support'

# Effect classification and deferred-damage evaluation.
RSpec.describe 'Abilities.classify_effect' do
  it 'classifies "0" and "none" as none' do
    expect(Abilities.classify_effect('0')).to eq(kind: :none)
    expect(Abilities.classify_effect('none')).to eq(kind: :none)
  end

  it 'classifies a non-damage string as a named effect' do
    expect(Abilities.classify_effect('frightened')).to eq(kind: :effect, name: 'frightened')
  end

  it 'classifies a damage expression, taking severity from the Damage Type when implicit' do
    obj = Abilities.classify_effect('4*rank damage', damage_type: 'fire')
    expect(obj[:kind]).to eq(:damage)
    expect(obj[:formula]).to eq('4*rank')
    expect(obj[:damage_type]).to eq('fire')
    expect(obj[:severity]).to be_nil
  end

  it 'records an explicit inline severity' do
    obj = Abilities.classify_effect('3*rank major damage', damage_type: 'fire')
    expect(obj[:severity]).to eq(:major)
    expect(obj[:formula]).to eq('3*rank')
  end
end

RSpec.describe 'Abilities.evaluate_damage' do
  let(:obj) do
    Abilities.classify_effect('4*rank + 2*success + 3*critical damage',
                              context: { 'rank' => 3, 'tier' => 2 }, damage_type: 'fire')
  end

  it 'applies caller-supplied success and critical' do
    expect(Abilities.evaluate_damage(obj, success: 1, critical: 0)).to eq(14)
  end

  it 'clamps a negative result to zero' do
    neg = Abilities.classify_effect('2 - 5*success damage',
                                    context: {}, damage_type: 'fire')
    expect(Abilities.evaluate_damage(neg, success: 4)).to eq(0)
  end

  it 'exposes attribute inside damage expressions' do
    a = Abilities.classify_effect('attribute/2 + 2 damage', context: {}, damage_type: 'fire')
    expect(Abilities.evaluate_damage(a, attribute: 8)).to eq(6)
  end
end
