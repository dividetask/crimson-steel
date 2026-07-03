require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require 'json'
require 'cgi'
require_relative '../app'

# The DM Page reuses the Combat Turn Action panel to run a Character's actions
# outside of Combat (drink a Potion, use an Item, cast a utility Spell). The DM
# selects a Player Character, and the panel renders with the Combat-only
# actions — Attack, Move, End Turn — hidden.
RSpec.describe 'DM Page — out-of-combat actions', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('dm-oob') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  before do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    cond = Conditions::Instance.new
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(id) { Creatures.lookup(id) }, conditions_for: ->(_id) { cond }
    )
  end

  def dm_get(params = {})
    header 'Host', 'localhost'
    get '/dm', params, 'REMOTE_ADDR' => '127.0.0.1'
  end

  it 'renders the out-of-combat action section and a button per Player Character' do
    dm_get
    expect(last_response.status).to eq(200)
    body = last_response.body
    expect(body).to include('Out-of-combat actions')
    expect(body).to include('dm-actor-btn')
    # Every Player Character is reconciled as a Combatant and offered.
    pc_count = Creatures.player_controlled.length
    expect(body.scan(/dm-actor-btn/).length).to be >= pc_count
  end

  it 'does not render the action panel server-side (it is fetched over JS)' do
    dm_get
    body = last_response.body
    # The picker offers JS buttons and an empty mount point; no panel inline.
    expect(body).to include('id="dm-actor-panel"')
    expect(body).to include('data-actor-id=')
    expect(body).not_to include('class="turn-action"')
    # app.js drives the fetch + the mounted panel's controllers.
    expect(body).to include('/app.js')
  end

  it 'serves a selected PC panel from /dm/actor_panel with Attack / Move / End Turn hidden' do
    dm_get
    actor_id = last_response.body[/data-actor-id="(\d+)"/, 1]
    expect(actor_id).not_to be_nil

    header 'Host', 'localhost'
    get '/dm/actor_panel', { 'actor_id' => actor_id }, 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
    body = last_response.body

    expect(body).to include('turn-action')
    # Combat-only actions are gone — no buttons and no panes.
    expect(body).not_to include('data-ta-action="attack"')
    expect(body).not_to include('data-ta-action="move"')
    expect(body).not_to include('data-ta-action="end_turn"')
    expect(body).not_to include('data-ta-pane="attack"')
    expect(body).not_to include('data-ta-pane="move"')
    expect(body).not_to include('data-ta-pane="end_turn"')
    # The Item pane host is still present so the DM can drink a Potion / use an Item.
    expect(body).to include('data-ta-pane="item"')
  end

  it 'returns 404 from /dm/actor_panel for an unknown actor id' do
    header 'Host', 'localhost'
    get '/dm/actor_panel', { 'actor_id' => '999999' }, 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(404)
  end

  describe 'the Skill action' do
    def get_dm(path, params = {})
      header 'Host', 'localhost'
      get path, params, 'REMOTE_ADDR' => '127.0.0.1'
    end

    let(:actor_ids) do
      dm_get
      last_response.body.scan(/data-actor-id="(\d+)"/).flatten
    end

    it 'offers a Skill action and a Skill-panel host in the out-of-combat panel' do
      get_dm('/dm/actor_panel', 'actor_id' => actor_ids.first)
      body = last_response.body
      expect(body).to include('data-ta-action="skill"')
      expect(body).to include('data-ta-pane="skill"')
      expect(body).to include('class="ta-skill"')
    end

    it 'renders the skill panel: skill buttons + a target multi-select' do
      get_dm('/dm/skill_panel', 'actor_id' => actor_ids.first)
      body = last_response.body
      expect(last_response.status).to eq(200)
      expect(body).to include('ta-sk-skill')
      expect(body).to include('creature-multiselect')
    end

    it 'flags opposed skills (so the panel shows targets) and not unopposed ones' do
      get_dm('/dm/skill_panel', 'actor_id' => actor_ids.first)
      body = last_response.body
      # An opposed skill button carries data-opposed="1"; an unopposed one is empty.
      expect(body).to match(/data-skill="stealth" data-opposed="1"/)
      expect(body).to match(/data-skill="nature" data-opposed=""/)
    end

    it 'rolls one actor vs several targets via /dm/skill_check (multi-target)' do
      a = actor_ids
      get_dm('/dm/skill_check', 'actors' => [a[0]], 'skill' => 'stealth', 'targets' => [a[1], a[2]])
      body = last_response.body
      expect(body.scan(/data-side="supporting"/).length).to eq(1)
      expect(body.scan(/data-side="opposing"/).length).to eq(2)
      expect(body).to include('Stealth check')
      expect(body).to include('Perception check')
    end

    it 'returns 404 from /dm/skill_panel for an unknown actor' do
      get_dm('/dm/skill_panel', 'actor_id' => '999999')
      expect(last_response.status).to eq(404)
    end
  end

  describe 'the Multiple group action' do
    def get_dm(path, params = {})
      header 'Host', 'localhost'
      get path, params, 'REMOTE_ADDR' => '127.0.0.1'
    end

    let(:combatant_ids) do
      dm_get
      last_response.body.scan(/data-actor-id="(\d+)"/).flatten
    end

    it 'renders the selection panel with characters and skills' do
      get_dm('/dm/multiple')
      body = last_response.body
      expect(body).to include('dm-multiple')
      expect(body).to include('creature-multiselect') # the reusable multi-select partial
      expect(body).to include('dm-mult-skill')
      expect(body).not_to include('dm-mult-kind') # no PC/NPC role labels
    end

    it 'builds a group opposed check: every actor supporting, every target opposing' do
      a = combatant_ids
      get_dm('/dm/skill_check',
             'actors' => [a[0], a[1]], 'skill' => 'stealth', 'targets' => [a[2]])
      body = last_response.body
      expect(last_response.status).to eq(200)
      expect(body.scan(/data-side="supporting"/).length).to eq(2)
      expect(body.scan(/data-side="opposing"/).length).to eq(1)
      expect(body).to include('Stealth check')
      expect(body).to include('Perception check') # the opposed roll
    end

    it 'rolls only the supporting side when no targets are chosen' do
      a = combatant_ids
      get_dm('/dm/skill_check', 'actors' => [a[0], a[1]], 'skill' => 'nature')
      body = last_response.body
      expect(body.scan(/data-side="supporting"/).length).to eq(2)
      expect(body).not_to include('data-side="opposing"')
    end

    it '404s a group check with no valid actors' do
      get_dm('/dm/skill_check', 'actors' => ['999999'], 'skill' => 'stealth')
      expect(last_response.status).to eq(404)
    end
  end

  # The group Item branch: pick several Characters, then Item. Only no-roll
  # self-buffs (invisibility, disguise, darkvision, blur, …) are offered — never
  # a healing or combat consumable — and Use applies each Character's own copy
  # (self, no roll) and subtracts one.
  describe 'the Multiple group Item action' do
    def get_dm(path, params = {})
      header 'Host', 'localhost'
      get path, params, 'REMOTE_ADDR' => '127.0.0.1'
    end

    let(:combatant_ids) do
      dm_get
      last_response.body.scan(/data-actor-id="(\d+)"/).flatten
    end

    let(:helper) { Sinatra::Application.new! }

    it 'offers no-roll self-buffs but never a healing / combat item' do
      # Pure classification of the eligibility gate the routes share.
      expect(helper.send(:group_item_eligible?, 'Blur')).to be true       # active-effect buff
      expect(helper.send(:group_item_eligible?, 'Blindspot')).to be true  # invisibility (observer save)
      expect(helper.send(:group_item_eligible?, 'Darkvision')).to be true # utility, no effect hash
      expect(helper.send(:group_item_eligible?, 'Heal')).to be false      # healing (channel check)
      expect(helper.send(:group_item_eligible?, 'Ward')).to be false      # temp HP (healing-adjacent)
    end

    it 'derives the named self-buff Effect a buff Item confers on the drinker' do
      expect(helper.send(:self_buff_effects, 'Blur')).to eq([{ 'kind' => 'effect', 'name' => 'blurred' }])
      # Invisibility's Save is rolled by observers, so its fail Effect lands on self.
      expect(helper.send(:self_buff_effects, 'Blindspot')).to eq([{ 'kind' => 'effect', 'name' => 'blindspot' }])
      expect(helper.send(:self_buff_effects, 'Heal')).to eq([]) # nothing self-applied
    end

    it 'lists only no-roll buffs carried by every selected Character (no healing)' do
      ids = combatant_ids
      get_dm('/dm/multiple/items', 'actors' => ids)
      expect(last_response.status).to eq(200)
      body = last_response.body
      expect(body).to include('dm-mult-item')
      # A buff every Character carries is offered; no healing item ever is.
      expect(body).to include('Potion of Darkvision')
      expect(body).not_to match(/data-item="[^"]*Heal[^"]*"/)
      expect(body).not_to match(/data-item="[^"]*Ward[^"]*"/)
    end

    it 'previews the magic toxicity each Character will take, gated by a Confirm button' do
      ids = combatant_ids
      get_dm('/dm/multiple/item_preview', 'item_type' => 'Potion of Darkvision', 'actors' => ids)
      expect(last_response.status).to eq(200)
      body = last_response.body
      # The apply is not offered directly — Confirm must be pushed.
      expect(body).to include('dm-mult-item-confirm')
      # A concrete Magic Toxicity amount is shown per carrying Character.
      expect(body).to match(/\+\d+ magic toxicity/)
      expect(body.scan(/magic toxicity/).length).to eq(ids.length)
    end

    context 'applying a buff Item (isolated inventory)' do
      let(:pc_id) { Creatures.player_controlled.first[:id].to_s }
      let(:cond)  { build_instance } # a Conditions instance with the real effect-name catalog

      before do
        File.write(File.join(tmp, 'equipment_data.yaml'), <<~YAML)
          characters:
            #{pc_id}:
              inventory:
              - item: Scroll of Blur
                tier: 2
        YAML
        ds = Equipment::Dataset.load(data_path: File.join(tmp, 'equipment_data.yaml'))
        Equipment.instance_variable_set(:@instance, Equipment::Instance.new(
          catalog: Equipment.catalog,
          store: Equipment::Dataset::StoreAdapter.new(ds),
          creature_accessor: Equipment::Dataset::CreatureAdapter.new(ds),
          loot: Equipment::LootTables.load
        ))
        Encounter.state = Encounter::State.new(
          {}, data_path: File.join(tmp, 'enc-item.json'),
          creature_lookup: ->(id) { Creatures.lookup(id) }, conditions_for: ->(_id) { cond }
        )
        allow(Conditions.store).to receive(:persist!) # don't write the live conditions file
      end
      after { Equipment.reset! }

      it 'applies the buff’s Active Effect to the drinker and subtracts one' do
        get_dm('/dm') # reconcile the PC Combatants
        cid = Encounter.state.combatants.find { |c| c[:creature_id].to_s == pc_id }[:id]

        header 'Host', 'localhost'
        post '/dm/multiple/use_item', { item_type: 'Scroll of Blur', actors: [cid.to_s] }.to_json,
             'REMOTE_ADDR' => '127.0.0.1', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        res = JSON.parse(last_response.body)
        expect(res['ok']).to be true
        expect(res['results'].length).to eq(1)

        # The blurred Active Effect landed on the drinker …
        expect(cond.active_effect_names.map(&:to_s)).to include('blurred')
        # … and the one Scroll is gone from the inventory.
        get_dm('/dm/multiple/items', 'actors' => [cid.to_s])
        expect(last_response.body).not_to include('Scroll of Blur')
      end
    end
  end
end
