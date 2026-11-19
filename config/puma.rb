# When started with `puma` or `rackup` (config.ru) instead of `ruby app.rb`:
# enough threads for a full table — each phone and the DM's page holds one
# live-updates connection (lib/change_feed.rb, ChangeFeed::THREADS).
threads 0, 32
# On Ctrl-C, close the live-updates connections first (each would otherwise
# keep the graceful stop waiting), and never wait more than a second.
force_shutdown_after 1
after_booted { ChangeFeed.close_on_signals! if defined?(ChangeFeed) }
