get '/notes' do
  @store      = Chronicle.store
  @viewer     = viewer_role
  @viewing_id = viewing_creature_id
  @timestamp  = @store.timestamp
  @chapters   = @store.list_chapters
  @current_chapter = @store.current_chapter
  @player_creatures = player_creatures

  @selected_chapter =
    if params[:chapter].to_s == 'all'
      nil
    elsif params.key?(:chapter)
      n = parse_chapter(params[:chapter])
      @chapters.any? { |c| c[:number] == n } ? n : nil
    else
      @current_chapter
    end

  # Keep Characters of Interest in sync with the npc roster: every `npc`
  # Creature gets a (DM-only, inactive) Creature Reference if it lacks one, so
  # it is visible and toggleable here. Promotion creates an active one instead.
  @store.ensure_creature_references(Creatures.list(group: 'npc').map { |id, _| id }) if @viewer == :dm

  entries = if @viewer == :dm
              @store.list_entries
            else
              @store.list_entries(visible_to: @viewing_id)
            end

  @entries = entries.sort_by { |e| [e['chapter'] || 0, e['notes_position'] || 9999] }
  erb :notes
end
