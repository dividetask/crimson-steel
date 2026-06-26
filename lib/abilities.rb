require 'yaml'

# Abilities domain. See docs/common/abilities/abilities_design.md.
#
# A strict reference: answers "what does this Ability do?" for other
# modules to consume. Rolls no dice, tracks no active effects, consumes
# no resources.
#
# Module owns:
#   - Config    — abilities_config.yaml view (+ cross-domain damage types)
#   - Formula   — safe arithmetic evaluator for embedded Formula strings
#   - Effect    — Effect-string classification and deferred damage
#   - Catalog   — loads + validates the data files; holds raw entries
#   - Resolver  — raw Catalog Ability -> resolved Variant; range/target/etc.
module Abilities
  module_function

  def catalog
    @catalog ||= Catalog.load
  end

  def resolver
    @resolver ||= Resolver.new(catalog)
  end

  # Reset memoized state (used after pointing at a different data dir).
  def reset!
    @catalog = nil
    @resolver = nil
  end

  # ---- Catalog Ability lookups ----------------------------------------

  # Resolve a Catalog Ability to the Variant at axis_index. Extra keyword
  # bindings (e.g. rank:, level:) feed Effect Hash / description formulas.
  # Returns the resolved Hash, or nil for an unknown name.
  def lookup(name, axis_index: 0, **bindings)
    resolver.resolve(name, axis_index: axis_index, bindings: stringify(bindings))
  end

  def resolve_range(ability_or_name, rank: 0, reach: nil, axis_index: 0)
    ability = as_ability(ability_or_name, axis_index)
    return nil unless ability
    resolver.resolve_range(ability, rank: rank, reach: reach)
  end

  def resolve_activation(ability_or_name, axis_index: 0)
    ability = as_ability(ability_or_name, axis_index)
    return nil unless ability
    resolver.resolve_activation(ability)
  end

  def resolve_target(ability_or_name, rank: 0, axis_index: 0, **bindings)
    ability = as_ability(ability_or_name, axis_index)
    return nil unless ability
    resolver.resolve_target(ability, rank: rank, bindings: stringify(bindings))
  end

  # Resolve an Area `size` (a 5-foot-square count, possibly a per-rank
  # Formula like "8*rank") to a concrete non-negative integer, or nil when
  # it cannot be evaluated. See abilities_design.md "Area".
  def resolve_area_size(size, rank: 0, **bindings)
    resolver.resolve_area_size(size, rank: rank, bindings: stringify(bindings))
  end

  # Resolve a Spell into the consumption view Equipment routes at
  # Consume Item time: `{ effects: [...], polarity: :positive | :forced }`.
  # `tier` selects the Variant on a Tier-axis Spell. Returns nil for an
  # unknown name. See abilities_design.md "Resolve a Spell for item
  # consumption".
  def resolve_spell(name, tier: nil)
    resolver.resolve_spell(name, tier: tier)
  end

  # Whether a Spell suppresses non-item invocation paths (its `item_only`
  # flag). Exposed for Equipment's Is Item-Only?. False for an unknown
  # name or a Spell without the flag.
  def item_only?(name)
    entry = catalog.ability(name)
    !!(entry && entry['item_only'])
  end

  # Trigger Spec verbatim, or nil if the Ability has none (or isn't a
  # Catalog Ability).
  def get_trigger(name)
    entry = catalog.ability(name)
    entry && entry['trigger']
  end

  # A named Roll Table (roll_tables.yaml) verbatim, or nil for an
  # unknown name. See `Abilities::Catalog#roll_table`.
  def roll_table(name)
    catalog.roll_table(name)
  end

  # The Roll Table name a Catalog Ability fires on (its `roll_table`
  # field), or nil when it declares none / isn't a Catalog Ability.
  def roll_table_for(name)
    entry = catalog.ability(name)
    entry && entry['roll_table']
  end

  # Modifier Entries verbatim across every Ability flavor that carries
  # `modifiers:`. Always returns a list (empty when none / unknown).
  def get_modifiers(name, source: nil)
    entry = catalog.ability(name)
    return entry['modifiers'] if entry && entry['modifiers']

    mod = catalog.modifier_ability(name)
    return mod['modifiers'] || [] if mod

    []
  end

  # Equipment item names a Natural Attack Talent grants (its
  # `grants_equipment` list). Always returns a list (empty when none /
  # unknown). The names resolve to Equipment catalog Weapons.
  def granted_equipment(name)
    entry = catalog.ability(name)
    Array(entry && entry['grants_equipment']).map(&:to_s)
  rescue StandardError
    []
  end

  # Catalog Abilities matching a Type and/or School filter, on un-resolved
  # data (the Variant Axis is not iterated). Returns entries with `name`.
  def list(type: nil, school: nil)
    catalog.catalog.filter_map do |name, entry|
      next if type && entry['type'] != type.to_s
      next if school && entry['school'] != school.to_s
      entry.merge('name' => name)
    end
  end

  # ---- Other Ability flavors ------------------------------------------

  def lookup_stateful(name)
    entry = catalog.stateful_ability(name)
    return nil unless entry
    { name: name.to_s, description: entry['description'] }
  end

  def lookup_modifier_ability(name)
    entry = catalog.modifier_ability(name)
    return nil unless entry
    {
      name: name.to_s,
      description: entry['description'],
      modifiers: entry['modifiers'] || []
    }
  end

  # ---- Effect classification / damage ---------------------------------

  def classify_effect(str, context: {}, damage_type: nil)
    Effect.classify(str, context: context, damage_type: damage_type)
  end

  def evaluate_damage(damage_object, success: 0, critical: 0, attribute: 0)
    Effect.evaluate_damage(damage_object, success: success, critical: critical, attribute: attribute)
  end

  # ---- internals ------------------------------------------------------

  def as_ability(ability_or_name, axis_index)
    return ability_or_name if ability_or_name.is_a?(Hash)
    lookup(ability_or_name, axis_index: axis_index)
  end

  def stringify(hash)
    hash.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
  end
end

require_relative 'abilities/formula'
require_relative 'abilities/config'
require_relative 'abilities/effect'
require_relative 'abilities/catalog'
require_relative 'abilities/resolver'
