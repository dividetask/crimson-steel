STATUS_VIEWS = %w[status dice check conditions creatures timekeeping chronicle encounter].freeze

get '/status' do
  redirect '/character-sheets' unless dm_view?
  @view = STATUS_VIEWS.include?(params[:view]) ? params[:view] : 'status'
  @check = Status::SampleCheck.check
  @rolls = Status::SampleRolls.rolls

  if @view == 'conditions'
    @catalog = Conditions::Catalog.load
    @creatures = Status::SampleConditions.creatures
    @save_examples = Status::SampleConditions.save_resolution_examples(@catalog)
  elsif @view == 'check'
    @catalog = Conditions::Catalog.load
    # Check Resolution sub-view shows just the multi-source demo (the
    # save with both a Reroll source and a Blessing Nudge source).
    # The other Conditions-tied saves live under the Conditions
    # sub-view.
    @save_examples = Status::SampleConditions.save_resolution_examples(@catalog)
                                              .select { |s| s[:stub_id] == 'save-bleed-t2-blessing' }
  elsif @view == 'creatures'
    @creature_demos = Status::SampleCreatures.demos
  elsif @view == 'encounter'
    @encounter_scenarios = Status::SampleEncounter.scenarios
  elsif @view == 'timekeeping'
    @timekeeping_examples = Status::SampleTimekeeping.timekeeping_examples
  elsif @view == 'chronicle'
    @chronicle_examples = Status::SampleChronicle.chronicle_examples.map do |ex|
      ex.merge(entry: Chronicle::Entry.normalize(ex[:entry]))
    end
  end

  @tests_html  = TestDocs.render_for(@view)
  @tests_title = TestDocs.title_for(@view)

  erb :status
end
