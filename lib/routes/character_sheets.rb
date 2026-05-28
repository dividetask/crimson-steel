get '/character-sheets' do
  @detail = params[:detail] == 'full' ? 'full' : 'minimal'

  # The sheet is rendered exclusively from the live Creatures domain
  # (docs/common/creatures + data/) via the CreatureSheet bridge —
  # never from Status sample data. ?creature_id selects directly;
  # ?i pages through the live roster in load order.
  ids = LiveRoster.ordered_ids
  @total = ids.length
  @creature_id =
    if params[:creature_id] && (acc = (Creatures.lookup(params[:creature_id]) rescue nil))
      acc.id
    elsif !ids.empty?
      i = params[:i].to_i
      i = 0 if i < 0
      i = ids.length - 1 if i >= ids.length
      ids[i]
    end
  @i = @creature_id ? (ids.index(@creature_id) || 0) : -1
  accessor = @creature_id && (Creatures.lookup(@creature_id) rescue nil)
  @demo = accessor ? CreatureSheet.build(accessor) : nil

  # Random Encounter Template viewer (replaces the sheet in the main
  # panel when ?random_encounter_template=<table_id> is set).
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

  # Roster Sidebar (DM only). Reconcile PCs first so they always show.
  if dm_view?
    reconcile_player_combatants!
    @roster = LiveRoster.build
  end

  erb :character_sheets
end

# JS-driven encounter roll fetch (creatures_random_encounter_roll_result_stub.md).
# Returns an HTML fragment that the client inserts above the main panel.
# Each roll calls Creatures.roll_random_encounter to spawn fresh
# Creatures, then adds each as a Combatant to the active Encounter
# roster. Loot is not yet rolled — that lands when the Equipment
# domain ships.
get '/random_encounters/roll/:table_id' do
  halt 404 unless dm_view?
  table_id = params[:table_id]
  halt 404 unless Creatures::RandomEncounter.tables.key?(table_id)

  spawn_ids = Creatures.roll_random_encounter(table_id)
  spawn_ids.each { |id| Encounter.state.add_combatant(id) }

  table = Creatures::RandomEncounter.tables[table_id]

  # Group spawns by name for a compact "3× Goblin" display.
  grouped = spawn_ids.each_with_object({}) do |id, acc|
    a = Creatures.lookup(id)
    name = a ? a.name : "Creature ##{id}"
    acc[name] ||= 0
    acc[name] += 1
  end

  result = {
    table_id:   table_id,
    table_name: table['name'] || table_id,
    subtitle:   nil,
    rolls:      grouped.map { |name, count| { count: count, name: name, gold: 0, items: [] } }
  }

  erb :_random_encounter_roll_result, layout: false, locals: { result: result }
end
