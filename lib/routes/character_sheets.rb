get '/character-sheets' do
  demos = Status::SampleCreatures.demos
  total = demos.length
  i = params[:i].to_i
  i = 0 if i < 0
  i = total - 1 if i >= total

  @demo   = demos[i]
  @i      = i
  @total  = total
  @detail = params[:detail] == 'full' ? 'full' : 'minimal'

  # Pager wraps at both ends: prev from index 0 jumps to the last
  # index, next from the last index jumps to 0.
  @prev_i = (i - 1) % total
  @next_i = (i + 1) % total

  erb :character_sheets
end
