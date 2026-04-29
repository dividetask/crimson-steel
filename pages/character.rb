# /character — character sheet preview. Renders the
# character_sheet_stub for one character at a time, with
# prev/next arrows for cycling and a button to toggle between
# the minimal and full layouts.
#
# Routes:
#   GET /character           → first character, minimal layout
#   GET /character/:index    → that character (1-indexed, wraps),
#                              ?detail=full for the full layout

get '/character' do
  redirect "/character/1#{request.query_string.empty? ? '' : "?#{request.query_string}"}"
end

get '/character/:index' do
  list = DATA.pc_objects
  @total = list.length

  if @total.zero?
    @character = nil
    erb :"pages/character"
    next
  end

  raw = params[:index].to_i
  raw = 1 if raw < 1
  @current_index = ((raw - 1) % @total) + 1
  @character     = list[@current_index - 1]
  @prev_index    = ((@current_index - 2) % @total) + 1
  @next_index    = (@current_index % @total) + 1
  @detail        = params[:detail].to_s == 'full' ? :full : :minimal

  erb :"pages/character"
end
