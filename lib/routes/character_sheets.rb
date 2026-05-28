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
  # main panel when ?encounter_template=<table_id> is set).
  @encounter_template_id = params[:encounter_template]
  if @encounter_template_id && Creatures::Encounter.tables.key?(@encounter_template_id)
    @encounter_template = Creatures::Encounter.tables[@encounter_template_id]
    @encounter_name_for = ->(template_id) do
      a = Creatures.lookup(template_id)
      a ? a.name : "Creature ##{template_id}"
    end
  else
    @encounter_template_id = nil
  end

  # Roster Sidebar (DM only).
  @roster = Status::SampleCreatures.roster if dm_view?

  erb :character_sheets
end

# JS-driven encounter roll fetch (creatures_encounter_roll_result_stub.md).
# Returns an HTML fragment that the client inserts above the main panel.
# The fragment includes its own Roll button; further clicks fire the
# same endpoint and replace the panel's content with a fresh roll.
#
# Combat / enemy-data-file side effects of the roll are NOT wired
# yet — the stub spec calls those out as future work. For now the
# server picks a sample roll result and returns it.
get '/encounters/roll/:table_id' do
  halt 404 unless dm_view?
  table_id = params[:table_id]
  halt 404 unless Creatures::Encounter.tables.key?(table_id)

  result = Status::SampleCreatures.random_roll_result(table_id)
  erb :_encounter_roll_result, layout: false, locals: { result: result }
end
