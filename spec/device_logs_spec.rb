require 'spec_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require 'base64'
require_relative '../app'

# Logs and screenshots the phones send to device-logs/ (lib/device_logs.rb,
# docs/project/device_logs.md), and the player's Status page with the app
# download (views/status_player.erb).
RSpec.describe 'Device logs and the player Status page', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  PLAYER = { 'REMOTE_ADDR' => '192.168.1.50' }.freeze
  PNG = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==')

  let(:dir) { Dir.mktmpdir }
  before do
    header 'Host', '192.168.1.10:4567'
    stub_const('DeviceLogs::DIR', dir)
    DeviceRegistry.instance_variable_set(:@instance, DeviceRegistry.new(File.join(dir, 'devices.json')))
  end
  after { DeviceRegistry.instance_variable_set(:@instance, nil) }

  def post_log(body)
    post '/api/logs', JSON.generate(body), PLAYER.merge('CONTENT_TYPE' => 'application/json')
    JSON.parse(last_response.body)
  end

  it 'saves a log with the device and both commits at the top' do
    j = post_log(log: "one\ntwo", app: { version: 'v0.038 a (e687)' }, device: { model: 'Pixel 7', android: '14 (API 34)' })
    expect(j['ok']).to be(true)
    text = File.read(File.join(dir, j['saved'].first))
    expect(text).to start_with('=' * 60)
    expect(text).to match(/^Kind +: log$/)
    expect(text).to match(/^App version +: v0\.038 a \(e687\)$/)
    expect(text).to match(/^Device model +: Pixel 7$/)
    expect(text).to match(/Server commit +: \S+/)
    expect(text).to match(/Device id +: \S+/)
    expect(text).to end_with("one\ntwo\n")
  end

  it 'saves a screenshot next to its log' do
    j = post_log(log: 'x', screenshot: Base64.strict_encode64(PNG))
    expect(j['saved'].map { |f| File.extname(f) }).to eq(%w[.log .png])
    expect(File.binread(File.join(dir, j['saved'][1]))).to eq(PNG.b)
    expect(File.read(File.join(dir, j['saved'][0]))).to include("Screenshot", j['saved'][1])
  end

  it 'refuses something that is not a PNG' do
    j = post_log(screenshot: Base64.strict_encode64('hello'))
    expect(last_response.status).to eq(400)
    expect(j['error']).to include('PNG')
    expect(Dir.children(dir).grep(/\.(log|png)\z/)).to be_empty
  end

  it 'shows a player who they are, their device id and the app download' do
    get '/status', {}, PLAYER
    expect(last_response.status).to eq(200)
    body = last_response.body
    expect(body).to include('Device id', 'not assigned yet')
    expect(body).not_to include('Device Assignment')
    expect(body).to include('href="/api/app/apk"') if AppRelease.latest
  end

  it 'lists Status in the menu for players' do
    get '/status', {}, PLAYER
    expect(last_response.body).to match(%r{<a[^>]+href="/status"})
  end
end
