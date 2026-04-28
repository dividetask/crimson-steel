require 'sinatra'
require 'json'
require 'securerandom'
require 'socket'
require_relative 'lib/dice_system'
require_relative 'lib/user'
require_relative 'lib/dummy_data'
require_relative 'lib/notes_state'

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
DATA        = DummyData

# Hard rule: DummyData stays out of production. In dev it returns
# its hard-coded sample content; in any other environment every
# method funnels through gate(empty) and returns the empty default.
DummyData.enabled = settings.development?

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

  # The char_id of whose turn it is right now. NotesState owns the
  # active combat slot (combat_id like 'pc-3'); we resolve that to
  # the underlying character id by looking up the turn record.
  def current_turn_char_id
    cid = NOTES_STATE.current_turn || DATA.combat_state['current_turn']
    DATA.combat_state['turns'].find { |t| t['combat_id'] == cid }&.dig('char_id')
  end

  # Can the viewer add map arrows right now? DMs always can (via the
  # tool picker). Players can only when their assigned character is
  # the current-turn character. Devices with no character assigned
  # are spectators.
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
