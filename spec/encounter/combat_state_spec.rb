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
  # Pool budget 10 → pool 11.
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
      expect(s.get_combat_pool(c[:id])).to eq(11)
    end

    it 'Spend increments combat_pool_spent and refuses overdraft' do
      s = state
      c = s.add_combatant('101')
      expect(s.spend_combat_pool(c[:id], 3)).to eq(8)   # 11 - 3
      expect(s.spend_combat_pool(c[:id], 100)).to be_nil # overdraft refused
      expect(s.combat_pool_remaining(c[:id])).to eq(8)
    end

    it 'Reset zeroes the spend' do
      s = state
      c = s.add_combatant('101')
      s.spend_combat_pool(c[:id], 5)
      s.reset_combat_pool(c[:id])
      expect(s.combat_pool_remaining(c[:id])).to eq(11)
    end
  end

  describe 'Set-Value Spend' do
    it 'translates a preroll into dice_count + preroll and spends extra dice' do
      s = state
      c = s.add_combatant('101')
      out = s.set_value_spend(c[:id], dice_cap: 7, preroll_count: 4)
      expect(out).to eq(dice_count: 3, preroll: 4)
      expect(s.combat_pool_remaining(c[:id])).to eq(7) # 11 - 4 (ratio 1)
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

  describe 'Advance Turn' do
    it 'moves to the next acting combatant in initiative order' do
      s = state
      a = s.add_combatant('1'); b = s.add_combatant('2')
      s.start_combat
      s.reroll_initiative(prerolled_initiatives: { a[:id] => '97', b[:id] => '85' })
      s.set_acting_combatant(a[:id])
      expect(s.advance_turn).to eq(b[:id])
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

  describe 'Critical Modifier For' do
    it 'reads the Damage Type critical_value, else the default 2' do
      expect(Encounter::Severity.critical_modifier_for('emotional')).to eq(3)
      expect(Encounter::Severity.critical_modifier_for('fire')).to eq(2)
    end
  end
end
