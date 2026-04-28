# /character — character sheet preview. Renders via the
# character_sheet_stub helper using a hard-coded Character plus
# dummy data for everything the new class doesn't yet own.

get '/character' do
  erb :"pages/character"
end
