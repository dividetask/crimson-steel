require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Verifies the user-reported scenario: a bleeding Affliction inflicted before
# the DM advances time by 1 minute (= 10 Rounds, per conditions_config.yaml
# Frequency Rounds) should, when the victim's turn arrives, be due — and stay
# due, owing one save per missed Round, until the elapsed minute is worked off.
#
# The mechanic under test: Conditions' Resolve Affliction reschedules the
# survivor from its PREVIOUS scheduled Round + frequency (lib/conditions/
# instance.rb), not from "now", so a forward time jump does not let the bleed
# skip the Rounds it slept through. Encounter::State#pending_afflictions reads
# the gap against current_abs_round.
RSpec.describe 'Encounter::State — Affliction catch-up after a time jump' do
  let(:tmpdir) { Dir.mktmpdir('enc-bleed') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature(tier: 1)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 200 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Mob' }
    obj
  end

  # One live Conditions::Instance per Creature ID, carrying the shipped catalog.
  let(:conditions) do
    Hash.new { |h, k| h[k] = Conditions::Instance.new(catalog: Conditions::Catalog.load) }
  end

  # A mutable clock: round_of_day is read live from `clock[:round]`, so the test
  # can "advance time" by bumping it (1 minute = 10 Rounds).
  let(:clock) { { round: 100 } }

  def state
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(id) { conditions[id.to_s] },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: clock[:round] } },
                         rounds_per_day: 100_000)
  end

  it 'a bleed inflicted before a 1-minute jump owes one save per missed Round' do
    s = state
    c = s.add_combatant('101')
    inst = conditions['101']

    # Inflict bleeding at the current Round (100). It schedules to the next
    # Round (101) — bleeding ticks every Round. Potency 30 is high enough that
    # the bleed survives the catch-up (tier-1 decay loses 1 Potency per save).
    inst.inflict_affliction('bleeding', inflicter_tier: 1, delta: 30, current_round: clock[:round])
    expect(inst.state.afflictions['bleeding'][:next_resolution_round]).to eq(101)
    expect(s.pending_afflictions(c[:id])).to eq([]) # not yet due — it ticks next Round

    # The DM advances time by 1 minute = 10 Rounds (the Encounter "+1 min"
    # control). The bleed slept through Rounds 101..110.
    clock[:round] += 10 # -> Round 110

    # When the victim's turn arrives, the bleed is due.
    expect(s.pending_afflictions(c[:id])).to eq(['bleeding'])

    # Resolve it turn after turn (0 net successes). Each resolution reschedules
    # one Round forward — NOT to "now" — so it keeps showing up until the
    # schedule catches up to Round 110: one save per missed Round.
    schedule = []
    resolutions = 0
    while s.pending_afflictions(c[:id]).include?('bleeding')
      s.resolve_affliction_save(c[:id], 'bleeding', 0)
      schedule << inst.state.afflictions.dig('bleeding', :next_resolution_round)
      resolutions += 1
      break if resolutions > 50 # guard against a runaway loop
    end

    # 10 catch-up saves — exactly the 10 Rounds the minute covered — each
    # stepping the schedule forward by one Round (102, 103, … 111).
    expect(resolutions).to eq(10)
    expect(schedule).to eq([102, 103, 104, 105, 106, 107, 108, 109, 110, 111])

    # The bleed survived and its schedule has caught up to just past "now", so
    # it is no longer due this Round.
    expect(inst.state.afflictions['bleeding'][:next_resolution_round]).to eq(111)
    expect(s.pending_afflictions(c[:id])).to eq([])
  end

  it 'without the jump, a bleed comes due once per Round (no backlog)' do
    s = state
    c = s.add_combatant('101')
    inst = conditions['101']
    inst.inflict_affliction('bleeding', inflicter_tier: 1, delta: 30, current_round: clock[:round]) # Round 100 -> schedules 101
    expect(s.pending_afflictions(c[:id])).to eq([]) # not due the Round it lands

    clock[:round] += 1 # -> Round 101: first tick
    expect(s.pending_afflictions(c[:id])).to eq(['bleeding'])
    s.resolve_affliction_save(c[:id], 'bleeding', 0) # reschedules to 102
    expect(s.pending_afflictions(c[:id])).to eq([]) # only the one tick this Round

    clock[:round] += 1 # -> Round 102
    expect(s.pending_afflictions(c[:id])).to eq(['bleeding']) # due again, just once
  end
end
