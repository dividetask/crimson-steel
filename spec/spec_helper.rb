$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'conditions'
require 'chronicle'
require 'tmpdir'
require 'fileutils'

module ConditionsHelpers
  def build_state(**fields)
    Conditions::State.new(**fields)
  end

  def build_catalog(config: nil, afflictions: nil, effect_names: nil)
    base = Conditions::Catalog.load
    Conditions::Catalog.new(
      config:       config       || base.config,
      afflictions:  afflictions  || base.afflictions,
      effect_names: effect_names || base.effect_names
    )
  end

  def build_instance(state: Conditions::State.new, catalog: nil)
    Conditions::Instance.new(state: state, catalog: catalog || build_catalog)
  end
end

RSpec.configure do |c|
  c.include ConditionsHelpers

  # Isolate the global Chronicle store. Encounter specs that wrap a Round go
  # through Encounter::State#notify_round_elapsed -> Chronicle.store.advance_time,
  # which persists; without this they would write the live data/chronicle_data.json
  # (the round_of_day kept drifting on every run). Point the singleton at a
  # throwaway data path (loaded from the example) so persistence stays in /tmp.
  c.before(:suite) do
    dir = Dir.mktmpdir('chronicle-spec')
    Chronicle.store = Chronicle::Store.load(
      data_path:    File.join(dir, 'chronicle_data.json'),
      example_path: Chronicle::Store::EXAMPLE_PATH
    )
    Chronicle.instance_variable_set(:@spec_tmp_dir, dir)
  end

  c.after(:suite) do
    dir = Chronicle.instance_variable_get(:@spec_tmp_dir)
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end

# Session Tests (spec/sessions, docs/project/session_tests.md) emulate whole
# play sessions over HTTP. They are slower than the unit specs and depend on
# node for scripted dice, so a plain `rspec` skips them; they run when the
# command targets spec/sessions or SESSION_TESTS is set. bin/session-tests
# runs them.
RSpec.configure do |c|
  running_sessions = ENV['SESSION_TESTS'] ||
                     ARGV.any? { |a| a.include?('spec/sessions') }
  c.filter_run_excluding(:session) unless running_sessions
end
