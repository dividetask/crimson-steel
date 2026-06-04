require 'json'
require_relative '../character_creation'

# Character Creation Stub — the DM's "New Character" wizard. Reached
# from the New Character button on the Character Sheets roster. DM-only;
# players are bounced to the default landing page.
get '/character-creation' do
  redirect '/character-sheets' unless dm_view?
  @blob_json = CharacterCreation.blob.to_json
  erb :character_creation
end

# Persist an assembled character. The browser POSTs the collected
# choices as JSON; on success we return the new Creature's sheet URL so
# the client can navigate there.
post '/character-creation' do
  halt 403 unless dm_view?
  content_type :json
  begin
    payload = JSON.parse(request.body.read)
    raise ArgumentError, 'malformed request' unless payload.is_a?(Hash)
    id = CharacterCreation.create!(payload)
    { ok: true, id: id, redirect: "/character-sheets?creature_id=#{id}&detail=full" }.to_json
  rescue JSON::ParserError
    status 400
    { ok: false, error: 'invalid JSON' }.to_json
  rescue ArgumentError => e
    status 422
    { ok: false, error: e.message }.to_json
  end
end
