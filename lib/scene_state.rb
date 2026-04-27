# Mutable shared state for the scene/map UI. Lives in process memory
# (resets on server restart) — fine for the dummy-data phase. Each
# of the per-map sub-stores is keyed by integer map id.
#
# Tracked here:
#   * arrows         — drawn by players (or DM) to indicate actions
#   * added_objects  — DM-added tokens layered on top of DummyData
#   * object_moves   — overrides of token position, both for base
#                      DummyData objects and added ones
#   * shapes         — DM-placed primitives (rect, circle)
#   * map_sizes      — DM overrides of viewBox width/height
#   * current_turn   — the combat_id of whose initiative slot is
#                      currently active (set by the initiative stub)

class SceneState
  ARROW_TYPES = %w[attack move-hurry move-sneak move-carefully].freeze
  SHAPE_KINDS = %w[rect ellipse].freeze
  ICON_KINDS  = %w[pc npc enemy scenery door trap treasure hazard].freeze

  # One grid square is this many viewBox units. Map sizes are stored
  # in squares; the partial multiplies up for the SVG viewBox.
  SQUARE_PX = 50

  attr_accessor :current_turn

  def initialize
    @arrows_by_map         = Hash.new { |h, k| h[k] = [] }
    @added_objects_by_map  = Hash.new { |h, k| h[k] = [] }
    @removed_objects_by_map= Hash.new { |h, k| h[k] = [] }
    @moves_by_map          = Hash.new { |h, k| h[k] = {} }
    @shapes_by_map         = Hash.new { |h, k| h[k] = [] }
    @icons_by_map          = Hash.new { |h, k| h[k] = [] }
    @map_settings_by_map   = {}    # map_id => { 'label', 'w', 'h', 'public', 'active', 'archived' }
    @created_maps          = []    # full map records that don't exist in DummyData
    @next_created_id       = 10_000
    @current_turn          = nil
  end

  # ----- Arrows -----------------------------------------------------------

  def arrows_for(map_id)
    @arrows_by_map[map_id.to_i]
  end

  def add_arrow(map_id:, type:, device_id:, label: nil,
                from_id: nil, from_x: nil, from_y: nil,
                to_id: nil,   to_x: nil,   to_y: nil)
    return false unless ARROW_TYPES.include?(type)
    from_id = nil if from_id.to_s.empty?
    to_id   = nil if to_id.to_s.empty?
    return false if from_id.nil? && (from_x.nil? || from_y.nil?)
    return false if to_id.nil?   && (to_x.nil?   || to_y.nil?)
    return false if from_id && to_id && from_id == to_id
    @arrows_by_map[map_id.to_i] << {
      'id'        => SecureRandom.hex(4),
      'type'      => type,
      'device_id' => device_id,
      'label'     => label,
      'from_id'   => from_id,
      'from_x'    => from_x&.to_f,
      'from_y'    => from_y&.to_f,
      'to_id'     => to_id,
      'to_x'      => to_x&.to_f,
      'to_y'      => to_y&.to_f
    }
    true
  end

  def clear_arrows(map_id)
    @arrows_by_map[map_id.to_i] = []
  end

  def remove_arrow(map_id, arrow_id, requester_device_id, dm: false)
    arr = @arrows_by_map[map_id.to_i]
    idx = arr.index { |a| a['id'] == arrow_id }
    return false unless idx
    return false unless dm || arr[idx]['device_id'] == requester_device_id
    arr.delete_at(idx)
    true
  end

  # ----- Objects (icons / tokens) ----------------------------------------

  def add_object(map_id:, kind:, x:, y:, label:)
    obj = {
      'id'    => "added_#{SecureRandom.hex(3)}",
      'kind'  => kind.to_s,
      'x'     => x.to_f,
      'y'     => y.to_f,
      'label' => label.to_s
    }
    @added_objects_by_map[map_id.to_i] << obj
    obj
  end

  # Move a base or added object. Stored as an override so we don't
  # mutate the DummyData rows.
  def move_object(map_id, object_id, x, y)
    @moves_by_map[map_id.to_i][object_id.to_s] = { 'x' => x.to_f, 'y' => y.to_f }
  end

  # Remove an object. Base DummyData rows are flagged in the
  # removed-set; added objects are dropped from the added array.
  def remove_object(map_id, object_id)
    object_id = object_id.to_s
    @added_objects_by_map[map_id.to_i].reject! { |o| o['id'] == object_id }
    @removed_objects_by_map[map_id.to_i] << object_id unless @removed_objects_by_map[map_id.to_i].include?(object_id)
    @moves_by_map[map_id.to_i].delete(object_id)
  end

  # Merged object list: base + added + per-id move overrides minus
  # anything in the removed-set.
  def objects_for(map_id, base_objects)
    moves   = @moves_by_map[map_id.to_i]
    removed = @removed_objects_by_map[map_id.to_i]
    list    = (base_objects || []) + @added_objects_by_map[map_id.to_i]
    list.reject { |o| removed.include?(o['id'].to_s) }
        .map    { |o| moves[o['id']] ? o.merge(moves[o['id']]) : o }
  end

  # ----- Shapes -----------------------------------------------------------

  def shapes_for(map_id)
    @shapes_by_map[map_id.to_i]
  end

  def add_shape(map_id:, kind:, x:, y:, w: nil, h: nil, rx: nil, ry: nil,
                fill: nil, stroke: nil)
    return false unless SHAPE_KINDS.include?(kind)
    fill   = '#cfd8dc' if fill.nil? || fill.to_s.empty?
    stroke = (stroke || '#444').to_s
    shape = {
      'id'     => "shape_#{SecureRandom.hex(3)}",
      'kind'   => kind,
      'x'      => x.to_f,
      'y'      => y.to_f,
      'fill'   => fill.to_s,
      'stroke' => stroke
    }
    case kind
    when 'rect'    then shape['w']  = (w  || 40).to_f; shape['h']  = (h  || 40).to_f
    when 'ellipse' then shape['rx'] = (rx || 20).to_f; shape['ry'] = (ry || 20).to_f
    end
    @shapes_by_map[map_id.to_i] << shape
    shape
  end

  def remove_shape(map_id, shape_id)
    @shapes_by_map[map_id.to_i].reject! { |s| s['id'] == shape_id }
  end

  def move_shape(map_id, shape_id, x, y)
    s = @shapes_by_map[map_id.to_i].find { |sh| sh['id'] == shape_id }
    return false unless s
    s['x'] = x.to_f
    s['y'] = y.to_f
    true
  end

  # ----- Icons (emoji glyphs placed on the map) -------------------------

  def icons_for(map_id)
    @icons_by_map[map_id.to_i]
  end

  def add_icon(map_id:, glyph:, x:, y:, size: 28)
    icon = {
      'id'    => "icon_#{SecureRandom.hex(3)}",
      'glyph' => glyph.to_s,
      'x'     => x.to_f,
      'y'     => y.to_f,
      'size'  => size.to_f
    }
    @icons_by_map[map_id.to_i] << icon
    icon
  end

  def remove_icon(map_id, icon_id)
    @icons_by_map[map_id.to_i].reject! { |i| i['id'] == icon_id }
  end

  def move_icon(map_id, icon_id, x, y)
    icon = @icons_by_map[map_id.to_i].find { |i| i['id'] == icon_id }
    return false unless icon
    icon['x'] = x.to_f
    icon['y'] = y.to_f
    true
  end

  # ----- Map settings (label / size in squares / flags) ----------------

  # Returns merged settings: per-map override wins, otherwise fall
  # back to whatever the base map record supplied.
  def map_settings_for(map_id, base_label: nil, base_w: 8, base_h: 5,
                       base_public: nil, base_active: nil, base_archived: false)
    s = @map_settings_by_map[map_id.to_i] || {}
    {
      'label'    => s.key?('label')    ? s['label']    : base_label.to_s,
      'w'        => s['w']     || base_w,
      'h'        => s['h']     || base_h,
      'public'   => s.key?('public')   ? s['public']   : (base_public.nil? ? true : base_public),
      'active'   => s.key?('active')   ? s['active']   : (base_active.nil? ? false : base_active),
      'archived' => s.key?('archived') ? s['archived'] : base_archived
    }
  end

  def update_map_settings(map_id, label: nil, width_squares: nil, height_squares: nil,
                          public: nil, active: nil, archived: nil)
    cur = @map_settings_by_map[map_id.to_i] || {}
    cur['label']    = label.to_s                       unless label.nil?
    cur['w']        = width_squares.to_i.clamp(1, 80)  unless width_squares.nil?
    cur['h']        = height_squares.to_i.clamp(1, 80) unless height_squares.nil?
    cur['public']   = !!public                          unless public.nil?
    cur['active']   = !!active                          unless active.nil?
    cur['archived'] = !!archived                        unless archived.nil?
    @map_settings_by_map[map_id.to_i] = cur
  end

  # ----- Created maps (live alongside DummyData.note_maps) -------------

  attr_reader :created_maps

  def create_map(label: '', width_squares: 8, height_squares: 5,
                 public_flag: true, active: false, chapter: nil)
    rec = {
      'id'             => @next_created_id,
      'label'          => label.to_s,
      'caption'        => '',
      'chapter'        => chapter,
      'public'         => !!public_flag,
      'active'         => !!active,
      'archived'       => false,
      'width_squares'  => width_squares.to_i.clamp(1, 80),
      'height_squares' => height_squares.to_i.clamp(1, 80),
      'objects'        => []
    }
    @next_created_id += 1
    @created_maps << rec
    rec
  end

  # Merge DummyData's static maps with anything the DM has created
  # in this session. Caller passes in DummyData.note_maps; the
  # `archived` flag is honored via map_settings_for so created and
  # base maps share the same toggle.
  def all_maps(base_maps)
    (base_maps || []) + @created_maps
  end

  # ----- Helpers ---------------------------------------------------------

  # Resolve an arrow endpoint to (x, y) given the current object map.
  # Returns nil when the referenced id no longer exists and no raw
  # coords are stored — the renderer should skip those arrows.
  def self.resolve_endpoint(arrow, side, by_id)
    id = arrow["#{side}_id"]
    if id && (obj = by_id[id])
      [obj['x'], obj['y']]
    elsif arrow["#{side}_x"] && arrow["#{side}_y"]
      [arrow["#{side}_x"], arrow["#{side}_y"]]
    end
  end
end
