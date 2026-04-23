# /status — DM-only dashboard. Refuses to render for any viewer whose
# request is not DM, so even a correct URL guess from a player device
# sees a 404.

get '/status' do
  halt 404 unless @current_user&.dm?
  erb :"pages/status"
end
