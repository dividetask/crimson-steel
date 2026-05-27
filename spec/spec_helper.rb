$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'conditions'

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
end
