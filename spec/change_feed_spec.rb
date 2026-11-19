require 'spec_helper'
require 'rack/test'
require 'json'
require_relative '../app'

# Live updates (lib/change_feed.rb, lib/routes/live_events.rb,
# docs/project/live_updates.md).
RSpec.describe ChangeFeed do
  it 'wakes a waiting listener as soon as something changes' do
    feed = described_class.new
    t = Thread.new { feed.wait_past(0, 5) }
    sleep 0.05
    feed.bump!
    expect(t.value).to eq(1)
  end

  it 'gives up waiting after the timeout' do
    feed = described_class.new
    started = Time.now
    expect(feed.wait_past(0, 0.1)).to eq(0)
    expect(Time.now - started).to be < 1
  end

  it 'streams a "changed" on connect, one per burst of changes, and heartbeats' do
    feed = described_class.new
    out = []
    t = Thread.new { feed.stream(out, max: 0.6, heartbeat: 0.25) }
    sleep 0.05
    3.times { feed.bump! }
    t.join
    events = out.join.scan(/event: changed\ndata: (\{.*?\})/).flatten.map { |j| JSON.parse(j)['v'] }
    expect(events).to eq([0, 3])
    expect(out.join).to include(': ping')
  end

  describe 'routes' do
    include Rack::Test::Methods
    def app = Sinatra::Application

    before do
      ChangeFeed.instance = ChangeFeed.new
      header 'Host', '192.168.1.10:4567'
    end

    it 'moves on for a successful POST, not for a GET or a refused POST' do
      get '/api/hello', {}, 'REMOTE_ADDR' => '192.168.1.50'
      expect(ChangeFeed.instance.version).to eq(0)
      post '/dice_colors', { who: 'dm', color: 'sky' }, 'REMOTE_ADDR' => '192.168.1.50' # a player: 403
      expect(ChangeFeed.instance.version).to eq(0)
      header 'Host', 'localhost'
      post '/encounter/live/sync', '{"idle":true}', 'REMOTE_ADDR' => '127.0.0.1', 'CONTENT_TYPE' => 'application/json'
      expect(ChangeFeed.instance.version).to eq(1)
    end

    it 'serves the phones an event stream' do
      get '/api/events', { max: '0.2' }, 'REMOTE_ADDR' => '192.168.1.50'
      expect(last_response.content_type).to start_with('text/event-stream')
      expect(last_response.body).to include("event: changed\ndata: {\"v\":0}")
    end

    it 'serves the DM page its own, and no one else' do
      get '/encounter/events', { max: '0.2' }, 'REMOTE_ADDR' => '192.168.1.50'
      expect(last_response.status).to eq(403)
      header 'Host', 'localhost'
      get '/encounter/events', { max: '0.2' }, 'REMOTE_ADDR' => '127.0.0.1'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('event: changed')
    end
  end
end
