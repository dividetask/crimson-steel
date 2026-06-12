require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Ring of Parry resolution: the free Parry ('ringparry') opposes the attack like
# a normal Parry but spends NO Combat Pool from the defender (pool_cost false) —
# its cost is the daily ring charge, consumed route-side on commit.
RSpec.describe 'Encounter — Ring of Parry (free defense)' do
  let(:tmpdir)    { Dir.mktmpdir('enc-ringparry') }
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

  it "opposes the attack with the defender's Successes but spends no Combat Pool" do
    s = state
    atk = s.add_combatant('1')
    dfn = s.add_combatant('2')
    pool_before = s.combat_pool_remaining(dfn[:id])

    out = s.resolve_attack_payload(
      target_id: dfn[:id], attack_kind: 'melee', damage_bonus: 0,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 5 },
      defense:  { choice: 'ringparry', id: dfn[:id], dice: 7, speed: 0, successes: 3 },
      allies: [], commit: true
    )

    expect(out[:ok]).not_to eq(false)
    # The defender's 3 Successes opposed the 5 → net 2 dos.
    expect(out[:net_dos]).to eq(2)
    # No Combat Pool was charged to the defender (the ring charge pays instead).
    expect(out[:pool_spends].any? { |sp| sp[:id] == dfn[:id] }).to be(false)
    expect(s.combat_pool_remaining(dfn[:id])).to eq(pool_before)
  end

  it "a normal Parry, by contrast, does spend the defender's Combat Pool" do
    s = state
    atk = s.add_combatant('1')
    dfn = s.add_combatant('2')
    pool_before = s.combat_pool_remaining(dfn[:id])

    s.resolve_attack_payload(
      target_id: dfn[:id], attack_kind: 'melee', damage_bonus: 0,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 5 },
      defense:  { choice: 'parry', id: dfn[:id], dice: 4, speed: 0, successes: 3 },
      allies: [], commit: true
    )

    expect(s.combat_pool_remaining(dfn[:id])).to be < pool_before
  end
end
