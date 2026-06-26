require 'spec_helper'
require 'creatures'
require 'tmpdir'

RSpec.describe 'Creatures encounter operations', type: :model do
  # Spawn / Delete persist to the writable overlay dir; point it at a
  # tmpdir so tests never touch the live data/ directory.
  around(:each) do |ex|
    Dir.mktmpdir('creatures-data') do |dir|
      Creatures::Dataset.data_dir = dir
      ex.run
    ensure
      Creatures::Dataset.reset!
    end
  end

  before(:each) { Creatures::Dataset.load! }

  describe 'spawn_from_template' do
    it 'returns a fresh id one past the dataset max' do
      max_before = Creatures::Dataset.all.keys.max
      new_id = Creatures.spawn_from_template(101)
      expect(new_id).to eq(max_before + 1)
    end

    it 'applies name_override on the spawn only' do
      original = Creatures.lookup(101).name
      new_id = Creatures.spawn_from_template(101, name_override: 'Skullsplitter')
      expect(Creatures.lookup(new_id).name).to eq('Skullsplitter')
      expect(Creatures.lookup(101).name).to eq(original)
    end

    it 'applies loot_table override on the spawn only' do
      new_id = Creatures.spawn_from_template(101, loot_table: 'captain_loot')
      expect(Creatures.lookup(new_id).record[:loot_table]).to eq('captain_loot')
    end

    it 'rejects an unknown template id' do
      expect { Creatures.spawn_from_template(9999) }.to raise_error(ArgumentError, /no template/)
    end
  end

  describe 'delete' do
    it 'removes the record idempotently' do
      new_id = Creatures.spawn_from_template(101)
      expect(Creatures.delete(new_id)).to be true
      expect(Creatures.lookup(new_id)).to be_nil
      expect(Creatures.delete(new_id)).to be false # second delete is a no-op
    end
  end

  describe 'persistence' do
    it 'writes the spawn to the template source file under data/ and it survives a reload' do
      # Template 101 lives in creatures_data_enemies(.example).yaml, so its
      # spawned instance routes to data/creatures_data_enemies.yaml.
      new_id = Creatures.spawn_from_template(101, name_override: 'Skullsplitter')
      overlay = File.join(Creatures::Dataset.data_dir, 'creatures_data_enemies.yaml')
      expect(File.exist?(overlay)).to be true

      # A fresh load (simulating a server restart) still has the spawn.
      Creatures::Dataset.load!
      rec = Creatures::Dataset.get(new_id)
      expect(rec).not_to be_nil
      expect(rec[:name]).to eq('Skullsplitter')
      expect(rec[:spawned_from]).to eq(101)
      expect(rec[:source]).to eq('creatures_data_enemies.yaml')
    end

    it 'persists a delete so the record is gone after a reload' do
      new_id = Creatures.spawn_from_template(101)
      Creatures.delete(new_id)
      Creatures::Dataset.load!
      expect(Creatures::Dataset.get(new_id)).to be_nil
    end
  end

  describe 'roll_random_encounter' do
    it 'deterministic with a seed' do
      a = Creatures.roll_random_encounter('slave_lords_caravan', seed: 42)
      Creatures::Dataset.load!
      b = Creatures.roll_random_encounter('slave_lords_caravan', seed: 42)
      # Same number of spawns; ids reset to the same starting point.
      expect(a.length).to eq(b.length)
    end

    it 'rejects unknown table id' do
      expect { Creatures.roll_random_encounter('no_such_table') }.to raise_error(ArgumentError, /no Random Encounter Table/)
    end

    it 'each spawn is a fresh Creature record' do
      ids = Creatures.roll_random_encounter('general_pirate_raid', seed: 7)
      expect(ids).to all be_an(Integer)
      ids.each { |id| expect(Creatures.lookup(id)).not_to be_nil }
    end

    it 'raises MissingTemplates (not a mid-roll crash) when a referenced template is absent' do
      # hill_fort_gnoll_band references template 367, which lives only in the
      # untracked campaign data file — absent from the example dataset.
      expect { Creatures.roll_random_encounter('hill_fort_gnoll_band') }
        .to raise_error(Creatures::RandomEncounter::MissingTemplates) do |e|
          expect(e.table_id).to eq('hill_fort_gnoll_band')
          expect(e.missing).to include(367)
        end
    end

    it 'spawns nothing when validation fails (no partial encounter)' do
      max_before = Creatures::Dataset.all.keys.max
      expect { Creatures.roll_random_encounter('hill_fort_gnoll_band') }
        .to raise_error(Creatures::RandomEncounter::MissingTemplates)
      expect(Creatures::Dataset.all.keys.max).to eq(max_before)
    end
  end

  describe 'missing_template_ids' do
    it 'returns the distinct unresolved template ids for a table' do
      table = Creatures::RandomEncounter.tables['hill_fort_patrol']
      missing = Creatures::RandomEncounter.missing_template_ids(table)
      expect(missing).to match_array([364, 365, 366])
    end

    it 'is empty when every referenced template resolves' do
      table = Creatures::RandomEncounter.tables['general_pirate_raid']
      expect(Creatures::RandomEncounter.missing_template_ids(table)).to be_empty
    end
  end
end
