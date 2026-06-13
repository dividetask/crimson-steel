ENV['RACK_ENV'] = 'test'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'rack/test'
require_relative '../app'

module AppHelpers
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end
end

RSpec.configure do |c|
  c.include AppHelpers
end
