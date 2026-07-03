require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Passive Damage Reduction — the defender's equipped Armor + direct
# `damage_reduction` attribute + active-effect DR Modifiers (Rage) — reduces
# both weapon and spell damage before the Severity split, alongside the
# Tier-Mismatch Inherent DR. (encounter_design.md -> Damage / Severity.)
RSpec.describe 'Encounter — passive Damage Reduction in combat' do
  let(:tmpdir)    { Dir.mktmpdir('enc-dr') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  # A creature that exposes Damage Reduction directly (a monster stat / the
  # equipped-Armor total surfaces the same way in production).
  def creature_for(tier, reduction: 0)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:damage_reduction) { reduction }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 40 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { 'd' }
    obj
  end

  # creatures: { id_string => creature }; a stable Conditions instance per id
  # so active-effect DR Modifiers persist and can be read.
  def build(creatures)
    @cond ||= {}
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(id) { creatures[id.to_s] },
                         conditions_for: ->(id) { @cond[id] ||= Conditions::Instance.new },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
                         rounds_per_day: 10_000)
  end

  def weapon
    { base_damage: 0, threshold: 1, damage_types: ['physical'], bleed: 0 }
  end

  it 'reduces weapon damage by the defender Damage Reduction (equal Tier, no Inherent DR)' do
    s = build('1' => creature_for(1), '2' => creature_for(1, reduction: 3))
    atk = s.add_combatant('1'); dfn = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], weapon: weapon,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8 },
      defense: { choice: 'none' }, allies: [], commit: false)
    expect(out[:inherent_dr]).to eq(0)
    expect(out[:passive_dr]).to eq(3)
    expect(out[:damage]).to eq(5) # net 8 - 3
  end

  it 'stacks passive Damage Reduction on top of the Tier-Mismatch Inherent DR' do
    s = build('1' => creature_for(1), '3' => creature_for(3, reduction: 2))
    atk = s.add_combatant('1'); dfn = s.add_combatant('3')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], weapon: weapon,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 14 },
      defense: { choice: 'none' }, allies: [], commit: false)
    expect(out[:inherent_dr]).to eq(10) # 5 * (3 - 1)
    expect(out[:passive_dr]).to eq(2)
    expect(out[:damage]).to eq(2)        # net 14 - 10 - 2
  end

  it 'adds active-effect (Rage) Damage Reduction Modifiers to the passive total' do
    s = build('1' => creature_for(1), '2' => creature_for(1)) # no direct attribute DR
    atk = s.add_combatant('1'); dfn = s.add_combatant('2')
    # An active-effect Damage Reduction Modifier (as Rage grants: +2 Circumstance).
    inst = (@cond[dfn[:creature_id]] ||= Conditions::Instance.new)
    inst.apply_effect(source_id: 'special:rage:0', bonus_type: 'Circumstance',
                      amount: 2, target_key: 'damage_reduction')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], weapon: weapon,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8 },
      defense: { choice: 'none' }, allies: [], commit: false)
    expect(out[:passive_dr]).to eq(2) # rage: 1 + floor(5/3)
    expect(out[:damage]).to eq(6)     # net 8 - 2
  end

  it 'stacks passive Damage Reduction with the one-shot Primal Tenacity Reaction' do
    s = build('1' => creature_for(1), '2' => creature_for(1, reduction: 3))
    atk = s.add_combatant('1'); dfn = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], weapon: weapon,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8 },
      defense: { choice: 'none' },
      defender_reactions: [{ target: 'damage_reduction', amount: 4, mana_cost: 4 }],
      allies: [], commit: false)
    expect(out[:passive_dr]).to eq(3) # Reaction rides separately, not double-counted
    expect(out[:damage]).to eq(1)     # net 8 - 3 (passive) - 4 (Primal Tenacity)
  end

  describe 'spell damage' do
    def dmg_of(out, tid)
      out[:targets].find { |t| t[:id] == tid }[:applied].find { |e| e[:kind] == 'damage' }
    end

    it 'reduces spell damage by the target Damage Reduction' do
      s = build('1' => creature_for(1), '2' => creature_for(1, reduction: 3))
      caster = s.add_combatant('1'); tgt = s.add_combatant('2')
      out = s.resolve_cast_payload(
        caster: { id: caster[:id], dice: 3, speed: 0, successes: 3 },
        spell:  { name: 'Bolt', tier: 1, mana_cost: 0 },
        targets: [{ id: tgt[:id], effects: [{ kind: 'damage', amount: 10, damage_type: 'fire', threshold: 0 }] }],
        commit: false)
      expect(dmg_of(out, tgt[:id])[:amount]).to eq(7) # 10 - 3
    end

    it 'stacks spell passive DR on top of the Inherent DR' do
      s = build('1' => creature_for(1), '3' => creature_for(3, reduction: 2))
      caster = s.add_combatant('1'); tgt = s.add_combatant('3')
      out = s.resolve_cast_payload(
        caster: { id: caster[:id], dice: 3, speed: 0, successes: 3 },
        spell:  { name: 'Bolt', tier: 1, mana_cost: 0 },
        targets: [{ id: tgt[:id], effects: [{ kind: 'damage', amount: 14, damage_type: 'fire', threshold: 0 }] }],
        commit: false)
      expect(dmg_of(out, tgt[:id])[:amount]).to eq(2) # 14 - 10 (Inherent) - 2 (passive)
    end
  end
end
