require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Tier Mismatch Inherent damage reduction applied through the live
# resolve_attack_payload path (encounter_design.md -> Tier Mismatch).
RSpec.describe 'Encounter — Tier Mismatch in combat' do
  let(:tmpdir)    { Dir.mktmpdir('enc-tm') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature_for(tier)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 40 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { 't' }
    obj
  end

  # tiers: { creature_id_string => tier }
  def build(tiers)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(id) { (t = tiers[id.to_s]) && creature_for(t) },
                         conditions_for: ->(_id) { Conditions::Instance.new },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
                         rounds_per_day: 10_000)
  end

  it 'a higher-Tier defender shrugs off 5 damage per Tier above the attacker' do
    s = build('1' => 1, '3' => 3)
    atk = s.add_combatant('1'); dfn = s.add_combatant('3')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 12 },
      defense: { choice: 'none' }, allies: [], commit: false)
    expect(out[:inherent_dr]).to eq(10)   # 5 * (3 - 1)
    expect(out[:damage]).to eq(2)         # net 12 - 10
  end

  it 'Glorious Charge (attacker tier_bonus) shrinks the Tier gap and the Inherent DR' do
    s = build('1' => 1, '2' => 2)
    atk = s.add_combatant('1'); dfn = s.add_combatant('2')
    base = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8 },
      defense: { choice: 'none' }, allies: [], commit: false)
    expect(base[:inherent_dr]).to eq(5)   # 5 * (2 - 1)

    bumped = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8, tier_bonus: 1 },
      defense: { choice: 'none' }, allies: [], commit: false)
    expect(bumped[:inherent_dr]).to eq(0) # effective Tier 2 == defender Tier 2
    expect(bumped[:damage]).to eq(8)
  end

  it 'no reduction when the attacker is equal or higher Tier' do
    s = build('3' => 3, '1' => 1)
    atk = s.add_combatant('3'); dfn = s.add_combatant('1')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0,
      attacker: { id: atk[:id], dice: 6, speed: 0, successes: 5 },
      defense: { choice: 'none' }, allies: [], commit: false)
    expect(out[:inherent_dr]).to eq(0)
    expect(out[:damage]).to eq(5)
  end
end
