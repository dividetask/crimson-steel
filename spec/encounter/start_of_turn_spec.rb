require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Start of Turn (turn_action_stub.md → Start of Turn): the Acting
# Combatant resolves the Afflictions due this Round (using DM-supplied
# Successes) and clears expired Active Effects. Exercised through
# Encounter::State with injected creature_lookup / conditions_for /
# timestamp so it runs without the live Creatures / Chronicle domains.
RSpec.describe 'Encounter::State start of turn' do
  let(:tmpdir) { Dir.mktmpdir('enc-sot') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature(tier: 1)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |_a| 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Mob' }
    obj
  end

  # One live Conditions::Instance per Creature ID, carrying the real
  # Affliction catalog so resolution and scheduling behave as shipped.
  let(:conditions) do
    Hash.new { |h, k| h[k] = Conditions::Instance.new(catalog: Conditions::Catalog.load) }
  end

  def state(round_of_day: 100)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(id) { conditions[id.to_s] },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: round_of_day } },
                         rounds_per_day: 1000)
  end

  it 'lists the Afflictions due this Round for the Acting Combatant' do
    s = state
    c = s.add_combatant('101')
    # Inflicted last Round → next resolution this Round (current_abs_round 100).
    conditions['101'].inflict_affliction('bleeding', inflicter_tier: 1, delta: 3, current_round: 99)
    expect(s.pending_afflictions(c[:id])).to eq(['bleeding'])
  end

  it 'resolves a due Affliction Save and reschedules the survivor to the next Round' do
    s = state
    c = s.add_combatant('101')
    inst = conditions['101']
    inst.inflict_affliction('bleeding', inflicter_tier: 1, delta: 5, current_round: 99)

    result = s.resolve_affliction_save(c[:id], 'bleeding', 0)
    expect(result).not_to be_nil
    # Potency 5 decays by Tier (1) on a 0-success save → 4, so it survives
    # and reschedules one Round forward (current Round 100 + 1).
    expect(inst.state.afflictions['bleeding'][:next_resolution_round]).to eq(101)
  end

  it 'applies the Affliction consequence (HP damage) on a failed save' do
    s = state
    c = s.add_combatant('101')
    inst = conditions['101']
    inst.inflict_affliction('bleeding', inflicter_tier: 1, delta: 1, current_round: 99)
    s.resolve_affliction_save(c[:id], 'bleeding', 0)
    expect(inst.state.hp_damage[:minor]).to be > 0
  end

  it 'lets enough Successes negate the consequence' do
    s = state
    c = s.add_combatant('101')
    inst = conditions['101']
    inst.inflict_affliction('bleeding', inflicter_tier: 1, delta: 1, current_round: 99)
    # Magnitude is 1 (Potency 1); a single Success cancels it.
    s.resolve_affliction_save(c[:id], 'bleeding', 5)
    expect(inst.state.hp_damage[:minor].to_i).to eq(0)
  end

  it 'resolve_affliction_save returns nil for an unknown Combatant or Affliction' do
    s = state
    c = s.add_combatant('101')
    expect(s.resolve_affliction_save(999, 'bleeding', 0)).to be_nil       # no Combatant
    expect(s.resolve_affliction_save(c[:id], 'bleeding', 0)).to be_nil    # no such Affliction
  end

  it 'clears expired Active Effects for the current Round when the turn begins' do
    s = state
    c = s.add_combatant('101')
    inst = conditions['101']
    inst.apply_effect(target_key: 'martial', bonus_type: 'Circumstance', amount: 2,
                      source_id: 'spell:expiring', ends_on_round: 100)
    inst.apply_effect(target_key: 'martial', bonus_type: 'Enhancement', amount: 1,
                      source_id: 'spell:lasting', ends_on_round: 200)

    out = s.begin_turn_for(c[:id])
    expect(out[:cleared].map { |e| e[:source_id] }).to eq(['spell:expiring'])
    expect(inst.state.effects.map { |e| e[:source_id] }).to eq(['spell:lasting'])
  end

  it 'treats an active Affliction with no schedule (nil) as due' do
    s = state
    c = s.add_combatant('101')
    inst = conditions['101']
    # Seeded / clock-less bleeding, as in the example data: it has no
    # next_resolution_round but should still resolve at the Start of Turn.
    inst.state.afflictions['bleeding'] =
      { potency: 3, inflicting_tier: 1, next_resolution_round: nil }

    expect(s.pending_afflictions(c[:id])).to eq(['bleeding'])

    s.resolve_affliction_save(c[:id], 'bleeding', 0)
    # Resolving stamps a real schedule (current Round 100 + 1) so the
    # bleed then recurs every Round.
    expect(inst.state.afflictions['bleeding'][:next_resolution_round]).to eq(101)
  end

  it 'returns nil for an unknown Combatant' do
    expect(state.begin_turn_for(999)).to be_nil
  end

  describe 'Affliction scheduled on the victim\'s next turn' do
    # Bleed inflicted by the Acting Combatant on a Combatant whose turn is
    # still coming this Round → due this Round; on a Combatant that has
    # already acted → due next Round.
    def two_combatant_combat
      s = state
      a = s.add_combatant('101'); c = s.add_combatant('102')
      s.start_combat
      s.set_initiative(a[:id], '9'); s.set_initiative(c[:id], '5') # a acts before c
      [s, a, c]
    end

    it 'is due this Round when the victim has not yet acted' do
      s, a, c = two_combatant_combat
      s.set_acting_combatant(a[:id]) # a is acting; c still to come
      s.apply_weapon_bleed(c[:id], a[:id], 3)
      # current_abs_round is 100 → due this Round.
      expect(conditions['102'].state.afflictions['bleeding'][:next_resolution_round]).to eq(100)
      expect(s.pending_afflictions(c[:id])).to eq(['bleeding'])
    end

    it 'is due next Round when the victim has already acted' do
      s, a, c = two_combatant_combat
      s.set_acting_combatant(c[:id]) # c is acting; a already acted (a is above c)
      s.apply_weapon_bleed(a[:id], c[:id], 3)
      expect(conditions['101'].state.afflictions['bleeding'][:next_resolution_round]).to eq(101)
      expect(s.pending_afflictions(a[:id])).to eq([]) # not due until next Round
    end
  end

  describe 'Combat Pool lifecycle' do
    it 'starts empty at Start Combat and refills when the turn begins' do
      s = state
      c = s.add_combatant('101')
      s.start_combat
      pool = s.get_combat_pool(c[:id])
      expect(pool).to be > 0
      expect(s.combat_pool_remaining(c[:id])).to eq(0) # empty when Combat starts

      s.begin_turn_for(c[:id])
      expect(s.combat_pool_remaining(c[:id])).to eq(pool) # refilled when the turn begins
    end

    it 'does not refill the outgoing Combatant\'s Combat Pool on End Turn' do
      s = state
      a = s.add_combatant('101'); b = s.add_combatant('102')
      s.start_combat
      s.begin_turn_for(a[:id])         # a's turn begins, pool full
      s.spend_combat_pool(a[:id], 2)   # a spends 2
      s.set_initiative(a[:id], '9'); s.set_initiative(b[:id], '7')
      s.set_acting_combatant(a[:id])

      s.advance_turn # a ends; b's turn begins
      # a is the outgoing Combatant — its spend persists until a's next turn.
      expect(s.combatant(a[:id])[:combat_pool_spent]).to eq(2)
      # b is the incoming Combatant — its turn began, so its pool is full.
      expect(s.combat_pool_remaining(b[:id])).to eq(s.get_combat_pool(b[:id]))
    end
  end

  describe 'Main Actions' do
    it 'start at -1 and are granted at the start of a turn' do
      s = state
      c = s.add_combatant('101')
      expect(s.main_actions_remaining(c[:id])).to eq(-1) # before the first turn
      s.begin_turn_for(c[:id])
      expect(s.main_actions_remaining(c[:id])).to eq(Encounter::State::MAIN_ACTIONS_PER_TURN)
    end

    it 'decrement as Main Actions are spent, unenforced (may go negative)' do
      s = state
      c = s.add_combatant('101')
      s.begin_turn_for(c[:id])
      expect(s.spend_main_action(c[:id])).to eq(1)
      expect(s.spend_main_action(c[:id])).to eq(0)
      expect(s.spend_main_action(c[:id])).to eq(-1) # not enforced — goes negative
    end

    it 'a committed Move spends a Main Action' do
      s = state
      c = s.add_combatant('101')
      s.start_combat
      s.begin_turn_for(c[:id])
      s.apply_move(c[:id])
      expect(s.main_actions_remaining(c[:id])).to eq(1)
    end

    it 'grants the next Combatant its Main Actions on advance_turn' do
      s = state
      a = s.add_combatant('101'); b = s.add_combatant('102')
      s.start_combat
      s.set_initiative(a[:id], '9'); s.set_initiative(b[:id], '5')
      s.set_acting_combatant(a[:id])
      s.advance_turn # -> b's turn begins
      expect(s.acting_combatant_id).to eq(b[:id])
      expect(s.main_actions_remaining(b[:id])).to eq(2)
    end
  end
end
