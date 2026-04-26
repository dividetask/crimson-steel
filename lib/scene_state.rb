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
  SHAPE_KINDS = %w[rect circle].freeze
  ICON_KINDS  = %w[pc npc enemy scenery door trap treasure hazard].freeze

  # One grid square is this many viewBox units. Map sizes are stored
  # in squares; the partial multiplies up for the SVG viewBox.
  SQUARE_PX = 50

  attr_accessor :current_turn

  def initialize
    @arrows_by_map         = Hash.new { |h, k| h[k] = [] }
    @added_objects_by_map  = Hash.new { |h, k| h[k] = [] }
    @moves_by_map          = Hash.new { |h, k| h[k] = {} }
    @shapes_by_map         = Hash.new { |h, k| h[k] = [] }
    @map_settings_by_map   = {}    # map_id => { 'label' => str, 'w' => sq, 'h' => sq }
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

  # Merged object list: base + added + per-id move overrides.
  def objects_for(map_id, base_objects)
    moves = @moves_by_map[map_id.to_i]
    list  = (base_objects || []) + @added_objects_by_map[map_id.to_i]
    list.map { |o| moves[o['id']] ? o.merge(moves[o['id']]) : o }
  end

  # ----- Shapes -----------------------------------------------------------

  def shapes_for(map_id)
    @shapes_by_map[map_id.to_i]
  end

  def add_shape(map_id:, kind:, x:, y:, w: nil, h: nil, r: nil,
                fill: '#cfd8dc', stroke: '#546e7a')
    return false unless SHAPE_KINDS.include?(kind)
    shape = {
      'id'     => "shape_#{SecureRandom.hex(3)}",
      'kind'   => kind,
      'x'      => x.to_f,
      'y'      => y.to_f,
      'fill'   => fill,
      'stroke' => stroke
    }
    case kind
    when 'rect'   then shape['w'] = (w || 40).to_f; shape['h'] = (h || 40).to_f
    when 'circle' then shape['r'] = (r || 20).to_f
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

  # ----- Map settings (label + size in squares) -------------------------

  # Returns the merged settings: DM overrides win, otherwise fall back
  # to the values supplied by the base map record.
  def map_settings_for(map_id, base_label: nil, base_w: 8, base_h: 5)
    s = @map_settings_by_map[map_id.to_i] || {}
    {
      'label' => s['label'] || base_label.to_s,
      'w'     => s['w']     || base_w,
      'h'     => s['h']     || base_h
    }
  end

  def update_map_settings(map_id, label: nil, width_squares: nil, height_squares: nil)
    cur = @map_settings_by_map[map_id.to_i] || {}
    cur['label'] = label.to_s                                    unless label.nil?
    cur['w']     = width_squares.to_i.clamp(1, 80)               unless width_squares.nil?
    cur['h']     = height_squares.to_i.clamp(1, 80)              unless height_squares.nil?
    @map_settings_by_map[map_id.to_i] = cur
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
