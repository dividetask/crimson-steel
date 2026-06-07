require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Spiritual Weapon: an auto-channel Spell that fills a persistent Reservoir at
# cast and strikes each turn with Reservoir dice — a free force attack.
RSpec.describe 'Encounter — Spiritual Weapon' do
  let(:tmpdir) { Dir.mktmpdir('enc-sw') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature
    obj = Object.new
    obj.define_singleton_method(:tier) { 0 }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 40 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { 'c' }
    obj
  end

  def state
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(_id) { Conditions::Instance.new },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
                         rounds_per_day: 10_000)
  end

  it 'casting fills a persistent Reservoir with the cast dice' do
    s = state
    caster = s.add_combatant('1')
    out = s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 5, speed: 0, successes: 0 },
      spell:  { name: 'Spiritual Weapon', tier: 2, cast_skill: 'invocation', mana_cost: 0 }, targets: [],
      sustain: { kind: 'concentration', mode: 'auto', reservoir_reset: 'persistent' }
    )
    expect(out[:sustain][:reservoir]).to eq(5)
    held = s.combatant(caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:reservoir]).to eq(5)
    expect(held[:reservoir_reset]).to eq('persistent')
  end

  it "the strike deals force damage and costs no Combat Pool (Reservoir dice)" do
    s = state
    caster = s.add_combatant('1'); dfn = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0, free_attacker_pool: true,
      weapon: { damage_types: ['force'], threshold: 0, base_damage: 0 },
      attacker: { id: caster[:id], dice: 5, speed: 0, successes: 4 },
      defense: { choice: 'none' }, allies: []
    )
    expect(out[:damage]).to eq(4)         # base 0 + net 4 force
    expect(out[:damage_type]).to eq('force')
    expect(s.combatant(caster[:id])[:combat_pool_spent]).to eq(0) # nothing spent
  end
end
