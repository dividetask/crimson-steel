require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Shield of Faith: the shielding caster blocks an attack on the protected ally
# as a separate Opposing Roll, fueled by spending Reservoir dice.
RSpec.describe 'Encounter — Shield of Faith block' do
  let(:tmpdir) { Dir.mktmpdir('enc-shield') }
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

  it "the caster's block opposes the attack and spends Reservoir dice" do
    s = state
    atk = s.add_combatant('1'); dfn = s.add_combatant('2'); caster = s.add_combatant('3')
    s.begin_concentration(caster[:id], spell_name: 'Shield of Faith', source: 'sof',
                          spell_tier: 1, cast_skill: 'invocation', mode: 'reservoir',
                          reservoir_reset: 'per_turn', initial_reservoir: 5)

    out = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 5 },
      defense: { choice: 'none' },
      shield: { id: caster[:id], successes: 3, dice: 4, spell_name: 'Shield of Faith' },
      allies: [])

    expect(out[:net_dos]).to eq(2) # 5 attacker − 3 shield
    res = s.combatant(caster[:id])[:concentration].find { |e| e[:spell_name] == 'Shield of Faith' }
    expect(res[:reservoir]).to eq(1) # 5 − 4 discharged
  end

  it 'a preview (commit: false) reports the reduced net without spending the Reservoir' do
    s = state
    atk = s.add_combatant('1'); dfn = s.add_combatant('2'); caster = s.add_combatant('3')
    s.begin_concentration(caster[:id], spell_name: 'Shield of Faith', source: 'sof',
                          spell_tier: 1, cast_skill: 'invocation', mode: 'reservoir',
                          reservoir_reset: 'per_turn', initial_reservoir: 5)
    out = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0, commit: false,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 5 },
      defense: { choice: 'none' },
      shield: { id: caster[:id], successes: 3, dice: 4, spell_name: 'Shield of Faith' },
      allies: [])
    expect(out[:net_dos]).to eq(2)
    res = s.combatant(caster[:id])[:concentration].find { |e| e[:spell_name] == 'Shield of Faith' }
    expect(res[:reservoir]).to eq(5) # untouched on preview
  end
end
