require 'sinatra'
require 'json'
require 'securerandom'
require 'socket'
require_relative 'lib/dice_system'
require_relative 'lib/user'
require_relative 'lib/dummy_data'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false

enable :sessions

DICE_SYSTEM = DiceSystem.new(File.join(__dir__, 'data', 'dice_resolution.yaml'))
USER_STORE = UserStore.new(File.join(__dir__, 'data', 'users.json'))
DATA = DummyData

helpers do
  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end

  def current_user
    @current_user
  end

  def dm?
    @current_user&.dm? == true
  end

  # LAN address players connect to. We pick the first non-loopback
  # IPv4 the server binds; if there isn't one (e.g. no network), fall
  # back to the loopback address the DM is browsing from.
  def server_ip
    @server_ip ||= begin
      addr = Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }
      addr ? addr.ip_address : '127.0.0.1'
    end
  end
end

before do
  @current_user = User.identify(request, response, USER_STORE)
end

get '/' do
  redirect '/test'
end

post '/user/assign_character' do
  char_id = params[:character_id].to_s.empty? ? nil : params[:character_id].to_i
  if char_id.nil?
    @current_user.unassign_character
  else
    @current_user.assign_character(char_id)
  end
  redirect(request.referrer || '/')
end

post '/combat/set_turn/:combat_id' do
  session[:current_turn] = params[:combat_id]
  redirect(request.referrer || '/')
end

require_relative 'stubs/roll_stub'
require_relative 'stubs/initiative_stub'
require_relative 'pages/test'
