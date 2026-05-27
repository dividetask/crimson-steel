require 'yaml'

module Creatures
  # Loads `creatures_advancement.yaml` and exposes Class catalog
  # lookup with Archetype merge. This is the minimum slice of the
  # Creatures domain needed for Proficiencies' Skill Rate
  # Resolution; the rest of the domain (Creature Records, Effective
  # Attributes, Tier resolution, etc.) is not implemented yet.
  module Advancement
    DEFAULT_PATH = File.expand_path(
      '../../docs/common/creatures/creatures_advancement.yaml', __dir__
    )

    module_function

    def data
      @data ||= YAML.safe_load_file(DEFAULT_PATH)
    end

    def classes
      data['Classes'] || {}
    end

    def breakpoints
      data['Tier Breakpoints'] || {}
    end

    # Look up a Class key. Returns the resolved Class Catalog Entry,
    # applying Archetype merge when the entry declares `parent_class`.
    # Returns nil when the key is absent.
    def look_up_class(key)
      entry = classes[key]
      return nil unless entry
      return entry unless entry['parent_class']

      parent = classes[entry['parent_class']]
      raise "Archetype #{key.inspect} declares parent_class " \
            "#{entry['parent_class'].inspect}, which is absent" unless parent
      merge_archetype(entry, parent)
    end

    # Merge an Archetype entry over its parent per creatures_design.md
    # `Archetype` section: wholesale-override fields use the
    # archetype's value when present; proficiency-list fields are
    # additive adjustments; ability_progression appends per level.
    def merge_archetype(archetype, parent)
      merged = parent.dup

      %w[martial_advancement saves bonus_skills mana_per_level granted_spells].each do |f|
        merged[f] = archetype[f] if archetype.key?(f)
      end

      added_aligned   = archetype['aligned_proficiencies']   || []
      added_unaligned = archetype['unaligned_proficiencies'] || []
      added_opposed   = archetype['opposed_proficiencies']   || []

      base_aligned   = parent['aligned_proficiencies']
      base_unaligned = parent['unaligned_proficiencies']
      base_opposed   = parent['opposed_proficiencies'] || []

      # Additive merge with cross-removal on aligned/unaligned per the
      # design's "removed from Aligned if present there" rule.
      if base_aligned || added_aligned.any?
        eff_aligned = (base_aligned || []) + added_aligned
        eff_aligned -= added_unaligned
        merged['aligned_proficiencies'] = eff_aligned
      end
      if base_unaligned || added_unaligned.any?
        eff_unaligned = (base_unaligned || []) + added_unaligned
        eff_unaligned -= added_aligned
        merged['unaligned_proficiencies'] = eff_unaligned
      end
      merged['opposed_proficiencies'] = base_opposed + added_opposed

      ap = (parent['ability_progression'] || {}).each_with_object({}) do |(k, v), h|
        h[k] = v.dup
      end
      (archetype['ability_progression'] || {}).each do |level, abs|
        ap[level] = (ap[level] || []) + abs
      end
      merged['ability_progression'] = ap

      merged
    end

    def reset!
      @data = nil
    end
  end
end
