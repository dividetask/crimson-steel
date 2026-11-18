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
    ActionFlows.instance = ActionFlows.new
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
      # The skill it rolls, with its Dice Cap and bonus, for the dice picker.
      expect(attack['skill']).to include('name' => 'Martial')
      expect(attack['skill']['dice']).to eq(attack['dice'].last['dice'])
      expect(attack['name']).to eq('Unarmed')
      expect(j['me']['pool']['remaining']).to eq(j['me']['pool']['max'])
    end

    it 'sends a cast option its Tier (for the name colour) instead of writing it' do
      start_combat_on_my_turn!
      cast = api_get('/api/initiative')['options'].find { |o| o['kind'] == 'cast' }
      skip 'the assigned PC knows no spells' unless cast
      expect(cast['tier']).to be_a(Integer)
      expect(cast['detail']).not_to include('Tier')
      expect(cast['name']).not_to start_with('Cast')
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
      j = api_post('/api/turn/requests', key: 'move')
      expect(last_response.status).to eq(200)
      expect(j['requests'].length).to eq(1)
      expect(j['requests'].first).to include('label' => 'Move', 'dice' => nil, 'pool_cost' => Encounter::Config.move_cost)
      expect(Encounter.state.combat_pool_remaining(mine[:id])).to eq(pool_before)

      id = j['requests'].first['id']
      j = api_post("/api/turn/requests/#{id}/delete")
      expect(j['requests']).to eq([])
    end

    it 'rejects a dice count outside the choices' do
      start_combat_on_my_turn!
      target = api_get('/api/initiative')['targets'].first
      api_post('/api/turn/requests', key: 'attack:Unarmed', dice: 99, target_id: target['combatant_id'])
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

  describe 'player-driven attack flow' do
    let(:other_pc) { Creatures.player_controlled[1] }
    let(:dm_env) { { 'REMOTE_ADDR' => '127.0.0.1' } }

    def dm_post(path, params = {})
      header 'Host', 'localhost'
      post path, params, dm_env
      header 'Host', '192.168.1.10:4567'
    end

    # A second phone, assigned to another Player Character.
    def as_other_phone
      with_session(:other) do
        header 'Host', '192.168.1.10:4567'
        get '/api/hello', {}, 'REMOTE_ADDR' => '192.168.1.51'
        device = last_response.headers['set-cookie'].to_s[/crimson_device_id=([^;]+)/, 1]
        DeviceRegistry.instance.assign_character(device, other_pc[:id])
        yield
      end
    end

    def other_get(path)
      get path, {}, 'REMOTE_ADDR' => '192.168.1.51'
      JSON.parse(last_response.body)
    end

    def other_post(path, body)
      post path, JSON.generate(body), 'REMOTE_ADDR' => '192.168.1.51', 'CONTENT_TYPE' => 'application/json'
      JSON.parse(last_response.body)
    end

    before { assign_device! }

    def attack_other_pc!
      start_combat_on_my_turn!
      ini = api_get('/api/initiative')
      target = ini['targets'].find { |t| t['name'] == other_pc[:name] }
      atk = ini['options'].find { |o| o['kind'] == 'attack' && o['dice'].any? { |d| d['affordable'] } }
      dice = atk['dice'].find { |d| d['affordable'] }['dice']
      j = api_post('/api/turn/requests', key: atk['key'], dice: dice, target_id: target['combatant_id'])
      expect(last_response.status).to eq(200), j.inspect
      ActionFlows.instance.active.last
    end

    it 'lists targets for the attacker, enemies first' do
      start_combat_on_my_turn!
      targets = api_get('/api/initiative')['targets']
      expect(targets).not_to be_empty
      expect(targets.map { |t| t['enemy'] }).to eq(targets.map { |t| t['enemy'] }.sort_by { |e| e ? 0 : 1 })
    end

    it 'needs a target to attack' do
      start_combat_on_my_turn!
      atk = api_get('/api/initiative')['options'].find { |o| o['kind'] == 'attack' }
      api_post('/api/turn/requests', key: atk['key'], dice: 2)
      expect(last_response.status).to eq(422)
    end

    it 'runs request -> DM approval -> defender prompt -> rolls -> pre-fill -> commit closes it' do
      flow = attack_other_pc!
      expect(flow.stage).to eq('declare')

      # The DM sees it and approves the request.
      header 'Host', 'localhost'
      get '/encounter', {}, dm_env
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('class="af-title">Player actions')
      expect(last_response.body).to include('/approve')
      dm_post("/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve")
      expect(flow.stage).to eq('respond')

      # The target's phone is asked for a defense, and answers.
      as_other_phone do
        prompts = other_get('/api/prompts')['prompts']
        defense = prompts.find { |p| p['step'] == 'defense' }
        expect(defense['options'].map { |o| o['value'] }).to include('none')
        j = other_post("/api/prompts/#{flow.id}/#{defense['task_id']}", value: 'none')
        expect(j['prompts'].find { |p| p['task_id'] == defense['task_id'] }['status']).to eq('submitted')
      end

      # The attacker cannot answer the defender's step.
      t = flow.open_tasks.find { |x| x['step'] == 'defense' }
      api_post("/api/prompts/#{flow.id}/#{t['id']}", value: 'none')
      expect(last_response.status).to eq(403)

      dm_post("/encounter/flows/#{flow.id}/tasks/#{t['id']}/approve")
      flow.open_tasks.dup.each { |x| dm_post("/encounter/flows/#{flow.id}/tasks/#{x['id']}/decide", value: flow.options_for(x).first[:value]) } if flow.stage == 'luck'
      expect(flow.stage).to eq('roll')

      # The attacker rolls on their phone; the DM approves it.
      roll = api_get('/api/initiative')['prompts'].find { |p| p['kind'] == 'roll' }
      n = roll['roll']['dice_count']
      api_post("/api/prompts/#{flow.id}/#{roll['task_id']}", roll: { dice: [10] * n, final: [10] * n })
      expect(last_response.status).to eq(200)
      dm_post("/encounter/flows/#{flow.id}/tasks/#{roll['task_id']}/approve")
      expect(flow.stage).to eq('resolve')

      header 'Host', 'localhost'
      get "/encounter/flows/#{flow.id}/prefill", {}, dm_env
      pre = JSON.parse(last_response.body)
      expect(pre['choices'].map(&:first)).to eq(%w[target action defense])
      expect(pre['rolls']['attacker']['successes']).to eq(2 * n)

      # A committed attack carrying the flow id closes it.
      payload = { target_id: pre['choices'][0][1].to_i, weapon_type: pre['choices'][1][1].split('|').first, commit: true,
                  flow_id: flow.id, luck: [], defense: { choice: 'none' },
                  attacker: { id: flow.attacker_id, dice: n, speed: 0, successes: 2 * n } }
      post '/encounter/resolve_attack', JSON.generate(payload), dm_env.merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(200), last_response.body[0, 300]
      expect(flow.status).to eq('done')
    end

    it 'lets the DM decide for a player, which clears their prompt' do
      flow = attack_other_pc!
      dm_post("/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve")
      t = flow.open_tasks.find { |x| x['step'] == 'defense' }
      dm_post("/encounter/flows/#{flow.id}/tasks/#{t['id']}/decide", value: 'none')
      expect(flow.task(t['id'])).to include('status' => 'approved', 'by' => 'dm')
      as_other_phone do
        expect(other_get('/api/prompts')['prompts'].map { |p| p['task_id'] }).not_to include(t['id'])
      end
    end

    it 'keeps the DM actions DM-only' do
      flow = attack_other_pc!
      post "/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve", {}, player_env
      expect(last_response.status).to eq(403)
      expect(flow.stage).to eq('declare')
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
