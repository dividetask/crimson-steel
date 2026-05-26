STATUS_VIEWS = %w[status dice check conditions].freeze

get '/status' do
  redirect '/character-sheets' unless dm_view?
  @view = STATUS_VIEWS.include?(params[:view]) ? params[:view] : 'status'
  @check = DummyData.check
  @rolls = DummyData.rolls

  if @view == 'conditions'
    @catalog = Conditions::Catalog.load
    @creatures = DummyData.creatures
  elsif @view == 'check'
    @catalog = Conditions::Catalog.load
    @save_examples = DummyData.save_resolution_examples(@catalog)
  end

  erb :status
end
