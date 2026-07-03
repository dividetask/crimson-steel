require 'spec_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require_relative '../../app'

# End-to-end coverage for the Atlas fog-of-war endpoints (lib/routes/atlas.rb),
# focused on the "Reveal" workflow: on a Map with no fog yet, Reveal fogs the
# whole Map and cuts out the dragged box (fog over everything but the revealed
# area); once a Map has fog, Reveal only erases.
RSpec.describe 'Atlas fog-of-war routes', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('fog-routes') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  before do
    # The DM is identified by a loopback request; emulate that here (rack-test
    # does not surface a REMOTE_ADDR to Rack::Request#ip).
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    Atlas.state = Atlas::State.new({}, data_path: File.join(tmp, 'atlas.json'))
    @map_id = Atlas.state.add_map(name: 'Field', width: 10, height: 10)
    Atlas.state.set_active_map(@map_id)
  end

  def post_json(path, body)
    header 'Host', 'localhost'
    post path, JSON.generate(body), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    JSON.parse(last_response.body)
  end

  # Is (x, y) inside any fog region on the active Map?
  def fogged?(x, y)
    Atlas.state.list_fog(map_id: @map_id).any? do |f|
      xs = f[:points].map { |p| p[0] }; ys = f[:points].map { |p| p[1] }
      x >= xs.min && x < xs.max && y >= ys.min && y < ys.max
    end
  end

  it 'Hide adds a fog region' do
    res = post_json('/atlas/add_fog', points: [[0, 0], [5, 5]])
    expect(res['ok']).to be true
    expect(Atlas.state.list_fog(map_id: @map_id).size).to eq(1)
    expect(res['snapshot']['fog'].size).to eq(1)
  end

  it 'Reveal on a Map with no fog conceals everything but the revealed box' do
    expect(Atlas.state.list_fog(map_id: @map_id)).to be_empty

    res = post_json('/atlas/erase_fog', points: [[3, 3], [7, 7]])
    expect(res['ok']).to be true
    # A full-map fog was seeded then the box cut out — leaving a ring of fog.
    expect(Atlas.state.list_fog(map_id: @map_id).size).to eq(4)
    expect(fogged?(5, 5)).to be(false)   # revealed window
    expect(fogged?(1, 1)).to be(true)    # still concealed
    expect(fogged?(9, 9)).to be(true)
  end

  it 'Reveal on a Map that already has fog only erases (no full re-seed)' do
    Atlas.state.add_fog(map_id: @map_id, points: [[0, 0], [4, 4]])
    post_json('/atlas/erase_fog', points: [[0, 0], [2, 2]])
    # The lone 4x4 region is trimmed by the box; nothing outside it is fogged.
    expect(fogged?(3, 3)).to be(true)    # remainder of the original region
    expect(fogged?(8, 8)).to be(false)   # never seeded a full-map fog
  end

  it 'Clear Fog reveals the whole Map' do
    Atlas.state.add_fog(map_id: @map_id, points: [[0, 0], [10, 10]])
    res = post_json('/atlas/clear_fog', {})
    expect(res['removed']).to eq(1)
    expect(Atlas.state.list_fog(map_id: @map_id)).to be_empty
  end

  # --- Elements panel: edit coordinates by id ---

  def post_form(path, body)
    header 'Host', 'localhost'
    post path, body, 'REMOTE_ADDR' => '127.0.0.1'
    JSON.parse(last_response.body)
  end

  it 'Edit Terrain moves a wall to new corners (the Elements-panel edit)' do
    id = Atlas.state.add_terrain(map_id: @map_id, points: [[1, 1], [2, 2]], texture: 'wall.png')
    post_form('/atlas/edit_terrain', 'terrain_id' => id.to_s, 'points' => JSON.generate([[4, 4], [20, 5]]))
    expect(Atlas.state.get_terrain(id)[:points]).to eq([[4.0, 4.0], [20.0, 5.0]])
  end

  it 'Edit Fog moves a region to new corners' do
    id = Atlas.state.add_fog(map_id: @map_id, points: [[0, 0], [3, 3]])
    post_form('/atlas/edit_fog', 'fog_id' => id.to_s, 'points' => JSON.generate([[2, 2], [9, 9]]))
    expect(Atlas.state.get_fog(id)[:points]).to eq([[2.0, 2.0], [9.0, 9.0]])
  end

  it 'Edit Token repositions and resizes' do
    id = Atlas.state.place_token(map_id: @map_id, creature_id: '1', x: 1, y: 1)
    post_form('/atlas/edit_token', 'token_id' => id.to_s, 'x' => '5', 'y' => '7', 'size' => '2')
    t = Atlas.state.get_token(id)
    expect([t[:x], t[:y], t[:size]]).to eq([5.0, 7.0, 2.0])
  end

  it 'Edit Terrain on an unknown id is a 404' do
    post_form('/atlas/edit_terrain', 'terrain_id' => '999', 'points' => JSON.generate([[0, 0], [1, 1]]))
    expect(last_response.status).to eq(404)
  end
end
