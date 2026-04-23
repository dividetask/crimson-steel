# Debug stub. Small readout of who the server thinks the viewer is:
# role (DM/Player), request IP, device id, and assigned character.
# Cheap to embed on any page while the UI is under construction.

helpers do
  def debug_stub(user: @current_user, req: request)
    char = user&.character_id ? DummyData.character_by_id(user.character_id) : nil
    erb :"stubs/_debug_stub", layout: false, locals: {
      user: user,
      req: req,
      character: char
    }
  end
end
