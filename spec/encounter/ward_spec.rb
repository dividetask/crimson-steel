require 'spec_helper'
require 'encounter'
require 'conditions'
require 'tmpdir'

# Ward: grants temporary hit points that expire with the Spell's duration
# ("rank turns"). It is NOT a concentration Spell — the temp HP and the
# matching `ward` condition fade together when the duration runs out.
RSpec.describe 'Encounter — Ward' do
  let(:tmpdir) { Dir.mktmpdir('enc-ward') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature
    obj = Object.new
    obj.define_singleton_method(:tier) { 1 }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:total_level) { 4 } # rank = 4 → "rank turns" = 4
    obj.define_singleton_method(:max_hit_points) { 40 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { 'c' }
    obj
  end

  # One persistent Conditions::Instance per creature so applied temp HP /
  # conditions stick across reads.
  def conditions
    cat = (@catalog ||= Conditions::Catalog.load)
    @conditions ||= Hash.new { |h, k| h[k] = Conditions::Instance.new(catalog: cat) }
  end

  def state
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(id) { conditions[id] },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
                         rounds_per_day: 10_000)
  end

  def cast_ward(s, caster, ally, amount: 5)
    s.resolve_cast_payload(
      caster: { id: caster[:id], dice: 0, speed: 0, successes: 0 },
      # enrich_cast_payload! marks the temp-HP condition by base name; simulate
      # that here (the spec drives resolve_cast_payload directly).
      spell:  { name: 'Ward', tier: 1, cast_skill: 'invocation', mana_cost: 0, temp_hp_condition: 'ward' },
      targets: [{ id: ally[:id],
                  effects: [{ kind: 'temp_hp', amount: amount, duration: 'rank turns' }] }]
    )
  end

  it 'grants temporary hit points with a turns-based expiry' do
    s = state
    caster = s.add_combatant('1'); ally = s.add_combatant('2')
    cast_ward(s, caster, ally, amount: 5)

    thp = conditions[ally[:creature_id]].state.temporary_hit_points
    expect(thp[:amount]).to eq(5)
    expect(thp[:ends_on_round]).to be > s.current_round
  end

  it 'shows a `ward` condition that shares the temp HP expiry' do
    s = state
    caster = s.add_combatant('1'); ally = s.add_combatant('2')
    cast_ward(s, caster, ally)

    inst = conditions[ally[:creature_id]]
    expect(inst.active_effect_names).to include('ward')
    thp_end = inst.state.temporary_hit_points[:ends_on_round]
    # Just before expiry both are still live; at expiry both are gone.
    expect(inst.active_effect_names(current_round: thp_end - 1)).to include('ward')
    inst.clear_expired_effects(thp_end)
    expect(inst.state.temporary_hit_points).to be_nil
    expect(inst.active_effect_names).not_to include('ward')
  end
end
