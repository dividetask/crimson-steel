# Demo data seeding for local development. Loaded by app.rb only when
# Sinatra is running in development mode, so production deployments
# never create these placeholder devices. Safe to re-run — each
# insert is skipped when the device id is already present.
#
# Set RACK_ENV=production (or APP_ENV=production) to suppress.

%w[demo-phone-alice demo-tablet-bob].each do |did|
  USER_STORE.create(did) unless USER_STORE.find(did)
end
