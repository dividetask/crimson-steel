require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Encounter::State#turns_before — whose turns come before a Combatant's next
# one (encounter_design.md → Turns Before). It is what a player waiting for
# their turn is told: how many creatures act before them.
RSpec.describe 'Encounter::State#turns_before' do
  let(:tmpdir) { Dir.mktmpdir('enc-turns-before') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  let(:conditions) { Hash.new { |h, k| h[k] = Conditions::Instance.new } }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature(tier: 0, max_hp: 20)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { max_hp }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Mob' }
    obj
  end

  def state(creatures = Hash.new { |_h, _k| creature })
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(id) { creatures[id.to_s] },
                         conditions_for: ->(id) { conditions[id.to_s] },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } })
  end

  # Four one-turn Combatants in Combat, acting in the order a, b, c, d.
  def four
    s = state
    list = %w[1 2 3 4].map { |id| s.add_combatant(id) }
    s.start_combat
    s.reroll_initiative(prerolled_initiatives: list.map { |c| c[:id] }.zip(%w[9 8 7 6]).to_h)
    [s, *list.map { |c| c[:id] }]
  end

  it 'lists everyone from the Acting Combatant up to the Combatant' do
    s, a, b, c, d = four
    s.set_acting_combatant(a)
    expect(s.turns_before(d)).to eq([a, b, c])
    expect(s.turns_before(b)).to eq([a])
  end

  it "is empty on the Combatant's own turn" do
    s, a, = four
    s.set_acting_combatant(a)
    expect(s.turns_before(a)).to eq([])
  end

  it 'runs on into the next Round for a Combatant that has already acted' do
    s, a, b, c, d = four
    s.set_acting_combatant(c)
    expect(s.turns_before(a)).to eq([c, d])
    expect(s.turns_before(b)).to eq([c, d, a])
  end

  it 'leaves out a Combatant that cannot act: its turn is skipped' do
    s, a, _b, c, d = four
    conditions['2'].state.hp_damage = { major: 25 } # dying: past its 20 Hit Points
    s.set_acting_combatant(a)
    expect(s.turns_before(d)).to eq([a, c])
  end

  it 'has one entry per turn for a Combatant with several turns a Round' do
    # Tier 3 takes two turns a Round (Turns Per Round): Time Ticks 1 and 2.
    s = state('1' => creature(tier: 0), '2' => creature(tier: 3))
    slow = s.add_combatant('1')[:id]
    fast = s.add_combatant('2')[:id]
    s.start_combat
    s.reroll_initiative(prerolled_initiatives: { slow => '9', fast => '8' })
    expect(s.time_ticks_per_round).to eq(2)
    s.set_acting_combatant(fast) # Tick 1, after the slow one
    expect(s.turns_before(slow)).to eq([fast, fast])
    s.set_acting_combatant(slow)
    expect(s.turns_before(fast)).to eq([slow])
  end

  it 'is nil when nobody is acting, and outside Combat' do
    s = state
    c = s.add_combatant('1')[:id]
    expect(s.turns_before(c)).to be_nil # no Combat
    s.start_combat
    expect(s.acting_combatant_id).to be_nil
    expect(s.turns_before(c)).to be_nil
  end
end
