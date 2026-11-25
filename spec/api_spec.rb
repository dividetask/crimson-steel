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
    DiceColors.instance_variable_set(:@instance, DiceColors.new(File.join(tmp, 'dice_colors.json')))
    ActionFlows.instance = ActionFlows.new
    cond = Hash.new { |h, id| h[id] = Conditions::Instance.new }
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(id) { Creatures.lookup(id) }, conditions_for: ->(id) { cond[id] }
    )
  end

  after do
    DeviceRegistry.reset!
    DiceColors.reset!
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

    it 'sends the math behind each number, for the "?" on the sheet' do
      j = api_get('/api/sheet')
      vitals = j['vitals']
      expect(vitals['combat_pool']).to be_a(Integer)
      expect(vitals['math'].keys).to eq(%w[hp mana toxicity damage_reduction damage_resilience combat_pool])
      expect(vitals['math']['hp']).to include('title' => 'Hit Points')
      expect(vitals['math']['hp']['lines']).to all(be_a(String))
      expect(vitals['math']['combat_pool']['table']['head']).to eq(%w[Dice Each Cost Left])
      strength = j['attributes'].first
      expect(strength['math']['title']).to eq('Strength')
      expect(strength['check_math']['title']).to eq('Strength check')
      expect(strength['save_math']['title']).to eq('Strength save')
      j['skills'].each { |s| expect(s['math']['lines']).not_to be_empty, s['key'] }
    end

    it 'ends the math of every Check, Save and Skill on the dice and TN its Roll uses' do
      j = api_get('/api/sheet')
      pairs = j['attributes'].flat_map { |a| [[a['check'], a['check_math']], [a['save'], a['save_math']]] }
      pairs += j['skills'].select { |s| s['roll'] }.map { |s| [s['roll'], s['math']] }
      pairs.each do |roll, math|
        lines = math['lines']
        expect(lines.grep(/\ADice: /).first).to end_with("= #{roll['dice_count']}"), roll['name']
        expect(lines.grep(/\ATN: /).first[/\d+\z/].to_i).to eq(roll['tn']), roll['name']
      end
    end

    it 'sends no math for a Creature whose Tier is hidden: the math names the Tier' do
      record = Creatures.lookup(pc[:id]).record
      record[:hide_tier] = true
      j = api_get('/api/sheet')
      expect(j['tier']).to be_nil
      expect(j['vitals']['math']).to eq({})
      expect(j['attributes'].first.keys).not_to include('math', 'check_math', 'save_math')
      expect(j['skills'].first.keys).not_to include('math')
    ensure
      record[:hide_tier] = false
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
      expect(j['order'].first.keys).not_to include('toxicity')
      # Status rows: a Player Character's vitals; an enemy's are hidden ("?" on the phone).
      pc_row = j['order'].find { |r| r['is_pc'] }
      expect(pc_row['hp']).to include('current', 'max')
      expect(pc_row['tier']).to be_a(Integer)
      enemy = j['order'].find { |r| !r['is_pc'] }
      if enemy
        expect(enemy).to include('hp' => { 'hidden' => true }, 'mana' => { 'hidden' => true }, 'conditions' => nil, 'tier' => nil)
      end
      expect(j['order'].map { |r| r['acted'] }).to all(be(true).or(be(false)))
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

    it 'ties a sound to an action listed in config/action_sounds.yml, and serves it' do
      start_combat_on_my_turn!
      garroth = Creatures.player_controlled.find { |c| c[:name].start_with?('Garroth') }
      skip 'no Garroth in this campaign' unless garroth
      c = Encounter.state.combatants.find { |x| x[:creature_id].to_s == garroth[:id].to_s }
      opts = Sinatra::Application.new!.send(:api_turn_options, c)
      expect(opts.find { |o| o[:name] == 'Rage' }[:sound]).to eq('/sounds/RAGE_AGAIN.mp3')
      expect(opts.find { |o| o[:kind] == 'attack' }).not_to have_key(:sound)
      get '/sounds/RAGE_AGAIN.mp3', {}, player_env
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('audio/mpeg')
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
      expect(ini['targets'].last['self']).to be true
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

    # The DM's builder reporting its state (public/js/ui/liveSync.js).
    def dm_sync(body)
      header 'Host', 'localhost'
      post '/encounter/live/sync', JSON.generate(body), dm_env.merge('CONTENT_TYPE' => 'application/json')
      header 'Host', '192.168.1.10:4567'
      JSON.parse(last_response.body)
    end

    def dm_json(path, body = {})
      header 'Host', 'localhost'
      post path, JSON.generate(body), dm_env.merge('CONTENT_TYPE' => 'application/json')
      header 'Host', '192.168.1.10:4567'
      JSON.parse(last_response.body)
    end

    def defense_step = { key: 'defense', options: [{ value: 'none', label: 'No defense' }, { value: 'dodge|2', group: 'dodge', label: '2', summary: 'Dodge — 2 dice' }] }

    def builder_rolls(n)
      [{ id: 'attacker', side: 'supporting', creature_name: 'me', roll_name: 'Attack', dice_count: n, tn: 7, starting_value: 0,
         bonus_penalty_list: [['Competency', 1]] },
       { id: 'defender', side: 'opposing', creature_name: 'them', roll_name: 'Dodge', dice_count: 2, tn: 7, starting_value: 0,
         bonus_penalty_list: [] }]
    end

    it 'runs request -> DM approval -> the builder, with the target and attacker answering on their phones' do
      flow = attack_other_pc!
      expect(flow.stage).to eq('declare')
      target_id = flow.target_id

      # The DM sees it and approves: the builder opens by itself on the page.
      header 'Host', 'localhost'
      get '/encounter', {}, dm_env
      expect(last_response.body).to include('class="af-title">Player actions')
      expect(last_response.body).to include('/js/ui/liveSync.js')
      dm_post("/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve")
      expect(flow.stage).to eq('builder')
      header 'Host', 'localhost'
      get '/encounter/flows_panel', {}, dm_env
      expect(last_response.body).to include('data-open-now="1"')
      get "/encounter/flows/#{flow.id}/prefill", {}, dm_env
      expect(JSON.parse(last_response.body)['choices'].map(&:first)).to eq(%w[target action])

      as_other_phone { other_get('/api/hello') } # the target has the app too
      # The builder reaches the Defense: the target's phone is asked.
      res = dm_sync(flow_id: flow.id, kind: 'attack', actor_id: flow.actor_id, choices: { target: target_id.to_s },
                    target_id: target_id, step: defense_step)
      expect(res).to include('flow_id' => flow.id, 'waiting_on' => other_pc[:name])
      as_other_phone do
        defense = other_get('/api/prompts')['prompts'].find { |p| p['step'] == 'defense' }
        expect(defense['options'].map { |o| o['value'] }).to eq(%w[none dodge|2])
        other_post("/api/prompts/#{flow.id}/#{defense['task_id']}", value: 'dodge|2')
      end
      # The attacker cannot answer the defender's step.
      t = flow.choice_tasks.first
      api_post("/api/prompts/#{flow.id}/#{t['id']}", value: 'none')
      expect(last_response.status).to eq(403)
      # The builder picks the phone's answer.
      res = dm_sync(flow_id: flow.id, kind: 'attack', actor_id: flow.actor_id, choices: { target: target_id.to_s },
                    target_id: target_id, step: defense_step)
      expect(res['answer']).to eq('step' => 'defense', 'value' => 'dodge|2')

      # The dice are up: both players have their own roll.
      n = 3
      res = dm_sync(flow_id: flow.id, kind: 'attack', actor_id: flow.actor_id, target_id: target_id,
                    choices: { target: target_id.to_s, defense: 'dodge|2' }, step: nil, rolls: builder_rolls(n))
      expect(res['rolls'].values.map { |r| r['claimed'] }).to eq([true, true])
      expect(as_other_phone { other_get('/api/prompts')['prompts'].map { |p| p['kind'] } }).to eq(['roll'])
      roll = api_get('/api/prompts')['prompts'].find { |p| p['kind'] == 'roll' }
      expect(roll['headline']).to start_with('Attacking with')
      api_post("/api/prompts/#{flow.id}/#{roll['task_id']}", roll: { dice: [10] * n, final: [10] * n })
      expect(last_response.status).to eq(200)

      # Not shared with the target until the DM approves it.
      seen = lambda do
        as_other_phone do
          other_get('/api/prompts')['prompts'].first['all_rolls'].find { |r| r['task_id'] == roll['task_id'] }
        end
      end
      expect(seen.call['final']).to be_nil
      expect(dm_sync(flow_id: flow.id, kind: 'attack', actor_id: flow.actor_id, target_id: target_id,
                     choices: { target: target_id.to_s, defense: 'dodge|2' }, rolls: builder_rolls(n))['rolls']['attacker'])
        .to include('by' => 'player', 'final' => [10] * n)
      dm_json("/encounter/live/#{flow.id}/rolls/#{roll['task_id']}/approve")
      expect(seen.call['final']).to eq([10] * n)

      # The DM rolls the target's dice: only the DM sees them; Confirm shares them.
      dfn = flow.roll_tasks.find { |x| x['roll']['roll_id'] == 'defender' }
      res = dm_json("/encounter/live/#{flow.id}/rolls/#{dfn['id']}/roll")
      expect(res['rolls']['defender']).to include('by' => 'dm', 'status' => 'submitted')
      mine_view = api_get('/api/prompts')['prompts'].first['all_rolls'].find { |r| r['task_id'] == dfn['id'] }
      expect(mine_view['final']).to be_nil
      as_other_phone do
        own = other_get('/api/prompts')['prompts'].first
        expect(own['status']).to eq('waiting') # still theirs to roll
      end
      dm_json("/encounter/live/#{flow.id}/share", rolls: {})
      mine_view = api_get('/api/prompts')['prompts'].first['all_rolls'].find { |r| r['task_id'] == dfn['id'] }
      expect(mine_view['final']).not_to be_nil

      # A committed attack carrying the flow id closes it.
      payload = { target_id: target_id, weapon_type: flow.prefill[:choices][1][1].split('|').first, commit: true,
                  flow_id: flow.id, luck: [], defense: { choice: 'none' },
                  attacker: { id: flow.attacker_id, dice: n, speed: 0, successes: 2 * n } }
      post '/encounter/resolve_attack', JSON.generate(payload), dm_env.merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(200), last_response.body[0, 300]
      expect(flow.status).to eq('done')
      # Everyone hears what happened.
      news = as_other_phone { other_get('/api/prompts')['news'] }
      expect(news.map { |n| n['text'] }.first).to match(/\A#{Regexp.escape(flow.actor_name)} (hit|missed) /)
      expect(api_get('/api/initiative')['news'].first['yours']).to be true
    end

    it "asks a player on their phone during an attack the DM started, until the DM chooses for them" do
      mine = start_combat_on_my_turn!
      enemy = Encounter.state.combatants.find { |c| c[:id] != mine[:id] }
      res = dm_sync(kind: 'attack', actor_id: enemy[:id], choices: { target: mine[:id].to_s }, target_id: mine[:id],
                    action_label: 'Claws', step: defense_step)
      flow = ActionFlows.instance.find(res['flow_id'])
      expect(flow.dm_started?).to be true
      prompt = api_get('/api/prompts')['prompts'].first
      expect(prompt).to include('step' => 'defense', 'title' => 'Choose your defense')
      expect(api_get('/api/initiative')['busy']).to be false # someone else's action
      # The DM picks in the builder, which moves on: the prompt goes away.
      dm_sync(flow_id: flow.id, kind: 'attack', actor_id: enemy[:id], choices: { target: mine[:id].to_s, defense: 'none' }, step: nil)
      expect(api_get('/api/prompts')['prompts']).to eq([])
      # The builder is closed without committing: the flow is dropped.
      expect(dm_sync(flow_id: flow.id, idle: true)['status']).to eq('cancelled')
    end

    it 'keeps an action going while the DM is on another page, and reopens it where it was' do
      mine = start_combat_on_my_turn!
      enemy = Encounter.state.combatants.find { |c| c[:id] != mine[:id] }
      res = dm_sync(kind: 'attack', actor_id: enemy[:id], choices: { target: mine[:id].to_s, action: 'Claws|2' },
                    target_id: mine[:id], step: defense_step)
      # The DM goes to another page: the prompt stays, and the player can answer.
      prompt = api_get('/api/prompts')['prompts'].first
      api_post("/api/prompts/#{res['flow_id']}/#{prompt['task_id']}", value: 'none')
      expect(last_response.status).to eq(200)
      # Back on the Encounter page: the action is listed to reopen, with its choices in order.
      header 'Host', 'localhost'
      get '/encounter/live/open', {}, dm_env
      expect(JSON.parse(last_response.body)['flows'].map { |f| f['flow_id'] }).to include(res['flow_id'])
      get "/encounter/flows/#{res['flow_id']}/prefill", {}, dm_env
      pre = JSON.parse(last_response.body)
      expect(pre['resumed']).to be true
      expect(pre['choices']).to eq([['target', mine[:id].to_s], ['action', 'Claws|2']])
      # The reopened builder reaches the step again and gets the answer.
      res2 = dm_sync(flow_id: res['flow_id'], kind: 'attack', actor_id: enemy[:id], choices: pre['choices'].to_h,
                     target_id: mine[:id], step: defense_step)
      expect(res2['answer']).to eq('step' => 'defense', 'value' => 'none')
    end

    it 'shows the DM what the players are waiting on, on every DM page' do
      flow = attack_other_pc!
      header 'Host', 'localhost'
      get '/status', {}, dm_env
      expect(last_response.body).to include('id="dm-notices"', 'Player actions <b>1</b>', "/approve?go=encounter")
      dm_post("/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve?go=encounter")
      expect(last_response.headers['Location']).to end_with('/encounter')
    end

    it 'lets a player ask for a Free action on someone else’s turn, but nothing else' do
      mine = start_combat_on_my_turn!
      other = Encounter.state.combatants.find { |c| c[:id] != mine[:id] }
      Encounter.state.set_acting_combatant(other[:id])
      ini = api_get('/api/initiative')
      expect(ini['my_turn']).to be false
      expect(ini['options'].map { |o| o['category'] }.uniq - ['free']).to eq([])
      expect(ini['options'].map { |o| o['kind'] }).not_to include('end_turn')
      api_post('/api/turn/requests', key: 'move')
      expect(last_response.status).to eq(409)
    end

    it 'shows every phone in combat the rolls the DM shared' do
      mine = start_combat_on_my_turn!
      enemy = Encounter.state.combatants.find { |c| c[:id] != mine[:id] }
      rolls = [{ id: 'attacker', side: 'supporting', creature_name: 'x', roll_name: 'Attack', dice_count: 2, tn: 7 }]
      res = dm_sync(kind: 'attack', actor_id: enemy[:id], choices: { target: mine[:id].to_s, action: 'Claws|2' },
                    target_id: mine[:id], rolls: rolls)
      expect(api_get('/api/initiative')['shared']).to eq([])
      # Every phone sees the action in play, rolling in it or not (its dice once shared).
      watching = api_get('/api/initiative')['actions'].find { |a| a['flow_id'] == res['flow_id'] }
      expect(watching['action_line']).to end_with('Attacks You with Claws')
      expect(watching['rolls'].first['final']).to be_nil
      dm_json("/encounter/live/#{res['flow_id']}/share", rolls: { attacker: { dice: [3, 9], final: [3, 9] } })
      shared = api_get('/api/initiative')['shared']
      expect(shared.first["action_line"]).to eq("#{ActionFlows.instance.find(res["flow_id"]).actor_name} Attacks You with Claws")
      expect(shared.first['rolls'].first).to include('final' => [3, 9], 'successes' => 1)
    end

    it 'fudges a player’s roll on their phone only, set with the request or in the builder' do
      flow = attack_other_pc!
      header 'Host', 'localhost'
      get '/encounter/flows_panel', {}, dm_env
      expect(last_response.body).to include('name="fudge"', '>Critical<')
      dm_post("/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve", fudge: 'crit')
      as_other_phone { other_get('/api/hello') }
      dm_sync(flow_id: flow.id, kind: 'attack', actor_id: flow.actor_id, target_id: flow.target_id,
              choices: { target: flow.target_id.to_s }, rolls: builder_rolls(3))
      mine = api_get('/api/prompts')['prompts'].find { |p| p['kind'] == 'roll' }
      expect(mine['roll']['fudge']).to eq('crit')
      # Nobody else learns of it: not in anyone's list of rolls, nor the target's own prompt.
      expect(mine['all_rolls'].map(&:keys).flatten).not_to include('fudge')
      theirs = as_other_phone { other_get('/api/prompts')['prompts'].first }
      expect(theirs['roll']).not_to have_key('fudge')
      # The DM fudges the target's Dodge in the builder, until it is rolled.
      dfn = flow.roll_tasks.find { |t| t['roll']['roll_id'] == 'defender' }
      res = dm_json("/encounter/live/#{flow.id}/rolls/#{dfn['id']}/fudge", fudge: 'fumble')
      expect(res['rolls']['defender']['fudge']).to eq('fumble')
      expect(as_other_phone { other_get('/api/prompts')['prompts'].first['roll']['fudge'] }).to eq('fumble')
      as_other_phone { other_post("/api/prompts/#{flow.id}/#{dfn['id']}", roll: { dice: [1, 1], final: [1, 1] }) }
      dm_json("/encounter/live/#{flow.id}/rolls/#{dfn['id']}/fudge", fudge: 'success')
      expect(last_response.status).to eq(422) # already rolled
    end

    it 'keeps the live builder DM-only' do
      post '/encounter/live/sync', JSON.generate(kind: 'attack', actor_id: 1), player_env.merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(403)
    end

    def request_option(match, body = {})
      ini = api_get('/api/initiative')
      opt = ini['options'].find { |o| match.call(o) }
      skip 'no such option for this character' unless opt
      body = body.dup
      body[:dice] ||= opt['dice'].find { |d| d['affordable'] }&.dig('dice')
      j = api_post('/api/turn/requests', { key: opt['key'] }.merge(body.compact))
      expect(last_response.status).to eq(200), j.inspect
      [opt, ActionFlows.instance.active.last]
    end

    def approve_request!(flow)
      dm_post("/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve")
    end

    it 'opens a spell or ability request in its own builder once approved' do
      start_combat_on_my_turn!
      target = api_get('/api/initiative')['targets'].find { |t| t['name'] == other_pc[:name] }
      opt, flow = request_option(->(o) { o['kind'] == 'cast' && o['name'] == 'Vicious Mockery' && !o['disabled'] },
                                 dice: nil, target_id: target['combatant_id'])
      expect(opt['target']).to eq('creature')
      approve_request!(flow)
      expect(flow.prefill[:choices].map(&:first)).to eq(%w[spell dice target])
      header 'Host', 'localhost'
      get '/encounter/flows_panel', {}, dm_env
      expect(last_response.body).to include('data-open-now="1"')
      # Not opened (no sync yet), e.g. after a reload: the DM can open it by hand.
      expect(last_response.body).to include('Open in Cast builder')
    end

    it 'applies an approved Move and End Turn' do
      mine = start_combat_on_my_turn!
      pool = Encounter.state.combat_pool_remaining(mine[:id])
      id = api_post('/api/turn/requests', key: 'move')['requests'].last['id']
      dm_post("/encounter/player_requests/#{id}/apply")
      expect(Encounter.state.combat_pool_remaining(mine[:id])).to eq(pool - Encounter::Config.move_cost)
      expect(api_get('/api/initiative')['requests']).to eq([])
      id = api_post('/api/turn/requests', key: 'end_turn')['requests'].last['id']
      dm_post("/encounter/player_requests/#{id}/apply")
      expect(Encounter.state.acting_combatant_id).not_to eq(mine[:id])
    end

    it 'holds up new requests only while a die roll waits on the player' do
      flow = attack_other_pc!
      expect(api_get('/api/initiative')['busy']).to be false # requested, nothing to roll yet
      dm_post("/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve")
      dm_sync(flow_id: flow.id, kind: 'attack', actor_id: flow.actor_id, target_id: flow.target_id,
              choices: { target: flow.target_id.to_s }, rolls: builder_rolls(3))
      expect(api_get('/api/initiative')['busy']).to be true
      api_post('/api/turn/requests', key: 'move')
      expect(last_response.status).to eq(409)
      expect(JSON.parse(last_response.body)['error']).to include('roll your dice first')
      roll = api_get('/api/prompts')['prompts'].find { |p| p['kind'] == 'roll' }
      api_post("/api/prompts/#{flow.id}/#{roll['task_id']}", roll: { dice: [5, 5, 5], final: [5, 5, 5] })
      expect(api_get('/api/initiative')['busy']).to be false
    end

    it 'does not hold up actions for a spell that rolls nothing' do
      start_combat_on_my_turn!
      me_id = api_get('/api/initiative')['me']['combatant_id']
      _, heal = request_option(->(o) { o['kind'] == 'cast' && o['name'] == 'Healing Word' && !o['disabled'] }, target_id: me_id)
      expect(heal.blocking?).to be false
      expect(api_get('/api/initiative')['busy']).to be false
    end

    it 'keeps the DM actions DM-only' do
      flow = attack_other_pc!
      post "/encounter/flows/#{flow.id}/tasks/#{flow.tasks.first['id']}/approve", {}, player_env
      expect(last_response.status).to eq(403)
      expect(flow.stage).to eq('declare')
    end
  end

  describe 'dice colours' do
    before { assign_device! }

    it 'gives each player their own colour and lets them change it to a free one' do
      j = api_get('/api/dice_colors')
      expect(j['color']).not_to eq('silver')
      expect(j['options'].length).to be >= 12
      expect(api_get('/api/hello')['dice_color']).to eq(j['hex'])

      DiceColors.instance.key_for(DiceColors::DM) # the DM holds light grey
      taken = api_post('/api/dice_color', color: 'silver')
      expect(last_response.status).to eq(409)
      expect(taken['error']).to match(/already/)

      free = api_get('/api/dice_colors')['options'].find { |o| o['taken_by'].nil? && o['key'] != j['color'] }
      expect(api_post('/api/dice_color', color: free['key'])['color']).to eq(free['key'])
      grey = api_get('/api/dice_colors')['options'].find { |o| o['key'] == 'silver' }
      expect(grey['taken_by']).to eq('the DM')
    end

    it 'lets only the DM change colours on the web' do
      post '/dice_colors', { who: 'dm', color: 'sky' }, player_env
      expect(last_response.status).to eq(403)
      post '/dice_colors', { who: 'dm', color: 'peach' }, 'REMOTE_ADDR' => '127.0.0.1'
      expect(DiceColors.instance.key_for('dm')).to eq('peach')
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
