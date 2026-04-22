require 'sinatra'
require 'json'
require 'securerandom'
require_relative 'lib/dice_system'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false

enable :sessions

DICE_SYSTEM = DiceSystem.new(File.join(__dir__, 'data', 'dice_resolution.yaml'))

helpers do
  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end
end

get '/' do
  redirect '/test'
end

require_relative 'stubs/roll_stub'
require_relative 'pages/test'
