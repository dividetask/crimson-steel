require 'json'
require 'net/http'
require 'socket'
require 'securerandom'
require 'tmpdir'
require 'fileutils'

# Scenario harness: the DM's laptop and the players' tablets talking to one
# Crimson Steel server (docs/project/scenarios/README.md).
#
# The same scenario runs on two transports:
# - Http: a real server process. The DM is 127.0.0.1 (plus a headless browser
#   for click steps); tablets use this machine's LAN address so the server
#   sees them as players.
# - Rack: in process through rack-test (spec/scenarios/), no browser.
module Scenarios
  ROOT = File.expand_path('../../..', __dir__)

  Response = Struct.new(:status, :body) do
    def json = (JSON.parse(body) rescue nil)
    def ok? = status.between?(200, 399)
  end

  def self.lan_ip
    Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }&.ip_address or
      raise 'no non-loopback IPv4 address: tablets would look like the DM'
  end

  class HttpTransport
    def initialize(host, port, cookies = {})
      @host, @port, @cookies = host, port, cookies
    end

    def get(path, params = {})
      path = "#{path}?#{URI.encode_www_form(params)}" unless params.empty?
      send_req(Net::HTTP::Get.new(path))
    end

    def post_json(path, body = {})
      req = Net::HTTP::Post.new(path, 'Content-Type' => 'application/json')
      req.body = JSON.generate(body)
      send_req(req)
    end

    def post_form(path, form = {})
      req = Net::HTTP::Post.new(path)
      req.set_form_data(form)
      send_req(req)
    end

    def cookie(name) = @cookies[name]

    private

    def send_req(req)
      req['Cookie'] = @cookies.map { |k, v| "#{k}=#{v}" }.join('; ') unless @cookies.empty?
      res = Net::HTTP.start(@host, @port, read_timeout: 30) { |h| h.request(req) }
      Array(res.get_fields('set-cookie')).each do |c|
        k, v = c.split(';', 2).first.split('=', 2)
        @cookies[k] = v
      end
      Response.new(res.code.to_i, res.body.to_s)
    end
  end

  # rack-test session; remote_addr decides DM (loopback) vs player.
  class RackTransport
    def initialize(app, remote_addr, cookies = {})
      require 'rack/test'
      @session = Rack::Test::Session.new(app, '192.168.1.10')
      cookies.each { |k, v| @session.set_cookie("#{k}=#{v}") }
      @env = { 'REMOTE_ADDR' => remote_addr }
    end

    def get(path, params = {}) = wrap { @session.get(path, params, @env) }
    def post_json(path, body = {}) = wrap { @session.post(path, JSON.generate(body), @env.merge('CONTENT_TYPE' => 'application/json')) }
    def post_form(path, form = {}) = wrap { @session.post(path, form, @env) }
    def cookie(name) = @session.cookie_jar[name]

    private

    def wrap
      r = yield
      Response.new(r.status, r.body)
    end
  end

  # A player's tablet running the Android app: its own 16-hex-digit per-phone
  # id in the device cookie (docs/project/device_assignment.md).
  class Tablet
    attr_reader :name, :device_id, :http

    def initialize(name, transport_factory)
      @name = name
      @device_id = SecureRandom.hex(8)
      @http = transport_factory.call('crimson_device_id' => @device_id)
    end

    def hello = api(:get, '/api/hello')
    def sheet = api(:get, '/api/sheet')
    def inventory = api(:get, '/api/inventory')
    def initiative = api(:get, '/api/initiative')
    def prompts = api(:get, '/api/prompts')
    def request_action(**body) = api(:post, '/api/turn/requests', body)
    def withdraw(id) = api(:post, "/api/turn/requests/#{id}/delete")

    def waiting_prompts = Array(prompts['prompts']).select { _1['status'] == 'waiting' }

    def choose(prompt, value) = api(:post, "/api/prompts/#{prompt['flow_id']}/#{prompt['id']}", value: value)

    # The app rolls on the tablet and sends the faces; the scenario fixes them.
    def roll(prompt, dice:, rerolled: nil, final: nil)
      api(:post, "/api/prompts/#{prompt['flow_id']}/#{prompt['id']}",
          roll: { dice: dice, rerolled: rerolled, final: final || dice })
    end

    def last = @last

    private

    def api(verb, path, body = nil)
      @last = verb == :get ? @http.get(path) : @http.post_json(path, body || {})
      @last.json || {}
    end
  end

  # The DM's laptop. Route calls are the fast track; #browser is the real
  # page for steps the scenario says are clicks.
  class DM
    attr_reader :http

    def initialize(transport, browser_factory: nil, dice: nil)
      @http = transport
      @browser_factory = browser_factory
      @dice = dice
    end

    def browser
      @browser ||= @browser_factory&.call or raise 'this step needs the browser (run it with test/scenarios/run.rb)'
    end

    def assign(tablet, character_id)
      @http.post_form('/devices/assign', device_id: tablet.device_id, character_id: character_id.to_s)
    end

    # Queue scripted dice (lib/test_dice.rb), in the order they will be rolled.
    def dice(*faces, reset: false) = @dice.push(faces.flatten, reset: reset)
    def dice_status = @dice.status

    def close = @browser&.quit
  end

  # Scripted dice over HTTP (real server) or directly (in process).
  class HttpDice
    def initialize(http) = @http = http
    def push(faces, reset:) = @http.post_json('/test/dice', faces: faces, reset: reset).json
    def status = @http.get('/test/dice').json
  end

  class LocalDice
    def push(faces, reset:)
      TestDice.reset! if reset
      TestDice.push(faces)
      status
    end

    def status = JSON.parse(JSON.generate(TestDice.status))
  end

  # A real server process on its own port and data folder.
  class Server
    attr_reader :port, :data_dir

    def initialize(port: 4590, seed_data: nil)
      @port = port
      @data_dir = Dir.mktmpdir('crimson-scenario-data')
      FileUtils.cp_r(File.join(seed_data, '.'), @data_dir) if seed_data
    end

    def start
      @log = File.join(@data_dir, 'server.log')
      env = { 'CRIMSON_DATA_DIR' => @data_dir, 'CRIMSON_TEST_DICE' => '1', 'CRIMSON_PORT' => @port.to_s }
      @pid = Process.spawn(env, 'bundle', 'exec', 'ruby', 'app.rb', chdir: ROOT, out: @log, err: @log, pgroup: true)
      60.times do
        return self if (Net::HTTP.get_response('127.0.0.1', '/api/hello', @port) rescue nil)
        sleep 0.5
      end
      raise "server did not start; see #{@log}"
    end

    def stop
      Process.kill('-INT', @pid) rescue nil
      Process.wait(@pid) rescue nil
      FileUtils.remove_entry(@data_dir) if ENV['KEEP_DATA'].to_s.empty?
    end

    def dm_transport = HttpTransport.new('127.0.0.1', @port)
    def tablet_transport(cookies) = HttpTransport.new(Scenarios.lan_ip, @port, cookies)
  end

  BROWSER_PATH = ENV['CHROMIUM_PATH'] || ['/opt/pw-browsers/chromium', '/usr/bin/chromium', '/usr/bin/chromium-browser',
                                          '/usr/bin/google-chrome'].find { File.exist?(_1) }
end
