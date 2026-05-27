get '/character-sheets' do
  demos = Status::SampleCreatures.demos
  total = demos.length
  i = params[:i].to_i
  i = 0 if i < 0
  i = total - 1 if i >= total

  @demo  = demos[i]
  @i     = i
  @total = total
  @detail = params[:detail] == 'full' ? 'full' : 'minimal'

  @prev_i = i > 0           ? i - 1 : nil
  @next_i = i < total - 1   ? i + 1 : nil

  erb :character_sheets
end
