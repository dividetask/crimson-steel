require 'sinatra'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false
enable :sessions

$LOAD_PATH.unshift(File.join(__dir__, 'lib'))

require 'abilities'
require 'conditions'
require 'dice_resolution'
require 'timekeeping'
require 'chronicle'
require 'creatures'
require 'uploads'
require_relative 'lib/dummy_data'
require_relative 'lib/test_docs'
require_relative 'lib/helpers'

%w[home character_sheets scene store notes social status view_as chronicle].each do |name|
  require_relative "lib/routes/#{name}"
end
