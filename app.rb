require 'bundler/setup'
require 'sinatra'

set :port, 4567
set :bind, '0.0.0.0'
# Enough web-server threads for a full table: each phone and the DM's page
# holds one live-updates connection (lib/change_feed.rb).
# On Ctrl-C, Puma waits for open requests to finish — and a live-updates
# connection stays open for minutes. Give them a second, then stop anyway.
# ChangeFeed::THREADS; once Puma is up, Ctrl-C first closes those connections.
puma_events = begin
  require 'puma/events'
  Puma::Events.new.tap { |ev| ev.after_booted { ChangeFeed.close_on_signals! } }
rescue LoadError, NoMethodError
  nil
end
set :server_settings, { Threads: "0:32", force_shutdown_after: 1 }.merge(puma_events ? { events: puma_events } : {})
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :static_cache_control, [:no_cache]
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
require 'atlas'
require 'equipment'
require 'item_icons'
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
require_relative 'lib/status/sample_equipment'

require_relative 'lib/creature_sheet'
require_relative 'lib/roll_log'
require_relative 'lib/scene_round'
require_relative 'lib/spell_list'
require_relative 'lib/class_list'
require_relative 'lib/live_roster'
require_relative 'lib/test_docs'
require_relative 'lib/glossary_docs'
require_relative 'lib/explainer_docs'
require_relative 'lib/design_docs'
require_relative 'lib/device_registry'
require_relative 'lib/helpers'
require_relative 'lib/lan_discovery'
require_relative 'lib/player_requests'
require_relative 'lib/action_flow'
require_relative 'lib/dice_colors'
require_relative 'lib/change_feed'
require_relative 'lib/action_sounds'

%w[home character_sheets character_creation store notes compendium status view_as devices chronicle encounter encounter_looting encounter_afflictions encounter_reactions encounter_special encounter_attack_ui encounter_cast_ui encounter_cast_resolution inventory atlas sheet_modals dm monster_creation api action_flows live_events].each do |name|
  require_relative "lib/routes/#{name}"
end

# LAN discovery for the Android app: answer its UDP probe so it can find this
# server without typing an IP address (lib/lan_discovery.rb). Only when this
# file is run as the server (`ruby app.rb`), never under rspec / rack-test.
if Sinatra::Application.run?
  LanDiscovery.start(http_port: settings.port, name: -> { Chronicle.store.campaign_name })
end
