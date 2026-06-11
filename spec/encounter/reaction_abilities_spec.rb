require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Defender Reaction Abilities resolved in an attack:
#   Better Lucky Than Good — a Defense-step Reaction: no defender roll, costs no
#     Combat Pool, spends Mana; the attacker's halved dice arrive pre-rolled.
#   Danger Sense / Primal Tenacity — post-roll Reactions: one-shot Damage
#     Resilience / Damage Reduction on this attack, plus a Mana debit.
RSpec.describe 'Encounter — defender Reaction Abilities' do
  let(:tmpdir) { Dir.mktmpdir('enc-react') }
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

  # Stable Conditions instance per id so Mana spends accumulate and can be read.
  def state
    @cond ||= {}
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(id) { @cond[id] ||= Conditions::Instance.new },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
                         rounds_per_day: 10_000)
  end

  def weapon
    { base_damage: 0, threshold: 1, damage_types: ['physical'], bleed: 0 }
  end

  describe 'Better Lucky Than Good (Defense-step Reaction)' do
    it 'rolls no defense (full net), is eligible against any attack, and spends Mana on commit' do
      s = state
      atk = s.add_combatant('1'); dfn = s.add_combatant('2')
      out = s.resolve_attack_payload(
        target_id: dfn[:id], attack_kind: 'spell', weapon: weapon,
        attacker: { id: atk[:id], dice: 3, speed: 0, successes: 4 },
        defense: { choice: 'better_lucky', id: dfn[:id], mana_cost: 4 }, allies: [])
      expect(out[:ok]).not_to be false
      expect(out[:net_dos]).to eq(4) # no opposing roll
      expect(@cond[dfn[:creature_id]].state.mana_spent).to eq(4)
    end

    it 'spends no Mana on a preview' do
      s = state
      atk = s.add_combatant('1'); dfn = s.add_combatant('2')
      s.resolve_attack_payload(
        target_id: dfn[:id], commit: false, weapon: weapon,
        attacker: { id: atk[:id], dice: 3, speed: 0, successes: 4 },
        defense: { choice: 'better_lucky', id: dfn[:id], mana_cost: 4 }, allies: [])
      expect(@cond[dfn[:creature_id]].state.mana_spent).to eq(0)
    end
  end

  describe 'post-roll Reactions' do
    it 'Primal Tenacity reduces the damage and spends Mana' do
      s = state
      atk = s.add_combatant('1'); dfn = s.add_combatant('2')
      base = s.resolve_attack_payload(
        target_id: dfn[:id], commit: false, weapon: weapon,
        attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8 },
        defense: { choice: 'none' }, allies: [])
      out = s.resolve_attack_payload(
        target_id: dfn[:id], weapon: weapon,
        attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8 },
        defense: { choice: 'none' },
        defender_reactions: [{ target: 'damage_reduction', amount: 4, mana_cost: 4 }], allies: [])
      expect(out[:damage]).to eq(base[:damage] - 4)
      expect(@cond[dfn[:creature_id]].state.mana_spent).to eq(4)
    end

    it 'Danger Sense adds one-shot Damage Resilience and spends Mana' do
      s = state
      atk = s.add_combatant('1'); dfn = s.add_combatant('2')
      out = s.resolve_attack_payload(
        target_id: dfn[:id], weapon: weapon,
        attacker: { id: atk[:id], dice: 6, speed: 0, successes: 8 },
        defense: { choice: 'none' },
        defender_reactions: [{ target: 'damage_resilience', amount: 4, mana_cost: 4 }], allies: [])
      expect(out[:damage_resilience]).to eq(4) # base 0 + Danger Sense 4
      expect(@cond[dfn[:creature_id]].state.mana_spent).to eq(4)
    end
  end
end
