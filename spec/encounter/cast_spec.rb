require 'spec_helper'
require 'encounter'
require 'abilities'
require 'tmpdir'

RSpec.describe Encounter::Cast do
  describe 'resource helpers' do
    it 'checks Mana affordability against what remains' do
      expect(described_class.mana_affordable?(remaining: 5, cost: 5)).to be true
      expect(described_class.mana_affordable?(remaining: 4, cost: 5)).to be false
    end

    it 'costs Combat Pool as the casting-time Speed plus one per die' do
      expect(described_class.pool_cost(speed: 3, dice: 4)).to eq(7) # not 3 × 4
    end
  end

  describe 'Halved Effect' do
    it 'floor-halves each Severity count independently and drops zeros' do
      expect(described_class.halve_severity_map(minor: 3, moderate: 2, major: 1))
        .to eq(minor: 1, moderate: 1) # 3→1, 2→1, 1→0 dropped
    end

    it 'halves a scalar amount with floor' do
      expect(described_class.halve_amount(5)).to eq(2)
    end

    it 'halves the numeric core of each Effect kind' do
      expect(described_class.halve_effect(kind: 'damage', amount: 7, damage_type: 'fire'))
        .to eq(kind: 'damage', amount: 3, damage_type: 'fire')
      expect(described_class.halve_effect(kind: 'heal', severity_map: { minor: 4 }))
        .to eq(kind: 'heal', severity_map: { minor: 2 })
      expect(described_class.halve_effect(kind: 'mana', amount: 5))
        .to eq(kind: 'mana', amount: 2)
      # A bare named effect has nothing numeric to halve.
      expect(described_class.halve_effect(kind: 'effect', name: 'prone'))
        .to eq(kind: 'effect', name: 'prone')
    end
  end

  describe '.resolve_save' do
    let(:effects) { [{ kind: 'damage', amount: 6, damage_type: 'fire' }] }

    it 'lands full Effects when the spell offers no Save' do
      expect(described_class.resolve_save(effects: effects, caster_successes: 0, save: nil))
        .to eq(['hit', effects])
    end

    it 'lands full Effects when the caster beats the target Save (target fails)' do
      out = described_class.resolve_save(effects: effects, caster_successes: 4,
                                         save: { successes: 2, on_success: 'halved' })
      expect(out).to eq(['failed_save', effects])
    end

    it 'floor-halves every Effect when the Save succeeds with on_success: halved' do
      outcome, halved = described_class.resolve_save(effects: effects, caster_successes: 2,
                                                     save: { successes: 3, on_success: 'halved' })
      expect(outcome).to eq('saved_halved')
      expect(halved).to eq([{ kind: 'damage', amount: 3, damage_type: 'fire' }])
    end

    it 'negates every Effect when the Save succeeds with on_success: none' do
      expect(described_class.resolve_save(effects: effects, caster_successes: 1,
                                          save: { successes: 1, on_success: 'none' }))
        .to eq(['saved_negated', []])
    end

    it 'swaps in success_effects for any other on_success directive' do
      alt = [{ kind: 'effect', name: 'dazzled' }]
      out = described_class.resolve_save(effects: effects, caster_successes: 0,
                                         save: { successes: 1, on_success: 'dazzled', success_effects: alt })
      expect(out).to eq(['saved_alternate', alt])
    end
  end

  describe '.default_spell_damage' do
    it 'is floor(casting stat / 4) + Tier + Successes' do
      # 14/4 = 3, + tier 2 + 3 successes = 8.
      expect(described_class.default_spell_damage(casting_stat: 14, tier: 2, successes: 3)).to eq(8)
    end

    it 'treats Tier 0 as 0.5 and floors the total' do
      # 14/4 = 3, + 0.5 + 3 = 6.5 -> 6.
      expect(described_class.default_spell_damage(casting_stat: 14, tier: 0, successes: 3)).to eq(6)
    end
  end

  describe '.sustain_spec' do
    it 'classifies a Channeled spell as Concentration' do
      expect(described_class.sustain_spec(channel: { mode: 'fire' }, reservoir: { reset: 'per_turn' }))
        .to eq(kind: :concentration, mode: 'fire', reservoir_reset: 'per_turn')
    end

    it 'classifies a multi-turn cast as a Long Cast' do
      expect(described_class.sustain_spec(turns_required: 3)).to eq(kind: :long_cast, turns_required: 3)
    end

    it 'needs no sustain Entry for an instantaneous single-turn cast' do
      expect(described_class.sustain_spec(turns_required: 1)).to be_nil
    end
  end
end

RSpec.describe 'Encounter::State#resolve_cast_payload' do
  let(:tmpdir)    { Dir.mktmpdir('enc-cast') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature(cha: 12, tier: 0)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |a| a == :cha ? cha : 12 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Caster' }
    obj
  end

  def state(cond = Conditions::Instance.new, creature_obj = creature)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature_obj },
                         conditions_for: ->(_id) { cond })
  end

  it 'spends the caster Combat Pool as casting-time Speed plus one per die' do
    s = state
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 4, speed: 3, successes: 2 },
      spell:  { name: 'Firebolt', tier: 1, mana_cost: 0 },
      targets: [{ id: tgt[:id], effects: [] }]
    )
    expect(s.combatant(caster[:id])[:combat_pool_spent]).to eq(7) # 3 + 4, not 3 × 4
  end

  it 'debits Mana through Conditions, capped by what remains' do
    cond = build_instance
    s = state(cond)
    caster = s.add_combatant('1')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 2, speed: 1, successes: 1 },
      spell:  { name: 'Heal', tier: 2, mana_cost: 5 }, targets: []
    )
    expect(out[:mana_spent]).to eq(5)
    expect(cond.state.mana_spent).to eq(5)
  end

  it 'routes spell damage to the target through Apply Damage (Severity bucketed)' do
    cond = build_instance
    s = state(cond)
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 3, speed: 1, successes: 3 },
      spell:  { name: 'Firebolt', tier: 1, mana_cost: 0 },
      targets: [{ id: tgt[:id], effects: [{ kind: 'damage', amount: 4, damage_type: 'fire', threshold: 0 }] }]
    )
    applied = out[:targets].first[:applied].first
    expect(applied[:kind]).to eq('damage')
    expect(applied[:severity_map]).to eq(moderate: 5) # 4 fire, +1 per hit
    expect(cond.state.hp_damage.values.sum).to eq(5)
  end

  describe 'buff modifiers' do
    it 'applies a buff Spell modifier as an Active Effect on the target' do
      cond = Conditions::Instance.new
      s = state(cond, creature(tier: 1))
      caster = s.add_combatant('1'); tgt = s.add_combatant('2')
      s.resolve_cast_payload(
        caster: { id: caster[:id], dice: 2, speed: 0, successes: 2 },
        spell:  { name: 'Haste', tier: 1, mana_cost: 0 },
        targets: [{ id: tgt[:id], effects: [{ kind: 'modifiers', duration: 'rank minutes',
                    modifiers: [{ target: 'speed', type: 'Guidance', add: 30 }] }] }]
      )
      expect(cond.get_modifiers('speed')).to include(['Guidance', 30])
    end

    it 'evaluates a caster_tier modifier against the caster (Magic Weapon)' do
      cond = Conditions::Instance.new
      s = state(cond, creature(tier: 3))
      caster = s.add_combatant('1'); tgt = s.add_combatant('2')
      s.resolve_cast_payload(
        caster: { id: caster[:id], dice: 2, speed: 0, successes: 2 },
        spell:  { name: 'Magic Weapon', tier: 2, mana_cost: 0 },
        targets: [{ id: tgt[:id], effects: [{ kind: 'modifiers', duration: 'rank minutes',
                    modifiers: [{ target: 'attack', type: 'Guidance', add: 'caster_tier' },
                                { target: 'damage', type: 'Guidance', add: 'caster_tier' }] }] }]
      )
      expect(cond.get_modifiers('attack')).to include(['Guidance', 3])
      expect(cond.get_modifiers('damage')).to include(['Guidance', 3])
    end

    it 'narrows the target_key by a non-all descriptor (Protection from Poison)' do
      cond = Conditions::Instance.new
      s = state(cond, creature(tier: 1))
      caster = s.add_combatant('1'); tgt = s.add_combatant('2')
      s.resolve_cast_payload(
        caster: { id: caster[:id], dice: 1, speed: 0, successes: 1 },
        spell:  { name: 'Protection from Poison', tier: 2, mana_cost: 0 },
        targets: [{ id: tgt[:id], effects: [{ kind: 'modifiers', duration: 'rank*10 minutes',
                    modifiers: [{ target: 'save', type: 'Guidance', add: 1, descriptors: ['poison'] }] }] }]
      )
      expect(cond.get_modifiers('poison')).to include(['Guidance', 1])
      expect(cond.get_modifiers('save')).to be_empty # a poison-only ward, not all saves
    end

    it 'a turn-based duration sets the Active Effect expiry; minutes are open-ended' do
      cond = Conditions::Instance.new
      # Fixed timestamp so current_abs_round is deterministically 0.
      s = Encounter::State.new({}, data_path: data_path,
                               creature_lookup: ->(_id) { creature(tier: 1) },
                               conditions_for: ->(_id) { cond },
                               current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
                               rounds_per_day: 10_000)
      caster = s.add_combatant('1'); tgt = s.add_combatant('2')
      s.resolve_cast_payload(
        caster: { id: caster[:id], dice: 1, speed: 0, successes: 1 },
        spell:  { name: 'Bless', tier: 1, mana_cost: 0 },
        targets: [{ id: tgt[:id], effects: [{ kind: 'modifiers', duration: '1 turn',
                    modifiers: [{ target: 'damage_reduction', type: 'Guidance', add: 3 }] }] }]
      )
      # current_abs_round is 0 outside combat, so a 1-turn buff expires on round 1.
      expect(cond.get_modifiers('damage_reduction', current_round: 0)).to include(['Guidance', 3])
      expect(cond.get_modifiers('damage_reduction', current_round: 1)).to be_empty
    end
  end

  it 'routes heal, mana restore, and Temporary HP Effects to Conditions' do
    cond = build_instance
    cond.apply_hit_point_damage(minor: 6)
    cond.apply_mana_cost(amount: 6, mana_max: 8)
    s = state(cond)
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 2, speed: 1, successes: 1 },
      spell:  { name: 'Renew', tier: 1, mana_cost: 0 },
      targets: [{ id: tgt[:id], effects: [
        { kind: 'heal', severity_map: { minor: 4 } },
        { kind: 'mana', amount: 3 },
        { kind: 'temp_hp', amount: 5 }
      ] }]
    )
    expect(cond.state.hp_damage[:minor]).to eq(2)        # 6 − 4 healed
    expect(cond.state.mana_spent).to eq(3)               # 6 − 3 restored
    expect(cond.state.temporary_hit_points[:amount]).to eq(5)
  end

  it 'applies Magic Toxicity, gating a positive contribution over threshold' do
    cond = build_instance
    s = state(cond, creature(cha: 10, tier: 0)) # threshold = floor(10 × 0.5) = 5
    caster = s.add_combatant('1')
    accepted = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 1, speed: 0, successes: 0 },
      spell:  { name: 'Burst', tier: 1, mana_cost: 0, toxicity: 3 }, targets: []
    )
    expect(accepted[:toxicity][:accepted]).to be true
    expect(cond.state.magic_toxicity).to eq(3)

    cond.state.magic_toxicity = 9 # now over the threshold of 5
    blocked = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 1, speed: 0, successes: 0 },
      spell:  { name: 'Burst', tier: 1, mana_cost: 0, toxicity: 3 }, targets: []
    )
    expect(blocked[:toxicity][:accepted]).to be false
    expect(cond.state.magic_toxicity).to eq(9) # unchanged
  end

  it 'nets the caster Successes against a target Save (save-for-half / negates)' do
    cond = build_instance
    s = state(cond)
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    # Caster 2 vs Save 3 → target saves; on_success halved → 6 damage becomes 3.
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 2, speed: 0, successes: 2 },
      spell:  { name: 'Fireball', tier: 3, mana_cost: 0 },
      targets: [{ id: tgt[:id], save: { successes: 3, on_success: 'halved' },
                  effects: [{ kind: 'damage', amount: 6, damage_type: 'fire', threshold: 0 }] }]
    )
    expect(out[:targets].first[:outcome]).to eq('saved_halved')
    # 3 fire +1 per hit = 4 moderate.
    expect(out[:targets].first[:applied].first[:severity_map]).to eq(moderate: 4)
  end

  it 'computes default Spell damage (floor(stat/4) + Tier + Successes) when none is given' do
    cond = build_instance
    s = state(cond, creature(cha: 16))
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 3, speed: 1, successes: 4 },
      spell:  { name: 'Scorch', tier: 2, mana_cost: 0, default_damage: true,
                damage_type: 'fire', casting_attribute: 'cha' },
      targets: [{ id: tgt[:id], effects: [] }]
    )
    applied = out[:targets].first[:applied].first
    # cha 16/4 = 4, + tier 2 + 4 successes = 10 fire; +1 per fire hit -> 11.
    expect(applied[:amount]).to eq(10)
    expect(applied[:damage_type]).to eq('fire')
    expect(applied[:severity_map]).to eq(moderate: 11)
  end

  it 'halves the default Spell damage when the target saves for half' do
    cond = build_instance
    s = state(cond, creature(cha: 16))
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 3, speed: 1, successes: 4 },
      spell:  { name: 'Scorch', tier: 2, mana_cost: 0, default_damage: true,
                damage_type: 'fire', casting_attribute: 'cha' },
      targets: [{ id: tgt[:id], save: { successes: 5, on_success: 'halved' }, effects: [] }]
    )
    # Saved: default 10 -> halved 5 fire; +1 per hit -> 6.
    expect(out[:targets].first[:outcome]).to eq('saved_halved')
    expect(out[:targets].first[:applied].first[:amount]).to eq(5)
  end

  it 'resolves an attack-roll spell as a spell attack — damage from net successes' do
    cond = build_instance
    s = state(cond, creature(cha: 16))
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 3, speed: 1, successes: 4 },
      spell:  { name: 'Bolt', tier: 0, mana_cost: 0, attack_roll: true,
                damage_type: 'physical', casting_attribute: 'cha' },
      targets: [{ id: tgt[:id], defense: { choice: 'none' } }]
    )
    t = out[:targets].first
    expect(t[:outcome]).to eq('hit')
    # net 4: floor(16/4) + 0.5 + 4 = 8.
    expect(t[:applied].first[:amount]).to eq(8)
    expect(cond.state.hp_damage.values.sum).to eq(8)
  end

  it 'an attack-roll spell missed via Dodge deals no damage and spends the defender pool' do
    cond = build_instance
    s = state(cond, creature(cha: 16))
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 3, speed: 1, successes: 2 },
      spell:  { name: 'Bolt', tier: 0, mana_cost: 0, attack_roll: true,
                damage_type: 'physical', casting_attribute: 'cha' },
      targets: [{ id: tgt[:id], defense: { choice: 'dodge', successes: 3, dice: 5, speed: 0 } }]
    )
    expect(out[:targets].first[:outcome]).to eq('defended')
    expect(cond.state.hp_damage.values.sum).to eq(0)
    # Dodge is a pool-costed Defensive Action: Speed 0 + 5 dice = 5.
    expect(s.combatant(tgt[:id])[:combat_pool_spent]).to eq(5)
  end

  it 'an attack-roll spell Block spends the defender pool and still hits on positive net' do
    cond = build_instance
    s = state(cond, creature(cha: 16))
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 3, speed: 1, successes: 5 },
      spell:  { name: 'Bolt', tier: 0, mana_cost: 0, attack_roll: true,
                damage_type: 'physical', casting_attribute: 'cha' },
      targets: [{ id: tgt[:id], defense: { choice: 'block', successes: 2, dice: 3, speed: 1 } }]
    )
    expect(out[:targets].first[:outcome]).to eq('hit')
    expect(out[:targets].first[:applied].first[:amount]).to eq(7)     # net 3: floor(16/4)+0.5+3
    expect(s.combatant(tgt[:id])[:combat_pool_spent]).to eq(4)        # Block speed 1 + dice 3
    expect(s.combatant(caster[:id])[:combat_pool_spent]).to eq(4)     # caster speed 1 + dice 3
  end

  it 'registers a Concentration Entry for a Channeled sustain' do
    s = state
    caster = s.add_combatant('1')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 2, speed: 1, successes: 1 },
      spell:  { name: 'Bless', tier: 1, cast_skill: 'faith', mana_cost: 0 }, targets: [],
      sustain: { kind: 'concentration', mode: 'maintain', reservoir_reset: 'per_turn' }
    )
    expect(out[:sustain]).to eq(kind: 'concentration', spell_name: 'Bless')
    held = s.combatant(caster[:id])[:concentration]
    expect(held.map { |e| e[:spell_name] }).to include('Bless')
    expect(held.first[:cast_skill]).to eq('faith')
  end

  it 'registers a Casting Entry for a multi-turn Long Cast' do
    s = state
    caster = s.add_combatant('1')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 2, speed: 1, successes: 1 },
      spell:  { name: 'Ritual of Warding', tier: 2, mana_cost: 0 }, targets: [],
      sustain: { kind: 'long_cast', turns_required: 3 }
    )
    expect(out[:sustain]).to eq(kind: 'long_cast', spell_name: 'Ritual of Warding', turns_required: 3)
    casting = s.combatant(caster[:id])[:casting].first
    expect(casting[:turns_remaining]).to eq(2) # turns_required − 1
  end

  it 'preview (commit: false) reports the same numbers but mutates nothing' do
    cond = build_instance
    s = state(cond)
    caster = s.add_combatant('1'); tgt = s.add_combatant('2')
    out = s.resolve_cast_payload(
      commit: false,
      caster: { id: caster[:id], dice: 3, speed: 1, successes: 3 },
      spell:  { name: 'Firebolt', tier: 1, mana_cost: 5, toxicity: 2 },
      targets: [{ id: tgt[:id], effects: [{ kind: 'damage', amount: 4, damage_type: 'fire', threshold: 0 }] }]
    )
    expect(out[:committed]).to be false
    expect(out[:mana_spent]).to eq(5)
    expect(out[:targets].first[:applied].first[:severity_map]).to eq(moderate: 5) # same bucketing
    # ...but nothing was applied:
    expect(s.combatant(caster[:id])[:combat_pool_spent]).to eq(0)
    expect(cond.state.mana_spent).to eq(0)
    expect(cond.state.magic_toxicity).to eq(0)
    expect(cond.state.hp_damage.values.sum).to eq(0)
  end

  it 'honors DM overrides for Mana, Toxicity, and pool spends on commit' do
    cond = build_instance
    s = state(cond)
    caster = s.add_combatant('1')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 4, speed: 2, successes: 1 },
      spell:  { name: 'Firebolt', tier: 1, mana_cost: 5, toxicity: 3 }, targets: [],
      override: { mana: 2, toxicity: 0, pool_spends: [{ id: caster[:id], amount: 9 }] }
    )
    expect(out[:mana_spent]).to eq(2)
    expect(out[:toxicity][:requested]).to eq(0)
    expect(s.combatant(caster[:id])[:combat_pool_spent]).to eq(9)
    expect(cond.state.magic_toxicity).to eq(0)
  end

  it 'rejects a payload with no caster id without mutating' do
    s = state
    out = s.resolve_cast_payload(spell: { name: 'Firebolt' }, targets: [])
    expect(out[:ok]).to be false
  end
end
