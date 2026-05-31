require 'bundler/setup'
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
require 'creatures/advancement'
require 'proficiencies'
require 'encounter'
require 'equipment'
require 'uploads'

require_relative 'lib/dice_resolution/config_js_generator'
# Regenerate the JS config from the YAML so the browser modules always
# reflect the current dice_resolution_config.yaml.
DiceResolution::ConfigJsGenerator.generate

# Status page sample data — one module per sub-view so each page's
# dummy data stays scoped to that page.
require_relative 'lib/status/sample_rolls'
require_relative 'lib/status/sample_check'
require_relative 'lib/status/sample_conditions'
require_relative 'lib/status/sample_creatures'
require_relative 'lib/status/sample_timekeeping'
require_relative 'lib/status/sample_chronicle'
require_relative 'lib/status/sample_encounter'

require_relative 'lib/creature_sheet'
require_relative 'lib/live_roster'
require_relative 'lib/test_docs'
require_relative 'lib/glossary_docs'
require_relative 'lib/explainer_docs'
require_relative 'lib/helpers'

%w[home character_sheets store notes social compendium status view_as chronicle encounter].each do |name|
  require_relative "lib/routes/#{name}"
end
