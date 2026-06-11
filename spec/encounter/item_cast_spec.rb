require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Item casts (turn_action_stub.md → Item) reuse the Cast pipeline:
# resolve_cast_payload spends Combat Pool, applies Magic Toxicity, and routes
# the Spell's Effects exactly as a normal cast. A consumable (Potion / Scroll)
# differs only in two inputs the Item route supplies — a zero Mana Cost (the
# Item, not the caster, supplies the Spell) and, for a Potion / Oil, an
# Item-Form Magic Toxicity amount. This spec locks that contract at the
# Encounter::State seam the route depends on.
RSpec.describe 'Encounter — Item cast contract' do
  let(:tmpdir)    { Dir.mktmpdir('enc-item') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature
    obj = Object.new
    obj.define_singleton_method(:tier) { 1 }
    obj.define_singleton_method(:attribute_value) { |_a| 12 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 40 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:total_level) { 4 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { 'c' }
    obj
  end

  def state(inst)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(_id) { inst },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
                         rounds_per_day: 10_000)
  end

  it 'spends no Mana for a consumable (mana_cost 0) yet imposes the supplied Item-Form Toxicity' do
    inst = Conditions::Instance.new
    s = state(inst)
    drinker = s.add_combatant('1')

    out = s.resolve_cast_payload(
      commit: true,
      spell: { name: 'Heal', tier: 1, cast_skill: 'healing', mana_cost: 0,
               toxicity: 4, polarity: 'positive' },
      caster: { id: drinker[:id], dice: 4, speed: 0, successes: 0 },
      targets: [{ id: drinker[:id] }]
    )

    expect(out[:mana_spent]).to eq(0)               # the Item supplied the Spell
    expect(out[:toxicity][:requested]).to eq(4)     # Item-Form Toxicity imposed
    expect(out[:toxicity][:accepted]).to be true
    expect(inst.state.magic_toxicity).to eq(4)      # actually applied to the drinker
  end

  it 'still spends the Combat Pool dice the cast rolls' do
    inst = Conditions::Instance.new
    s = state(inst)
    drinker = s.add_combatant('1')

    s.resolve_cast_payload(
      commit: true,
      spell: { name: 'Heal', tier: 1, cast_skill: 'healing', mana_cost: 0 },
      caster: { id: drinker[:id], dice: 4, speed: 0, successes: 0 },
      targets: [{ id: drinker[:id] }]
    )
    # pool_cost = speed(0) + dice(4)
    expect(s.combatant(drinker[:id])[:combat_pool_spent]).to eq(4)
  end
end
