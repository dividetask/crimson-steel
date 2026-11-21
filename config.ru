require_relative 'app'
DataMigrations.run! # one-time changes to the campaign data in data/
(w = AppRelease.pending_warning) && warn("\n#{w}\n\n") # still waiting for the APK?
# Started via rackup/puma instead of `ruby app.rb`: answer the Android app's
# LAN discovery probe too. Set CRIMSON_STEEL_HTTP_PORT if you pass rackup -p.
LanDiscovery.start(http_port: Integer(ENV.fetch('CRIMSON_STEEL_HTTP_PORT', Sinatra::Application.settings.port)),
                   name: -> { Chronicle.store.campaign_name })
run Sinatra::Application
