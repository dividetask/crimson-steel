require 'spec_helper'
require 'encounter'
require 'abilities'
require 'conditions'
require 'tmpdir'

# Encounter::RollTable + Encounter::State#use_roll_table_payload — a
# Reaction Ability that fires on a provided table (Kesser's Gambit → the
# Kesser Reversal Table). The channeler spends Combat Pool dice + Mana,
# a die is rolled, and the matched entry is reported with the Channel
# Successes the channel check produced. Combat does not apply the entry.
RSpec.describe Encounter::RollTable do
  let(:table) { Abilities.roll_table('Kesser Reversal Table') }

  describe '.roll' do
    it 'reports the entry at a forced face with the Channel Successes echoed' do
      out = described_class.roll(table, face: 4, successes: 3)
      expect(out).to include(die: 10, face: 4, name: 'Counter', successes: 3)
      expect(out[:effect]).to include('free weapon attack')
    end

    it 'rolls 1..die through the injected rng' do
      out = described_class.roll(table, rng: Random.new(1))
      expect(out[:face]).to be_between(1, 10)
      expect(out[:name]).to eq(table['entries'][out[:face]]['name'])
    end

    it 'returns nil for an out-of-range face or a missing table' do
      expect(described_class.roll(table, face: 11)).to be_nil
      expect(described_class.roll(nil)).to be_nil
    end

    it 'resolves a table by name through the catalog' do
      expect(described_class.roll_named('Kesser Reversal Table', face: 1)[:name]).to eq('Disaster')
    end
  end
end

RSpec.describe 'Encounter::State#use_roll_table_payload' do
  let(:tmpdir)    { Dir.mktmpdir('enc-roll-table') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def creature
    obj = Object.new
    obj.define_singleton_method(:granted_abilities) { |source: nil| [] }
    obj.define_singleton_method(:tier) { 1 }
    obj.define_singleton_method(:attribute_value) { |_a| 14 }
    obj.define_singleton_method(:ranks_for) { |_k| 6 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:max_mana) { 10 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Reki' }
    obj.define_singleton_method(:record) { { classes: {} } }
    obj
  end

  def state(cond = Conditions::Instance.new)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { creature },
                         conditions_for: ->(_id) { cond })
  end

  it 'spends Combat Pool dice + Mana and reports the rolled entry' do
    cond = Conditions::Instance.new
    s = state(cond)
    c = s.add_combatant('1')
    out = s.use_roll_table_payload({ combatant_id: c[:id], ability: "Kesser's Gambit",
                                     dice: 4, successes: 3, face: 4 })
    expect(out[:ok]).to be true
    expect(out[:table]).to eq('Kesser Reversal Table')
    expect(out[:entry]).to match(name: 'Counter', effect: a_string_including('free weapon attack'))
    expect(out[:successes]).to eq(3)
    expect(out[:pool_spent]).to eq(4)
    expect(out[:mana_spent]).to eq(4) # inherited from Channel Divinity
    expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(4)
    expect(cond.state.mana_spent).to eq(4)
  end

  it 'rolls server-side through an injected rng when no face is given' do
    s = state
    c = s.add_combatant('1')
    out = s.use_roll_table_payload({ combatant_id: c[:id], ability: "Kesser's Gambit",
                                     dice: 2, successes: 0 }, rng: Random.new(1))
    expect(out[:ok]).to be true
    expect(out[:face]).to be_between(1, 10)
  end

  it 'refuses fewer than the Reaction Action Minimum dice' do
    s = state
    c = s.add_combatant('1')
    out = s.use_roll_table_payload({ combatant_id: c[:id], ability: "Kesser's Gambit",
                                     dice: 1, successes: 0, face: 1 })
    expect(out[:ok]).to be false
    expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(0)
  end

  it 'refuses when the channeler cannot afford the dice' do
    s = state
    c = s.add_combatant('1')
    pool = s.combat_pool_remaining(c[:id])
    out = s.use_roll_table_payload({ combatant_id: c[:id], ability: "Kesser's Gambit",
                                     dice: pool + 1, successes: 0, face: 1 })
    expect(out[:ok]).to be false
    expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(0)
  end

  it 'refuses when the channeler cannot afford the Mana' do
    cond = Conditions::Instance.new
    cond.apply_mana_cost(amount: 8, mana_max: 10) # only 2 left, gambit costs 4
    s = state(cond)
    c = s.add_combatant('1')
    out = s.use_roll_table_payload({ combatant_id: c[:id], ability: "Kesser's Gambit",
                                     dice: 2, successes: 0, face: 1 })
    expect(out[:ok]).to be false
    expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(0)
  end

  it 'refuses an Ability that declares no roll table' do
    s = state
    c = s.add_combatant('1')
    out = s.use_roll_table_payload({ combatant_id: c[:id], ability: 'Rage', dice: 2, successes: 0 })
    expect(out[:ok]).to be false
    expect(out[:error]).to match(/no roll table/)
  end
end
