require 'spec_helper'
require 'encounter'
require 'conditions'
require 'tmpdir'

# Spiritual Weapon is a TIMED channel (not true Concentration): it lasts
# "rank turns", is immune to the damage-break Save, shows a condition on the
# caster, and is dropped by per-turn cleanup when its time runs out.
RSpec.describe 'Encounter — Spiritual Weapon (timed)' do
  let(:tmpdir) { Dir.mktmpdir('enc-swt') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature
    obj = Object.new
    obj.define_singleton_method(:tier) { 2 }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:total_level) { 3 } # rank = 3 → 3 turns
    obj.define_singleton_method(:max_hit_points) { 40 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { 'c' }
    obj
  end

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

  def cast_sw(s, caster, dice: 5)
    s.resolve_cast_payload(
      caster: { id: caster[:id], dice: dice, speed: 0, successes: 0 },
      spell:  { name: 'Spiritual Weapon', tier: 2, cast_skill: 'invocation',
                mana_cost: 0, duration: 'rank turns' },
      targets: [],
      sustain: { kind: 'concentration', mode: 'auto', reservoir_reset: 'persistent' }
    )
  end

  it 'casts with a turns-based expiry, a filled Reservoir, and a caster condition' do
    s = state
    caster = s.add_combatant('1')
    cast_sw(s, caster)

    held = s.combatant(caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:reservoir]).to eq(5)
    expect(held[:expires_on_round]).to eq(s.current_round + 3) # rank (total_level) = 3
    expect(conditions[caster[:creature_id]].active_effect_names).to include('spiritual_weapon')
  end

  it 'is immune to the damage-break Save (timed, not Concentration)' do
    s = state
    caster = s.add_combatant('1')
    cast_sw(s, caster)
    c = s.combatant(caster[:id])
    # A resolver that always fails would end a true Concentration; the timed
    # entry must be skipped and survive.
    s.send(:trigger_concentration_saves, c, 99, ->(**) { false })
    expect(s.combatant(caster[:id])[:concentration]).not_to be_empty
  end

  it 'is dropped by per-turn cleanup once its time runs out' do
    s = state
    caster = s.add_combatant('1')
    cast_sw(s, caster)
    # Force the entry past its expiry and run the caster's end-of-turn cleanup.
    s.combatant(caster[:id])[:concentration].first[:expires_on_round] = s.current_round
    notes = s.send(:apply_per_turn_cleanup, caster[:id])
    expect(s.combatant(caster[:id])[:concentration]).to be_empty
    expect(notes.map { |n| n[:reason] }).to include('expired')
  end
end
