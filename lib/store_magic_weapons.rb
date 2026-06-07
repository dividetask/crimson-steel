require 'equipment'

# Store "Magical Weapons" builder: lets the Store sell enchanted weapons
# (a base Weapon + a Weapon Property like Elemental / Emotional / Vicious /
# Glory + a Tier). Pure helpers shared by the Store route — `builder` feeds
# the page's picker, `fields` revalidates a checkout line and produces the
# Stack fields. The client computes a live price (base + Tier Surcharge +
# Property cost); the server reprices and revalidates here at checkout.
module StoreMagicWeapons
  module_function

  # Whether a Weapon counts as `melee` or `ranged` for a Property's
  # `applies_to` list (One/Two Handed → melee; Ranged → ranged).
  def attack_category(defn)
    (defn['category'] == 'Ranged') ? 'ranged' : 'melee'
  end

  # The picker data for the Store: buyable Weapons (no natural attacks), the
  # Weapon Properties flattened per Subtype, and the Tier Surcharge table.
  def builder(catalog)
    weapons = catalog.item_types_in_category('Weapon').filter_map do |name|
      defn = catalog.definition_of(name) || {}
      next if defn['natural']
      { name: name, category: attack_category(defn), base_price: catalog.base_price_for(name, 0) }
    end
    properties = catalog.weapon_properties.flat_map do |name, defn|
      base = { name: name, cost: (defn['cost'] || 0), min_tier: (defn['min_tier'] || 1),
               applies_to: Array(defn['applies_to']) }
      if defn['has_subtype']
        Array(defn['subtypes']).map { |st| base.merge(subtype: st, label: "#{name} — #{st}") }
      else
        [base.merge(subtype: nil, label: name)]
      end
    end
    tiers = (1..5).map { |t| { tier: t, surcharge: (catalog.default_tier_surcharge[t] || 0) } }
    { weapons: weapons, properties: properties, tiers: tiers }
  end

  # Validate a magical-weapon checkout line and build its Stack fields.
  # `props` is a list of { name, subtype }. Returns { fields:, label: } on
  # success or { error: } on rejection (unknown / ineligible Property, Tier
  # below the Property minimum, wrong weapon category, …). Property costs are
  # stamped from the catalog so the stored Stack reprices independently.
  def fields(item, props, tier_raw, catalog)
    defn = catalog.definition_of(item) || {}
    return { error: 'not a weapon' } unless catalog.category_of(item) == 'Weapon'
    return { error: 'natural weapon' } if defn['natural']
    tier = (Integer(tier_raw) rescue nil)
    return { error: 'invalid tier' } if tier.nil? || tier < 1
    wcat = attack_category(defn)

    built = []
    Array(props).each do |p|
      h = p.is_a?(Hash) ? p : {}
      pname = (h['name'] || h[:name]).to_s
      pdef  = catalog.weapon_property(pname)
      return { error: "unknown property #{pname}" } unless pdef
      subtype = h['subtype'] || h[:subtype]
      if pdef['has_subtype']
        return { error: "#{pname} needs a subtype" } if subtype.to_s.strip.empty?
        return { error: "invalid #{pname} subtype" } unless Array(pdef['subtypes']).map(&:to_s).include?(subtype.to_s)
      else
        subtype = nil
      end
      return { error: "#{pname} needs tier #{pdef['min_tier']}" } if tier < (pdef['min_tier'] || 1)
      return { error: "#{pname} can't go on a #{wcat} weapon" } unless Array(pdef['applies_to']).include?(wcat)
      built << { 'name' => pname, 'subtype' => subtype, 'cost' => pdef['cost'] }
    end
    return { error: 'no properties' } if built.empty?

    f = { 'item' => item, 'tier' => tier, 'properties' => built }
    { fields: f, label: Equipment::DisplayName.call(Equipment::Stack.normalize(f), catalog) }
  end
end
