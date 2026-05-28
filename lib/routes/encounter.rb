# Encounter page + mutation endpoints.
#
# Page (DM + Player):
#   GET  /encounter — shows the active scene of play: timekeeping,
#                     the Combat Tracker (when Combat is active or the
#                     viewer is the DM), and Chronicle notes (hidden
#                     from players once Combat starts).
#
# Mutation endpoints (DM only; JSON-in, JSON-out):
#   POST /encounter/add                — Add Combatant by Creature ID
#   POST /encounter/spawn_and_add      — Spawn from template + Add Combatant
#   POST /encounter/remove_by_creature — Remove the most recently added
#                                        Combatant whose creature_id matches
#   POST /encounter/set_pc_active      — Toggle a PC's `excluded_pcs` membership
#   POST /encounter/set_npc_active     — Toggle an NPC's roster presence
#   POST /encounter/start_combat       — Enter Combat mode
#   POST /encounter/end_combat         — Leave Combat mode
#   POST /random_encounters/roll/:id   — Roll a Random Encounter and add the
#                                        spawned Creatures to the roster
#
# Mutation endpoints return `{ ok: true, ... }` on success,
# `{ ok: false, error: "..." }` on failure.

get '/encounter' do
  @store      = Chronicle.store
  @viewer     = viewer_role
  @viewing_id = viewing_creature_id
  @timestamp  = @store.timestamp
  @encounter_state = Encounter.state
  @combat_active   = @encounter_state.combat_active?

  if @viewer == :dm
    @active_entries = @store.list_entries(active_only: true)
  else
    @active_entries = @store.list_entries(active_only: true, visible_to: @viewing_id)
  end

  @active_entries = @active_entries.sort_by { |e| e['scene_position'] || 9999 }
  @chapters       = @store.list_chapters
  @current_chapter = @store.current_chapter
  @player_creatures = player_creatures

  # Build the Combat Tracker rows from the live Combatant roster.
  # Each row carries everything `_initiative_stub.erb` needs to render.
  @tracker_rows = @encounter_state.combatants.map do |c|
    creature = Creatures.lookup(c[:creature_id]) rescue nil
    display_name = if !c[:name].to_s.empty?
      c[:name]
    elsif creature
      creature.name
    else
      "Creature ##{c[:creature_id]}"
    end
    {
      combatant_id:    c[:id],
      creature_id:     c[:creature_id],
      name:            display_name,
      initiative:      '—',  # Initiative rolling lands in a later pass.
      acting:          (c[:id] == @encounter_state.to_h['acting_combatant_id'])
    }
  end

  erb :encounter
end

helpers do
  def encounter_state
    Encounter.state
  end

  def require_dm!
    halt 403, { 'Content-Type' => 'application/json' }, JSON.generate(ok: false, error: 'DM only') unless dm_view?
  end

  def encounter_response(payload)
    [200, { 'Content-Type' => 'application/json' }, JSON.generate(payload)]
  end

  def encounter_error(status, msg)
    [status, { 'Content-Type' => 'application/json' }, JSON.generate(ok: false, error: msg)]
  end

  # Build the JSON snapshot the JS uses to update the sidebar row.
  def encounter_row_snapshot(creature_id)
    {
      creature_id: creature_id.to_s,
      copy_count:  encounter_state.copy_count(creature_id),
      in_combat:   encounter_state.includes_creature?(creature_id),
      pc_excluded: encounter_state.pc_excluded?(creature_id)
    }
  end
end

post '/encounter/add' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  combatant = encounter_state.add_combatant(creature_id, name_override: params[:name])
  encounter_response(ok: true, combatant: combatant, row: encounter_row_snapshot(creature_id))
end

post '/encounter/spawn_and_add' do
  require_dm!
  template_id = params[:template_id]
  return encounter_error(400, 'template_id is required') if template_id.nil? || template_id.to_s.empty?

  begin
    new_creature_id = Creatures.spawn_from_template(Integer(template_id))
  rescue ArgumentError => e
    return encounter_error(404, e.message)
  end

  combatant = encounter_state.add_combatant(new_creature_id)
  encounter_response(
    ok: true,
    combatant: combatant,
    spawned_creature_id: new_creature_id,
    row: encounter_row_snapshot(template_id)
  )
end

post '/encounter/remove_by_creature' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  removed = encounter_state.remove_last_combatant_by_creature_id(creature_id)
  if removed
    encounter_response(ok: true, removed: removed, row: encounter_row_snapshot(creature_id))
  else
    encounter_response(ok: false, error: 'no matching combatant', row: encounter_row_snapshot(creature_id))
  end
end

post '/encounter/set_pc_active' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  active = params[:active].to_s == 'true' || params[:active] == true || params[:active] == '1'
  if active
    encounter_state.remove_pc_exclusion(creature_id)
    # Auto-add the PC to the roster when activated, unless already present.
    encounter_state.add_combatant(creature_id) unless encounter_state.includes_creature?(creature_id)
  else
    encounter_state.add_pc_exclusion(creature_id) # also drops any matching Combatants
  end
  encounter_response(ok: true, active: active, row: encounter_row_snapshot(creature_id))
end

post '/encounter/set_npc_active' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  active = params[:active].to_s == 'true' || params[:active] == true || params[:active] == '1'
  if active
    encounter_state.add_combatant(creature_id) unless encounter_state.includes_creature?(creature_id)
  else
    encounter_state.remove_all_combatants_by_creature_id(creature_id)
  end
  encounter_response(ok: true, active: active, row: encounter_row_snapshot(creature_id))
end

post '/encounter/start_combat' do
  require_dm!
  encounter_state.start_combat
  redirect back || '/encounter'
end

post '/encounter/end_combat' do
  require_dm!
  encounter_state.end_combat
  redirect back || '/encounter'
end
