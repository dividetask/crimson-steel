# Mutable shared state for the scene/map UI: arrows drawn by players
# to indicate their actions, plus DM-added object overlays. Lives in
# process memory (resets on server restart) — fine for the dummy
# data phase. When we wire a real backend this becomes a small JSON
# file like data/users.json.
#
# Each arrow endpoint is either an object id (snaps to a token's
# current position) or a raw (x, y) in viewBox coords. That lets a
# player draw an arrow to/from empty space — eg "I move here" with
# no destination token. An arrow records the device_id of whoever
# drew it so removal can be limited to the drawer (and the DM).

class SceneState
  ARROW_TYPES = %w[attack move-hurry move-sneak move-carefully].freeze

  def initialize
    @arrows_by_map        = Hash.new { |h, k| h[k] = [] }
    @added_objects_by_map = Hash.new { |h, k| h[k] = [] }
  end

  def arrows_for(map_id)
    @arrows_by_map[map_id.to_i]
  end

  # Either *_id is set (snap to that object) or *_x/*_y are set (raw
  # coordinates). At least one of each pair must be present.
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

  # Remove a single arrow. Allowed when the requester is the DM, or
  # when their device_id matches the arrow's device_id.
  def remove_arrow(map_id, arrow_id, requester_device_id, dm: false)
    arr = @arrows_by_map[map_id.to_i]
    idx = arr.index { |a| a['id'] == arrow_id }
    return false unless idx
    return false unless dm || arr[idx]['device_id'] == requester_device_id
    arr.delete_at(idx)
    true
  end

  def added_objects_for(map_id)
    @added_objects_by_map[map_id.to_i]
  end

  def add_object(map_id:, kind:, x:, y:, label:)
    obj = {
      'id'    => "added_#{SecureRandom.hex(3)}",
      'kind'  => kind.to_s,
      'x'     => x.to_f.clamp(0, 400),
      'y'     => y.to_f.clamp(0, 240),
      'label' => label.to_s
    }
    @added_objects_by_map[map_id.to_i] << obj
    obj
  end

  # Merged object list for rendering: base objects from DummyData
  # plus any DM-added overlays.
  def objects_for(map_id, base_objects)
    (base_objects || []) + added_objects_for(map_id)
  end

  # Resolve an arrow endpoint to (x, y) given the current object map.
  # Returns nil when the referenced object id no longer exists and no
  # raw coords are stored — the renderer should skip those arrows.
  def self.resolve_endpoint(arrow, side, by_id)
    id = arrow["#{side}_id"]
    if id && (obj = by_id[id])
      [obj['x'], obj['y']]
    elsif arrow["#{side}_x"] && arrow["#{side}_y"]
      [arrow["#{side}_x"], arrow["#{side}_y"]]
    end
  end
end
