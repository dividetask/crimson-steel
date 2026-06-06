require_relative 'advancement'
require_relative 'config'
require_relative 'races'

module Creatures
  # Validation + normalization for a single Creature Record. The
  # on-disk shape from the `creatures_data_*.yaml` files is loose
  # (integer or full Class Entry for class values; attributes as a
  # Hash with string-or-symbol keys); this module produces the
  # canonical in-memory form the rest of the domain consumes.
  module Record
    module_function

    REQUIRED_ATTR_KEYS = Creatures::Config.attribute_keys.freeze

    # Returns a normalized record (symbol-keyed, integer-typed).
    # Raises ArgumentError when validation fails, with a message
    # that includes the source file path when supplied.
    def normalize(raw, source: nil)
      r = stringify_keys(raw)
      out = {}

      out[:id]     = require_integer(r, 'id', source: source)
      out[:name]   = require_string(r, 'name', source: source)
      out[:player] = r['player']
      out[:group]  = (r['group'] || '').to_s
      # Per creatures_data_pcs.example.yaml: tags are optional and
      # default to [player_character] when the key is absent. Every
      # non-PC data file declares tags explicitly, so only Player
      # Characters pick up this default.
      out[:tags]   = r.key?('tags') ? Array(r['tags']).map(&:to_s) : ['player_character']
      out[:race]   = require_string(r, 'race', source: source)
      unless Races.known?(out[:race])
        raise ArgumentError, "Creature #{out[:id]}: unknown race #{out[:race].inspect}" \
                             "#{source ? " (in #{source})" : ''}"
      end

      out[:attributes]  = normalize_attributes(r['attributes'], out[:id], source)
      out[:tier]        = normalize_tier(r['tier'], out[:id], source)
      out[:loot_table]  = r['loot_table']
      # Optional Equipment Loot Table ID rolled once at spawn time to
      # generate the Creature's starting (and equipped) loadout — gear,
      # ammunition, pocket change. Distinct from `loot_table`, which
      # Collect Combat Loot rolls as extra drops on death.
      out[:equipment_table] = r['equipment_table']
      out[:metadata]    = r['metadata'] || {}
      # Persisted spawned-instance marker (Spawn Creature From Template);
      # round-tripped so a reloaded spawn still groups under its template.
      out[:spawned_from] = r['spawned_from'] ? Integer(r['spawned_from']) : nil

      adv = r['advancement'] || {}
      out[:classes] = normalize_classes(adv['classes'] || {}, out[:id], source)
      out[:tier_attribute_advancement] = normalize_tier_attr_adv(
        adv['tier_attribute_advancement'] || [], out[:id], source
      )

      validate_archetype_exclusivity!(out[:classes], out[:id], source)

      out
    end

    # Inverse of `normalize`: turn a normalized in-memory record back into
    # the loose on-disk YAML shape (string keys) for persistence. Only
    # writes keys that carry meaning, so a round-trip stays close to the
    # hand-authored files. `:source` / `:spawned_from` are persistence
    # bookkeeping — `spawned_from` is written so a reloaded spawn still
    # groups under its template; `source` is the file routing key and is
    # not part of the record body.
    def serialize(rec)
      classes = {}
      rec[:classes].each do |key, e|
        entry = { 'level' => e[:level] }
        entry['skills']  = e[:skills]  unless Array(e[:skills]).empty?
        entry['choices'] = e[:choices] unless (e[:choices] || {}).empty?
        classes[key.to_s] = entry
      end

      adv = { 'classes' => classes }
      unless Array(rec[:tier_attribute_advancement]).empty?
        adv['tier_attribute_advancement'] = rec[:tier_attribute_advancement].map(&:to_s)
      end

      out = {
        'id'    => rec[:id],
        'name'  => rec[:name],
        'race'  => rec[:race],
        'attributes' => rec[:attributes].transform_keys(&:to_s),
        'advancement' => adv
      }
      out['player']       = rec[:player]                       unless rec[:player].nil?
      out['group']        = rec[:group]                        unless rec[:group].to_s.empty?
      out['tags']         = rec[:tags]                         unless Array(rec[:tags]).empty?
      out['tier']         = rec[:tier]                         unless rec[:tier].nil?
      out['loot_table']   = rec[:loot_table]                   unless rec[:loot_table].nil?
      out['equipment_table'] = rec[:equipment_table]           unless rec[:equipment_table].nil?
      out['metadata']     = rec[:metadata]                     unless (rec[:metadata] || {}).empty?
      out['spawned_from'] = rec[:spawned_from]                 unless rec[:spawned_from].nil?
      out
    end

    # ---- helpers --------------------------------------------------------

    def stringify_keys(h)
      h.is_a?(Hash) ? h.transform_keys(&:to_s) : h
    end

    def require_integer(r, key, source:)
      v = r[key]
      raise ArgumentError, "Creature record missing #{key.inspect}#{source ? " (in #{source})" : ''}" if v.nil?
      Integer(v)
    end

    def require_string(r, key, source:)
      v = r[key]
      raise ArgumentError, "Creature record missing #{key.inspect}#{source ? " (in #{source})" : ''}" if v.nil? || v.to_s.empty?
      v.to_s
    end

    def normalize_attributes(attrs, cid, source)
      raise ArgumentError, "Creature #{cid}: missing `attributes`#{source ? " (in #{source})" : ''}" \
        unless attrs.is_a?(Hash)
      a = stringify_keys(attrs)
      out = {}
      REQUIRED_ATTR_KEYS.each do |k|
        unless a.key?(k.to_s)
          raise ArgumentError, "Creature #{cid}: `attributes` missing #{k.inspect}" \
                               "#{source ? " (in #{source})" : ''}"
        end
        out[k] = Integer(a[k.to_s])
      end
      out
    end

    def normalize_tier(v, cid, source)
      return nil if v.nil?
      Integer(v)
    rescue ArgumentError
      raise ArgumentError, "Creature #{cid}: `tier` must be a non-negative integer or null" \
                           "#{source ? " (in #{source})" : ''}"
    end

    def normalize_classes(raw_classes, cid, source)
      raise ArgumentError, "Creature #{cid}: `advancement.classes` must be a map" \
                           "#{source ? " (in #{source})" : ''}" unless raw_classes.is_a?(Hash)

      out = {}
      raw_classes.each do |key, val|
        class_key = key.to_s
        unless Creatures::Advancement.classes.key?(class_key)
          raise ArgumentError, "Creature #{cid}: unknown class #{class_key.inspect}" \
                               "#{source ? " (in #{source})" : ''}"
        end
        entry = val.is_a?(Integer) ? { 'level' => val } : stringify_keys(val)
        level = Integer(entry.fetch('level'))
        if level < 0
          raise ArgumentError, "Creature #{cid}: class #{class_key} has negative level"
        end
        skills = (entry['skills'] || []).map(&:to_s)
        skills.each do |s|
          if s.end_with?('_')
            raise ArgumentError, "Creature #{cid}: class #{class_key} skills entry " \
                                 "#{s.inspect} is a bare Set Skill key (not allowed)" \
                                 "#{source ? " (in #{source})" : ''}"
          end
        end
        choices = entry['choices'] || {}
        out[class_key] = { level: level, skills: skills, choices: stringify_keys(choices) }
      end
      out
    end

    def normalize_tier_attr_adv(list, cid, source)
      Array(list).map do |e|
        key = e.to_s.to_sym
        unless Creatures::Config.attribute_keys.include?(key)
          raise ArgumentError, "Creature #{cid}: `tier_attribute_advancement` entry " \
                               "#{e.inspect} is not a recognized attribute" \
                               "#{source ? " (in #{source})" : ''}"
        end
        key
      end
    end

    # Reject when the classes map contains both a Class and one of
    # its Archetypes, or two Archetypes of the same parent.
    def validate_archetype_exclusivity!(classes, cid, source)
      keys = classes.keys
      keys.each do |k|
        entry = Creatures::Advancement.classes[k] || {}
        next unless entry['parent_class']
        parent = entry['parent_class']
        if keys.include?(parent)
          raise ArgumentError, "Creature #{cid}: Archetype Exclusivity — has both " \
                               "#{parent.inspect} (parent) and #{k.inspect} (archetype)" \
                               "#{source ? " (in #{source})" : ''}"
        end
        keys.each do |other|
          next if other == k
          other_entry = Creatures::Advancement.classes[other] || {}
          if other_entry['parent_class'] == parent
            raise ArgumentError, "Creature #{cid}: Archetype Exclusivity — has two " \
                                 "archetypes of #{parent.inspect}: #{k.inspect} and " \
                                 "#{other.inspect}#{source ? " (in #{source})" : ''}"
          end
        end
      end
    end
  end
end
