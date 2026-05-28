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

  # Encounter template viewer (replaces the character sheet in the
  # main panel when ?random_encounter_template=<table_id> is set).
  @random_encounter_template_id = params[:random_encounter_template]
  if @random_encounter_template_id && Creatures::RandomEncounter.tables.key?(@random_encounter_template_id)
    @random_encounter_template = Creatures::RandomEncounter.tables[@random_encounter_template_id]
    @random_encounter_name_for = ->(template_id) do
      a = Creatures.lookup(template_id)
      a ? a.name : "Creature ##{template_id}"
    end
  else
    @random_encounter_template_id = nil
  end

  # Roster Sidebar (DM only).
  @roster = Status::SampleCreatures.roster if dm_view?

  erb :character_sheets
end

# JS-driven encounter roll fetch (creatures_random_encounter_roll_result_stub.md).
# Returns an HTML fragment that the client inserts above the main panel.
# The fragment includes its own Roll button; further clicks fire the
# same endpoint and replace the panel's content with a fresh roll.
#
# Combat / enemy-data-file side effects of the roll are NOT wired
# yet — the stub spec calls those out as future work. For now the
# server picks a sample roll result and returns it.
get '/random_encounters/roll/:table_id' do
  halt 404 unless dm_view?
  table_id = params[:table_id]
  halt 404 unless Creatures::RandomEncounter.tables.key?(table_id)

  result = Status::SampleCreatures.random_roll_result(table_id)
  erb :_random_encounter_roll_result, layout: false, locals: { result: result }
end
