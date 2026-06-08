require 'equipment'

# Store "Magical Armor" builder: lets the Store sell tiered (magical) Armor
# — a base Armor piece (incl. Shields) plus a Tier (1–5). It mirrors the
# Magical Weapons builder but drops the Property dimension, so there are no
# Armor Properties to pick: a magical Armor's only enchantment is its Tier
# (which confers the Resilience / Hardness the Tier grants — see
# equipment_design.md → Get Armor Details). Pure helpers shared by the Store
# route — `builder` feeds the page's picker, `fields` revalidates a checkout
# line into Stack fields. The client shows a live price (base + Tier
# Surcharge); the server reprices and revalidates here at checkout.
module StoreMagicalArmor
  module_function

  # The picker data for the Store: every buyable Armor piece with its
  # mundane (Tier 0) base price, plus the Tier Surcharge table (Tiers 1–5).
  def builder(catalog)
    armor = catalog.item_types_in_category('Armor').map do |name|
      { name: name, base_price: catalog.base_price_for(name, 0) }
    end
    tiers = (1..5).map { |t| { tier: t, surcharge: (catalog.default_tier_surcharge[t] || 0) } }
    { armor: armor, tiers: tiers }
  end

  # Validate a magical-armor checkout line and build its Stack fields.
  # Returns { fields:, label: } on success or { error: } on rejection (not
  # an Armor piece, or a Tier below 1). No Properties are stamped — a
  # magical Armor is just a tiered base Armor.
  def fields(item, tier_raw, catalog)
    return { error: 'not armor' } unless catalog.category_of(item) == 'Armor'
    tier = (Integer(tier_raw) rescue nil)
    return { error: 'invalid tier' } if tier.nil? || tier < 1

    f = { 'item' => item, 'tier' => tier }
    { fields: f, label: Equipment::DisplayName.call(Equipment::Stack.normalize(f), catalog) }
  end
end
