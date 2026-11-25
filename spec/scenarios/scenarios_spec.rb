require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require_relative '../../app'
require_relative '../../test/scenarios/support/scenario'

Dir[File.expand_path('../../test/scenarios/*.rb', __dir__)].sort.each { |f| require f unless File.basename(f) == 'run.rb' }

# The scenarios in test/scenarios/ on the fast track: in process, DM routes
# only. Steps marked browser: true run only under test/scenarios/run.rb.
RSpec.describe 'Scenarios (fast track)' do
  let(:tmp) { Dir.mktmpdir('scenario-spec') }

  around do |ex|
    ENV['CRIMSON_TEST_DICE'] = '1'
    TestDice.reset!
    ex.run
  ensure
    ENV.delete('CRIMSON_TEST_DICE')
    TestDice.reset!
  end

  before do
    DeviceRegistry.instance_variable_set(:@instance, DeviceRegistry.new(File.join(tmp, 'devices.json')))
    DiceColors.instance_variable_set(:@instance, DiceColors.new(File.join(tmp, 'dice_colors.json')))
    PlayerRequests.instance = PlayerRequests.new
    ActionFlows.instance = ActionFlows.new
    cond = Hash.new { |h, id| h[id] = Conditions::Instance.new }
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(id) { Creatures.lookup(id) }, conditions_for: ->(id) { cond[id] }
    )
  end

  after do
    DeviceRegistry.reset!
    DiceColors.reset!
    FileUtils.remove_entry(tmp) if File.exist?(tmp)
  end

  Scenarios::REGISTRY.each_value do |definition|
    it definition.name do
      app = Sinatra::Application
      dm = Scenarios::DM.new(Scenarios::RackTransport.new(app, '127.0.0.1'), dice: Scenarios::LocalDice.new)
      ctx = Scenarios::Context.new(dm: dm, tablet_factory: ->(c) { Scenarios::RackTransport.new(app, '192.168.1.50', c) },
                                   browser_available: false)
      results = Scenarios.run(definition, ctx)
      out = StringIO.new
      ok = Scenarios.report(definition, results, io: out)
      expect(ok).to be(true), out.string
    end
  end
end
