require 'bundler/setup'
require 'sinatra'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false
enable :sessions

$LOAD_PATH.unshift(File.join(__dir__, 'lib'))

require_relative 'lib/compendium_docs'
require_relative 'lib/combat/sample_turn'
require_relative 'lib/helpers'

# Page routes. Every menu link maps to a route file here; a link whose
# route file is absent falls through to the `not_found` handler below and
# renders the "Not Yet Implemented" page. To bring a page online, drop its
# route file (and view) back in and add it to this list; to take it
# offline, remove it again.
%w[home compendium view_as status].each do |name|
  require_relative "lib/routes/#{name}"
end

# Any page that isn't coded yet — i.e. no route matched the request —
# renders the shared "Not Yet Implemented" notice inside the normal menu
# layout, so the menu stays navigable while that page is offline.
not_found do
  erb :not_implemented
end
