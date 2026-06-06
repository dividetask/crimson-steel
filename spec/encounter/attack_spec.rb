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
    it 'applies Flatfooted when set, plus Unaware when applicable, each tagged with its source' do
      expect(described_class.attacker_bonuses(flatfooted: true, unaware: false)).to eq([['Circumstance', 1, 'flatfooted']])
      expect(described_class.attacker_bonuses(flatfooted: false, unaware: false)).to eq([])
      expect(described_class.attacker_bonuses(flatfooted: true, unaware: true))
        .to eq([['Circumstance', 1, 'flatfooted'], ['Circumstance', 2, 'unaware']])
    end

    it 'keeps Flatfooted for a non-Dodge defence (Block / Parry) but not for Dodge' do
      # The route passes flatfooted:true for Block/Parry/no-defence and
      # flatfooted:false only for a Dodge.
      expect(described_class.attacker_bonuses(flatfooted: true,  unaware: false)).to eq([['Circumstance', 1, 'flatfooted']])
      expect(described_class.attacker_bonuses(flatfooted: false, unaware: false)).to eq([])
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
      # competency + flatfooted (no defense) + unaware (each source-tagged)
      expect(a[:bonus_penalty_list]).to eq([['Competency', 2], ['Circumstance', 1, 'flatfooted'], ['Circumstance', 2, 'unaware']])
      expect(spec[:target][:flatfooted]).to be true
      expect(spec[:eligible_defenses]).to contain_exactly('parry', 'block', 'dodge')
      expect(spec).not_to have_key(:defense)
    end

    it 'builds a Dodge defense spec that costs pool (Reaction min .. remaining pool), and drops Flatfooted' do
      spec = described_class.build_spec(
        attacker: attacker, target: target, attack_kind: 'ranged', weapon: weapon,
        attacker_dice_cap: 6, declared_defense: 'dodge',
        defender_inputs: { dice_cap: 5, pool_remaining: 8 }
      )
      expect(spec[:target][:flatfooted]).to be false
      d = spec[:defense]
      expect(d[:choice]).to eq('dodge')
      # Dodge borrows dex_save inputs but is a pool-costed Defensive Action.
      expect(d[:pool_cost]).to be true
      expect(d[:min_dice]).to eq(Encounter::Config.reaction_action_minimum)
      expect(d[:max_dice]).to eq(5) # min(dice_cap 5, pool_remaining 8)
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

  it 'buckets damage into Minor/Moderate/Major by the weapon Threshold' do
    s = state
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 3, base_damage: 0 },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 5 },
      defense:  { choice: 'none' }, allies: []
    )
    expect(out[:damage]).to eq(5)
    expect(out[:threshold]).to eq(3)
    expect(out[:severity_map]).to eq(minor: 3, moderate: 2) # threshold 3: 3 minor, 2 moderate
  end

  it 'honors DM overrides (damage / bleed / pool) on commit, re-bucketing damage' do
    cond = build_instance
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 3, base_damage: 0, bleed: 0 },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 2 },
      defense:  { choice: 'none' }, allies: [],
      override: { damage: 8, bleed: 1, pool_spends: [{ id: atk[:id], amount: 9 }] }
    )
    expect(out[:damage]).to eq(8)
    expect(out[:severity_map]).to eq(minor: 3, moderate: 3, major: 2) # 8 @ threshold 3
    expect(out[:bleed]).to eq(1)
    expect(s.combatant(atk[:id])[:combat_pool_spent]).to eq(9) # overridden pool
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

  it 'reports weapon Bleed and Combat-Pool spends, and applies Bleed on a hit' do
    cond = build_instance # catalog-backed, so the Bleeding Affliction resolves
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 2, bleed: 3 },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 3 },
      defense:  { choice: 'none' }, allies: []
    )
    # Bleed = weapon Bleed (3) + damage dealt (base 2 + net 3 = 5) = 8.
    expect(out[:bleed]).to eq(8)
    expect(out[:pool_spends]).to include(a_hash_including(id: atk[:id], amount: 6)) # 2 + 4
    expect(cond.state.afflictions).to have_key('bleeding')
    expect(cond.state.afflictions['bleeding'][:potency]).to eq(8)
  end

  it 'a 0-Bleed weapon still bleeds for the damage dealt' do
    cond = build_instance
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 0, bleed: 0 },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 4 },
      defense:  { choice: 'none' }, allies: []
    )
    expect(out[:damage]).to eq(4)            # base 0 + net 4
    expect(out[:bleed]).to eq(4)             # 0 + damage 4
    expect(cond.state.afflictions['bleeding'][:potency]).to eq(4)
  end

  it 'inflicts the weapon Affliction (poison): potency = Affliction Potency constant + damage' do
    cond = build_instance # catalog-backed, so spider_venom resolves
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['piercing'], threshold: 0, base_damage: 1, bleed: 0,
                affliction: 'spider_venom', affliction_potency: 5 },
      attacker: { id: atk[:id], dice: 4, speed: 0, successes: 3 },
      defense:  { choice: 'none' }, allies: []
    )
    expect(out[:poison_name]).to eq('Spider Venom')
    expect(out[:damage]).to eq(4)  # base 1 + net 3
    expect(out[:poison]).to eq(9)  # affliction_potency 5 + damage 4
    expect(cond.state.afflictions['spider_venom'][:potency]).to eq(9)
  end

  it 'honors a DM poison override' do
    cond = build_instance
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['piercing'], threshold: 0, base_damage: 0, bleed: 0, affliction: 'spider_venom' },
      attacker: { id: atk[:id], dice: 4, speed: 0, successes: 2 },
      defense:  { choice: 'none' }, allies: [],
      override: { poison: 5 }
    )
    expect(cond.state.afflictions['spider_venom'][:potency]).to eq(5)
  end

  it 'a weapon without an Affliction inflicts no poison' do
    cond = build_instance
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 2 },
      attacker: { id: atk[:id], dice: 4, speed: 0, successes: 3 },
      defense:  { choice: 'none' }, allies: []
    )
    expect(out[:poison_name]).to be_nil
    expect(cond.state.afflictions).not_to have_key('spider_venom')
  end

  it 'preview (commit: false) reports the same numbers but mutates nothing' do
    cond = Conditions::Instance.new
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee', commit: false,
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 2, bleed: 3 },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 3 },
      defense:  { choice: 'none' }, allies: []
    )
    expect(out[:committed]).to be false
    expect(out[:damage]).to eq(5)        # base 2 + net 3 — same as commit
    expect(out[:bleed]).to eq(8)         # weapon 3 + damage 5
    expect(out[:pool_spends]).to include(a_hash_including(id: atk[:id], amount: 6))
    # ...but nothing was applied:
    expect(s.combatant(atk[:id])[:combat_pool_spent]).to eq(0)
    expect(cond.state.afflictions).to be_empty
    expect(cond.state.hp_damage.values.sum).to eq(0)
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

  it 'Dodge contributes opposing successes and spends Combat Pool (Speed 0 + dice)' do
    s = state
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'ranged',
      weapon: { damage_types: ['piercing'], threshold: 2, base_damage: 3 },
      attacker: { id: atk[:id], dice: 4, speed: 1, successes: 5 },
      defense:  { choice: 'dodge', id: tgt[:id], dice: 5, speed: 0, successes: 2 }, allies: []
    )
    expect(s.combatant(tgt[:id])[:combat_pool_spent]).to eq(5) # Speed 0 + 5 dice
    expect(out[:net_dos]).to eq(3)
  end

  it 'spends the attacker’s own Luck on commit (one per reroll), not on preview' do
    raw = { 'combatants' => [
      { 'id' => 1, 'creature_id' => '1', 'luck_points' => 3 },
      { 'id' => 2, 'creature_id' => '2', 'luck_points' => 0 }
    ], 'next_combatant_id' => 3 }
    s = Encounter::State.new(raw, data_path: data_path,
                             creature_lookup: ->(_id) { creature },
                             conditions_for: ->(_id) { Conditions::Instance.new })
    args = { target_id: 2, attack_kind: 'melee',
             weapon: { damage_types: ['physical'], threshold: 0, base_damage: 0 },
             attacker: { id: 1, dice: 2, speed: 1, successes: 1, luck: { source_id: 'self', amount: 2 } },
             defense: { choice: 'none' } }

    s.resolve_attack_payload(args.merge(commit: false)) # preview spends nothing
    expect(s.combatant(1)[:luck_points]).to eq(3)

    s.resolve_attack_payload(args.merge(commit: true))   # commit debits 2 Luck
    expect(s.combatant(1)[:luck_points]).to eq(1)
  end

  it 'discharges an ally Bard’s Reservoir when their Luck is applied to the attack' do
    raw = { 'combatants' => [
      { 'id' => 1, 'creature_id' => '1', 'luck_points' => 0 }, # attacker
      { 'id' => 2, 'creature_id' => '2', 'luck_points' => 0 }, # target
      { 'id' => 3, 'creature_id' => '3', 'luck_points' => 0,   # ally bard
        'concentration' => [{ 'spell_name' => 'Bardic Inspiration', 'mode' => 'reservoir',
                              'reservoir' => 5, 'reservoir_reset' => 'per_turn', 'source' => 'x',
                              'spell_tier' => 1, 'cast_skill' => 'perform_', 'channeled_this_turn' => true }] }
    ], 'next_combatant_id' => 4 }
    s = Encounter::State.new(raw, data_path: data_path,
                             creature_lookup: ->(_id) { creature },
                             conditions_for: ->(_id) { Conditions::Instance.new })
    s.resolve_attack_payload(
      target_id: 2, attack_kind: 'melee', commit: true,
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 0 },
      attacker: { id: 1, dice: 2, speed: 1, successes: 1, luck: { source_id: 3, amount: 2 } },
      defense: { choice: 'none' }
    )
    # The Bard's Reservoir is debited; the attacker gains no lingering Luck.
    expect(s.combatant(3)[:concentration].first[:reservoir]).to eq(3) # 5 − 2
    expect(s.combatant(1)[:luck_points]).to eq(0)
  end

  it 'debits each Luck source (ally Reservoir + the DM) from the luck list on commit' do
    raw = { 'combatants' => [
      { 'id' => 1, 'creature_id' => '1' }, # attacker
      { 'id' => 2, 'creature_id' => '2' }, # target
      { 'id' => 3, 'creature_id' => '3',   # ally bard
        'concentration' => [{ 'spell_name' => 'Bardic Inspiration', 'mode' => 'reservoir',
                              'reservoir' => 5, 'reservoir_reset' => 'per_turn', 'source' => 'x',
                              'spell_tier' => 1, 'cast_skill' => 'perform_', 'channeled_this_turn' => true }] }
    ], 'next_combatant_id' => 4, 'dm_luck_points' => 4 }
    s = Encounter::State.new(raw, data_path: data_path,
                             creature_lookup: ->(_id) { creature },
                             conditions_for: ->(_id) { Conditions::Instance.new })
    args = {
      target_id: 2, attack_kind: 'melee',
      weapon: { damage_types: ['physical'], threshold: 0, base_damage: 0 },
      attacker: { id: 1, dice: 2, speed: 1, successes: 1 }, defense: { choice: 'none' },
      luck: [{ source_id: 3, amount: 2 }, { source_id: nil, amount: 3 }] # Bard +2, DM +3
    }
    s.resolve_attack_payload(args.merge(commit: false)) # preview spends nothing
    expect(s.combatant(3)[:concentration].first[:reservoir]).to eq(5)
    expect(s.dm_luck_points).to eq(4)

    s.resolve_attack_payload(args.merge(commit: true))
    expect(s.combatant(3)[:concentration].first[:reservoir]).to eq(3) # 5 − 2
    expect(s.dm_luck_points).to eq(1) # 4 − 3
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
