# notes_map_stub — gallery of map entries with optional interactive
# editing. When `interactive` is true the partial renders objects
# as clickable tokens, draws stored arrows on top, and shows the
# arrow-type picker / clear / add-object controls. When false (the
# default) it renders read-only thumbnails.

# Rendering style per arrow type. Pulled out as a top-level
# constant so the partial can reach it without going through a
# helper call.
NOTES_MAP_ARROW_STYLES = {
  'attack'         => { color: '#c62828', dash: nil,        width: 2.5 },
  'move-hurry'     => { color: '#ef6c00', dash: '6 4',      width: 2 },
  'move-sneak'     => { color: '#6a1b9a', dash: '2 3',      width: 1.5 },
  'move-carefully' => { color: '#2e7d32', dash: nil,        width: 2 }
}.freeze

NOTES_MAP_ARROW_TYPES = NOTES_MAP_ARROW_STYLES.keys.freeze

# Emoji palette (DM only for now). Adapted from
# claude/add-scene-map-drawing-xzz3R — the original branch had three
# groups (player / general / class). The general + class groups are
# the DM palette here.
NOTES_MAP_DM_ICONS = {
  'general' => [
    ['🕸',   'Web'],
    ['🔥',   'Fire'],
    ['💧',   'Water'],
    ['☠',    'Death / skull'],
    ['🪤',   'Trap'],
    ['🚪',   'Door'],
    ['⛏',    'Rubble / mining'],
    ['⭐',   'Objective / star'],
    ['⬆',    'Up / north'],
    ['⬇',    'Down / south'],
    ['⬅',    'Left / west'],
    ['➡',    'Right / east'],
    ['❓',   'Unknown'],
    ['❗',   'Alert']
  ],
  'class' => [
    ['🪓',   'Axe — barbarian / warrior'],
    ['⚔️',   'Crossed swords — fighter'],
    ['🛡️',   'Shield — defender / paladin'],
    ['🗡️',   'Dagger — rogue / assassin'],
    ['🏹',   'Bow — archer / ranger / elf'],
    ['🪄',   'Wand — mage / sorcerer'],
    ['📖',   'Tome — wizard / scholar'],
    ['⚕️',   'Medical staff — cleric / healer'],
    ['🎵',   'Music note — bard'],
    ['🎭',   'Masks — bard / performer'],
    ['🧝',   'Elf'],
    ['🧙',   'Mage / druid'],
    ['🐺',   'Wolf — druid / ranger companion'],
    ['👑',   'Crown — noble / leader'],
    ['💀',   'Skull — fallen / undead']
  ]
}.freeze

helpers do
  def notes_map_stub(entries:, dm_view: false, current_chapter: nil,
                     active_only: false, interactive: false,
                     scene_state: nil, can_draw: nil)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    visible = visible.select { |e| e['active'] } if active_only
    # `can_draw` lets the test page simulate a non-DM "current
    # turn" player; nil means use the live viewer_can_draw_arrow?
    # check.
    resolved_can_draw = if can_draw.nil?
                         interactive && (defined?(viewer_can_draw_arrow?) ? viewer_can_draw_arrow? : true)
                       else
                         interactive && can_draw
                       end
    erb :"stubs/_notes_map_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view,
      interactive: interactive,
      scene_state: scene_state,
      can_draw: resolved_can_draw
    }
  end

  # Visual style per object kind. Returns [fill, stroke, glyph]
  # where glyph is one of :circle, :rect, :triangle, :diamond.
  def notes_map_object_style(kind)
    case kind.to_s
    when 'pc'       then ['#577a99', '#1d3a5b', :circle]
    when 'npc'      then ['#9e9e9e', '#424242', :circle]
    when 'enemy'    then ['#a04848', '#5e1818', :circle]
    when 'scenery'  then ['#9c7a4a', '#5d4520', :rect]
    when 'door'     then ['#5d4037', '#2e1c14', :rect]
    when 'trap'     then ['#ffb300', '#7b5e00', :triangle]
    when 'hazard'   then ['#e53935', '#7b1c1c', :triangle]
    when 'treasure' then ['#fdd835', '#9c7a00', :diamond]
    else                 ['#888888', '#3a3a3a', :circle]
    end
  end

  def notes_map_arrow_label(type)
    case type
    when 'attack'         then 'Attack'
    when 'move-hurry'     then 'Move (hurry)'
    when 'move-sneak'     then 'Move (sneak)'
    when 'move-carefully' then 'Move (carefully)'
    else type.to_s
    end
  end
end

post '/scene/draw_arrow' do
  content_type :json
  unless viewer_can_draw_arrow?
    status 403
    return { ok: false, error: 'not your turn' }.to_json
  end
  ok = SCENE_STATE.add_arrow(
    map_id:    params[:map_id].to_i,
    type:      params[:type].to_s,
    device_id: current_user&.device_id,
    label:     current_user&.character_id ? DATA.character_by_id(current_user.character_id)&.dig('name') : nil,
    from_id:   params[:from_id].to_s.empty? ? nil : params[:from_id],
    from_x:    params[:from_x].to_s.empty? ? nil : params[:from_x],
    from_y:    params[:from_y].to_s.empty? ? nil : params[:from_y],
    to_id:     params[:to_id].to_s.empty? ? nil : params[:to_id],
    to_x:      params[:to_x].to_s.empty? ? nil : params[:to_x],
    to_y:      params[:to_y].to_s.empty? ? nil : params[:to_y]
  )
  status(ok ? 200 : 422)
  { ok: ok }.to_json
end

post '/scene/move_object' do
  halt 403, 'forbidden' unless current_user&.dm?
  content_type :json
  SCENE_STATE.move_object(
    params[:map_id].to_i, params[:object_id].to_s,
    params[:x].to_f, params[:y].to_f
  )
  { ok: true }.to_json
end

post '/scene/add_shape' do
  halt 403, 'forbidden' unless current_user&.dm?
  SCENE_STATE.add_shape(
    map_id: params[:map_id].to_i,
    kind:   params[:kind].to_s,
    x:      params[:x].to_f,
    y:      params[:y].to_f,
    w:      params[:w]  ? params[:w].to_f  : nil,
    h:      params[:h]  ? params[:h].to_f  : nil,
    rx:     params[:rx] ? params[:rx].to_f : nil,
    ry:     params[:ry] ? params[:ry].to_f : nil,
    fill:   params[:fill].to_s.empty? ? 'none' : params[:fill]
  )
  redirect(request.referrer || '/scene')
end

post '/scene/add_icon' do
  halt 403, 'forbidden' unless current_user&.dm?
  SCENE_STATE.add_icon(
    map_id: params[:map_id].to_i,
    glyph:  params[:glyph].to_s,
    x:      params[:x].to_f,
    y:      params[:y].to_f
  )
  redirect(request.referrer || '/scene')
end

post '/scene/remove_shape' do
  halt 403, 'forbidden' unless current_user&.dm?
  content_type :json
  SCENE_STATE.remove_shape(params[:map_id].to_i, params[:shape_id].to_s)
  { ok: true }.to_json
end

post '/scene/move_shape' do
  halt 403, 'forbidden' unless current_user&.dm?
  content_type :json
  ok = SCENE_STATE.move_shape(
    params[:map_id].to_i, params[:shape_id].to_s,
    params[:x].to_f, params[:y].to_f
  )
  { ok: ok }.to_json
end

post '/scene/update_map' do
  halt 403, 'forbidden' unless current_user&.dm?
  fields = {}
  fields[:label]          = params[:label] if params.key?(:label)
  fields[:width_squares]  = params[:width_squares].to_i  if !params[:width_squares].to_s.empty?
  fields[:height_squares] = params[:height_squares].to_i if !params[:height_squares].to_s.empty?
  fields[:public]         = params[:public]   == '1' if params.key?('public_set')
  fields[:active]         = params[:active]   == '1' if params.key?('active_set')
  fields[:archived]       = params[:archived] == '1' if params.key?('archived_set')
  SCENE_STATE.update_map_settings(params[:map_id].to_i, **fields)
  redirect(request.referrer || '/scene')
end

post '/scene/create_map' do
  halt 403, 'forbidden' unless current_user&.dm?
  rec = SCENE_STATE.create_map(
    label:          params[:label].to_s,
    width_squares:  params[:width_squares].to_s.empty?  ? 8 : params[:width_squares].to_i,
    height_squares: params[:height_squares].to_s.empty? ? 5 : params[:height_squares].to_i,
    public_flag:    params[:public] == '1',
    active:         params[:active] == '1',
    chapter:        params[:chapter].to_s.empty? ? nil : params[:chapter].to_i
  )
  redirect(request.referrer || '/notes')
end

post '/scene/remove_arrow' do
  content_type :json
  ok = SCENE_STATE.remove_arrow(
    params[:map_id].to_i,
    params[:arrow_id].to_s,
    current_user&.device_id,
    dm: current_user&.dm? == true
  )
  status(ok ? 200 : 403)
  { ok: ok }.to_json
end

post '/scene/clear_arrows' do
  halt 403, 'forbidden' unless current_user&.dm?
  SCENE_STATE.clear_arrows(params[:map_id].to_i)
  redirect(request.referrer || '/scene')
end

# Batched DM map edits. The client queues moves / adds locally and
# submits the lot in one POST. Body is JSON:
#   { "map_id": 2, "ops": [
#       { "kind": "move_object", "object_id": "pc_ash", "x": 120, "y": 90 },
#       { "kind": "add_shape",   "shape_kind": "rect", "x": 150, "y": 150, "w": 60, "h": 40 },
#       { "kind": "add_icon",    "glyph": "🔥",   "x": 200, "y": 100 }
#   ] }
# Only DMs may send a batch; the whole request is rejected for
# non-DM viewers since every op type here is a map-edit.
post '/scene/batch' do
  halt 403, 'forbidden' unless current_user&.dm?
  content_type :json
  payload = JSON.parse(request.body.read) rescue {}
  map_id = payload['map_id'].to_i
  ops    = payload['ops'] || []
  applied = 0
  ops.each do |op|
    case op['kind']
    when 'move_object'
      SCENE_STATE.move_object(map_id, op['object_id'].to_s, op['x'].to_f, op['y'].to_f)
      applied += 1
    when 'add_shape'
      fill = op['fill'].to_s
      SCENE_STATE.add_shape(
        map_id: map_id,
        kind:   op['shape_kind'].to_s,
        x:      op['x'].to_f,
        y:      op['y'].to_f,
        w:      op['w']  ? op['w'].to_f  : nil,
        h:      op['h']  ? op['h'].to_f  : nil,
        rx:     op['rx'] ? op['rx'].to_f : nil,
        ry:     op['ry'] ? op['ry'].to_f : nil,
        fill:   fill.empty? ? 'none' : fill
      )
      applied += 1
    when 'add_icon'
      SCENE_STATE.add_icon(
        map_id: map_id,
        glyph:  op['glyph'].to_s,
        x:      op['x'].to_f,
        y:      op['y'].to_f
      )
      applied += 1
    when 'move_icon'
      SCENE_STATE.move_icon(map_id, op['icon_id'].to_s, op['x'].to_f, op['y'].to_f)
      applied += 1
    when 'move_shape'
      SCENE_STATE.move_shape(map_id, op['shape_id'].to_s, op['x'].to_f, op['y'].to_f)
      applied += 1
    when 'delete_object'
      SCENE_STATE.remove_object(map_id, op['object_id'].to_s)
      applied += 1
    when 'delete_shape'
      SCENE_STATE.remove_shape(map_id, op['shape_id'].to_s)
      applied += 1
    when 'delete_icon'
      SCENE_STATE.remove_icon(map_id, op['icon_id'].to_s)
      applied += 1
    end
  end
  { ok: true, applied: applied }.to_json
end
