require 'abilities'

# Rows for the Compendium's Spell List page (docs/common/ui/abilities_spell_list_stub.md).
# Every Spell is expanded into its individual Variants — a Tier-axis Spell
# yields one row per Tier (Heal → Heal Petty Wounds, Heal Lesser Wounds, …); an
# aspect-axis Spell one row per aspect (Elemental Dart → Fire / Acid /
# Electricity / Cold Dart). Rows are sorted by Tier (lowest first), then name.
# Casting Skills exclude the Universal Spell Casting Skills (Evocation).
module SpellList
  module_function

  def rows
    universal = Array((Abilities.catalog.config.universal_casting_skills rescue [])).map(&:to_s)
    (Abilities.list(type: 'spell') rescue []).flat_map do |e|
      base = e['name'].to_s
      next [] if base.empty?
      variant_indices(e).filter_map do |i|
        v = (Abilities.lookup(base, axis_index: i) rescue nil) or next nil
        row_for(v, universal)
      end
    end.uniq { |r| r[:name] }.sort_by { |r| [r[:tier], r[:name]] }
  end

  # School key → description (abilities_config.yaml → Spell Schools).
  def school_description(key)
    (Abilities.catalog.config.spell_schools[key.to_s] rescue nil)
  end

  # ---- internals -----------------------------------------------------

  # The Variant Axis indices to expand: one per Tier (Tier-axis), one per aspect
  # (aspect-axis), or a single Variant. Mirrors the Abilities resolver.
  def variant_indices(entry)
    n =
      if entry['tier'].is_a?(Array) && !entry['tier'].empty? then entry['tier'].length
      elsif entry['aspects'].is_a?(Array) && !entry['aspects'].empty? then entry['aspects'].length
      else 1
      end
    (0...n).to_a
  end

  def row_for(v, universal)
    tier   = v['tier'].is_a?(Integer) ? v['tier'] : Array(v['tier']).map(&:to_i).min
    skills = base_skills(v).reject { |s| universal.include?(s) }
    saves  = Array(v['save']).filter_map { |s| s.is_a?(Hash) && s['attribute'] ? s['attribute'].to_s : nil }.uniq
    {
      name:         v['name'].to_s.strip,
      school:       v['school'].to_s,
      tier:         tier.to_i,
      skills:       skills,
      skills_label: skills.map { |s| titleize(s) }.join(', '),
      save:         saves.empty? ? nil : saves.map(&:upcase).join(' / '),
      range:        range_label(v['range']),
      duration:     v['duration'].to_s,
      activation:   activation_label(v['activation_time'])
    }
  end

  def base_skills(entry)
    s = Array(entry['skills']).map(&:to_s)
    s.empty? ? ['arcana'] : s
  end

  def titleize(key)
    key.to_s.tr('_', ' ').split.map { |w| w.empty? ? w : (w[0].upcase + w[1..]) }.join(' ')
  end

  def range_label(range)
    return '—' if range.nil?
    range.is_a?(Integer) ? "#{range} ft" : range.to_s
  end

  def activation_label(at)
    case at.to_s
    when '', 'main' then 'Main Action'
    else titleize(at)
    end
  end
end
