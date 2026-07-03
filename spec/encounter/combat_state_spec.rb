require 'spec_helper'
require 'encounter'
require 'tmpdir'

# Integration tests for the Encounter::State combat-mode entry points,
# with injected creature_lookup / conditions_for so they run without
# the live Creatures/Chronicle domains.
RSpec.describe 'Encounter::State combat mode' do
  let(:tmpdir) { Dir.mktmpdir('enc-combat') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  # Minimal Creature double. martial ranks 4, wis 12, tier 0 → Combat
  # Pool budget 20 → pool 14.
  def creature(tier: 0, wis: 12, martial: 4, max_hp: 20, tags: [])
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:attribute_value) { |a| a == :wis ? wis : 10 }
    obj.define_singleton_method(:ranks_for) { |_k| martial }
    obj.define_singleton_method(:max_hit_points) { max_hp }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:tags) { tags }
    obj.define_singleton_method(:name) { 'Mob' }
    obj
  end

  def state(creatures: Hash.new { |_h, _k| creature })
    cond = Hash.new { |h, k| h[k] = Conditions::Instance.new }
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(id) { creatures[id.to_s] },
                         conditions_for: ->(id) { cond[id.to_s] },
                         current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } })
  end

  describe 'Combat Pool' do
    it 'Get returns the computed pool size' do
      s = state
      c = s.add_combatant('101')
      expect(s.get_combat_pool(c[:id])).to eq(14)
    end

    it 'Spend increments combat_pool_spent and refuses overdraft' do
      s = state
      c = s.add_combatant('101')
      expect(s.spend_combat_pool(c[:id], 3)).to eq(11)  # 14 - 3
      expect(s.spend_combat_pool(c[:id], 100)).to be_nil # overdraft refused
      expect(s.combat_pool_remaining(c[:id])).to eq(11)
    end

    it 'Reset zeroes the spend' do
      s = state
      c = s.add_combatant('101')
      s.spend_combat_pool(c[:id], 5)
      s.reset_combat_pool(c[:id])
      expect(s.combat_pool_remaining(c[:id])).to eq(14)
    end
  end

  # Reckless Attacks carries a `combat_pool` Modifier gated on the `rage`
  # condition, so a raging barbarian's max pool grows by her class level.
  describe 'Combat Pool — Reckless Attacks rage bonus' do
    def reckless_creature(level: 4)
      obj = creature(tier: 2, wis: 12, martial: 4)
      obj.define_singleton_method(:granted_abilities) { [{ name: 'reckless_attacks' }] }
      obj.define_singleton_method(:level_for_ability) { |_n| level }
      obj
    end

    it 'adds class level to the max pool only while raging' do
      raging = { on: false }
      cond = Object.new
      cond.define_singleton_method(:active_effect_names) { |current_round: nil| raging[:on] ? ['rage'] : [] }
      crit = reckless_creature
      s = Encounter::State.new({}, data_path: data_path,
                               creature_lookup: ->(_id) { crit },
                               conditions_for: ->(_id) { cond },
                               current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } })
      c = s.add_combatant('9')
      base = Encounter::CombatPool.size_for(crit) # martial 4, wis 12, tier 2 → 14
      expect(s.get_combat_pool(c[:id])).to eq(base)
      raging[:on] = true
      expect(s.get_combat_pool(c[:id])).to eq(base + 4)
    end
  end

  describe 'Set-Value Spend' do
    it 'translates a preroll into dice_count + preroll and spends extra dice' do
      s = state
      c = s.add_combatant('101')
      out = s.set_value_spend(c[:id], dice_cap: 7, preroll_count: 4)
      expect(out).to eq(dice_count: 3, preroll: 4)
      expect(s.combat_pool_remaining(c[:id])).to eq(10) # 14 - 4 (ratio 1)
    end

    it 'refuses a preroll exceeding the Dice Cap' do
      s = state
      c = s.add_combatant('101')
      expect(s.set_value_spend(c[:id], dice_cap: 5, preroll_count: 6)).to be_nil
    end
  end

  describe 'Start Combat + Time Ticks' do
    it 'sets Time Ticks Per Round from the highest Tier and precomputes schedules' do
      creatures = { '1' => creature(tier: 1), '2' => creature(tier: 3), '3' => creature(tier: 4) }
      s = state(creatures: creatures)
      %w[1 2 3].each { |id| s.add_combatant(id) }
      s.start_combat
      expect(s.time_ticks_per_round).to eq(4)
      sched = s.combatants.map { |c| c[:time_tick_schedule] }
      expect(sched).to eq([[2], [1, 3], [1, 2, 3, 4]])
    end
  end

  describe 'Encounter Phase (DM view selector)' do
    it 'defaults to downtime and only accepts known phases' do
      s = state
      expect(s.phase).to eq(:downtime)
      expect(s.set_phase('combat')).to eq(:combat)
      expect(s.phase).to eq(:combat)
      expect(s.set_phase('nonsense')).to eq(:combat) # unknown ignored
      expect(s.phase).to eq(:combat)
      expect(s.set_phase(:looting)).to eq(:looting)  # symbol accepted
    end

    it 'is independent of Combat mechanics' do
      s = state
      s.add_combatant('1')
      s.set_phase(:looting)
      s.start_combat
      expect(s.phase).to eq(:looting)  # Start Combat does not touch the Phase
      s.end_combat
      expect(s.phase).to eq(:looting)
    end

    it 'round-trips through persistence' do
      s = state
      s.set_phase(:social)
      reloaded = Encounter::State.load(data_path: data_path)
      expect(reloaded.phase).to eq(:social)
    end
  end

  describe 'Advance Turn' do
    it 'moves to the next acting combatant in initiative order' do
      s = state
      a = s.add_combatant('1'); b = s.add_combatant('2')
      s.start_combat
      s.reroll_initiative(prerolled_initiatives: { a[:id] => '97', b[:id] => '85' })
      s.set_acting_combatant(a[:id])
      expect(s.advance_turn).to eq(b[:id])
    end

    it 'no-ops (no crash) when Combat has not started — Time Ticks unseeded' do
      s = state
      s.add_combatant('1'); s.add_combatant('2')
      # No start_combat: @time_tick is nil, so advancing must not do nil Time
      # Tick arithmetic (End Turn shown in the Combat phase before Start Combat).
      expect(s.combat_active?).to be(false)
      expect { expect(s.advance_turn).to be_nil }.not_to raise_error
    end
  end

  describe 'Partial-round skip (Time Ticks)' do
    it 'a lower-Tier Combatant sits out the ticks its schedule excludes' do
      # tier-0 → 1 turn/round; tier-3 → 2 turns/round (Turns Per Round config).
      s = state(creatures: { '1' => creature(tier: 0), '2' => creature(tier: 3) })
      low  = s.add_combatant('1')
      high = s.add_combatant('2')
      s.start_combat
      last = s.time_ticks_per_round
      expect(last).to be > 1
      # On the last tick the fast (tier-3) Combatant acts; the slow one is
      # skipped — exactly the rows the Tracker greys with "(skip)".
      acting = s.acting_combatants(last).map { |c| c[:id] }
      expect(acting).to include(high[:id])
      expect(acting).not_to include(low[:id])
    end
  end

  describe 'Apply Damage' do
    it 'routes severity to Conditions and reports the map' do
      cond = Conditions::Instance.new
      s = Encounter::State.new({}, data_path: data_path,
                               creature_lookup: ->(_id) { creature(max_hp: 20) },
                               conditions_for: ->(_id) { cond })
      c = s.add_combatant('101')
      out = s.apply_damage(c[:id], 5, 'fire')
      expect(out[:severity_map]).to eq(moderate: 6)
      expect(cond.state.hp_damage[:moderate]).to eq(6)
    end

    it 'ends Concentration on a failed Concentration Save' do
      s = state
      c = s.add_combatant('101')
      s.begin_concentration(c[:id], spell_name: 'Bless', source: 'spells:bless',
                            spell_tier: 1, cast_skill: 'religion', mode: 'fire',
                            reservoir_reset: 'per_turn')
      out = s.apply_damage(c[:id], 4, 'fire', save_resolver: ->(_) { false })
      expect(out[:concentration_notifications]).to include(hash_including(kind: :concentration_ended, spell_name: 'Bless'))
      expect(s.combatant(c[:id])[:concentration]).to be_empty
    end
  end

  describe 'Concentration channel rules' do
    it 'rejects a channel below the Main Action Minimum' do
      s = state
      c = s.add_combatant('101')
      s.begin_concentration(c[:id], spell_name: 'Shield', source: 'x', spell_tier: 1,
                            cast_skill: 'arcana', mode: 'reservoir', reservoir_reset: 'per_turn')
      expect(s.channel(c[:id], 'Shield', dice_spent: 2)).to be_nil
      expect(s.channel(c[:id], 'Shield', dice_spent: 4, reservoir_delta: 4)).not_to be_nil
    end
  end

  describe 'set_initiative (DM inline edit)' do
    it 'parses invalid characters out and sorts the survivors descending' do
      s = state
      c = s.add_combatant('101')
      expect(s.set_initiative(c[:id], '5 9 1 q')).to eq('951')
      expect(s.combatant(c[:id])[:initiative_string]).to eq('951')
    end

    it 'keeps the Critical label X and drops zeros / lowercase noise' do
      s = state
      c = s.add_combatant('101')
      expect(s.set_initiative(c[:id], 'x0 9 7')).to eq('X97')
    end
  end

  describe 'reroll_initiative missing_only' do
    it 'rolls only the un-rolled combatants when missing_only is true' do
      s = state
      a = s.add_combatant('1'); b = s.add_combatant('2')
      s.send(:combatant_for, a[:id])[:initiative_string] = 'X8'
      s.reroll_initiative(missing_only: true, roller: ->(_n) { [4, 4, 4, 4] })
      expect(s.combatant(a[:id])[:initiative_string]).to eq('X8')      # untouched
      expect(s.combatant(b[:id])[:initiative_string]).to eq('4444')    # rolled
    end
  end

  describe 'Critical Modifier For' do
    it 'reads the Damage Type critical_value, else the default 2' do
      expect(Encounter::Severity.critical_modifier_for('emotional')).to eq(3)
      expect(Encounter::Severity.critical_modifier_for('fire')).to eq(2)
    end
  end
end
