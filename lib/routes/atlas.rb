# Atlas map endpoints (atlas_stub.md). The map canvas is embedded on the
# Encounter page; these endpoints feed the canvas its render snapshot and
# back the DM toolbar — Map picker / Add / Edit / Archive / Unarchive /
# Delete Map, Place Token (drop a Combatant's icon on the Active Map),
# Move Token (drag), and Clear Tokens.
#
# Reads (DM + Player when Combat is active):
#   GET  /atlas/map[?map_id=]  — JSON snapshot of a Map (Active when omitted)
#
# Mutations (DM only; JSON-out, each returning a fresh snapshot):
#   POST /atlas/place_token / move_token / remove_token / clear_tokens
#   POST /atlas/set_active_map
#   POST /atlas/add_map / edit_map / archive_map / unarchive_map / delete_map

helpers do
  def atlas_state
    Atlas.state
  end

  def atlas_response(payload)
    [200, { 'Content-Type' => 'application/json' }, JSON.generate(payload)]
  end

  def atlas_error(status, msg)
    [status, { 'Content-Type' => 'application/json' }, JSON.generate(ok: false, error: msg)]
  end

  # One Token rendered for the canvas: resolves display name + Tier through
  # Creatures, and links the Token back to a live Combatant (matched by
  # creature_id) so a click on the map can target it in the Attack builder.
  # `acting_id` is the Acting Combatant (for the Acting ring + tooltip badge);
  # `viewer` gates the tooltip subtitle per atlas_token_tooltip.md.
  def atlas_token_view(token, acting_id, viewer)
    creature = Creatures.lookup(token[:creature_id]) rescue nil
    name = if token[:label] && !token[:label].to_s.empty?
             token[:label]
           elsif creature
             creature.name
           else
             "Creature ##{token[:creature_id]}"
           end
    combatant = encounter_state.combatants.find { |c| c[:creature_id].to_s == token[:creature_id].to_s }
    # Subtitle (race + class summary + Tier label) is DM-only, or shown to a
    # player when the Creature is a player_character.
    show_sub = viewer == :dm || (creature && Array(creature.tags).include?('player_character'))
    # Icon precedence (atlas_stub.md): the Token's own image override, then the
    # Creature's token image; absent both, the canvas draws a `?` marker.
    image = token[:image] && !token[:image].to_s.empty? ? token[:image] : (creature && (creature.creature_token rescue nil))
    {
      id:           token[:id],
      creature_id:  token[:creature_id].to_s,
      x:            token[:x],
      y:            token[:y],
      size:         token[:size],
      label:        name,
      subtitle:     show_sub ? atlas_subtitle(creature) : nil,
      image:        image,
      hidden:       token[:hidden],
      tier:         creature ? (creature.tier rescue nil) : nil,
      combatant_id: combatant && combatant[:id],
      initiative:   combatant ? combatant[:initiative_string].to_s : nil,
      acting:       !!(combatant && combatant[:id] == acting_id),
      unknown:      creature.nil?
    }
  end

  # Race + class summary and Tier label, e.g. "Human Bard 3 · Tier 2"
  # (atlas_token_tooltip.md → Subtitle). Omitted rows collapse out.
  def atlas_subtitle(creature)
    return nil unless creature
    parts = []
    rc = atlas_race_class(creature)
    parts << rc unless rc.empty?
    tier = (creature.tier rescue nil)
    parts << "Tier #{tier}" unless tier.nil?
    parts.empty? ? nil : parts.join(' · ')
  end

  def atlas_race_class(creature)
    titleize = ->(s) { s.to_s.split(/[_\s]+/).reject(&:empty?).map(&:capitalize).join(' ') }
    race = titleize.call((creature.race rescue nil))
    classes = (creature.class_summary rescue []).map { |k, lvl| "#{titleize.call(k)} #{lvl}".strip }
    [race, *classes].reject { |s| s.nil? || s.empty? }.join(' ')
  end

  # The render snapshot the canvas consumes. Players never see hidden Tokens
  # and may only view the Active Map; the DM may view any Map (including an
  # archived one, view-only). Returns map: nil when no Map is resolved.
  def atlas_map_snapshot(viewer, map_id: nil)
    map = map_id ? atlas_state.get_map(map_id) : atlas_state.get_active_map
    return { ok: true, viewer: viewer.to_s, map: nil, tokens: [] } unless map
    acting_id = encounter_state.acting_combatant_id
    tokens = atlas_state.list_tokens(map_id: map[:id], include_hidden: viewer == :dm)
    {
      ok:          true,
      viewer:      viewer.to_s,
      active:      map[:id] == atlas_state.active_map_id,
      map:         { id: map[:id], name: map[:name], image: map[:image],
                     width: map[:width], height: map[:height],
                     grid: map[:grid], archived: map[:archived] },
      tokens:      tokens.map { |t| atlas_token_view(t, acting_id, viewer) },
      # Annotations (drawings) are shared — every viewer sees them all.
      annotations: atlas_state.list_annotations(map_id: map[:id]),
      # Zones (spell areas / hazards). Anchor x/y are resolved Map Units.
      zones:       atlas_state.list_zones(map_id: map[:id])
    }
  end

  # Drawing is allowed for the DM always, and for a player while Combat is
  # active (the same gate that lets a player see the map at all). A player
  # may draw arrows only; the DM may draw any kind.
  def atlas_can_draw?(viewer)
    viewer == :dm || encounter_state.combat_active?
  end

  # Player arrows are transient suggestions: any change the DM makes to the
  # map wipes every player-drawn Annotation on the Active Map. DM drawings
  # persist until the DM clears them. Called from every DM mutation.
  def clear_player_drawings!
    map = atlas_state.get_active_map
    atlas_state.clear_annotations_on_map(map[:id], author: 'player') if map
  end

  # Combatants the *Place Token* control can drop on the Active Map — every
  # Combatant in the Encounter roster, by display name.
  def atlas_placeable_combatants
    encounter_state.combatants.map do |c|
      creature = Creatures.lookup(c[:creature_id]) rescue nil
      name = if !c[:name].to_s.empty? then c[:name]
             elsif creature then creature.name
             else "Creature ##{c[:creature_id]}" end
      { creature_id: c[:creature_id].to_s, name: name }
    end
  end

  # A sensible drop position for a freshly-placed Token: the Map's center
  # (or a small default for an unbounded Map), cascaded by how many Tokens
  # already sit on the Map so repeated placements don't perfectly stack.
  def atlas_default_position(map)
    base_x = map[:width]  ? (map[:width].to_f  / 2).floor : 5
    base_y = map[:height] ? (map[:height].to_f / 2).floor : 5
    n = atlas_state.list_tokens(map_id: map[:id]).length
    [base_x + (n % 8), base_y + (n / 8)]
  end
end

get '/atlas/map' do
  viewer = viewer_role
  halt 404 unless viewer == :dm || encounter_state.combat_active?
  map_id = params[:map_id].to_s.empty? ? nil : params[:map_id].to_i
  # A player may only view the Active Map.
  halt 404 if map_id && viewer != :dm && map_id != atlas_state.active_map_id
  atlas_response(atlas_map_snapshot(viewer, map_id: map_id))
end

post '/atlas/place_token' do
  require_dm!
  creature_id = params[:creature_id]
  return atlas_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  map = atlas_state.get_active_map
  return atlas_error(409, 'no active map') unless map

  x = params[:x] ? params[:x].to_f : nil
  y = params[:y] ? params[:y].to_f : nil
  x, y = atlas_default_position(map) if x.nil? || y.nil?

  token_id = atlas_state.place_token(map_id: map[:id], creature_id: creature_id.to_s, x: x, y: y,
                                     label: (params[:label].to_s.empty? ? nil : params[:label]))
  return atlas_error(409, 'could not place token') if token_id == Atlas::ERROR
  clear_player_drawings!
  atlas_response(ok: true, token_id: token_id, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/move_token' do
  require_dm!
  result = atlas_state.move_token(params[:token_id].to_i, params[:x].to_f, params[:y].to_f)
  return atlas_error(404, 'unknown token') if result == Atlas::ERROR || result.nil?
  clear_player_drawings!
  atlas_response(ok: true, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/remove_token' do
  require_dm!
  atlas_state.remove_token(params[:token_id].to_i)
  clear_player_drawings!
  atlas_response(ok: true, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/clear_tokens' do
  require_dm!
  map = atlas_state.get_active_map
  return atlas_error(409, 'no active map') unless map
  removed = atlas_state.clear_tokens_on_map(map[:id])
  clear_player_drawings!
  atlas_response(ok: true, removed: removed, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/set_active_map' do
  require_dm!
  raw = params[:map_id].to_s
  result = atlas_state.set_active_map(raw.empty? ? nil : raw.to_i)
  return atlas_error(409, 'could not set active map') if result == Atlas::ERROR
  clear_player_drawings!
  atlas_response(ok: true, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/add_map' do
  require_dm!
  name = params[:name].to_s.strip
  return atlas_error(400, 'name is required') if name.empty?
  width  = params[:width].to_s.empty?  ? nil : params[:width].to_i
  height = params[:height].to_s.empty? ? nil : params[:height].to_i
  id = atlas_state.add_map(name: name, width: width, height: height)
  atlas_state.set_active_map(id)
  clear_player_drawings!
  atlas_response(ok: true, map_id: id, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/edit_map' do
  require_dm!
  id = params[:map_id].to_i
  fields = {}
  fields[:name]   = params[:name].to_s unless params[:name].nil?
  fields[:width]  = (params[:width].to_s.empty?  ? nil : params[:width].to_i)  if params.key?('width')
  fields[:height] = (params[:height].to_s.empty? ? nil : params[:height].to_i) if params.key?('height')
  result = atlas_state.edit_map(id, **fields)
  return atlas_error(404, 'unknown map') if result == Atlas::ERROR
  clear_player_drawings!
  atlas_response(ok: true, snapshot: atlas_map_snapshot(:dm, map_id: id))
end

post '/atlas/archive_map' do
  require_dm!
  result = atlas_state.archive_map(params[:map_id].to_i)
  return atlas_error(404, 'unknown map') if result == Atlas::ERROR
  clear_player_drawings!
  atlas_response(ok: true, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/unarchive_map' do
  require_dm!
  id = params[:map_id].to_i
  result = atlas_state.unarchive_map(id)
  return atlas_error(404, 'unknown map') if result == Atlas::ERROR
  atlas_state.set_active_map(id) if params[:activate].to_s == 'true'
  clear_player_drawings!
  atlas_response(ok: true, snapshot: atlas_map_snapshot(:dm))
end

post '/atlas/delete_map' do
  require_dm!
  result = atlas_state.delete_map(params[:map_id].to_i)
  return atlas_error(404, 'unknown map') if result == Atlas::ERROR
  clear_player_drawings!
  atlas_response(ok: true, snapshot: atlas_map_snapshot(:dm))
end

# ---- Drawing (Annotations) -------------------------------------------
#
# A player may draw arrows only; the DM may draw any kind. The author is
# stamped from the viewer's role. JSON body: { type, points, color,
# shape_kind, text }.

post '/atlas/add_annotation' do
  viewer = viewer_role
  return atlas_error(403, 'cannot draw here') unless atlas_can_draw?(viewer)

  payload = JSON.parse(request.body.read) rescue nil
  return atlas_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  type = payload['type'].to_s
  # Players are restricted to arrows; the DM may draw any supported kind.
  allowed = viewer == :dm ? %w[arrow shape text] : %w[arrow]
  return atlas_error(403, "players may only draw arrows") unless allowed.include?(type)

  map = atlas_state.get_active_map
  return atlas_error(409, 'no active map') unless map
  points = Array(payload['points']).map { |p| [p[0].to_f, p[1].to_f] }
  return atlas_error(400, 'points are required') if points.empty?

  id = atlas_state.add_annotation(
    map_id: map[:id], type: type, points: points,
    color: payload['color'], shape_kind: payload['shape_kind'],
    text: payload['text'], author: viewer.to_s
  )
  return atlas_error(409, 'could not add annotation') if id == Atlas::ERROR
  clear_player_drawings! if viewer == :dm
  atlas_response(ok: true, annotation_id: id, snapshot: atlas_map_snapshot(viewer))
end

post '/atlas/remove_annotation' do
  viewer = viewer_role
  return atlas_error(403, 'cannot draw here') unless atlas_can_draw?(viewer)
  ann = atlas_state.get_annotation(params[:annotation_id].to_i)
  return atlas_error(404, 'unknown annotation') unless ann
  # A player may remove only their own annotations.
  return atlas_error(403, 'not your annotation') if viewer != :dm && ann[:author] != 'player'
  atlas_state.remove_annotation(ann[:id])
  atlas_response(ok: true, snapshot: atlas_map_snapshot(viewer))
end

post '/atlas/clear_annotations' do
  viewer = viewer_role
  return atlas_error(403, 'cannot draw here') unless atlas_can_draw?(viewer)
  map = atlas_state.get_active_map
  return atlas_error(409, 'no active map') unless map
  # The DM clears every drawing; a player clears only their own.
  author = viewer == :dm ? nil : 'player'
  removed = atlas_state.clear_annotations_on_map(map[:id], author: author)
  atlas_response(ok: true, removed: removed, snapshot: atlas_map_snapshot(viewer))
end
