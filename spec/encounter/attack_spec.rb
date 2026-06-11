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

    it 'Helpless supersedes Flatfooted / Unaware with a single, more severe advantage' do
      # A Helpless target (cannot act) yields only the +3 Helpless Circumstance
      # advantage — never also the lesser Flatfooted / Unaware.
      expect(described_class.attacker_bonuses(flatfooted: true, unaware: true, helpless: true))
        .to eq([['Circumstance', 3, 'helpless']])
      expect(described_class.attacker_bonuses(flatfooted: false, unaware: false, helpless: true))
        .to eq([['Circumstance', 3, 'helpless']])
    end
  end

  describe 'Tier modifiers on the attack check' do
    let(:table) { [0, 1, 2, 3, 4, 5] } # Tier Minimum Inherent Bonus

    it 'raises the wielder effective Tier with Glory only when fighting up' do
      expect(described_class.effective_attacker_tier(1, 2, 1)).to eq(2) # Glory vs higher
      expect(described_class.effective_attacker_tier(1, 0, 1)).to eq(1) # not fighting up → no bump
      expect(described_class.effective_attacker_tier(1, 2, 0)).to eq(1) # no Glory
    end

    it 'gives the attacker its Inherent Bonus on a defended attack' do
      expect(described_class.attacker_tier_bonuses(attacker_tier: 1, defender_tier: 2, tier_advantage: 0,
                                                   inherent_table: table, no_defense: false))
        .to eq([['Inherent', 1]])
      # Glory lifts the Inherent Bonus to the higher Tier's.
      expect(described_class.attacker_tier_bonuses(attacker_tier: 1, defender_tier: 2, tier_advantage: 1,
                                                   inherent_table: table, no_defense: false))
        .to eq([['Inherent', 2]])
    end

    it 'injects the un-rolled defender Inherent, negated, on a no-defense attack' do
      # The un-rolled defender propagates nothing, so its Inherent is injected
      # directly (keeping its name); Check Resolution derives the Ascendancy
      # from the imbalance exactly as in the defended case.
      expect(described_class.attacker_tier_bonuses(attacker_tier: 1, defender_tier: 2, tier_advantage: 0,
                                                   inherent_table: table, no_defense: true))
        .to eq([['Inherent', 1], ['Inherent', -2]])
      # Glory lifts the attacker's Inherent to the defender's — the entries
      # balance, so Check Resolution will derive no Ascendancy.
      expect(described_class.attacker_tier_bonuses(attacker_tier: 1, defender_tier: 2, tier_advantage: 1,
                                                   inherent_table: table, no_defense: true))
        .to eq([['Inherent', 2], ['Inherent', -2]])
    end

    it 'injects the crossing for equal-Tier opponents too (it cancels in the TN)' do
      # Same Tier, no defense: bonus and penalty balance — net zero on the TN
      # and no Ascendancy — matching the defended case, where the equal
      # Inherents cross and cancel the same way.
      expect(described_class.attacker_tier_bonuses(attacker_tier: 2, defender_tier: 2, tier_advantage: 0,
                                                   inherent_table: table, no_defense: true))
        .to eq([['Inherent', 2], ['Inherent', -2]])
    end

    it 'emits Tier-0 Inherent modifiers as 0 (so the Ascendancy gate fires)' do
      # A Tier-0 creature still emits an Inherent 0: its own 0 crosses so the
      # opponent's Ascendancy gate fires, and the injected defender 0 is the
      # Inherent Penalty the attacker's gate needs (a present Penalty, 0 read
      # as the Tier-0 value 0.5). Net zero on the TN — net_modifier drops 0s.
      expect(described_class.attacker_tier_bonuses(attacker_tier: 0, defender_tier: 0, tier_advantage: 0,
                                                   inherent_table: table, no_defense: true))
        .to eq([['Inherent', 0], ['Inherent', 0]])
      expect(described_class.defender_tier_bonuses(defender_tier: 0, inherent_table: table)).to eq([['Inherent', 0]])
    end

    it 'gives the defender its Inherent Bonus to propagate' do
      expect(described_class.defender_tier_bonuses(defender_tier: 2, inherent_table: table)).to eq([['Inherent', 2]])
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

  it 'rolls a Damage Rider as its own Severity Calculation on a hit' do
    cond = Conditions::Instance.new
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee', commit: true,
      weapon: { damage_types: ['slashing'], threshold: 5, base_damage: 0,
                damage_riders: [{ property: 'Elemental', subtype: 'Fire', label: 'Flaming',
                                  dice: 4, kind: 'damage', damage_type: 'fire', amount: 1, severity: nil }] },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 3 },
      defense:  { choice: 'none' },
      rider_results: [{ id: 0, damage: 2 }] # client-rolled bonus fire damage
    )
    ro = out[:rider_outcomes].first
    expect(ro[:damage]).to eq(2)
    expect(ro[:severity_map]).to eq(moderate: 3) # fire is moderate + its damage_per_hit 1
    # Main slashing (3, runtime-bucketed at threshold 5 → minor) is kept
    # separate from the rider's fire (moderate).
    expect(cond.state.hp_damage[:minor]).to eq(3)
    expect(cond.state.hp_damage[:moderate]).to eq(3)
  end

  it 'applies a Vicious rider as Major to the target and bites the wielder' do
    target_cond   = Conditions::Instance.new
    attacker_cond = Conditions::Instance.new
    conds = { '1' => attacker_cond, '2' => target_cond }
    s = Encounter::State.new({}, data_path: data_path,
                             creature_lookup: ->(_id) { creature },
                             conditions_for: ->(id) { conds[id.to_s] })
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee', commit: true,
      weapon: { damage_types: ['slashing'], threshold: 0, base_damage: 0,
                damage_riders: [{ property: 'Vicious', subtype: nil, label: 'Vicious',
                                  dice: 4, kind: 'damage', damage_type: 'slashing', amount: 1,
                                  severity: 'major',
                                  self_damage: { severity: 'minor', amount: 1, minimum: 1 } }] },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 2 },
      defense:  { choice: 'none' },
      # e.g. 3 crits + 1 one: bonus damage 6 (crits ×2, the 1 ignored), self 3.
      rider_results: [{ id: 0, damage: 6, self_damage: 3 }]
    )
    ro = out[:rider_outcomes].first
    expect(ro[:severity_map]).to eq(major: 6)               # all bonus damage is Major
    expect(target_cond.state.hp_damage[:major]).to eq(6)
    expect(ro[:self_damage]).to eq(severity: 'minor', amount: 3)
    expect(attacker_cond.state.hp_damage[:minor]).to eq(3)
  end

  it 'applies the DM-edited self-damage to the wielder (minimum with no 1s)' do
    target_cond   = Conditions::Instance.new
    attacker_cond = Conditions::Instance.new
    conds = { '1' => attacker_cond, '2' => target_cond }
    s = Encounter::State.new({}, data_path: data_path,
                             creature_lookup: ->(_id) { creature },
                             conditions_for: ->(id) { conds[id.to_s] })
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee', commit: true,
      weapon: { damage_types: ['slashing'], threshold: 0, base_damage: 0,
                damage_riders: [{ property: 'Vicious', label: 'Vicious', dice: 4, kind: 'damage',
                                  damage_type: 'slashing', amount: 1, severity: 'major',
                                  self_damage: { severity: 'minor', amount: 1, minimum: 1 } }] },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 2 },
      defense:  { choice: 'none' },
      rider_results: [{ id: 0, damage: 0, self_damage: 1 }] # minimum self-damage, no 1s
    )
    expect(attacker_cond.state.hp_damage[:minor]).to eq(1)
  end

  it 'preview returns rider metadata but applies no rider damage' do
    cond = Conditions::Instance.new
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee', commit: false,
      weapon: { damage_types: ['slashing'], threshold: 5, base_damage: 0,
                damage_riders: [{ property: 'Elemental', subtype: 'Fire', label: 'Flaming',
                                  dice: 4, kind: 'damage', damage_type: 'fire', amount: 1 }] },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 3 },
      defense:  { choice: 'none' }
    )
    expect(out[:riders].length).to eq(1)
    expect(out[:riders].first[:label]).to eq('Flaming')
    expect(cond.state.hp_damage.values.sum).to eq(0) # preview mutates nothing
  end

  it 'a miss carries no riders' do
    cond = Conditions::Instance.new
    s = state(cond)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee', commit: true,
      weapon: { damage_types: ['slashing'], threshold: 0, base_damage: 0,
                damage_riders: [{ property: 'Elemental', subtype: 'Fire', label: 'Flaming',
                                  dice: 4, kind: 'damage', damage_type: 'fire', amount: 1 }] },
      attacker: { id: atk[:id], dice: 2, speed: 2, successes: 0 },
      defense:  { choice: 'dodge', id: tgt[:id], dice: 3, speed: 0, successes: 2 }
    )
    expect(out[:net_dos]).to be <= 0
    expect(out[:riders]).to be_nil
    expect(out[:rider_outcomes]).to be_nil
  end

  # Tier Mismatch Inherent damage reduction + the Glory weapon Property.
  def tiered_creature(tier)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |_a| 12 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 60 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { "T#{tier}" }
    obj
  end

  def tier_state(tiers)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(id) { tiered_creature(tiers[id.to_s] || 0) },
                         conditions_for: ->(_id) { Conditions::Instance.new })
  end

  def attack_for_gap(s, atk, tgt, tier_advantage: 0)
    s.resolve_attack_payload(
      target_id: tgt[:id], attack_kind: 'melee', commit: false,
      weapon: { damage_types: ['slashing'], threshold: 0, base_damage: 10, tier_advantage: tier_advantage },
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 1 }, # base 10 + net 1 = 11 pre-reduction
      defense:  { choice: 'none' }
    )
  end

  it 'reduces weapon damage by the Tier Mismatch Inherent DR against a higher-Tier defender' do
    s = tier_state('1' => 0, '2' => 2) # attacker Tier 0, defender Tier 2
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = attack_for_gap(s, atk, tgt)
    expect(out[:inherent_dr]).to eq(7) # floor(5 × (2 − 0.5))
    expect(out[:damage]).to eq(4)      # 11 − 7
  end

  it 'Glory shrinks the gap by raising the wielder effective Tier' do
    s = tier_state('1' => 0, '2' => 2)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = attack_for_gap(s, atk, tgt, tier_advantage: 1)
    expect(out[:inherent_dr]).to eq(5) # effective Tier 1: floor(5 × (2 − 1))
    expect(out[:damage]).to eq(6)      # 11 − 5
  end

  it 'Glory lets a one-Tier-higher foe take full damage' do
    s = tier_state('1' => 0, '2' => 1)
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = attack_for_gap(s, atk, tgt, tier_advantage: 1)
    expect(out[:inherent_dr]).to eq(0) # effective Tier 1 == defender Tier 1
    expect(out[:damage]).to eq(11)
  end

  it 'never reduces damage against an equal or lower Tier defender' do
    s = tier_state('1' => 2, '2' => 0) # attacker outranks defender
    atk = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = attack_for_gap(s, atk, tgt)
    expect(out[:inherent_dr]).to eq(0)
    expect(out[:damage]).to eq(11)
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
