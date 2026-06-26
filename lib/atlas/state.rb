require 'fileutils'
require 'json'

module Atlas
  # Returned by entry points that refuse an operation (unknown / archived
  # target, an attempt to change an immutable field). Distinct from `nil`,
  # which a getter returns for an unknown id.
  ERROR = :error

  # In-memory spatial state for the Campaign — the catalog of Maps and the
  # Tokens (and Zones) placed on them — persisted to `data/atlas_data.json`.
  # See docs/common/atlas/atlas_design.md and atlas_tests.md.
  #
  # Atlas is a record-keeping domain: it does not snap Tokens to grids,
  # clamp positions to a Map's extent, or evaluate visibility — those are
  # UI concerns. Tokens cross-reference Creatures by `creature_id`; display
  # data is resolved by the consumer through `creature_lookup`.
  class State
    DATA_PATH    = File.expand_path('../../data/atlas_data.json', __dir__)
    EXAMPLE_PATH = File.expand_path('../../docs/common/atlas/atlas_data.example.json', __dir__)

    attr_reader :data_path

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH, **opts)
      path = File.exist?(data_path) ? data_path : example_path
      raw  = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      new(raw, data_path: data_path, **opts)
    end

    # `movement_notifier` (optional) is called with a Movement Notification
    # hash whenever Move Token changes a Token's Zone Membership. Persistence
    # writes to data_path on every mutation.
    def initialize(raw = {}, data_path: DATA_PATH, movement_notifier: nil)
      @data_path         = data_path
      @movement_notifier = movement_notifier
      @maps    = (raw['maps']   || []).map { |m| normalize_map(m) }
      @tokens  = (raw['tokens'] || []).map { |t| normalize_token(t) }
      @zones   = (raw['zones']  || []).map { |z| normalize_zone(z) }
      @annotations = (raw['annotations'] || []).map { |a| normalize_annotation(a) }
      @terrain = (raw['terrain'] || []).map { |t| normalize_terrain(t) }
      @active_map_id = raw['active_map_id']
      @next_map_id   = Integer(raw['next_map_id']   || ((@maps.map   { |m| m[:id] }.max || 0) + 1))
      @next_token_id = Integer(raw['next_token_id'] || ((@tokens.map { |t| t[:id] }.max || 0) + 1))
      @next_zone_id  = Integer(raw['next_zone_id']  || ((@zones.map  { |z| z[:id] }.max || 0) + 1))
      @next_annotation_id = Integer(raw['next_annotation_id'] || ((@annotations.map { |a| a[:id] }.max || 0) + 1))
      @next_terrain_id = Integer(raw['next_terrain_id'] || ((@terrain.map { |t| t[:id] }.max || 0) + 1))
    end

    # ---------- Snapshot / persistence ----------

    def to_h
      {
        'maps'          => @maps.map   { |m| stringify_map(m) },
        'tokens'        => @tokens.map { |t| stringify_token(t) },
        'zones'         => @zones.map  { |z| stringify_zone(z) },
        'annotations'   => @annotations.map { |a| stringify_annotation(a) },
        'terrain'       => @terrain.map { |t| stringify_terrain(t) },
        'active_map_id' => @active_map_id,
        'next_map_id'   => @next_map_id,
        'next_token_id' => @next_token_id,
        'next_zone_id'  => @next_zone_id,
        'next_annotation_id' => @next_annotation_id,
        'next_terrain_id' => @next_terrain_id
      }
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, JSON.pretty_generate(to_h))
      File.rename(tmp, @data_path)
    end

    # ---------- Manage Maps ----------

    # `grid` defaults to a fresh Grid of the configured Default Grid Type;
    # pass `grid: nil` for a Map with no overlay, or a Hash to override.
    def add_map(name:, image: nil, width: nil, height: nil, grid: :default, notes: '', archived: false)
      map = {
        id:       @next_map_id,
        name:     name.to_s,
        image:    image.nil? ? nil : image.to_s,
        width:    width,
        height:   height,
        grid:     grid == :default ? default_grid : normalize_grid(grid),
        archived: !!archived,
        notes:    notes.to_s
      }
      @next_map_id += 1
      @maps << map
      persist!
      map[:id]
    end

    # Update one or more fields of a Map. `id` cannot change. Unknown id
    # returns ERROR. Existing Token positions are never adjusted.
    def edit_map(id, **fields)
      map = map_for(id) or return ERROR
      return ERROR if fields.key?(:id)
      fields.each do |k, v|
        case k
        when :name     then map[:name]     = v.to_s
        when :image    then map[:image]    = v.nil? ? nil : v.to_s
        when :width    then map[:width]    = v
        when :height   then map[:height]   = v
        when :grid     then map[:grid]     = v.nil? ? nil : normalize_grid(v)
        when :archived then map[:archived] = !!v
        when :notes    then map[:notes]    = v.to_s
        end
      end
      persist!
      map.dup
    end

    def archive_map(id)
      map = map_for(id) or return ERROR
      map[:archived] = true
      @active_map_id = nil if @active_map_id == id
      persist!
      map.dup
    end

    def unarchive_map(id)
      map = map_for(id) or return ERROR
      map[:archived] = false
      persist!
      map.dup
    end

    # Destructive: removes the Map and cascades to every Token and Terrain
    # fill on it (Terrain is the Map's painted structure, so it dies with the
    # Map). Zones on the Map are left for the consumer (Conditions) to reap.
    def delete_map(id)
      map = map_for(id) or return ERROR
      @maps.delete(map)
      @tokens.reject! { |t| t[:map_id] == id }
      @terrain.reject! { |t| t[:map_id] == id }
      @active_map_id = nil if @active_map_id == id
      persist!
      map.dup
    end

    def get_map(id)
      map_for(id)&.dup
    end

    def list_maps(include_archived: false, archived_only: false)
      result =
        if archived_only
          @maps.select { |m| m[:archived] }
        elsif include_archived
          @maps
        else
          @maps.reject { |m| m[:archived] }
        end
      result.map(&:dup)
    end

    # ---------- Active Map ----------

    def get_active_map
      return nil if @active_map_id.nil?
      map_for(@active_map_id)&.dup
    end

    def active_map_id = @active_map_id

    # Point at an existing, non-archived Map, or null to clear. Refuses an
    # unknown or archived target with ERROR (active_map_id unchanged).
    def set_active_map(id)
      if id.nil?
        @active_map_id = nil
        persist!
        return nil
      end
      map = map_for(id) or return ERROR
      return ERROR if map[:archived]
      @active_map_id = id
      persist!
      @active_map_id
    end

    # ---------- Manage Tokens ----------

    def place_token(map_id:, creature_id:, x:, y:, size: nil, label: nil, image: nil, owner_id: nil, hidden: false)
      return ERROR unless map_for(map_id)
      token = {
        id:          @next_token_id,
        map_id:      map_id,
        creature_id: creature_id,
        x:           x,
        y:           y,
        size:        size.nil? ? Config.default_token_size : size,
        label:       label.nil? ? nil : label.to_s,
        image:       image.nil? ? nil : image.to_s,
        owner_id:    owner_id,
        hidden:      !!hidden
      }
      @next_token_id += 1
      @tokens << token
      persist!
      token[:id]
    end

    # Update a Token's position. Idempotent. Moves any anchor-following
    # Zones, then emits a Movement Notification when Zone Membership changed.
    def move_token(id, x, y)
      token = token_for(id) or return ERROR
      before = overlapping_zone_ids(token[:map_id], token[:x], token[:y], token[:size])
      token[:x] = x
      token[:y] = y
      follow_anchors!(token)
      after = overlapping_zone_ids(token[:map_id], token[:x], token[:y], token[:size])
      persist!
      notify_movement(token, before, after)
      token.dup
    end

    # Update one or more Token fields. `id` and `map_id` are immutable —
    # an attempt to change either returns ERROR (Token unchanged).
    def edit_token(id, **fields)
      token = token_for(id) or return ERROR
      return ERROR if fields.key?(:id) || fields.key?(:map_id)
      fields.each do |k, v|
        case k
        when :creature_id then token[:creature_id] = v
        when :x           then token[:x] = v
        when :y           then token[:y] = v
        when :size        then token[:size] = v
        when :label       then token[:label] = v.nil? ? nil : v.to_s
        when :image       then token[:image] = v.nil? ? nil : v.to_s
        when :owner_id    then token[:owner_id] = v
        when :hidden      then token[:hidden] = !!v
        end
      end
      persist!
      token.dup
    end

    def remove_token(id)
      token = token_for(id) or return nil
      @tokens.delete(token)
      persist!
      token.dup
    end

    def get_token(id)
      token_for(id)&.dup
    end

    def list_tokens(map_id: nil, creature_id: nil, include_hidden: true)
      result = @tokens
      result = result.select { |t| t[:map_id] == map_id } if map_id
      result = result.select { |t| t[:creature_id] == creature_id } if creature_id
      result = result.reject { |t| t[:hidden] } unless include_hidden
      result.map(&:dup)
    end

    # ---------- Manage Zones ----------

    def place_zone(map_id:, source_id:, shape:, size:, anchor:, texture: nil)
      return ERROR unless map_for(map_id)
      a = normalize_anchor(anchor)
      if %w[target caster].include?(a[:type])
        tok = @tokens.find { |t| t[:map_id] == map_id && t[:creature_id] == a[:creature_id] }
        return ERROR unless tok
        a[:x] = tok[:x]
        a[:y] = tok[:y]
      end
      zone = { id: @next_zone_id, map_id: map_id, source_id: source_id.to_s,
               shape: shape.to_s, size: Integer(size), anchor: a,
               texture: texture && texture.to_s }
      @next_zone_id += 1
      @zones << zone
      persist!
      zone[:id]
    end

    def remove_zone(id)
      zone = zone_for(id) or return nil
      @zones.delete(zone)
      persist!
      zone.dup
    end

    def get_zone(id)
      zone_for(id)&.dup
    end

    def list_zones(map_id: nil, source_id: nil)
      result = @zones
      result = result.select { |z| z[:map_id] == map_id } if map_id
      result = result.select { |z| z[:source_id] == source_id.to_s } if source_id
      result.map(&:dup)
    end

    # IDs of every Zone on the Map whose footprint overlaps the supplied
    # (x, y, size) footprint.
    def zones_in_position(map_id, x, y, size)
      overlapping_zone_ids(map_id, x, y, size)
    end

    # ---------- Manage Annotations ----------

    # A free-form drawing on a Map: an `arrow`, a `shape` (rectangle or
    # ellipse), or `text`. Geometry is a list of `[x, y]` points in Map
    # Units — two points for an arrow (tail → head) or a shape (opposite
    # corners of its bounding box), one for text. `author` records who drew
    # it (`dm` / `player`); enforcement of who may draw what is the
    # consumer's concern. Atlas treats coordinates as opaque (no clamping).
    # `dm_only` marks a drawing only the DM should see (e.g. a secret text
    # note). Atlas stores the flag; filtering it out of player snapshots is
    # the consumer's concern, exactly as with a hidden Token.
    def add_annotation(map_id:, type:, points:, color: nil, shape_kind: nil, text: nil, author: 'dm', dm_only: false)
      return ERROR unless map_for(map_id)
      ann = {
        id:         @next_annotation_id,
        map_id:     map_id,
        type:       type.to_s,
        points:     Array(points).map { |p| [p[0], p[1]] },
        color:      color.nil? ? nil : color.to_s,
        shape_kind: shape_kind.nil? ? nil : shape_kind.to_s,
        text:       text.nil? ? nil : text.to_s,
        author:     author.to_s,
        dm_only:    !!dm_only
      }
      @next_annotation_id += 1
      @annotations << ann
      persist!
      ann[:id]
    end

    # Update one or more fields of an Annotation. `id` and `map_id` are
    # immutable — an attempt to change either returns ERROR (Annotation
    # unchanged). Used to retext, recolor, or reposition a drawing (e.g. the
    # DM editing or moving a note).
    def edit_annotation(id, **fields)
      ann = annotation_for(id) or return ERROR
      return ERROR if fields.key?(:id) || fields.key?(:map_id)
      fields.each do |k, v|
        case k
        when :type       then ann[:type] = v.to_s
        when :points     then ann[:points] = Array(v).map { |p| [p[0], p[1]] }
        when :color      then ann[:color] = v.nil? ? nil : v.to_s
        when :shape_kind then ann[:shape_kind] = v.nil? ? nil : v.to_s
        when :text       then ann[:text] = v.nil? ? nil : v.to_s
        when :dm_only    then ann[:dm_only] = !!v
        end
      end
      persist!
      ann.dup
    end

    def remove_annotation(id)
      ann = annotation_for(id) or return nil
      @annotations.delete(ann)
      persist!
      ann.dup
    end

    def get_annotation(id)
      annotation_for(id)&.dup
    end

    def list_annotations(map_id: nil, type: nil, author: nil)
      result = @annotations
      result = result.select { |a| a[:map_id] == map_id } if map_id
      result = result.select { |a| a[:type] == type.to_s } if type
      result = result.select { |a| a[:author] == author.to_s } if author
      result.map(&:dup)
    end

    # Remove Annotations on a Map. With `author:` set, removes only that
    # author's Annotations (e.g. a player clearing their own arrows).
    def clear_annotations_on_map(map_id, author: nil)
      removed = @annotations.select do |a|
        a[:map_id] == map_id && (author.nil? || a[:author] == author.to_s)
      end
      @annotations -= removed
      persist!
      removed.length
    end

    # ---------- Manage Terrain ----------

    # Terrain is the Map's painted structure — rectangles filled with a
    # repeating texture (walls, dirt, stone floor) the DM lays down to build
    # a scene. Unlike an Annotation it is permanent map furniture: it is not
    # swept by Clear Annotations and persists until the DM clears it (or the
    # Map is deleted). `texture` is the fill image's filename; `points` are
    # the two opposite corners of the rectangle in Map Units (opaque — no
    # clamping or snapping, exactly as Token positions).
    def add_terrain(map_id:, points:, texture:, shape_kind: 'rect')
      return ERROR unless map_for(map_id)
      t = {
        id:         @next_terrain_id,
        map_id:     map_id,
        shape_kind: shape_kind.to_s,
        points:     Array(points).map { |p| [p[0], p[1]] },
        texture:    texture.to_s
      }
      @next_terrain_id += 1
      @terrain << t
      persist!
      t[:id]
    end

    def remove_terrain(id)
      t = terrain_for(id) or return nil
      @terrain.delete(t)
      persist!
      t.dup
    end

    def get_terrain(id)
      terrain_for(id)&.dup
    end

    def list_terrain(map_id: nil)
      result = @terrain
      result = result.select { |t| t[:map_id] == map_id } if map_id
      result.map(&:dup)
    end

    def clear_terrain_on_map(map_id)
      removed = @terrain.select { |t| t[:map_id] == map_id }
      @terrain -= removed
      persist!
      removed.length
    end

    # Erase the rectangular region (x0, y0)-(x1, y1) (Map Units) from a Map's
    # Terrain — the eraser box tool. A rect fill overlapping the box is
    # replaced by the (up to four) rectangles that remain after subtracting
    # the box; a fully covered fill vanishes. An ellipse fill that overlaps is
    # removed wholesale (the brushes only paint rects, so this is rare).
    # Returns the number of fills the box touched.
    def erase_terrain_box(map_id, x0, y0, x1, y1)
      bx0, bx1 = [x0, x1].minmax
      by0, by1 = [y0, y1].minmax
      affected = 0
      result = []
      @terrain.each do |t|
        unless t[:map_id] == map_id
          result << t
          next
        end
        xs = t[:points].map { |p| p[0] }
        ys = t[:points].map { |p| p[1] }
        ax0, ax1 = xs.minmax
        ay0, ay1 = ys.minmax
        ix0 = [ax0, bx0].max; iy0 = [ay0, by0].max
        ix1 = [ax1, bx1].min; iy1 = [ay1, by1].min
        if ix0 >= ix1 || iy0 >= iy1
          result << t           # no overlap — keep as-is
          next
        end
        affected += 1
        next unless t[:shape_kind] == 'rect'   # ellipse: drop it entirely
        remainders = []
        remainders << [ax0, ay0, ax1, iy0] if iy0 > ay0   # strip above the box
        remainders << [ax0, iy1, ax1, ay1] if iy1 < ay1   # strip below
        remainders << [ax0, iy0, ix0, iy1] if ix0 > ax0   # strip left
        remainders << [ix1, iy0, ax1, iy1] if ix1 < ax1   # strip right
        remainders.each do |(rx0, ry0, rx1, ry1)|
          result << { id: @next_terrain_id, map_id: map_id, shape_kind: 'rect',
                      points: [[rx0, ry0], [rx1, ry1]], texture: t[:texture] }
          @next_terrain_id += 1
        end
      end
      @terrain = result
      persist! if affected.positive?
      affected
    end

    # ---------- Bulk operations ----------

    # Place one Token per (creature_id, x, y) triple on the given Map.
    # Returns the assigned Token IDs in input order.
    def place_tokens_for_combat(map_id, triples)
      Array(triples).map do |(creature_id, x, y)|
        place_token(map_id: map_id, creature_id: creature_id, x: x, y: y)
      end
    end

    def clear_tokens_on_map(map_id)
      removed = @tokens.select { |t| t[:map_id] == map_id }
      @tokens.reject! { |t| t[:map_id] == map_id }
      persist!
      removed.length
    end

    def clear_zones_on_map(map_id)
      removed = @zones.select { |z| z[:map_id] == map_id }
      @zones.reject! { |z| z[:map_id] == map_id }
      persist!
      removed.length
    end

    # ---------- Internal ----------

    private

    def map_for(id)   = @maps.find   { |m| m[:id] == id }
    def token_for(id) = @tokens.find { |t| t[:id] == id }
    def zone_for(id)  = @zones.find  { |z| z[:id] == id }
    def annotation_for(id) = @annotations.find { |a| a[:id] == id }
    def terrain_for(id)    = @terrain.find    { |t| t[:id] == id }

    def default_grid = { type: Config.default_grid_type, origin: [0, 0] }

    # Move every target/caster-anchored Zone that follows this Token's
    # Creature to the Token's current position.
    def follow_anchors!(token)
      @zones.each do |z|
        a = z[:anchor]
        next unless %w[target caster].include?(a[:type])
        next unless a[:creature_id] == token[:creature_id] && z[:map_id] == token[:map_id]
        a[:x] = token[:x]
        a[:y] = token[:y]
      end
    end

    def notify_movement(token, before, after)
      entered = after - before
      exited  = before - after
      return if entered.empty? && exited.empty?
      return unless @movement_notifier
      @movement_notifier.call(creature_id: token[:creature_id], map_id: token[:map_id],
                              entered: entered, exited: exited)
    end

    # AABB overlap between a (x, y, size) footprint (top-left + side) and
    # each Zone's bounding box (centered on its Anchor). Approximate but
    # sufficient for the record-keeping contract; precise geometry is a UI
    # concern.
    def overlapping_zone_ids(map_id, x, y, size)
      fx0 = x.to_f
      fy0 = y.to_f
      fx1 = fx0 + size.to_f
      fy1 = fy0 + size.to_f
      @zones.select do |z|
        next false unless z[:map_id] == map_id
        cx = z[:anchor][:x].to_f
        cy = z[:anchor][:y].to_f
        half = zone_half_extent(z)
        boxes_overlap?(fx0, fy0, fx1, fy1, cx - half, cy - half, cx + half, cy + half)
      end.map { |z| z[:id] }
    end

    def zone_half_extent(zone)
      case zone[:shape]
      when 'square' then zone[:size].to_f / 2.0
      else zone[:size].to_f # circle radius / cone / line reach
      end
    end

    def boxes_overlap?(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1)
      ax0 < bx1 && ax1 > bx0 && ay0 < by1 && ay1 > by0
    end

    # ----- normalization (load) -----

    def normalize_map(m)
      m = m.transform_keys(&:to_s) if m.respond_to?(:transform_keys)
      {
        id:       Integer(m['id']),
        name:     (m['name'] || '').to_s,
        image:    m['image'].nil? ? nil : m['image'].to_s,
        width:    m['width'],
        height:   m['height'],
        grid:     m['grid'].nil? ? nil : normalize_grid(m['grid']),
        archived: !!m['archived'],
        notes:    (m['notes'] || '').to_s
      }
    end

    def normalize_grid(g)
      g = g.transform_keys(&:to_s) if g.respond_to?(:transform_keys)
      origin = Array(g['origin'])
      { type:   (g['type'] || Config.default_grid_type).to_s,
        origin: [origin[0] || 0, origin[1] || 0] }
    end

    def normalize_token(t)
      t = t.transform_keys(&:to_s) if t.respond_to?(:transform_keys)
      {
        id:          Integer(t['id']),
        map_id:      t['map_id'],
        creature_id: t['creature_id'],
        x:           t['x'],
        y:           t['y'],
        size:        t['size'].nil? ? Config.default_token_size : t['size'],
        label:       t['label'].nil? ? nil : t['label'].to_s,
        image:       t['image'].nil? ? nil : t['image'].to_s,
        owner_id:    t['owner_id'],
        hidden:      !!t['hidden']
      }
    end

    def normalize_zone(z)
      z = z.transform_keys(&:to_s) if z.respond_to?(:transform_keys)
      { id:        Integer(z['id']),
        map_id:    z['map_id'],
        source_id: (z['source_id'] || '').to_s,
        shape:     (z['shape'] || 'square').to_s,
        size:      Integer(z['size'] || 0),
        anchor:    normalize_anchor(z['anchor']),
        texture:   z['texture'] }
    end

    def normalize_annotation(a)
      a = a.transform_keys(&:to_s) if a.respond_to?(:transform_keys)
      { id:         Integer(a['id']),
        map_id:     a['map_id'],
        type:       (a['type'] || 'arrow').to_s,
        points:     Array(a['points']).map { |p| [p[0], p[1]] },
        color:      a['color'].nil? ? nil : a['color'].to_s,
        shape_kind: a['shape_kind'].nil? ? nil : a['shape_kind'].to_s,
        text:       a['text'].nil? ? nil : a['text'].to_s,
        author:     (a['author'] || 'dm').to_s,
        dm_only:    !!a['dm_only'] }
    end

    def normalize_terrain(t)
      t = t.transform_keys(&:to_s) if t.respond_to?(:transform_keys)
      { id:         Integer(t['id']),
        map_id:     t['map_id'],
        shape_kind: (t['shape_kind'] || 'rect').to_s,
        points:     Array(t['points']).map { |p| [p[0], p[1]] },
        texture:    (t['texture'] || '').to_s }
    end

    def normalize_anchor(a)
      a ||= {}
      a = a.transform_keys(&:to_s) if a.respond_to?(:transform_keys)
      { type:        (a['type'] || 'point').to_s,
        x:           a['x'] || 0,
        y:           a['y'] || 0,
        creature_id: a['creature_id'] }
    end

    # ----- serialization (persist) -----

    def stringify_map(m)
      { 'id' => m[:id], 'name' => m[:name], 'image' => m[:image],
        'width' => m[:width], 'height' => m[:height],
        'grid' => m[:grid] && { 'type' => m[:grid][:type], 'origin' => m[:grid][:origin] },
        'archived' => m[:archived], 'notes' => m[:notes] }
    end

    def stringify_token(t)
      { 'id' => t[:id], 'map_id' => t[:map_id], 'creature_id' => t[:creature_id],
        'x' => t[:x], 'y' => t[:y], 'size' => t[:size], 'label' => t[:label],
        'image' => t[:image], 'owner_id' => t[:owner_id], 'hidden' => t[:hidden] }
    end

    def stringify_zone(z)
      { 'id' => z[:id], 'map_id' => z[:map_id], 'source_id' => z[:source_id],
        'shape' => z[:shape], 'size' => z[:size],
        'anchor' => { 'type' => z[:anchor][:type], 'x' => z[:anchor][:x],
                      'y' => z[:anchor][:y], 'creature_id' => z[:anchor][:creature_id] },
        'texture' => z[:texture] }.compact
    end

    def stringify_annotation(a)
      { 'id' => a[:id], 'map_id' => a[:map_id], 'type' => a[:type],
        'points' => a[:points], 'color' => a[:color],
        'shape_kind' => a[:shape_kind], 'text' => a[:text],
        'author' => a[:author], 'dm_only' => a[:dm_only] }
    end

    def stringify_terrain(t)
      { 'id' => t[:id], 'map_id' => t[:map_id], 'shape_kind' => t[:shape_kind],
        'points' => t[:points], 'texture' => t[:texture] }
    end
  end
end
