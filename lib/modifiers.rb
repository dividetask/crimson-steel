require 'set'

# Modifiers — typed numeric bonuses that pile up on top of base
# values for stats, skills, saves, and other character-derived
# numbers. Sourced from race abilities, class abilities, and
# (later) the EffectsState layer for spells, items, and
# conditions.
#
# Each entry targets a single field by string key. Recognized
# targets:
#
#   speed
#   damage_reduction
#   damage_resilience
#   max_hit_points
#   max_mana
#   attribute.<str|dex|con|int|wis|cha>
#   skill.<skill_key>
#   save.<attr_key>
#
# Optional `descriptors:` narrows when the modifier applies. A
# modifier with no descriptors applies to every query for that
# target. A modifier *with* descriptors applies only when the
# query supplies a descriptor set that includes all of them —
# so a "+1 inherent to con saves vs poison" entry has
# descriptors: [poison] and only fires when the roll asks for
# save.con with poison in its descriptor set.
#
# `type:` names the Bonus Type (Competency, Circumstance, Morale,
# Guidance, Inherent, Ascendancy — see data/dice_resolution.yaml).
# Within a single type, only the most extreme positive and most
# extreme negative contribute (typed bonuses don't stack with
# themselves). Untyped modifiers (no `type:`) all stack
# additively.

class Modifiers
  Modifier = Struct.new(:target, :type, :descriptors, :add, keyword_init: true)

  def initialize(raw_modifiers = [])
    @modifiers = Array(raw_modifiers).map { |m| self.class.normalize(m) }
  end

  attr_reader :modifiers

  # Total signed value applying to `target`. When `descriptors:`
  # is supplied, modifiers whose own descriptor list is a subset
  # of the query's contribute as well; modifiers with extra
  # descriptors not in the query are filtered out.
  def total_for(target, descriptors: [])
    target_str    = target.to_s
    requested_set = Array(descriptors).map(&:to_s).to_set
    relevant      = @modifiers.select do |m|
      m.target == target_str && (m.descriptors - requested_set.to_a).empty?
    end
    sum_with_stacking(relevant)
  end

  def self.normalize(raw)
    return raw if raw.is_a?(Modifier)
    hash = raw.respond_to?(:transform_keys) ? raw.transform_keys(&:to_s) : {}
    Modifier.new(
      target:      hash['target'].to_s,
      type:        (t = hash['type']) && !t.to_s.empty? ? t.to_s : nil,
      descriptors: Array(hash['descriptors']).map(&:to_s),
      add:         hash['add'].to_i
    )
  end

  private

  # Apply Bonus-Type stacking rules: same-typed bonuses don't
  # stack (the most positive wins) and same-typed penalties
  # don't stack (the most negative wins). Untyped modifiers all
  # stack.
  def sum_with_stacking(mods)
    typed, untyped = mods.partition { |m| m.type }
    untyped_total = untyped.sum(&:add)
    typed_total   = typed.group_by(&:type).sum do |_type, list|
      values    = list.map(&:add)
      positives = values.select { |v| v > 0 }
      negatives = values.select { |v| v < 0 }
      (positives.max || 0) + (negatives.min || 0)
    end
    untyped_total + typed_total
  end
end
