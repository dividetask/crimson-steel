require 'spec_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require_relative '../../app'

# End-to-end coverage for the seam that drops an area Spell's footprint on the
# Map as a persistent Atlas Zone when the cast is committed
# (encounter_design.md → "Area Spells place a Zone"). Exercises the real
# POST /encounter/resolve_cast route so a regression in the enrich → place
# chain is caught.
RSpec.describe 'POST /encounter/resolve_cast — area Spell Zone placement', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('cast-zone') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  # A minimal caster Creature the cast resolution can read.
  def creature
    obj = Object.new
    obj.define_singleton_method(:tier) { 1 }
    obj.define_singleton_method(:attribute_value) { |_a| 12 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Caster' }
    obj
  end

  before do
    # The DM is identified by a loopback request; emulate that here (rack-test
    # does not surface a REMOTE_ADDR to Rack::Request#ip).
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)

    Atlas.state = Atlas::State.new({}, data_path: File.join(tmp, 'atlas.json'))
    @map_id = Atlas.state.add_map(name: 'Field', width: 20, height: 15)
    Atlas.state.set_active_map(@map_id)

    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'conditions.json'))

    cond = Conditions::Instance.new
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(_id) { creature }, conditions_for: ->(_id) { cond }
    )
    @caster = Encounter.state.add_combatant('1')
  end

  it 'places a persistent Zone at the dropped footprint on commit' do
    expect(Atlas.state.list_zones(map_id: @map_id)).to be_empty

    header 'Host', 'localhost'
    post '/encounter/resolve_cast', JSON.generate(
      commit: true,
      spell_name: 'Web', spell: { name: 'Web' },
      caster: { id: @caster[:id], dice: 2, speed: 0, successes: 2 },
      placement: { x: 5, y: 6 },
      targets: []
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body['committed']).to be true

    zones = Atlas.state.list_zones(map_id: @map_id)
    expect(zones.size).to eq(1)
    expect(zones.first[:shape]).to eq('circle')
    expect(zones.first[:anchor][:x]).to eq(5)
    expect(zones.first[:anchor][:y]).to eq(6)
  end

  it 'places a Zone for an Aspect-list area Spell (Grease: object vs. area)' do
    header 'Host', 'localhost'
    post '/encounter/resolve_cast', JSON.generate(
      commit: true,
      spell_name: 'Grease', spell: { name: 'Grease' },
      caster: { id: @caster[:id], dice: 2, speed: 0, successes: 1 },
      placement: { x: 3, y: 4 },
      targets: []
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'

    expect(last_response.status).to eq(200)
    zones = Atlas.state.list_zones(map_id: @map_id)
    expect(zones.size).to eq(1)
    expect(zones.first[:shape]).to eq('square') # Grease's footprint Aspect
  end
end
