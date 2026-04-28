# /scene — current scene's title, description, and map. The
# initiative track from the active combat is rendered below the
# map; players see the masked version, the DM sees full numbers.

get '/scene' do
  erb :"pages/scene"
end
