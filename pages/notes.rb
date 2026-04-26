# /notes — campaign log, characters of interest, and image gallery.
# Visible to everyone; per-entry public flags filter what non-DMs
# see (handled inside each stub).

get '/notes' do
  @current_chapter = params[:chapter].to_s.empty? ? nil : params[:chapter].to_i
  erb :"pages/notes"
end
