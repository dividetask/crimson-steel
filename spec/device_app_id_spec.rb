require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require 'json'
require_relative '../app'

# The Android app's own per-phone id (lib/device_registry.rb APP_ID,
# docs/project/device_assignment.md): one phone is always one device.
RSpec.describe 'Device ids from the Android app', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('dev-spec') }
  let(:phone) { { 'REMOTE_ADDR' => '192.168.1.50' } }
  let(:dm) { { 'REMOTE_ADDR' => '127.0.0.1' } }

  before do
    header 'Host', '192.168.1.10:4567'
    DeviceRegistry.instance_variable_set(:@instance, DeviceRegistry.new(File.join(tmp, 'devices.json')))
  end

  after do
    DeviceRegistry.reset!
    FileUtils.remove_entry(tmp)
  end

  def hello(cookie, previous = nil)
    env = phone.merge('HTTP_COOKIE' => "crimson_device_id=#{cookie}")
    env['HTTP_X_CRIMSON_PREVIOUS_DEVICE'] = previous if previous
    get '/api/hello', {}, env
    JSON.parse(last_response.body)
  end

  it 'keeps the phone’s own id instead of issuing a random one' do
    hello('0123456789abcdef')
    expect(last_response.headers['set-cookie'].to_s).not_to include('crimson_device_id')
    3.times { hello('0123456789abcdef') }
    expect(DeviceRegistry.instance.list.map { |d| d['device_id'] }).to eq(['0123456789abcdef'])
  end

  it 'carries the old id’s assignment over to the phone’s own id, once' do
    old = DeviceRegistry.instance.create('41d5075b-aaaa-bbbb-cccc-000000000000')
    DeviceRegistry.instance.assign_character(old['device_id'], Creatures.player_controlled.first[:id])
    j = hello('0123456789abcdef', old['device_id'])
    expect(j['character']).not_to be_nil
    expect(DeviceRegistry.instance.list.map { |d| d['device_id'] }).to eq(['0123456789abcdef'])
  end

  it 'still issues a random id to a browser' do
    get '/api/hello', {}, phone
    expect(last_response.headers['set-cookie'].to_s).to include('crimson_device_id=')
  end

  it 'lets the DM remove one device, or every unassigned one' do
    %w[1111111111111111 2222222222222222 3333333333333333].each { |id| hello(id) }
    DeviceRegistry.instance.assign_character('1111111111111111', Creatures.player_controlled.first[:id])
    header 'Host', 'localhost'
    post '/devices/remove', { device_id: '2222222222222222' }, dm
    expect(DeviceRegistry.instance.list.map { |d| d['device_id'] }).not_to include('2222222222222222')
    post '/devices/remove_unassigned', {}, dm
    ids = DeviceRegistry.instance.list.map { |d| d['device_id'] }
    expect(ids).to include('1111111111111111')
    expect(ids).not_to include('3333333333333333')
    header 'Host', '192.168.1.10:4567'
    post '/devices/remove', { device_id: '1111111111111111' }, phone
    expect(last_response.status).to eq(403)
  end
end
