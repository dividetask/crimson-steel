require 'spec_helper'
require 'encounter'
require 'tmpdir'

RSpec.describe Encounter::State do
  let(:tmpdir) { Dir.mktmpdir('encounter-state') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  # A creature_lookup stub responding to tier + tags (player_character)
  # so combat-mode computations and PC-exclusion validation run without
  # the live Creatures domain.
  let(:fake_creature) { Struct.new(:tier, :tags).new(0, ['player_character']) }
  let(:state) do
    described_class.new({}, data_path: data_path,
                        creature_lookup: ->(_id) { fake_creature })
  end

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  describe 'fresh state' do
    it 'starts with empty roster and exclusions' do
      expect(state.combatants).to eq([])
      expect(state.excluded_pcs).to eq([])
      expect(state.combat_active?).to be false
    end
  end

  describe 'add_combatant' do
    it 'appends a Combatant with a fresh id' do
      a = state.add_combatant(101)
      b = state.add_combatant(102)
      expect(a[:id]).to eq(1)
      expect(b[:id]).to eq(2)
      expect(state.combatants.length).to eq(2)
      expect(a[:creature_id]).to eq('101')
    end

    it 'persists across reloads' do
      state.add_combatant(101)
      state.add_combatant(102)
      reloaded = described_class.load(data_path: data_path, example_path: '/nonexistent')
      expect(reloaded.combatants.length).to eq(2)
      expect(reloaded.combatants.map { |c| c[:creature_id] }).to eq(%w[101 102])
    end

    it 'records the optional name override' do
      c = state.add_combatant(101, name_override: 'Skullsplitter')
      expect(c[:name]).to eq('Skullsplitter')
    end

    it 'rejects a blank creature_id' do
      expect { state.add_combatant('') }.to raise_error(ArgumentError)
    end
  end

  describe 'remove_combatant' do
    it 'removes by combatant id and is a no-op for unknown ids' do
      a = state.add_combatant(101)
      state.add_combatant(102)
      expect(state.remove_combatant(a[:id])).to include(creature_id: '101')
      expect(state.combatants.length).to eq(1)
      expect(state.remove_combatant(999)).to be_nil
    end
  end

  describe 'remove_last_combatant_by_creature_id' do
    it 'removes the most-recently-added Combatant matching the creature_id' do
      first  = state.add_combatant(101)
      second = state.add_combatant(101)
      removed = state.remove_last_combatant_by_creature_id(101)
      expect(removed[:id]).to eq(second[:id])
      expect(state.combatant_ids_for_creature(101)).to eq([first[:id]])
    end

    it 'returns nil when no Combatant references that creature_id' do
      expect(state.remove_last_combatant_by_creature_id(999)).to be_nil
    end
  end

  describe 'copy_count' do
    it 'counts Combatants referencing the same creature_id' do
      state.add_combatant(101)
      state.add_combatant(101)
      state.add_combatant(102)
      expect(state.copy_count(101)).to eq(2)
      expect(state.copy_count(102)).to eq(1)
      expect(state.copy_count(999)).to eq(0)
    end
  end

  describe 'PC exclusions' do
    it 'set_pc_exclusions replaces the list and drops matching Combatants' do
      state.add_combatant(1)
      state.add_combatant(1)
      state.add_combatant(2)
      state.set_pc_exclusions([1])
      expect(state.excluded_pcs).to eq(['1'])
      expect(state.copy_count(1)).to eq(0)
      expect(state.copy_count(2)).to eq(1)
    end

    it 'add_pc_exclusion removes that PC from the roster' do
      state.add_combatant(1)
      state.add_pc_exclusion(1)
      expect(state.pc_excluded?(1)).to be true
      expect(state.copy_count(1)).to eq(0)
    end

    it 'remove_pc_exclusion is a no-op when not excluded' do
      expect { state.remove_pc_exclusion(1) }.not_to raise_error
      expect(state.excluded_pcs).to eq([])
    end

    it 'persists exclusions across reload' do
      state.set_pc_exclusions([10, 11])
      reloaded = described_class.load(data_path: data_path, example_path: '/nonexistent')
      expect(reloaded.excluded_pcs).to eq(%w[10 11])
    end
  end

  describe 'combat-mode toggles' do
    it 'start_combat flags Combat as active' do
      state.add_combatant(101)
      state.start_combat
      expect(state.combat_active?).to be true
    end

    it 'end_combat clears combat-mode fields but leaves combatants and exclusions' do
      state.add_combatant(101)
      state.set_pc_exclusions([10])
      state.start_combat
      state.end_combat
      expect(state.combat_active?).to be false
      expect(state.combatants.length).to eq(1)
      expect(state.excluded_pcs).to eq(['10'])
    end
  end

  describe 'load' do
    it 'falls back to the example file when the data file is missing' do
      reloaded = described_class.load(
        data_path: data_path,
        example_path: File.expand_path('../../docs/common/encounter/encounter_data.example.json', __dir__)
      )
      # The shipped example is an in-progress combat — a Wolf + two Goblins
      # spawned as distinct instances (2003/2004/2005), initiative seated —
      # so the Encounter page has something to show and damaging one Goblin
      # does not affect the other.
      expect(reloaded.combat_active?).to be true
      expect(reloaded.combatants.map { |c| c[:creature_id] }).to eq(%w[2003 2004 2005])
      expect(reloaded.acting_combatant_id).to eq(1)
    end
  end
end
