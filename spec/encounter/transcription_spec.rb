require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Transcription of docs/common/encounter/encounter_tests.md cases that
# aren't already covered by combat_mode_spec / combat_state_spec /
# state_spec. Injected creature_lookup / conditions_for / timestamp so
# the suite runs without the live Creatures / Chronicle / Timekeeping.
RSpec.describe 'Encounter — encounter_tests.md transcription' do
  let(:tmpdir)    { Dir.mktmpdir('enc-trans') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  # Per-id creature attributes: { id => { tier:, wis:, tags: } }.
  def creature_for(spec)
    obj = Object.new
    tier = spec[:tier] || 0
    wis  = spec[:wis] || 8
    tags = spec[:tags] || ['player_character']
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |a| a == :wis ? wis : 10 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_hit_points) { 20 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { tags }
    obj.define_singleton_method(:name) { "C#{spec[:id]}" }
    obj
  end

  def build(specs: {}, raw: {}, ts: { day_index: 0, round_of_day: 0 }, rpd: 10_000, round_elapsed: nil)
    table = specs.transform_keys(&:to_s)
    Encounter::State.new(raw, data_path: data_path,
                         creature_lookup: ->(id) { (s = table[id.to_s]) && creature_for(s) },
                         conditions_for: ->(_id) { Conditions::Instance.new },
                         current_timestamp_fn: -> { ts },
                         rounds_per_day: rpd,
                         round_elapsed_fn: round_elapsed)
  end

  # ---- Start Combat ----

  it 'Start Combat errors on a Tier beyond Turns Per Round, leaving state unchanged' do
    s = build(specs: { '1' => { id: 1, tier: 6 } })
    s.add_combatant('1')
    expect { s.start_combat }.to raise_error(ArgumentError, /Turns Per Round/)
    expect(s.combat_active?).to be false
  end

  it 'Start Combat does not roll Initiative' do
    s = build(specs: { '1' => { id: 1 } })
    s.add_combatant('1')
    s.start_combat
    expect(s.combatants.first[:initiative_string]).to eq('')
  end

  # ---- Add / Remove Combatant ----

  it 'Add Combatant raising Time Ticks Per Round recomputes every schedule' do
    s = build(specs: { '1' => { id: 1, tier: 0 }, '2' => { id: 2, tier: 0 }, '3' => { id: 3, tier: 3 } })
    s.add_combatant('1'); s.add_combatant('2')
    s.start_combat
    expect(s.time_ticks_per_round).to eq(1)
    s.add_combatant('3') # Tier 3 → Turns Per Round 2 → TPR rises to 2
    expect(s.time_ticks_per_round).to eq(2)
    # Tier-0 → [1]; Tier-3 (T=2) → [1, 2] per the floored-midpoint formula.
    expect(s.combatants.map { |c| c[:time_tick_schedule] }).to eq([[1], [1], [1, 2]])
  end

  it 'Remove Combatant lowering Time Ticks Per Round recomputes and clamps the tick' do
    s = build(specs: { '1' => { id: 1, tier: 0 }, '2' => { id: 2, tier: 4 } })
    s.add_combatant('1'); b = s.add_combatant('2')
    s.start_combat # TPR = 4
    s.instance_variable_set(:@time_tick, 3)
    s.remove_combatant(b[:id]) # TPR drops to 1
    expect(s.time_ticks_per_round).to eq(1)
    expect(s.time_tick).to eq(1)
    expect(s.combatants.first[:time_tick_schedule]).to eq([1])
  end

  it 'Remove Combatant clears their Granted Actions (actor or eligible target)' do
    s = build(specs: { '5' => { id: 5 } })
    c = s.add_combatant('5')
    s.grant_action(combatant_id: c[:id], name: 'A', source: 'x')
    s.grant_action(combatant_id: 99, name: 'B', source: 'y', eligible_targets: [c[:id]])
    s.remove_combatant(c[:id])
    expect(s.granted_actions).to be_empty
  end

  # ---- Set PC Exclusions ----

  it 'Set PC Exclusions rejects a non-PC id and leaves the list unchanged' do
    s = build(specs: { '100' => { id: 100, tags: ['enemy_template'] } }, raw: { 'excluded_pcs' => ['7'] })
    expect { s.set_pc_exclusions(['100']) }.to raise_error(ArgumentError)
    expect(s.excluded_pcs).to eq(['7'])
  end

  it 'Set PC Exclusions rejects an unknown id' do
    s = build(specs: {}, raw: { 'excluded_pcs' => ['7'] })
    expect { s.set_pc_exclusions(['9999']) }.to raise_error(ArgumentError)
    expect(s.excluded_pcs).to eq(['7'])
  end

  it 'Set PC Exclusions replaces wholesale and drops the newly-excluded PC' do
    s = build(specs: { '10' => { id: 10 } })
    s.add_combatant('10')
    s.set_pc_exclusions(['10'])
    expect(s.excluded_pcs).to eq(['10'])
    expect(s.includes_creature?('10')).to be false
  end

  it 'excluded_pcs persists across End Combat' do
    s = build(specs: { '10' => { id: 10 } }, raw: { 'excluded_pcs' => ['10'] })
    s.start_combat
    s.end_combat
    expect(s.excluded_pcs).to eq(['10'])
    expect(s.combat_active?).to be false
  end

  # ---- Reroll Initiative ----

  it 'missing_only skips Combatants that already rolled' do
    s = build(specs: { '1' => { id: 1, wis: 8 }, '2' => { id: 2, wis: 8 } })
    a = s.add_combatant('1'); b = s.add_combatant('2')
    s.send(:combatant_for, a[:id])[:initiative_string] = 'X8' # already rolled
    s.reroll_initiative(missing_only: true, roller: ->(_n) { [5, 5, 5, 5] })
    expect(s.combatant(a[:id])[:initiative_string]).to eq('X8')
    expect(s.combatant(b[:id])[:initiative_string]).to eq('5555')
  end

  it 'prerolled_initiatives wins over missing_only' do
    s = build(specs: { '1' => { id: 1 } })
    a = s.add_combatant('1')
    s.reroll_initiative(prerolled_initiatives: { a[:id] => 'X8' })
    s.reroll_initiative(missing_only: true, prerolled_initiatives: { a[:id] => '987' })
    expect(s.combatant(a[:id])[:initiative_string]).to eq('987')
  end

  # ---- Round label ----

  it 'renders the Round label / sub-tick per the formula' do
    expect(build(raw: { 'time_ticks_per_round' => 1, 'elapsed_time_ticks' => 4 }).round_label).to eq('Round 5')
    expect(build(raw: { 'time_ticks_per_round' => 2, 'elapsed_time_ticks' => 0 }).round_label).to eq('Round 1 0/2')
    expect(build(raw: { 'time_ticks_per_round' => 2, 'elapsed_time_ticks' => 1 }).round_label).to eq('Round 1 1/2')
    expect(build(raw: { 'time_ticks_per_round' => 2, 'elapsed_time_ticks' => 9 }).round_label).to eq('Round 5 1/2')
  end

  # ---- Advance Time Tick ----

  it 'Advance Time Tick wrapping the Round notifies the round-elapsed hook and bumps elapsed' do
    elapsed_calls = 0
    s = build(specs: { '1' => { id: 1, tier: 4 } }, raw: { 'time_ticks_per_round' => 4, 'time_tick' => 4, 'elapsed_time_ticks' => 0 },
              round_elapsed: -> { elapsed_calls += 1 })
    s.add_combatant('1')
    s.advance_time_tick
    expect(s.time_tick).to eq(1)
    expect(s.elapsed_time_ticks).to eq(1)
    expect(elapsed_calls).to eq(1)
  end

  # ---- Is Stale? ----

  it 'Is Stale false when expected and actual Round agree' do
    s = build(raw: { 'combat_anchor' => { 'day_index' => 0, 'round_of_day' => 100 },
                     'elapsed_time_ticks' => 8, 'time_ticks_per_round' => 4 },
              ts: { day_index: 0, round_of_day: 102 })
    expect(s.stale?).to be false
  end

  it 'Is Stale true when Chronicle moved further' do
    s = build(raw: { 'combat_anchor' => { 'day_index' => 0, 'round_of_day' => 100 },
                     'elapsed_time_ticks' => 8, 'time_ticks_per_round' => 4 },
              ts: { day_index: 0, round_of_day: 110 })
    expect(s.stale?).to be true
  end

  it 'Is Stale handles Day rollover' do
    rpd = 100
    # anchor near end of day 50; 12 ticks / 4 = 3 rounds → crosses into day 51.
    s = build(raw: { 'combat_anchor' => { 'day_index' => 50, 'round_of_day' => rpd - 2 },
                     'elapsed_time_ticks' => 12, 'time_ticks_per_round' => 4 },
              ts: { day_index: 51, round_of_day: 1 }, rpd: rpd)
    expect(s.stale?).to be false
    s2 = build(raw: { 'combat_anchor' => { 'day_index' => 50, 'round_of_day' => rpd - 2 },
                      'elapsed_time_ticks' => 12, 'time_ticks_per_round' => 4 },
               ts: { day_index: 51, round_of_day: 2 }, rpd: rpd)
    expect(s2.stale?).to be true
  end

  # ---- Resolve Attack payload ----

  it 'Resolve Attack spends every participant and applies net-positive damage' do
    cond = Conditions::Instance.new
    s = Encounter::State.new({}, data_path: data_path,
                             creature_lookup: ->(_id) { creature_for(id: 1, wis: 12) },
                             conditions_for: ->(_id) { cond })
    atk = s.add_combatant('1'); dfn = s.add_combatant('2')
    a1 = s.add_combatant('3');  a2 = s.add_combatant('4')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0,
      attacker: { id: atk[:id], dice: 4, speed: 2, successes: 5 },
      defense:  { choice: 'parry', id: dfn[:id], dice: 3, speed: 1, successes: 3 },
      allies:   [{ id: a1[:id], dice: 2, speed: 1, successes: 1 }, { id: a2[:id], dice: 2, speed: 1, successes: 0 }]
    )
    expect(s.combatant(atk[:id])[:combat_pool_spent]).to eq(6) # Speed 2 + 4 dice
    expect(s.combatant(dfn[:id])[:combat_pool_spent]).to eq(4) # Speed 1 + 3 dice
    expect(s.combatant(a1[:id])[:combat_pool_spent]).to eq(3)  # Speed 1 + 2 dice
    expect(out[:net_dos]).to eq(3) # 5 + 1 + 0 - 3
    expect(out[:damage]).to eq(3)
  end

  it 'Resolve Attack with defense "none" skips the defender pool and deals no damage on negative net' do
    s = Encounter::State.new({}, data_path: data_path,
                             creature_lookup: ->(_id) { creature_for(id: 1, wis: 12) },
                             conditions_for: ->(_id) { Conditions::Instance.new })
    atk = s.add_combatant('1'); dfn = s.add_combatant('2')
    out = s.resolve_attack_payload(
      target_id: dfn[:id], damage_bonus: 0,
      attacker: { id: atk[:id], dice: 2, speed: 1, successes: 2 },
      defense:  { choice: 'none' },
      allies:   []
    )
    expect(s.combatant(dfn[:id])[:combat_pool_spent]).to eq(0)
    expect(out[:net_dos]).to eq(2)
    expect(out[:damage]).to eq(2)
  end

  # ---- Granted Actions ----

  it 'Grant / List / Revoke Granted Actions' do
    s = build(specs: { '7' => { id: 7 }, '8' => { id: 8 } })
    c7 = s.add_combatant('7'); c8 = s.add_combatant('8')
    s.grant_action(combatant_id: c7[:id], name: 'Block', source: 'Shield of Faith')
    s.grant_action(combatant_id: c7[:id], name: 'Bless', source: 'Shield of Faith')
    s.grant_action(combatant_id: c8[:id], name: 'Aid', source: 'other')
    expect(s.list_granted_actions(c7[:id]).length).to eq(2)
    expect(s.list_granted_actions(c8[:id]).length).to eq(1)
    s.revoke_action { |g| g[:source] == 'Shield of Faith' }
    expect(s.list_granted_actions(c7[:id])).to be_empty
  end

  # ---- Concentration ----

  it 'Begin Concentration appends an entry channeled this turn' do
    s = build(specs: { '4' => { id: 4 } })
    c = s.add_combatant('4')
    s.begin_concentration(c[:id], spell_name: 'Sacred Flame', source: 'spells:sacred_flame',
                          spell_tier: 0, cast_skill: 'religion', mode: 'fire', reservoir_reset: 'per_turn')
    e = s.combatant(c[:id])[:concentration].first
    expect(e[:channeled_this_turn]).to be true
    expect(e[:reservoir]).to eq(0)
  end

  it 'Discharge Reservoir decrements and refuses over-discharge / non-reservoir modes' do
    s = build(specs: { '5' => { id: 5 } })
    c = s.add_combatant('5')
    s.begin_concentration(c[:id], spell_name: 'Shield of Faith', source: 'x', spell_tier: 1,
                          cast_skill: 'religion', mode: 'reservoir', reservoir_reset: 'per_turn', initial_reservoir: 5)
    expect(s.discharge_reservoir(c[:id], 'Shield of Faith', 3)[:reservoir]).to eq(2)
    expect(s.discharge_reservoir(c[:id], 'Shield of Faith', 6)).to be_nil
    s.begin_concentration(c[:id], spell_name: 'Spiritual Weapon', source: 'y', spell_tier: 2,
                          cast_skill: 'religion', mode: 'auto', reservoir_reset: 'persistent', initial_reservoir: 4)
    expect(s.discharge_reservoir(c[:id], 'Spiritual Weapon', 1)).to be_nil
  end

  it 'Per-Turn Setup resets per-turn reservoirs but leaves persistent ones' do
    s = build(specs: { '5' => { id: 5 } })
    c = s.add_combatant('5')
    s.begin_concentration(c[:id], spell_name: 'Shield of Faith', source: 'x', spell_tier: 1,
                          cast_skill: 'religion', mode: 'reservoir', reservoir_reset: 'per_turn', initial_reservoir: 4)
    s.begin_concentration(c[:id], spell_name: 'Spiritual Weapon', source: 'y', spell_tier: 2,
                          cast_skill: 'religion', mode: 'auto', reservoir_reset: 'persistent', initial_reservoir: 4)
    s.apply_per_turn_setup(c[:id])
    by_name = s.combatant(c[:id])[:concentration].each_with_object({}) { |e, h| h[e[:spell_name]] = e[:reservoir] }
    expect(by_name['Shield of Faith']).to eq(0)
    expect(by_name['Spiritual Weapon']).to eq(4)
  end

  it 'End-of-turn cleanup ends un-channeled spells but keeps auto-mode and resets the flag' do
    s = build(specs: { '4' => { id: 4 } })
    c = s.add_combatant('4')
    s.begin_concentration(c[:id], spell_name: 'Sacred Flame', source: 'sf', spell_tier: 0,
                          cast_skill: 'religion', mode: 'fire', reservoir_reset: 'per_turn')
    s.begin_concentration(c[:id], spell_name: 'Vicious Mockery', source: 'vm', spell_tier: 0,
                          cast_skill: 'arcana', mode: 'fire', reservoir_reset: 'per_turn')
    s.begin_concentration(c[:id], spell_name: 'Spiritual Weapon', source: 'sw', spell_tier: 2,
                          cast_skill: 'religion', mode: 'auto', reservoir_reset: 'persistent', initial_reservoir: 4)
    # Sacred Flame stays channeled; Vicious Mockery is not re-channeled.
    s.combatant(c[:id]) # touch
    state_c = s.send(:combatant_for, c[:id])
    state_c[:concentration].find { |e| e[:spell_name] == 'Vicious Mockery' }[:channeled_this_turn] = false
    notes = s.apply_per_turn_cleanup(c[:id])
    held = s.combatant(c[:id])[:concentration].map { |e| e[:spell_name] }
    expect(held).to contain_exactly('Sacred Flame', 'Spiritual Weapon')
    expect(notes).to include(hash_including(kind: :concentration_ended, spell_name: 'Vicious Mockery'))
    expect(s.combatant(c[:id])[:concentration]).to all(satisfy { |e| e[:channeled_this_turn] == false })
  end

  # ---- Long Cast ----

  it 'Begin Long Cast sets turns_remaining one short and committed this turn' do
    s = build(specs: { '7' => { id: 7 } })
    c = s.add_combatant('7')
    s.begin_long_cast(c[:id], spell_name: 'Greater Summoning', source: 'gs', spell_tier: 3,
                      cast_skill: 'arcana', turns_required: 3)
    e = s.combatant(c[:id])[:casting].first
    expect(e[:turns_remaining]).to eq(2)
    expect(e[:committed_this_turn]).to be true
  end

  it 'End-of-turn cast check: decrement, cancel-if-uncommitted, complete-at-zero' do
    s = build(specs: { '7' => { id: 7 } })
    c = s.add_combatant('7')
    # committed, turns_remaining 2 -> 1
    s.begin_long_cast(c[:id], spell_name: 'A', source: 'a', spell_tier: 1, cast_skill: 'arcana', turns_required: 3)
    s.apply_per_turn_cleanup(c[:id])
    expect(s.combatant(c[:id])[:casting].first[:turns_remaining]).to eq(1)

    # uncommitted -> cancelled (incomplete_commit)
    s.begin_long_cast(c[:id], spell_name: 'B', source: 'b', spell_tier: 1, cast_skill: 'arcana', turns_required: 3)
    s.send(:combatant_for, c[:id])[:casting].find { |e| e[:spell_name] == 'B' }[:committed_this_turn] = false
    notes = s.apply_per_turn_cleanup(c[:id])
    expect(notes).to include(hash_including(kind: :cast_cancelled, spell_name: 'B', reason: 'incomplete_commit'))

    # completes at zero
    s.begin_long_cast(c[:id], spell_name: 'C', source: 'c', spell_tier: 1, cast_skill: 'arcana', turns_required: 1)
    notes2 = s.apply_per_turn_cleanup(c[:id])
    expect(notes2).to include(hash_including(kind: :cast_completed, spell_name: 'C'))
  end

  it 'Remove Combatant cancels their Long Casts' do
    s = build(specs: { '7' => { id: 7 } })
    c = s.add_combatant('7')
    s.begin_long_cast(c[:id], spell_name: 'A', source: 'a', spell_tier: 1, cast_skill: 'arcana', turns_required: 3)
    s.remove_combatant(c[:id])
    expect(s.combatant(c[:id])).to be_nil
  end

  # ---- Luck Points ----

  it 'Per-Combatant Luck clears in Per-Turn Cleanup; DM Luck clears only at End Combat' do
    s = build(specs: { '1' => { id: 1 } }, raw: { 'dm_luck_points' => 4 })
    c = s.add_combatant('1')
    s.send(:combatant_for, c[:id])[:luck_points] = 5
    s.apply_per_turn_cleanup(c[:id])
    expect(s.combatant(c[:id])[:luck_points]).to eq(0)
    expect(s.dm_luck_points).to eq(4)
    s.start_combat
    s.end_combat
    expect(s.dm_luck_points).to eq(0)
  end
end
