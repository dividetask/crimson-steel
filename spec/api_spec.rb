require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require 'json'
require_relative '../app'

# JSON API for the Android app (lib/routes/api.rb, docs/project/android_app.md).
# The app is a player device identified by the crimson_device_id cookie; every
# endpoint answers for the Character the DM assigned to that device.
RSpec.describe 'Android app JSON API', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('api-spec') }
  let(:pc)  { Creatures.player_controlled.first }
  let(:player_env) { { 'REMOTE_ADDR' => '192.168.1.50' } }

  before do
    header 'Host', '192.168.1.10:4567'
    DeviceRegistry.instance_variable_set(:@instance, DeviceRegistry.new(File.join(tmp, 'devices.json')))
    PlayerRequests.instance = PlayerRequests.new
    cond = Hash.new { |h, id| h[id] = Conditions::Instance.new }
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(id) { Creatures.lookup(id) }, conditions_for: ->(id) { cond[id] }
    )
  end

  after do
    DeviceRegistry.reset!
    FileUtils.remove_entry(tmp) if File.exist?(tmp)
  end

  def api_get(path)
    get path, {}, player_env
    JSON.parse(last_response.body)
  end

  def api_post(path, body = {})
    post path, JSON.generate(body), player_env.merge('CONTENT_TYPE' => 'application/json')
    JSON.parse(last_response.body)
  end

  # First request mints the device cookie; then the DM assigns the PC to it.
  def assign_device!
    api_get('/api/hello')
    device = rack_mock_session.cookie_jar['crimson_device_id']
    DeviceRegistry.instance.assign_character(device, pc[:id])
  end

  def start_combat_on_my_turn!
    es = Encounter.state
    es.reconcile_pcs(Creatures.player_controlled.map { |c| c[:id] })
    es.start_combat
    es.set_phase('combat')
    mine = es.combatants.find { |c| c[:creature_id].to_s == pc[:id].to_s }
    es.set_acting_combatant(mine[:id])
    es.begin_turn_for(mine[:id])
    mine
  end

  describe 'GET /api/hello' do
    it 'identifies the server and hands the device a cookie' do
      j = api_get('/api/hello')
      expect(last_response.status).to eq(200)
      expect(j).to include('ok' => true, 'service' => 'crimson-steel', 'character' => nil)
      expect(rack_mock_session.cookie_jar['crimson_device_id']).not_to be_nil
    end

    it 'reports the assigned Character once the DM assigns one' do
      assign_device!
      expect(api_get('/api/hello')['character']).to include('id' => pc[:id])
    end
  end

  it 'answers 409 unassigned for Character endpoints until the device is assigned' do
    %w[/api/sheet /api/inventory /api/initiative /api/notes /api/scene].each do |path|
      j = api_get(path)
      expect(last_response.status).to eq(409), path
      expect(j['error']).to eq('unassigned')
    end
  end

  describe 'GET /api/sheet' do
    before { assign_device! }

    it 'returns the assigned Character with server-computed Rolls' do
      j = api_get('/api/sheet')
      expect(j['name']).to eq(pc[:name])
      expect(j['attributes'].map { |a| a['key'] }).to eq(%w[str dex con int wis cha])
      check = j['attributes'].first['check']
      expect(check).to include('name' => 'Strength check')
      expect(check['dice_count']).to be_a(Integer)
      expect(check['tn']).to be_between(DiceResolution.config.minimum_target_number,
                                        DiceResolution.config.maximum_target_number)
      skill = j['skills'].find { |s| s['roll'] }
      expect(skill['roll']['dice_count']).to eq(skill['dice'])
    end
  end

  describe 'GET /api/inventory' do
    before { assign_device! }

    it 'returns the same sections as the web inventory stub' do
      j = api_get('/api/inventory')
      expect(j.keys).to include('equipped', 'inventory', 'sell')
      expect(j['creature_id']).to eq(pc[:id])
    end
  end

  describe 'GET /api/initiative' do
    before { assign_device! }

    it 'redacts enemy vitals and marks the viewer' do
      start_combat_on_my_turn!
      j = api_get('/api/initiative')
      expect(j['combat_active']).to be true
      expect(j['order'].count { |r| r['is_you'] }).to eq(1)
      expect(j['order'].first.keys).not_to include('hp', 'mana', 'toxicity')
    end

    it "lists the player's turn options from the DM's turn-menu code on their turn" do
      start_combat_on_my_turn!
      j = api_get('/api/initiative')
      expect(j['my_turn']).to be true
      keys = j['options'].map { |o| o['key'] }
      expect(keys).to include('move', 'end_turn', 'attack:Unarmed')
      attack = j['options'].find { |o| o['key'] == 'attack:Unarmed' }
      expect(attack['dice'].first['dice']).to eq(2)
      expect(j['me']['pool']['remaining']).to eq(j['me']['pool']['max'])
    end

    it 'offers no options when it is not their turn' do
      j = api_get('/api/initiative')
      expect(j['my_turn']).to be false
      expect(j['options']).to eq([])
    end
  end

  describe 'turn requests' do
    before { assign_device! }

    it 'records a request without spending anything, and lets the player withdraw it' do
      mine = start_combat_on_my_turn!
      pool_before = Encounter.state.combat_pool_remaining(mine[:id])
      j = api_post('/api/turn/requests', key: 'attack:Unarmed', dice: 3)
      expect(last_response.status).to eq(200)
      expect(j['requests'].length).to eq(1)
      expect(j['requests'].first).to include('label' => 'Attack: Unarmed', 'dice' => 3, 'pool_cost' => 3)
      expect(Encounter.state.combat_pool_remaining(mine[:id])).to eq(pool_before)

      id = j['requests'].first['id']
      j = api_post("/api/turn/requests/#{id}/delete")
      expect(j['requests']).to eq([])
    end

    it 'rejects a dice count outside the choices' do
      start_combat_on_my_turn!
      api_post('/api/turn/requests', key: 'attack:Unarmed', dice: 99)
      expect(last_response.status).to eq(422)
    end

    it "rejects a request when it is not the player's turn" do
      api_post('/api/turn/requests', key: 'move')
      expect(last_response.status).to eq(409)
    end

    it "drops the turn's requests once the turn moves on" do
      mine = start_combat_on_my_turn!
      api_post('/api/turn/requests', key: 'move')
      Encounter.state.advance_turn
      key = PlayerRequests.turn_key(Encounter.state, mine[:id])
      expect(PlayerRequests.instance.for_turn(mine[:id], key)).to eq([])
    end

    it "shows the acting player's requests on the DM's turn panel" do
      mine = start_combat_on_my_turn!
      api_post('/api/turn/requests', key: 'move')
      header 'Host', 'localhost'
      get '/encounter', {}, 'REMOTE_ADDR' => '127.0.0.1'
      expect(last_response.body).to include('Player requests')
      expect(last_response.body).to include('Move')
      expect(mine).not_to be_nil
    end
  end

  describe 'POST /encounter/player_requests/:id/dismiss' do
    before { assign_device! }

    it 'lets the DM dismiss a request but not a player' do
      start_combat_on_my_turn!
      id = api_post('/api/turn/requests', key: 'move')['requests'].first['id']

      post "/encounter/player_requests/#{id}/dismiss", {}, player_env
      expect(last_response.status).to eq(403)

      header 'Host', 'localhost'
      post "/encounter/player_requests/#{id}/dismiss", {}, 'REMOTE_ADDR' => '127.0.0.1'
      expect(last_response.status).to eq(302)
      header 'Host', '192.168.1.10:4567'
      expect(api_get('/api/initiative')['requests']).to eq([])
    end
  end

  describe 'GET /api/notes and /api/scene' do
    before { assign_device! }

    it 'never sends DM descriptions' do
      notes = api_get('/api/notes')
      expect(notes['notes']).not_to be_empty
      expect(JSON.generate(notes)).not_to include('dm_description')
      scene = api_get('/api/scene')
      expect(scene).to include('ok' => true)
      expect(JSON.generate(scene)).not_to include('dm_description')
    end
  end
end
