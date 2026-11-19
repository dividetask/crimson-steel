# When started with `puma` or `rackup` (config.ru) instead of `ruby app.rb`:
# enough threads for a full table — each phone and the DM's page holds one
# live-updates connection (lib/change_feed.rb, ChangeFeed::THREADS).
threads 0, 32
