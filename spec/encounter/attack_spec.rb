require 'spec_helper'
require 'encounter'
require 'tmpdir'

RSpec.describe Encounter::Attack do
  describe 'Defensive Action eligibility' do
    it 'allows Parry only against melee' do
      expect(described_class.defense_eligible?('parry', 'melee')).to be true
      expect(described_class.defense_eligible?('parry', 'ranged')).to be false
      expect(described_class.defense_eligible?('parry', 'spell')).to be false
    end

    it 'allows Block and Dodge against melee, ranged, and spell' do
      %w[melee ranged spell].each do |kind|
        expect(described_class.defense_eligible?('block', kind)).to be true
        expect(described_class.defense_eligible?('dodge', kind)).to be true
      end
    end

    it 'lists eligible defenses per attack kind' do
      expect(described_class.eligible_defenses('melee')).to contain_exactly('parry', 'block', 'dodge')
      expect(described_class.eligible_defenses('ranged')).to contain_exactly('block', 'dodge')
    end
  end

  describe 'Attacker bonuses' do
    it 'applies Flatfooted when no defense is declared and Unaware when applicable' do
      expect(described_class.attacker_bonuses(no_defense: true, unaware: false)).to eq([['Circumstance', 1]])
      expect(described_class.attacker_bonuses(no_defense: false, unaware: false)).to eq([])
      expect(described_class.attacker_bonuses(no_defense: true, unaware: true))
        .to eq([['Circumstance', 1], ['Circumstance', 2]])
    end

    it 'suppresses Unaware when a defense is declared (declaring proves awareness)' do
      # The defender has not acted, but declaring a Defensive Action makes
      # them Aware — so neither Flatfooted nor Unaware applies.
      expect(described_class.attacker_bonuses(no_defense: false, unaware: true)).to eq([])
    end
  end

  describe '.build_spec' do
    let(:attacker) { { id: 1 } }
    let(:target)   { { id: 2 } }
    let(:weapon)   { { damage_types: ['emotional'], threshold: 0, bleed: 3, speed: 2, base_damage: 4 } }

    it 'assembles the attacker roll spec with critical modifier and bonuses' do
      spec = described_class.build_spec(
        attacker: attacker, target: target, attack_kind: 'melee', weapon: weapon,
        attacker_dice_cap: 6, attacker_competency: ['Competency', 2], unaware: true
      )
      a = spec[:attacker]
      expect(a[:dice_cap]).to eq(6)
      expect(a[:critical_modifier]).to eq(3) # emotional critical_value
      expect(a[:speed]).to eq(2)
      # competency + flatfooted (no defense) + unaware
      expect(a[:bonus_penalty_list]).to eq([['Competency', 2], ['Circumstance', 1], ['Circumstance', 2]])
      expect(spec[:target][:flatfooted]).to be true
      expect(spec[:eligible_defenses]).to contain_exactly('parry', 'block', 'dodge')
      expect(spec).not_to have_key(:defense)
    end

    it 'builds a Dodge defense spec at full Dice Cap with no pool cost, and drops Flatfooted' do
      spec = described_class.build_spec(
        attacker: attacker, target: target, attack_kind: 'ranged', weapon: weapon,
        attacker_dice_cap: 6, declared_defense: 'dodge',
        defender_inputs: { dice_cap: 5, pool_remaining: 8 }
      )
      expect(spec[:target][:flatfooted]).to be false
      d = spec[:defense]
      expect(d[:choice]).to eq('dodge')
      expect(d[:pool_cost]).to be false
      expect(d[:min_dice]).to eq(5)
      expect(d[:max_dice]).to eq(5)
    end

    it 'builds a Parry defense spec bounded by Reaction minimum and remaining pool' do
      spec = described_class.build_spec(
        attacker: attacker, target: target, attack_kind: 'melee', weapon: weapon,
        attacker_dice_cap: 6, declared_defense: 'parry',
        defender_inputs: { dice_cap: 7, pool_remaining: 4 }
      )
      d = spec[:defense]
      expect(d[:pool_cost]).to be true
      expect(d[:min_dice]).to eq(Encounter::Config.reaction_action_minimum)
      expect(d[:max_dice]).to eq(4) # min(dice_cap 7, pool_remaining 4)
    end

    it 'rejects an ineligible declared defense' do
      expect do
        described_class.build_spec(attacker: attacker, target: target, attack_kind: 'ranged',
                                   weapon: weapon, attacker_dice_cap: 6, declared_defense: 'parry')
      end.to raise_error(ArgumentError, /not eligible/)
    end
  end
end

RSpec.describe 'Encounter::State#resolve_attack_payload (weapon-aware)' do
  let(:tmpdir)    { Dir.mktmpdir('enc-atk') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature
    obj = Object.new
    obj.define_singleton_method(:tier) { 0 }
    obj.define_singleton_method(:attribute_value) { |_a| 12 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Mob' }
    obj
  end

  def state(cond = Conditions::Instance.new)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(_id) { cond })
  end

  it 'routes weapon damage through the weapon damage type' do
    cond = Conditions::Instance.new
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['fire'], threshold: 0, base_damage: 4 },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 5 },
      defense:  { choice: 'none' }, allies: []
    )
    expect(out[:net_dos]).to eq(5)
    expect(out[:damage]).to eq(9)               # base 4 + net 5
    expect(out[:damage_type]).to eq('fire')
    expect(out[:severity_map]).to eq(moderate: 10) # fire +1 per hit
  end

  it 'spends Combat Pool as the flat Speed cost plus one per die (Speed + dice)' do
    s = state
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 0 },
      attacker: { id: atk[:id], dice: 4, speed: 3, successes: 1 },
      defense:  { choice: 'none' }, allies: []
    )
    # Speed 3 + 4 dice = 7 (not 3 × 4 = 12).
    expect(s.combatant(atk[:id])[:combat_pool_spent]).to eq(7)
  end

  it 'Parry spends the defender pool as Speed + dice' do
    s = state
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 0 },
      attacker: { id: atk[:id], dice: 2, speed: 1, successes: 1 },
      defense:  { choice: 'parry', id: tgt[:id], dice: 3, speed: 2, successes: 0 }, allies: []
    )
    expect(s.combatant(tgt[:id])[:combat_pool_spent]).to eq(5) # 2 + 3
  end

  it 'Dodge contributes opposing successes but spends no Combat Pool' do
    s = state
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'ranged',
      weapon: { damage_types: ['piercing'], threshold: 2, base_damage: 3 },
      attacker: { id: atk[:id], dice: 4, speed: 1, successes: 5 },
      defense:  { choice: 'dodge', id: tgt[:id], dice: 5, speed: 1, successes: 2 }, allies: []
    )
    expect(s.combatant(tgt[:id])[:combat_pool_spent]).to eq(0) # Dodge costs no pool
    expect(out[:net_dos]).to eq(3)
  end

  it 'rejects an ineligible defense (Parry vs ranged) before spending' do
    s = state
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'ranged',
      attacker: { id: atk[:id], dice: 4, speed: 1, successes: 5 },
      defense:  { choice: 'parry', id: tgt[:id], dice: 3, speed: 1, successes: 2 }
    )
    expect(out[:ok]).to be false
    expect(s.combatant(atk[:id])[:combat_pool_spent]).to eq(0)
  end
end
