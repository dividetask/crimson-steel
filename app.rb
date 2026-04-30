require 'sinatra'
require 'json'
require 'securerandom'
require 'socket'
require_relative 'lib/dice_system'
require_relative 'lib/user'
require_relative 'lib/notes_state'
require_relative 'lib/character'
require_relative 'lib/skills'

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
USER_STORE  = UserStore.new(File.join(__dir__, 'data', 'users.json'))
NOTES_STATE = NotesState.new(File.join(__dir__, 'data', 'notes_state.json'))
SKILLS      = Skills.new(config_path: File.join(__dir__, 'data', 'skills.yaml'),
                         dice_system: DICE_SYSTEM)

if settings.development?
  require_relative 'lib/dummy_data'
  DATA = DummyData
else
  require_relative 'lib/empty_data'
  DATA = EmptyData
end

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

  # Whether the UI should render the DM-facing view. dm? is the
  # auth check (IP-derived); dm_view? lets a real DM preview the
  # player experience by flipping a session flag without losing
  # their actual privileges.
  def dm_view?
    dm? && session[:view_mode] != 'player'
  end

  def server_ip
    @server_ip ||= begin
      addr = Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }
      addr ? addr.ip_address : '127.0.0.1'
    end
  end

  # The char_id of whose turn it is right now. NotesState owns the
  # active combat slot (combat_id like 'pc-3'); we resolve that to
  # the underlying character id by looking up the turn record.
  def current_turn_char_id
    cid = NOTES_STATE.current_turn || DATA.combat_state['current_turn']
    DATA.combat_state['turns'].find { |t| t['combat_id'] == cid }&.dig('char_id')
  end

  def viewer_can_draw_arrow?
    return true if dm?
    return false unless current_user&.character_id
    current_user.character_id == current_turn_char_id
  end
end

before do
  @current_user = User.identify(request, response, USER_STORE)
end

get '/' do
  redirect '/test'
end

# Toggle between DM and player view. Auth-gated on the real DM
# check so players (or anyone who somehow forms this POST) can't
# flip the flag for themselves. The flag has no effect for
# non-DMs since dm_view? still requires dm?.
post '/view-mode' do
  halt 403, 'forbidden' unless dm?
  session[:view_mode] = session[:view_mode] == 'player' ? 'dm' : 'player'
  redirect(request.referer || '/')
end

# In development a typo in the URL bar drops you on the test
# scratchpad rather than a 404. Production keeps the standard 404
# so we don't accidentally leak the test page to deployed users.
not_found do
  if settings.development?
    redirect '/test'
  else
    'Not Found'
  end
end

Dir[File.join(__dir__, 'stubs', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'pages', '*.rb')].sort.each { |f| require f }

require_relative 'seed_dev' if settings.development?
