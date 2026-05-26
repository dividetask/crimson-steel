STATUS_VIEWS = %w[status dice check conditions].freeze

get '/status' do
  redirect '/character-sheets' unless dm_view?
  @view = STATUS_VIEWS.include?(params[:view]) ? params[:view] : 'status'
  @check = DummyData.check
  @rolls = DummyData.rolls

  if @view == 'conditions'
    @catalog = Conditions::Catalog.load
    @creatures = DummyData.creatures
  end

  erb :status
end
