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

# Optional machine-local overrides (environment, port, etc). Not
# tracked in git — each host can drop in its own local.rb to set
# things like `set :environment, :production`. Loaded before the
# settings.development? check below so overrides take effect.
local_config = File.join(__dir__, 'local.rb')
require local_config if File.exist?(local_config)

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

Dir[File.join(__dir__, 'stubs', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'pages', '*.rb')].sort.each { |f| require f }

require_relative 'seed_dev' if settings.development?
