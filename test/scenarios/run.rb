# Run the scenarios (docs/project/scenarios/README.md).
#
#   bundle exec ruby test/scenarios/run.rb [--fast] [name filter]
#
# Full run: a real server, the DM in headless Chromium. --fast: in this
# process through rack-test, DM clicks replaced by their routes. Either way
# each scenario gets its own data folder (seeded from test/scenarios/data/
# when it names one), so data/ is never touched.
#
# KEEP_DATA=1 keeps each run's data folder; CRIMSON_SCENARIO_PORT picks the
# port (default 4590, so a server already running on 4567 is left alone).
require 'bundler/setup'
require_relative 'support/scenario'

fast = !ARGV.delete('--fast').nil?
filter = ARGV.first.to_s

Dir[File.join(__dir__, '*.rb')].sort.each { |f| require f unless File.basename(f) == 'run.rb' }
definitions = Scenarios::REGISTRY.values.select { _1.name.include?(filter) }
all_ok = true

if fast
  # One process holds one app, and the app reads its data folder at load: run
  # one scenario per process.
  if definitions.size > 1
    definitions.each { |d| all_ok &= system(RbConfig.ruby, __FILE__, '--fast', d.name) }
    exit(all_ok ? 0 : 1)
  end
  definition = definitions.first or exit(0)
  data_dir = Scenarios.prepare_data_dir(definition.options[:seed_data])
  ENV['CRIMSON_DATA_DIR'] = data_dir
  ENV['CRIMSON_TEST_DICE'] = '1'
  require_relative '../../app'
  DataMigrations.run!
  app = Sinatra::Application
  dm = Scenarios::DM.new(Scenarios::RackTransport.new(app, '127.0.0.1'), dice: Scenarios::LocalDice.new)
  ctx = Scenarios::Context.new(dm: dm, tablet_factory: ->(c) { Scenarios::RackTransport.new(app, '192.168.1.50', c) },
                               browser_available: false)
  begin
    all_ok = Scenarios.report(definition, Scenarios.run(definition, ctx))
  ensure
    FileUtils.remove_entry(data_dir) if ENV['KEEP_DATA'].to_s.empty?
  end
  exit(all_ok ? 0 : 1)
end

require 'ferrum'
port = (ENV['CRIMSON_SCENARIO_PORT'] || 4590).to_i

definitions.each do |definition|
  server = Scenarios::Server.new(port: port, seed_data: definition.options[:seed_data]).start
  browser_factory = lambda do
    Ferrum::Browser.new(browser_path: Scenarios::BROWSER_PATH, browser_options: { 'no-sandbox' => nil },
                        base_url: "http://127.0.0.1:#{port}", timeout: 15, window_size: [1366, 900])
  end
  dm = Scenarios::DM.new(server.dm_transport, browser_factory: browser_factory,
                                              dice: Scenarios::HttpDice.new(server.dm_transport))
  ctx = Scenarios::Context.new(dm: dm, tablet_factory: server.method(:tablet_transport), browser_available: true)
  begin
    all_ok &= Scenarios.report(definition, Scenarios.run(definition, ctx))
  ensure
    dm.close
    server.stop
  end
end

exit(all_ok ? 0 : 1)
