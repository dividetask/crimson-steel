require 'spec_helper'
require 'rack/test'
require 'json'
require 'cgi'
require 'tmpdir'
require_relative '../../app'

# End-to-end coverage for casting Spiritual Weapon through the real routes:
#   1. The Cast Builder offers the target a Defense (Spiritual Weapon's cast is
#      an attack roll, not a silent Reservoir pour).
#   2. Committing the cast deals damage to the defender AND fills the persistent
#      Reservoir, and the Attack Builder then offers the Spiritual Weapon strike
#      so the caster can re-use it on later turns.
RSpec.describe 'Spiritual Weapon cast flow', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('sw-flow') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  def creature(spells:)
    obj = Object.new
    obj.define_singleton_method(:tier) { 2 }
    obj.define_singleton_method(:total_level) { 3 }
    obj.define_singleton_method(:attribute_value) { |_a| 14 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:trained_skills) { [] }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { spells ? 'Cleric' : 'Goblin' }
    obj.define_singleton_method(:granted_abilities) do
      spells ? [{ name: 'Spiritual Weapon', source: 'class:cleric' }] : []
    end
    obj
  end

  before do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup) { |cid| creature(spells: cid.to_s == '1') }
    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'c.json'))
    cat = Conditions::Catalog.load
    @cond = Hash.new { |h, k| h[k] = Conditions::Instance.new(catalog: cat) }
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'e.json'),
      creature_lookup: ->(id) { creature(spells: id.to_s == '1') },
      conditions_for: ->(cid) { @cond[cid] }
    )
    @caster = Encounter.state.add_combatant('1')
    @target = Encounter.state.add_combatant('2')
    header 'Host', 'localhost'
  end

  def builder_blob(body)
    JSON.parse(CGI.unescapeHTML(body.match(/data-builder="([^"]*)"/)[1]))
  end

  it 'offers the target a Defense when casting Spiritual Weapon' do
    get "/encounter/cast_builder?caster_id=#{@caster[:id]}"
    blob = builder_blob(last_response.body)
    sw = blob['steps'].find { |s| s['key'] == 'spell' }['options'].find { |o| o['spell_name'] == 'Spiritual Weapon' }
    expect(sw.dig('cast', 'roll')).to be(true)
    defense = blob['steps'].find { |s| s['key'] == 'defense' }
    opts = (defense['options_map'] || {})["#{@target[:id]}|Spiritual Weapon"]
    expect(opts.map { |o| o['value'] }).to include('none', 'dodge|0')
  end

  it 'deals damage, fills the Reservoir, and exposes the re-use strike' do
    post '/encounter/resolve_cast', JSON.generate(
      commit: true, spell_name: 'Spiritual Weapon', spell: { name: 'Spiritual Weapon' },
      caster: { id: @caster[:id], dice: 5, speed: 0, successes: 4 },
      targets: [{ id: @target[:id], defense: { choice: 'none' } }]
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
    res = JSON.parse(last_response.body)
    expect(res['ok']).not_to be(false)

    # The cast struck the defender.
    expect(@cond['2'].state.hp_damage.values.sum).to be > 0
    # The cast banked its dice into the persistent Reservoir + flagged the caster.
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:reservoir]).to eq(5)
    expect(@cond['1'].active_effect_names).to include('spiritual_weapon')

    # The Attack Builder now offers the Spiritual Weapon strike for re-use.
    get "/encounter/attack_builder?attacker_id=#{@caster[:id]}"
    blob = builder_blob(last_response.body)
    action = blob['steps'].find { |s| s['key'] == 'action' }
    labels = (action['options'] || []).map { |o| o['summary'] || o['label'] }.compact
    expect(labels.join(' ')).to include('Spiritual Weapon')
  end

  it 'lets the target Parry the Spiritual Weapon strike (it is a melee attack)' do
    # The defender wields a melee weapon to Parry with.
    allow_any_instance_of(Sinatra::Application).to receive(:equipped_melee_weapons)
      .and_return([{ item_type: 'longsword', display_name: 'Longsword', speed: 0 }])
    # Give the caster a live Spiritual Weapon Reservoir so the strike is offered.
    Encounter.state.send(:begin_concentration, @caster[:id], spell_name: 'Spiritual Weapon',
                         source: 'x', spell_tier: 2, cast_skill: 'invocation',
                         mode: 'auto', reservoir_reset: 'persistent', initial_reservoir: 5)

    get "/encounter/attack_builder?attacker_id=#{@caster[:id]}"
    blob = builder_blob(last_response.body)
    defense = blob['steps'].find { |s| s['key'] == 'defense' }
    opts = (defense['options_map'] || {})["#{@target[:id]}|spiritual_weapon"]
    expect(opts).not_to be_nil
    values = opts.map { |o| o['value'] }.compact
    expect(values.any? { |v| v.to_s.start_with?('parry:') }).to be(true)
  end
end
