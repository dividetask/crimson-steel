require 'spec_helper'
require 'tmpdir'

RSpec.describe Conditions::Store do
  let(:tmpdir) { Dir.mktmpdir('conditions-store') }
  let(:data_path) { File.join(tmpdir, 'conditions_data.json') }

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def store(raw = {})
    Conditions::Store.new(raw, data_path: data_path)
  end

  describe 'state_for' do
    it 'returns a fresh empty State for an unknown creature' do
      s = store
      st = s.state_for('999')
      expect(st).to be_a(Conditions::State)
      expect(st.hp_damage).to eq({})
      # An untouched empty State is omitted from the serialized form.
      expect(s.to_h['creatures']).not_to have_key('999')
    end

    it 'loads recorded state by creature id' do
      s = store('creatures' => { '2' => { 'hp_damage' => { 'minor' => 8, 'major' => 6 } } })
      st = s.state_for('2')
      expect(st.hp_damage[:minor]).to eq(8)
      expect(st.hp_damage[:major]).to eq(6)
    end

    it 'keys are creature-id-string agnostic' do
      s = store('creatures' => { '2' => { 'mana_spent' => 5 } })
      expect(s.state_for(2).mana_spent).to eq(5)
    end
  end

  describe 'persistence' do
    it 'round-trips mutated state through disk' do
      s = store
      s.state_for('5').instance_variable_set(:@mana_spent, 3)
      s.persist!
      reloaded = Conditions::Store.load(data_path: data_path, example_path: '/nonexistent')
      expect(reloaded.state_for('5').mana_spent).to eq(3)
    end

    it 'omits empty states from the serialized form' do
      s = store
      s.state_for('7') # touched but unmutated
      expect(s.to_h['creatures']).to eq({})
    end
  end

  describe 'instance_for' do
    it 'pairs the creature State with the shared catalog' do
      s = store('creatures' => { '3' => { 'shock' => 4 } })
      inst = s.instance_for('3')
      expect(inst).to be_a(Conditions::Instance)
      expect(inst.state.shock).to eq(4)
    end
  end

  describe 'predicates via Instance' do
    let(:catalog) { Conditions::Catalog.load }

    def instance(state_hash)
      Conditions::Instance.new(state: Conditions::State.load(state_hash), catalog: catalog)
    end

    it 'dying? is true at/above max HP but below the death threshold' do
      inst = instance('hp_damage' => { 'minor' => 10, 'major' => 2 }) # total 12
      expect(inst.dying?(max_hit_points: 10)).to be true   # 12 >= 10, < 20
      expect(inst.dying?(max_hit_points: 6)).to be false   # 12 >= 12 death threshold (2*6) -> dead, not dying
    end

    it 'cannot_act_effect? detects a paralyzed-style flag' do
      inst = instance({})
      inst.apply_named_effect('paralyzed', source_id: 'x')
      expect(inst.cannot_act_effect?).to be true
    end

    it 'can_act? is false when dead, dying, or flagged' do
      healthy = instance({})
      expect(healthy.can_act?(max_hit_points: 20)).to be true

      down = instance('hp_damage' => { 'major' => 12 })
      expect(down.can_act?(max_hit_points: 10)).to be false # dying

      flagged = instance({})
      flagged.apply_named_effect('paralyzed', source_id: 'x')
      expect(flagged.can_act?(max_hit_points: 20)).to be false
    end

    it 'affliction_badges reports name, category, and potency' do
      inst = instance('afflictions' => { 'bleeding' => { 'potency' => 3, 'inflicting_tier' => 1 } })
      badges = inst.affliction_badges
      expect(badges).to contain_exactly(hash_including(name: 'bleeding', category: 'bleed', potency: 3))
    end
  end

  describe 'load fallback' do
    it 'falls back to the example file when the data file is absent' do
      reloaded = Conditions::Store.load(
        data_path: data_path,
        example_path: File.expand_path('../../docs/common/conditions/conditions_data.example.json', __dir__)
      )
      # The example keys creature "1" with minor HP damage.
      expect(reloaded.state_for('1').hp_damage[:minor]).to be > 0
    end
  end
end
