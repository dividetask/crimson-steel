STATUS_VIEWS = %w[status dice check conditions].freeze

get '/status' do
  redirect '/character-sheets' unless dm_view?
  @view = STATUS_VIEWS.include?(params[:view]) ? params[:view] : 'status'
  @check = DummyData.check
  @rolls = DummyData.rolls

  if @view == 'conditions'
    @catalog = Conditions::Catalog.load
    @creatures = DummyData.creatures
    @save_examples = DummyData.save_resolution_examples(@catalog)
  elsif @view == 'check'
    @catalog = Conditions::Catalog.load
    # Check Resolution sub-view shows just the multi-source demo (the
    # save with both a Reroll source and a Blessing Nudge source).
    # The other Conditions-tied saves live under the Conditions
    # sub-view.
    @save_examples = DummyData.save_resolution_examples(@catalog)
                              .select { |s| s[:stub_id] == 'save-bleed-t2-blessing' }
  end

  @tests_html  = TestDocs.render_for(@view)
  @tests_title = TestDocs.title_for(@view)

  erb :status
end
