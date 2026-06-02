require_relative 'support'

# Resolve a Spell for item consumption — the Equipment-facing view.
# Covered against both inline Spells (precise control of the Effect Hash)
# and the real shipped catalog (integration with actual data).
RSpec.describe 'Abilities#resolve_spell' do
  describe 'inline Spells' do
    def resolver_for(entry)
      r = build_ability_resolver('Test' => entry)
      r
    end

    it 'emits negated Severity magnitudes for a positive (cure) Spell' do
      r = resolver_for(
        'type' => 'spell', 'polarity' => 'positive',
        'effect_hash' => { 'minor_damage' => 8, 'moderate_damage' => 4, 'major_damage' => 0 }
      )
      result = r.resolve_spell('Test')
      expect(result[:polarity]).to eq(:positive)
      expect(result[:effects]).to eq([{ 'minor_damage' => -8, 'moderate_damage' => -4 }])
    end

    it 'keeps positive Severity magnitudes for a forced (attack) Spell' do
      r = resolver_for(
        'type' => 'spell', 'polarity' => 'forced',
        'effect_hash' => { 'minor_damage' => 6 }
      )
      expect(r.resolve_spell('Test')[:effects]).to eq([{ 'minor_damage' => 6 }])
    end

    it 'emits temp_hp from the Effect Hash' do
      r = resolver_for('type' => 'spell', 'polarity' => 'positive',
                       'effect_hash' => { 'temp_hp' => 8 })
      expect(r.resolve_spell('Test')[:effects]).to eq([{ 'temp_hp' => 8 }])
    end

    it 'emits mana from the Effect Hash' do
      r = resolver_for('type' => 'spell', 'polarity' => 'positive',
                       'effect_hash' => { 'mana' => 16 })
      expect(r.resolve_spell('Test')[:effects]).to eq([{ 'mana' => 16 }])
    end

    it 'emits explicit damage with type, defaulting damage-only variables to zero' do
      r = resolver_for(
        'type' => 'spell', 'damage_type' => 'emotional',
        'effects' => ['attribute/2 + 2 damage']
      )
      result = r.resolve_spell('Test')
      expect(result[:polarity]).to eq(:forced)
      expect(result[:effects]).to eq([{ 'damage' => { 'amount' => 2, 'type' => 'emotional' } }])
    end

    it 'skips a damage Effect whose Formula references an unbound name' do
      r = resolver_for('type' => 'spell', 'damage_type' => 'fire',
                       'effects' => ['4*rank damage'])
      # rank defaults to 0 in the consumption context, so this resolves to 0;
      # an unresolved name would instead be dropped. Use a per-cast-only name:
      r2 = build_ability_resolver('Test' => { 'type' => 'spell', 'damage_type' => 'fire',
                                      'effects' => ['mystery_var damage'] })
      expect(r.resolve_spell('Test')[:effects]).to eq([{ 'damage' => { 'amount' => 0, 'type' => 'fire' } }])
      expect(r2.resolve_spell('Test')[:effects]).to eq([])
    end

    it 'returns an empty effects list but a polarity for a pure attack Spell' do
      r = resolver_for('type' => 'spell', 'attack_roll' => true)
      expect(r.resolve_spell('Test')).to eq(effects: [], polarity: :forced)
    end

    it 'returns nil for an unknown name' do
      r = resolver_for('type' => 'spell')
      expect(r.resolve_spell('Nope')).to be_nil
    end
  end

  describe 'polarity inference' do
    it 'infers forced from attack_roll, damage_type, or a damage Effect string' do
      %w[a b c].zip([
        { 'type' => 'spell', 'attack_roll' => true },
        { 'type' => 'spell', 'damage_type' => 'fire' },
        { 'type' => 'spell', 'damage_type' => 'fire', 'effects' => ['2 damage'] }
      ]).each do |name, entry|
        r = build_ability_resolver(name => entry)
        expect(r.resolve_spell(name)[:polarity]).to eq(:forced)
      end
    end

    it 'infers positive for a Spell with none of those' do
      r = build_ability_resolver('Buff' => { 'type' => 'spell', 'effect_hash' => { 'temp_hp' => 3 } })
      expect(r.resolve_spell('Buff')[:polarity]).to eq(:positive)
    end

    it 'lets an explicit polarity win over inference' do
      r = build_ability_resolver('Odd' => { 'type' => 'spell', 'attack_roll' => true, 'polarity' => 'positive' })
      expect(r.resolve_spell('Odd')[:polarity]).to eq(:positive)
    end
  end

  describe 'tier selection on a Tier-axis Spell' do
    let(:entry) do
      { 'type' => 'spell', 'polarity' => 'forced', 'tier' => [1, 2, 3],
        'effect_hash' => { 'minor_damage' => [10, 20, 30] } }
    end

    it 'picks the Variant whose Tier matches the Item' do
      r = build_ability_resolver('Tiered' => entry)
      expect(r.resolve_spell('Tiered', tier: 2)[:effects]).to eq([{ 'minor_damage' => 20 }])
    end

    it 'clamps a tier not present in the list to the nearest in-range index' do
      r = build_ability_resolver('Tiered' => entry)
      expect(r.resolve_spell('Tiered', tier: 9)[:effects]).to eq([{ 'minor_damage' => 30 }])
    end

    it 'ignores tier on a single-Variant Spell' do
      r = build_ability_resolver('Flat' => { 'type' => 'spell', 'polarity' => 'forced',
                                     'effect_hash' => { 'minor_damage' => 5 } })
      expect(r.resolve_spell('Flat', tier: 4)[:effects]).to eq([{ 'minor_damage' => 5 }])
    end
  end

  describe 'against the shipped catalog' do
    it 'resolves Heal as a cure with negated magnitudes at the selected tier' do
      result = Abilities.resolve_spell('Heal', tier: 2)
      expect(result[:polarity]).to eq(:positive)
      expect(result[:effects]).to eq([{ 'minor_damage' => -8, 'moderate_damage' => -4 }])
    end

    it 'resolves Ward to temp_hp and Recharge to mana' do
      expect(Abilities.resolve_spell('Ward', tier: 2)[:effects]).to eq([{ 'temp_hp' => 8 }])
      expect(Abilities.resolve_spell('Recharge', tier: 3)[:effects]).to eq([{ 'mana' => 16 }])
    end

    it 'resolves Biting Words to explicit emotional damage, polarity forced' do
      result = Abilities.resolve_spell('Biting Words', tier: 1)
      expect(result).to eq(effects: [{ 'damage' => { 'amount' => 2, 'type' => 'emotional' } }],
                           polarity: :forced)
    end

    it 'resolves a pure attack Spell to empty effects' do
      expect(Abilities.resolve_spell('Sacred Flame', tier: 0)).to eq(effects: [], polarity: :forced)
    end

    it 'returns nil for an unknown spell' do
      expect(Abilities.resolve_spell('No Such Spell', tier: 1)).to be_nil
    end
  end
end

RSpec.describe 'Abilities#item_only?' do
  it 'reports the item_only flag' do
    catalog = build_ability_catalog(
      'Caged' => { 'type' => 'spell', 'item_only' => true, 'items' => ['potion'] },
      'Free'  => { 'type' => 'spell' }
    )
    allow(Abilities).to receive(:catalog).and_return(catalog)
    expect(Abilities.item_only?('Caged')).to be true
    expect(Abilities.item_only?('Free')).to be false
  end

  it 'returns false for an unknown name' do
    expect(Abilities.item_only?('No Such Spell')).to be false
  end
end
