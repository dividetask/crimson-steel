module Chronicle
  # Pure data normalization for a single Entry. Stored verbatim as a
  # Hash with string keys to round-trip cleanly through JSON.
  module Entry
    SHARED_FIELDS = %w[
      id entry_type chapter notes_position scene_position
      title public_description dm_description image
      shared hidden_from owner_id active
    ].freeze

    CREATURE_FIELDS = %w[creature_id creature_token tier].freeze

    module_function

    # Normalize an arbitrary input hash into the canonical on-disk
    # shape. Defaults match docs/common/chronicle/chronicle_design.md.
    def normalize(raw)
      h = stringify_keys(raw)
      out = {
        'id'                 => Integer(h.fetch('id')),
        'entry_type'         => h.fetch('entry_type').to_s,
        'chapter'            => Integer(h.fetch('chapter')),
        'notes_position'     => h['notes_position'] && Integer(h['notes_position']),
        'scene_position'     => h['scene_position'] && Integer(h['scene_position']),
        'title'              => (h['title'] || '').to_s,
        'public_description' => (h['public_description'] || '').to_s,
        'dm_description'     => (h['dm_description'] || '').to_s,
        'image'              => h['image'] && h['image'].to_s.then { |s| s.empty? ? nil : s },
        'shared'             => h.fetch('shared', false) ? true : false,
        'hidden_from'        => (h['hidden_from'] || []).map { |c| Integer(c) },
        'owner_id'           => h['owner_id'] && Integer(h['owner_id']),
        'active'             => h.fetch('active', false) ? true : false
      }
      raise ArgumentError, "unknown entry_type: #{out['entry_type'].inspect}" unless %w[note creature].include?(out['entry_type'])

      if out['entry_type'] == 'creature'
        out['creature_id']    = Integer(h.fetch('creature_id'))
        out['creature_token'] = h['creature_token'] && h['creature_token'].to_s.then { |s| s.empty? ? nil : s }
        out['tier']           = h['tier'].nil? || h['tier'].to_s.empty? ? nil : Integer(h['tier'])
      end
      out
    end

    # Merge an updates hash onto an existing normalized Entry. Only
    # the fields supplied in `updates` are touched; everything else
    # is preserved. After merge, the result is re-normalized so that
    # type coercions are reapplied.
    def merge(existing, updates)
      base = existing.dup
      stringify_keys(updates).each do |k, v|
        base[k] = v
      end
      normalize(base)
    end

    def stringify_keys(h)
      h = h.transform_keys(&:to_s) if h.respond_to?(:transform_keys)
      h
    end
  end
end
