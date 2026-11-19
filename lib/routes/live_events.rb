# Live updates (docs/project/live_updates.md): the Android app and the DM's
# Encounter page hold one Server-Sent Events connection each and fetch only
# when told something changed (lib/change_feed.rb).

# The web app changes the game only through POSTs: each one that succeeds
# is a change every listener should know about.
after do
  ChangeFeed.instance.bump! if request.post? && response.status < 400
end

helpers do
  def event_stream
    content_type 'text/event-stream'
    headers 'Cache-Control' => 'no-cache', 'X-Accel-Buffering' => 'no'
    # Tests ask for a short-lived stream.
    max = params[:max].to_s.match?(/\A\d+(\.\d+)?\z/) ? [params[:max].to_f, ChangeFeed::MAX_SECONDS].min : ChangeFeed::MAX_SECONDS
    stream { |out| ChangeFeed.instance.stream(out, max: max) }
  end
end

# The Android app: any device (one waiting to be assigned a Character too,
# so it hears the moment the DM assigns it).
get '/api/events' do
  event_stream
end

# The DM's Encounter page.
get '/encounter/events' do
  halt 403 unless dm_view?
  event_stream
end

# The DM's notice in the top bar, re-fetched when something changes.
get '/dm/notices' do
  halt 403 unless dm_view?
  erb :_dm_notices, layout: false
end
