require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require_relative '../../app'

# The loot pipeline (Collect Combat Loot → loot pile → sweep to the Sell Pile)
# is keyed to a Ground Pile location. When a Map is active the pile is named
# after it; when the campaign plays without the Atlas (no active Map) the
# location must still resolve to a stable pile so post-combat loot is collected
# and surfaced rather than silently lost when the looted Combatants are removed.
RSpec.describe 'Encounter loot pile location', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('loot-loc') }
  let(:helpers) { Sinatra::Application.new! }
  before { Atlas.state = Atlas::State.new({}, data_path: File.join(tmp, 'atlas.json')) }
  after  { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  context 'with no active Map' do
    it 'falls back to a single stable "loot" pile instead of nil' do
      expect(helpers.send(:loot_pile_location)).to eq('loot')
      expect(helpers.send(:combat_pile_owner)).to eq('ground:loot')
    end
  end

  context 'with an active Map' do
    it 'names the pile after the Map' do
      id = Atlas.state.add_map(name: 'Field', width: 10, height: 10)
      Atlas.state.set_active_map(id)
      expect(helpers.send(:loot_pile_location)).to eq("map_#{id}")
      expect(helpers.send(:combat_pile_owner)).to eq("ground:map_#{id}")
    end
  end
end
