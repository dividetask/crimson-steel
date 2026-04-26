# /notes — campaign log, characters of interest, image gallery, and
# maps. Visible to everyone; per-entry public flags filter what
# non-DMs see (handled inside each stub).
#
# Chapter routing:
#   /notes                  → defaults to the latest chapter
#   /notes?chapter=all      → all chapters
#   /notes?chapter=<n>      → that specific chapter

get '/notes' do
  c = params[:chapter].to_s
  @current_chapter = if c.empty?
                       DATA.chapters.last && DATA.chapters.last['number']
                     elsif c == 'all'
                       nil
                     else
                       c.to_i
                     end
  erb :"pages/notes"
end
