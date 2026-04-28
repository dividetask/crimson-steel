require 'json'
require 'fileutils'
require 'securerandom'

# Tracks campaign notes, battlemaps, and images

class NotesState
  ARROW_TYPES = %w[attack move-hurry move-sneak move-carefully].freeze
  SHAPE_KINDS = %w[rect ellipse].freeze
  ICON_KINDS  = %w[pc npc enemy scenery door trap treasure hazard].freeze

  # One grid square is this many viewBox units. Map sizes are stored
  # in squares; the partial multiplies up for the SVG viewBox.
  SQUARE_PX = 50

  # Snap an (x, y) coordinate to the center of the grid square that
  # contains it. Used for icons and image tokens so they always land
  # inside a single square instead of straddling grid lines.
  def self.snap_center(x, y)
    sq = SQUARE_PX
    cx = (x.to_f / sq).floor * sq + sq / 2.0
    cy = (y.to_f / sq).floor * sq + sq / 2.0
    [cx, cy]
  end

  attr_reader :created_maps

  def initialize(path = nil)
    @path = path
    # Notes track
    @additions              = []
    @overrides              = {}
    @deletions              = []
    # Image track
    @image_additions        = []
    @image_deletions        = []
    # Map / scene track
    @arrows_by_map          = {}
    @added_objects_by_map   = {}
    @removed_objects_by_map = {}
    @moves_by_map           = {}
    @shapes_by_map          = {}
    @icons_by_map           = {}
    @map_images_by_map      = {}
    @map_settings_by_map    = {}
    @created_maps           = []
    @next_created_id        = 10_000
    @current_turn           = nil
    load_from_disk! if @path && File.exist?(@path)
  end

  def current_turn
    @current_turn
  end

  def current_turn=(v)
    @current_turn = v
    save!
  end

  # ----- Notes (journal entries) -----------------------------------------

  def effective_notes(base)
    visible = (base || []).reject { |n| @deletions.include?(n['id']) }
    visible = visible.map { |n| @overrides[n['id']] ? n.merge(@overrides[n['id']]) : n }
    visible + @additions.map { |n| @overrides[n['id']] ? n.merge(@overrides[n['id']]) : n }
  end

  def add_note(chapter:, note:, public_flag:, active: false, owner_id: 0, title: nil)
    rec = {
      'id'       => next_note_id,
      'owner_id' => owner_id.to_i,
      'chapter'  => chapter.to_i,
      'note'     => note.to_s,
      'public'   => public_flag ? true : false,
      'active'   => active ? true : false
    }
    rec['title'] = title.to_s unless title.to_s.empty?
    @additions << rec
    save!
    rec
  end

  def update_note(id, fields)
    id = id.to_i
    cleaned = {}
    cleaned['note']    = fields['note'].to_s    if fields.key?('note')
    cleaned['title']   = fields['title'].to_s   if fields.key?('title')
    cleaned['chapter'] = fields['chapter'].to_i if fields.key?('chapter')
    cleaned['public']  = fields['public']  ? true : false if fields.key?('public')
    cleaned['active']  = fields['active']  ? true : false if fields.key?('active')
    return false if cleaned.empty?
    @overrides[id] = (@overrides[id] || {}).merge(cleaned)
    save!
    true
  end

  def delete_note(id)
    @deletions << id.to_i
    @overrides.delete(id.to_i)
    @additions.reject! { |n| n['id'] == id.to_i }
    save!
    true
  end

  # ----- Images ----------------------------------------------------------

  def effective_images(base)
    visible = (base || []).reject { |i| @image_deletions.include?(i['id']) }
    visible + @image_additions.reject { |i| @image_deletions.include?(i['id']) }
  end

  def add_image(chapter:, kind:, caption:, public_flag:, active:, path:)
    rec = {
      'id'      => next_image_id,
      'chapter' => chapter.to_i,
      'kind'    => kind.to_s,
      'caption' => caption.to_s,
      'public'  => public_flag ? true : false,
      'active'  => active ? true : false,
      'path'    => path.to_s
    }
    @image_additions << rec
    save!
    rec
  end

  def delete_image(id)
    id = id.to_i
    removed = @image_additions.find { |i| i['id'] == id }
    @image_additions.reject! { |i| i['id'] == id }
    @image_deletions << id unless @image_deletions.include?(id)
    save!
    removed
  end

  # ----- Arrows ----------------------------------------------------------

  def arrows_for(map_id)
    @arrows_by_map[map_id.to_i] || []
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
    (@arrows_by_map[map_id.to_i] ||= []) << {
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
    save!
    true
  end

  def clear_arrows(map_id)
    @arrows_by_map[map_id.to_i] = []
    save!
  end

  def remove_arrow(map_id, arrow_id, requester_device_id, dm: false)
    arr = @arrows_by_map[map_id.to_i] || []
    idx = arr.index { |a| a['id'] == arrow_id }
    return false unless idx
    return false unless dm || arr[idx]['device_id'] == requester_device_id
    arr.delete_at(idx)
    save!
    true
  end

  # ----- Objects (tokens) ------------------------------------------------

  def move_object(map_id, object_id, x, y)
    bucket = (@moves_by_map[map_id.to_i] ||= {})
    bucket[object_id.to_s] = { 'x' => x.to_f, 'y' => y.to_f }
    save!
  end

  def remove_object(map_id, object_id)
    object_id = object_id.to_s
    (@added_objects_by_map[map_id.to_i] ||= []).reject! { |o| o['id'] == object_id }
    rm = (@removed_objects_by_map[map_id.to_i] ||= [])
    rm << object_id unless rm.include?(object_id)
    (@moves_by_map[map_id.to_i] ||= {}).delete(object_id)
    save!
  end

  def objects_for(map_id, base_objects)
    moves   = @moves_by_map[map_id.to_i] || {}
    removed = @removed_objects_by_map[map_id.to_i] || []
    list    = (base_objects || []) + (@added_objects_by_map[map_id.to_i] || [])
    list.reject { |o| removed.include?(o['id'].to_s) }
        .map    { |o| moves[o['id']] ? o.merge(moves[o['id']]) : o }
  end

  # ----- Shapes ----------------------------------------------------------

  def shapes_for(map_id)
    @shapes_by_map[map_id.to_i] || []
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
    (@shapes_by_map[map_id.to_i] ||= []) << shape
    save!
    shape
  end

  def remove_shape(map_id, shape_id)
    list = @shapes_by_map[map_id.to_i] or return
    list.reject! { |s| s['id'] == shape_id }
    save!
  end

  def move_shape(map_id, shape_id, x, y)
    list = @shapes_by_map[map_id.to_i] or return false
    s = list.find { |sh| sh['id'] == shape_id }
    return false unless s
    s['x'] = x.to_f
    s['y'] = y.to_f
    save!
    true
  end

  # ----- Icons (emoji glyphs placed on the map) -------------------------

  def icons_for(map_id)
    @icons_by_map[map_id.to_i] || []
  end

  def add_icon(map_id:, glyph:, x:, y:, size: 28)
    cx, cy = self.class.snap_center(x, y)
    icon = {
      'id'    => "icon_#{SecureRandom.hex(3)}",
      'glyph' => glyph.to_s,
      'x'     => cx,
      'y'     => cy,
      'size'  => size.to_f
    }
    (@icons_by_map[map_id.to_i] ||= []) << icon
    save!
    icon
  end

  def remove_icon(map_id, icon_id)
    list = @icons_by_map[map_id.to_i] or return
    list.reject! { |i| i['id'] == icon_id }
    save!
  end

  def move_icon(map_id, icon_id, x, y)
    list = @icons_by_map[map_id.to_i] or return false
    icon = list.find { |i| i['id'] == icon_id }
    return false unless icon
    cx, cy = self.class.snap_center(x, y)
    icon['x'] = cx
    icon['y'] = cy
    save!
    true
  end

  # ----- Map images (image-token glyphs placed on the map) -------------

  def map_images_for(map_id)
    @map_images_by_map[map_id.to_i] || []
  end

  def add_map_image(map_id:, src:, x:, y:, size: SQUARE_PX)
    return false unless src.to_s.start_with?('/images/')
    cx, cy = self.class.snap_center(x, y)
    rec = {
      'id'   => "img_#{SecureRandom.hex(3)}",
      'src'  => src.to_s,
      'x'    => cx,
      'y'    => cy,
      'size' => size.to_f
    }
    (@map_images_by_map[map_id.to_i] ||= []) << rec
    save!
    rec
  end

  def remove_map_image(map_id, image_id)
    list = @map_images_by_map[map_id.to_i] or return
    list.reject! { |i| i['id'] == image_id }
    save!
  end

  def move_map_image(map_id, image_id, x, y)
    list = @map_images_by_map[map_id.to_i] or return false
    rec = list.find { |i| i['id'] == image_id }
    return false unless rec
    cx, cy = self.class.snap_center(x, y)
    rec['x'] = cx
    rec['y'] = cy
    save!
    true
  end

  # ----- Map settings (label / size in squares / flags) ----------------

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
    save!
  end

  # ----- Created maps (live alongside DummyData.note_maps) -------------

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
    save!
    rec
  end

  def all_maps(base_maps)
    (base_maps || []) + @created_maps
  end

  # ----- Helpers --------------------------------------------------------

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

  private

  # New note ids start above any DummyData id. 1000 is well clear of
  # the current placeholder numbering; created maps use a separate
  # high range (10_000+) so the two id spaces don't collide.
  def next_note_id
    base = 1000
    used = @additions.map { |n| n['id'].to_i }
    (used.max || base - 1) + 1
  end

  # Image ids live in their own range (2000+) so they don't collide
  # with note or map ids when they share the same JSON file.
  def next_image_id
    base = 2000
    used = @image_additions.map { |i| i['id'].to_i }
    (used.max || base - 1) + 1
  end

  # Atomic write so a crash mid-save doesn't leave a half-written
  # file. Map-id-keyed hashes serialize as JSON objects with string
  # keys; load_from_disk! coerces them back to integers.
  def save!
    return unless @path
    FileUtils.mkdir_p(File.dirname(@path))
    payload = {
      'additions'              => @additions,
      'overrides'              => @overrides,
      'deletions'              => @deletions,
      'image_additions'        => @image_additions,
      'image_deletions'        => @image_deletions,
      'arrows_by_map'          => @arrows_by_map,
      'added_objects_by_map'   => @added_objects_by_map,
      'removed_objects_by_map' => @removed_objects_by_map,
      'moves_by_map'           => @moves_by_map,
      'shapes_by_map'          => @shapes_by_map,
      'icons_by_map'           => @icons_by_map,
      'map_images_by_map'      => @map_images_by_map,
      'map_settings_by_map'    => @map_settings_by_map,
      'created_maps'           => @created_maps,
      'next_created_id'        => @next_created_id,
      'current_turn'           => @current_turn
    }
    tmp = "#{@path}.tmp.#{SecureRandom.hex(4)}"
    File.write(tmp, JSON.pretty_generate(payload))
    File.rename(tmp, @path)
  end

  def load_from_disk!
    data = JSON.parse(File.read(@path))
    @additions              = data['additions'] || []
    @overrides              = (data['overrides'] || {}).transform_keys(&:to_i)
    @deletions              = data['deletions'] || []
    @image_additions        = data['image_additions'] || []
    @image_deletions        = data['image_deletions'] || []
    @arrows_by_map          = (data['arrows_by_map']          || {}).transform_keys(&:to_i)
    @added_objects_by_map   = (data['added_objects_by_map']   || {}).transform_keys(&:to_i)
    @removed_objects_by_map = (data['removed_objects_by_map'] || {}).transform_keys(&:to_i)
    @moves_by_map           = (data['moves_by_map']           || {}).transform_keys(&:to_i)
    @shapes_by_map          = (data['shapes_by_map']          || {}).transform_keys(&:to_i)
    @icons_by_map           = (data['icons_by_map']           || {}).transform_keys(&:to_i)
    @map_images_by_map      = (data['map_images_by_map']      || {}).transform_keys(&:to_i)
    @map_settings_by_map    = (data['map_settings_by_map']    || {}).transform_keys(&:to_i)
    @created_maps           = data['created_maps']    || []
    @next_created_id        = data['next_created_id'] || 10_000
    @current_turn           = data['current_turn']
  end
end
