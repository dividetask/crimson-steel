require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require 'fileutils'
require 'live_roster'
require_relative '../app'

# Store Recipient visibility + the Sell Pile Delete action.
#
#   * NPCs are DM-only in the Store Recipient dropdowns, and the DM sees
#     only NPCs that are active in the current Scene. Players see neither
#     NPCs nor enemies.
#   * The Sell Pile (shared Party Inventory) gains a DM-only Delete that
#     permanently removes an item — a player cannot destroy party gear.
RSpec.describe 'Store recipients + Sell Pile delete', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('store-vis') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  # Isolate the Chronicle singleton so activating a Creature Reference here
  # never leaks into other specs (or the live data file).
  let(:orig_chronicle) { Chronicle.store }
  before do
    Chronicle.store = Chronicle::Store.load(
      data_path:    File.join(tmp, 'chronicle_data.json'),
      example_path: Chronicle::Store::EXAMPLE_PATH
    )
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(id) { Creatures.lookup(id) }
    )
  end
  after { Chronicle.store = orig_chronicle }

  def npc_ids
    Creatures.list.map(&:first).select { |id| Creatures.lookup(id)&.group == 'npc' }
  end

  let(:pc_id)    { Creatures.player_controlled.first[:id] }
  let(:enemy_id) { Creatures.list.map(&:first).find { |id| Creatures.lookup(id)&.group == 'enemy' } }
  let(:active_npc_id)   { npc_ids.first }
  let(:inactive_npc_id) { npc_ids.find { |id| !LiveRoster.scene_active_creature_ids.include?(id) } }

  before { Chronicle.store.activate_creature_reference(active_npc_id) }

  def get_store(as:)
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(as == :dm)
    header 'Host', 'localhost'
    get '/store', {}, 'REMOTE_ADDR' => (as == :dm ? '127.0.0.1' : '10.0.0.9')
    last_response.body
  end

  describe 'Recipient dropdown visibility' do
    it 'shows the DM active NPCs and PCs but not inactive NPCs' do
      body = get_store(as: :dm)
      expect(body).to include(%(value="#{pc_id}"))
      expect(body).to include(%(value="#{active_npc_id}"))
      expect(inactive_npc_id).not_to be_nil
      expect(body).not_to include(%(value="#{inactive_npc_id}"))
    end

    it 'hides every NPC (and enemy) from a player, keeping PCs' do
      body = get_store(as: :player)
      expect(body).to include(%(value="#{pc_id}"))
      expect(body).not_to include(%(value="#{active_npc_id}"))
      expect(body).not_to include(%(value="#{enemy_id}")) if enemy_id
    end
  end

  describe 'Sell Pile Delete (POST /inventory/sell_delete)' do
    before do
      File.write(File.join(tmp, 'equipment_data.yaml'), <<~YAML)
        party:
          inventory:
          - item: Falchion
            quantity: 3
          - item: Breastplate
            tier: 1
      YAML
      ds = Equipment::Dataset.load(data_path: File.join(tmp, 'equipment_data.yaml'))
      Equipment.instance_variable_set(:@instance, Equipment::Instance.new(
        catalog: Equipment.catalog,
        store: Equipment::Dataset::StoreAdapter.new(ds),
        creature_accessor: Equipment::Dataset::CreatureAdapter.new(ds),
        loot: Equipment::LootTables.load
      ))
    end
    after { Equipment.reset! }

    def party_items
      Equipment.instance.get_inventory('party').map(&:item_type)
    end

    def post_delete(as:, index:, quantity: nil)
      allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(as == :dm)
      header 'Host', 'localhost'
      params = { creature_id: pc_id.to_s, index: index.to_s, detail: 'minimal' }
      params[:quantity] = quantity.to_s if quantity
      post '/inventory/sell_delete', params, 'REMOTE_ADDR' => (as == :dm ? '127.0.0.1' : '10.0.0.9')
    end

    it 'lets the DM permanently remove an item from the Sell Pile' do
      expect(party_items).to include('Breastplate')
      post_delete(as: :dm, index: 1) # the Breastplate
      expect(last_response.status).to eq(302)
      expect(party_items).not_to include('Breastplate')
      expect(party_items).to include('Falchion')
    end

    it 'deletes only the requested quantity of a stack' do
      post_delete(as: :dm, index: 0, quantity: 1) # one of three Falchions
      falchion = Equipment.instance.get_inventory('party').find { |s| s.item_type == 'Falchion' }
      expect(falchion.quantity).to eq(2)
    end

    it 'ignores a player (only the DM may delete party gear)' do
      post_delete(as: :player, index: 1)
      expect(party_items).to include('Breastplate')
    end
  end
end
