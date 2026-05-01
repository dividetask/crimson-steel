require 'yaml'
require_relative 'dice_system' # for DefaultRandomSource

# MagicalItemGenerator — produces a single tiered, optionally
# propertied Item Stack from a Magical Item Constraint.
#
# Constraint shape (see equipment_glossary.md):
#
#   { category, tier, tier_weights?, properties_weighted, items_weighted? }
#
# `category` is one of `melee`, `ranged`, `ammo`, `all_armor`,
# `all_body` and selects both the eligible Item Type pool and which
# property catalog to draw from. `properties_weighted` may include
# the reserved key `none` to give propertyless magical items a slot
# in the draw — when `none` wins, the stack carries no properties.
#
# Output Stack shape:
#
#   { 'item_type' => <name>, 'tier' => <int>,
#     'properties' => [ { 'name' => <prop>, 'subtype' => <sub>? } ] | [],
#     'quantity' => 1 }
#
# `item_type` (rather than the YAML's `item:` key) matches the
# normalized stack format LootTables produces, since this generator
# is the natural callable to wire into LootTables' inline magical
# rows.
#
# At most one Property is applied per generated item — multi-property
# stacks must be built explicitly in a Loot Table as literal items.
class MagicalItemGenerator
  CATEGORY_TO_PROPERTY_CATALOG = {
    'melee'     => 'Weapon Properties',
    'ranged'    => 'Weapon Properties',
    'ammo'      => 'Weapon Properties',
    'all_armor' => 'Armor Properties',
    'all_body'  => 'Armor Properties'
  }.freeze

  NONE_KEY = 'none'.freeze

  def initialize(config_path: nil, config: nil, random_source: nil)
    @config        = config || YAML.load_file(config_path) || {}
    @random_source = random_source || DefaultRandomSource.new
  end

  # Returns a freshly generated Item Stack hash matching the shape
  # documented in the class header. Raises on missing constraint
  # keys, empty eligible pools, or unknown property names.
  def generate(constraint)
    raise ArgumentError, 'Magical constraint missing category' unless constraint['category']
    raise ArgumentError, 'Magical constraint missing properties_weighted' unless constraint['properties_weighted']

    category   = constraint['category']
    raise ArgumentError, "Unknown magical-item category: #{category}" unless CATEGORY_TO_PROPERTY_CATALOG.key?(category)
    tier       = pick_tier(constraint)
    item_name  = pick_item_type(constraint, eligible_items_for_category(category))
    eligible   = eligible_properties(constraint['properties_weighted'], category, tier)
    raise ArgumentError, "No properties eligible at tier #{tier} for category #{category}" if eligible.empty?

    chosen = pick_weighted_key(eligible)
    properties = chosen == NONE_KEY ? [] : [build_property_entry(chosen, category)]

    { 'item_type' => item_name, 'tier' => tier, 'properties' => properties, 'quantity' => 1 }
  end

  # Bound the LootTables-compatible callable: `lambda { |c| gen.generate(c) }`.
  def to_proc
    method(:generate).to_proc
  end

  private

  def pick_tier(constraint)
    tier_list = Array(constraint['tier'])
    raise ArgumentError, 'Magical constraint missing tier list' if tier_list.empty?
    weights = constraint['tier_weights']
    if weights
      restricted = tier_list.each_with_object({}) { |t, h| h[t] = weights[t] if weights.key?(t) }
      raise ArgumentError, 'tier_weights does not cover any tier in the list' if restricted.empty?
      return pick_weighted_key(restricted)
    end
    tier_list[@random_source.rand_int(0, tier_list.length - 1)]
  end

  def pick_item_type(constraint, eligible_names)
    raise ArgumentError, "No eligible items for category: #{constraint['category']}" if eligible_names.empty?
    weights = constraint['items_weighted']
    if weights
      restricted = eligible_names.each_with_object({}) { |n, h| h[n] = weights[n] if weights.key?(n) }
      raise ArgumentError, 'items_weighted does not cover any eligible item' if restricted.empty?
      return pick_weighted_key(restricted)
    end
    eligible_names[@random_source.rand_int(0, eligible_names.length - 1)]
  end

  def eligible_items_for_category(category)
    case category
    when 'melee'     then weapons_where { |w| ['One Handed', 'Two Handed'].include?(w['category']) }
    when 'ranged'    then weapons_where { |w| w['category'] == 'Ranged' }
    when 'ammo'      then (@config['Ammunition'] || {}).keys
    when 'all_armor' then (@config['Armor'] || {}).keys
    when 'all_body'  then (@config['Armor'] || {}).select { |_, a| a['category'] != 'Shield' }.keys
    else
      raise ArgumentError, "Unknown magical-item category: #{category}"
    end
  end

  def weapons_where
    (@config['Weapons'] || {}).each_with_object([]) do |(name, defn), out|
      out << name if yield(defn)
    end
  end

  # Filters the constraint's properties_weighted down to those the
  # picked tier and category permit. The reserved `none` key is
  # always eligible and skips the catalog lookup.
  def eligible_properties(weighted, category, tier)
    catalog = property_catalog_for(category)
    weighted.each_with_object({}) do |(name, weight), out|
      if name == NONE_KEY
        out[name] = weight
      else
        defn = catalog[name]
        next unless defn
        next if defn['min_tier'].to_i > tier
        next unless Array(defn['applies_to']).include?(category)
        out[name] = weight
      end
    end
  end

  def build_property_entry(name, category)
    defn = property_catalog_for(category)[name]
    raise ArgumentError, "Unknown property: #{name}" unless defn
    entry = { 'name' => name }
    if defn['has_subtype']
      subtypes = Array(defn['subtypes'])
      raise ArgumentError, "Property #{name} declares has_subtype but has no subtypes list" if subtypes.empty?
      entry['subtype'] = subtypes[@random_source.rand_int(0, subtypes.length - 1)]
    end
    entry
  end

  def property_catalog_for(category)
    section = CATEGORY_TO_PROPERTY_CATALOG[category]
    raise ArgumentError, "Unknown magical-item category: #{category}" unless section
    @config[section] || {}
  end

  # Cumulative-probability sample over a {key => weight} map. Total
  # weight need not equal 1; weights are normalized at draw time.
  def pick_weighted_key(weighted)
    total = weighted.values.sum(&:to_f)
    raise ArgumentError, 'Total weight must be positive' if total <= 0
    threshold = @random_source.rand_int(0, 9_999) / 10_000.0 * total
    cumulative = 0.0
    weighted.each do |key, weight|
      cumulative += weight.to_f
      return key if threshold < cumulative
    end
    weighted.keys.last # numerical fallback for the boundary
  end
end
