require_relative 'support'

# Variant lookup and per-Ability resolution (range / activation / target),
# exercised against the shipped catalog plus a few inline edge cases.
RSpec.describe 'Abilities.lookup' do
  it 'picks the Tier-axis Variant, applies the suffix, and substitutes the Effect Hash' do
    heal = Abilities.lookup('Heal', axis_index: 2)
    expect(heal['name']).to eq('Heal Simple Wounds')
    expect(heal['tier']).to eq(2)
    expect(heal['effect_hash']['minor_damage']).to eq(8)
    expect(heal['description']).to include('8 minor damage', '4 moderate damage')
  end

  it 'applies a prefix on a Tier-axis Variant' do
    expect(Abilities.lookup('Ward', axis_index: 2)['name']).to eq('Standard Ward')
  end

  it 'scales the Shield spell by Tier — range widens and its block bonus grows' do
    tier0 = Abilities.lookup('Shield', axis_index: 0)
    tier1 = Abilities.lookup('Shield', axis_index: 1)
    tier2 = Abilities.lookup('Shield', axis_index: 2)
    expect([tier0['name'], tier1['name'], tier2['name']]).to eq(%w[Shield Shield Shield])
    expect([tier0['range'], tier1['range'], tier2['range']]).to eq(%w[Self Close Medium])
    expect([tier0['shield_bonus'], tier1['shield_bonus'], tier2['shield_bonus']]).to eq([0, 1, 2])
    # The shield is a caster-controlled reservoir block that defends the target.
    expect(tier1.dig('reservoir', 'discharge', 'defends')).to eq('target')
    expect(tier1['duration']).to eq('rank minutes')
  end

  it 'uses the per-Variant name list and substitutes {aspect} on an Aspect-axis Spell' do
    dart = Abilities.lookup('Elemental Dart', axis_index: 1)
    expect(dart['name']).to eq('Acid Dart')
    expect(dart['damage_type']).to eq('acid')
    expect(dart['description']).to start_with('A ranged dart of acid.')
    expect(dart['channel']['description']).to eq('Throw acid dart at any valid target within range.')
  end

  it 'appends universal casting skills and item forms to a Spell' do
    heal = Abilities.lookup('Heal', axis_index: 0)
    expect(heal['skills']).to include('evocation')
    expect(heal['items']).to include('scroll', 'wand')
  end

  it 'raises on an out-of-range axis_index' do
    expect { Abilities.lookup('Heal', axis_index: 99) }.to raise_error(IndexError)
  end

  it 'returns nil for an unknown name' do
    expect(Abilities.lookup('No Such Ability')).to be_nil
  end

  describe 'Variant Overrides' do
    let(:resolver) do
      build_ability_resolver('Base' => {
                       'type' => 'spell', 'duration' => 'rank minutes',
                       'tier' => [0, 1, 2],
                       'variant_overrides' => [nil, { 'duration' => 'rank hours' }, { 'duration' => nil }]
                     })
    end

    it 'keeps the base value, replaces it, and removes it across Variants' do
      expect(resolver.resolve('Base', axis_index: 0)['duration']).to eq('rank minutes')
      expect(resolver.resolve('Base', axis_index: 1)['duration']).to eq('rank hours')
      expect(resolver.resolve('Base', axis_index: 2)).not_to have_key('duration')
    end
  end
end

RSpec.describe 'Abilities.resolve_range' do
  it 'returns a bare integer range as-is' do
    r = build_ability_resolver('R' => { 'type' => 'spell', 'range' => 1000 })
    expect(r.resolve_range(r.resolve('R'))).to eq(1000)
  end

  it 'evaluates a named range formula against rank' do
    expect(Abilities.resolve_range('Elemental Dart', axis_index: 1, rank: 0)).to eq(5)
    expect(Abilities.resolve_range('Elemental Dart', axis_index: 1, rank: 3)).to eq(20)
  end

  it 'uses Default Reach Feet for Touch when no reach is supplied' do
    expect(Abilities.resolve_range('Heal', axis_index: 0)).to eq(5)
    expect(Abilities.resolve_range('Heal', axis_index: 0, reach: 10)).to eq(10)
  end
end

RSpec.describe 'Abilities.resolve_activation' do
  it 'resolves an Action Alias to an action result' do
    expect(Abilities.resolve_activation('Heal')).to eq(kind: :action, alias: 'main', value: 0.5)
  end

  it 'resolves a reaction activation' do
    expect(Abilities.resolve_activation('Healing Word')).to eq(kind: :action, alias: 'reaction', value: 0.1)
  end

  it 'parses an explicit "<N> turns" string' do
    r = build_ability_resolver('T' => { 'type' => 'spell', 'activation_time' => '3 turns' })
    expect(r.resolve_activation(r.resolve('T'))).to eq(kind: :turns, turns: 3)
  end
end

RSpec.describe 'Abilities.resolve_target' do
  it 'returns an integer string target as an integer' do
    expect(Abilities.resolve_target('Heal', axis_index: 0)).to eq(1)
  end

  it 'evaluates a formula target against rank' do
    r = build_ability_resolver('F' => { 'type' => 'spell', 'target' => '1+rank' })
    expect(r.resolve_target(r.resolve('F'), rank: 3)).to eq(4)
  end

  it 'returns self verbatim' do
    r = build_ability_resolver('S' => { 'type' => 'spell', 'target' => 'self' })
    expect(r.resolve_target(r.resolve('S'))).to eq('self')
  end
end
