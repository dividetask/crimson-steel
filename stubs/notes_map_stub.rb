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

helpers do
  def notes_map_stub(entries:, dm_view: false, current_chapter: nil,
                     active_only: false, interactive: false,
                     scene_state: nil)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    visible = visible.select { |e| e['active'] } if active_only
    erb :"stubs/_notes_map_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view,
      interactive: interactive,
      scene_state: scene_state
    }
  end

  # Color/shape per object kind. Returns [fill, stroke].
  def notes_map_object_colors(kind)
    case kind.to_s
    when 'pc'      then ['#577a99', '#1d3a5b']
    when 'enemy'   then ['#a04848', '#5e1818']
    when 'scenery' then ['#9c7a4a', '#5d4520']
    else                ['#888888', '#3a3a3a']
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
  ok = SCENE_STATE.add_arrow(
    map_id: params[:map_id].to_i,
    from:   params[:from].to_s,
    to:     params[:to].to_s,
    type:   params[:type].to_s,
    label:  current_user&.character_id ? DATA.character_by_id(current_user.character_id)&.dig('name') : nil
  )
  status(ok ? 200 : 422)
  { ok: ok }.to_json
end

post '/scene/clear_arrows' do
  halt 403, 'forbidden' unless current_user&.dm?
  SCENE_STATE.clear_arrows(params[:map_id].to_i)
  redirect(request.referrer || '/scene')
end

post '/scene/add_object' do
  halt 403, 'forbidden' unless current_user&.dm?
  SCENE_STATE.add_object(
    map_id: params[:map_id].to_i,
    kind:   params[:kind].to_s,
    x:      params[:x],
    y:      params[:y],
    label:  params[:label].to_s
  )
  redirect(request.referrer || '/scene')
end
