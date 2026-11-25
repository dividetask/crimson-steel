# Run the scenarios against a real server, with the DM in headless Chromium.
#
#   bundle exec ruby test/scenarios/run.rb              # every scenario
#   bundle exec ruby test/scenarios/run.rb connect      # names containing "connect"
#
# KEEP_DATA=1 keeps each run's data folder; CRIMSON_SCENARIO_PORT picks the
# port (default 4590, so a server already running on 4567 is left alone).
require 'bundler/setup'
require 'ferrum'
require_relative 'support/scenario'

Dir[File.join(__dir__, '*.rb')].sort.each { |f| require f unless File.basename(f) == 'run.rb' }

filter = ARGV.first.to_s
port = (ENV['CRIMSON_SCENARIO_PORT'] || 4590).to_i
all_ok = true

Scenarios::REGISTRY.values.select { _1.name.include?(filter) }.each do |definition|
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
