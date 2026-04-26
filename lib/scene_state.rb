# Mutable shared state for the scene/map UI: arrows drawn by players
# to indicate their actions, plus DM-added object overlays. Lives
# in process memory (resets on server restart) — fine for the dummy
# data phase. When we wire a real backend this becomes a small JSON
# file like data/users.json.

class SceneState
  ARROW_TYPES = %w[attack move-hurry move-sneak move-carefully].freeze

  def initialize
    @arrows_by_map         = Hash.new { |h, k| h[k] = [] }
    @added_objects_by_map  = Hash.new { |h, k| h[k] = [] }
  end

  def arrows_for(map_id)
    @arrows_by_map[map_id.to_i]
  end

  def add_arrow(map_id:, from:, to:, type:, label: nil)
    return false unless ARROW_TYPES.include?(type)
    return false if from.nil? || to.nil? || from == to
    @arrows_by_map[map_id.to_i] << {
      'id'    => SecureRandom.hex(4),
      'from'  => from,
      'to'    => to,
      'type'  => type,
      'label' => label
    }
    true
  end

  def clear_arrows(map_id)
    @arrows_by_map[map_id.to_i] = []
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
end
