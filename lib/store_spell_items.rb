require 'equipment'

# Store "Scrolls / Potions / Oils" builder data + per-line pricing/validation,
# kept pure so it is unit-testable (mirrors StoreMagicWeapons / StoreMagicalArmor).
#
# The buyer picks a Form first (Scroll / Potion / Oil), which filters the Spell
# list: every Spell can be a Scroll; only Spells whose Item Forms include
# `potion` / `oil` offer those. A multi-Tier Spell is bought at a chosen Tier.
#
# Pricing (see equipment_design.md → Consumable): a Potion/Oil costs the full
# Consumable price; a Scroll costs half that. Tier 0 has no Tier Surcharge (the
# raw formula yields 0), so — per the project's "Tier 0 is treated as 0.5"
# rule — a Tier-0 Consumable costs half the Tier-1 price rather than nothing.
module StoreSpellItems
  SCROLL_FACTOR = 0.5   # a Scroll is half the price of the Potion / Oil.
  FORMS = %w[scroll potion oil].freeze

  module_function

  # { spells: [ { name:, scroll:, potion:, oil:,
  #               tiers: [ { tier:, scroll:, potion:, oil: } ] } ] },
  # sorted by Spell name. A form flag is true when that form exists for the
  # Spell; the per-tier price for an absent form is nil.
  def builder(catalog)
    spells = (Abilities.list(type: 'spell') rescue [])
    rows = spells.filter_map do |sp|
      name = sp['name'].to_s.strip
      next if name.empty?
      next unless catalog.item_type("Scroll of #{name}")   # a scroll form exists
      items  = Array(sp['items']).map(&:to_s)
      potion = items.include?('potion')
      oil    = items.include?('oil')
      tiers  = spell_tiers(sp)
      { name: name, scroll: true, potion: potion, oil: oil,
        tiers: tiers.map { |t| tier_row(name, t, potion, oil, catalog) } }
    end
    { spells: rows.sort_by { |r| r[:name] } }
  end

  # Validate + build the Stack fields for one checkout line. Returns
  # { fields:, label: } or { error: }.
  def fields(spell, form, tier_raw, catalog)
    spell = spell.to_s.strip
    form  = form.to_s.downcase
    return { error: 'unknown form' } unless FORMS.include?(form)
    item = "#{form.capitalize} of #{spell}"
    defn = catalog.definition_of(item)
    return { error: 'no such item' } if defn.nil?

    tier = (Integer(tier_raw) rescue nil)
    return { error: 'invalid tier' } if tier.nil? || !allowed_tiers(defn).include?(tier)

    { fields: { 'item' => item, 'tier' => tier }, label: display_label(item, tier, catalog) }
  end

  # Whether an Item Type is a purchasable spell-form Consumable (Scroll /
  # Potion / Oil).
  def spell_form_item?(item, catalog)
    it = item.to_s
    defn = catalog.definition_of(it) or return false
    defn['spell'] && defn['category'] == 'Consumable' && it =~ /\A(Scroll|Potion|Oil) of /
  end

  # The store price for a spell-form Consumable line (Scroll is half the
  # Potion / Oil price). Used for both the builder display and the checkout
  # charge, so they always agree.
  def line_price(item, tier, catalog)
    it   = item.to_s
    form = it.start_with?('Potion') ? 'potion' : it.start_with?('Oil') ? 'oil' : 'scroll'
    spell = it.sub(/\A(Scroll|Potion|Oil) of /, '')
    price_for(spell, form, tier.to_i, catalog)
  end

  # ---- internals -----------------------------------------------------

  def price_for(spell, form, tier, catalog)
    full = full_consumable_price(spell, tier, catalog)
    form == 'scroll' ? (full * SCROLL_FACTOR) : full
  end

  # The full (Potion / Oil) Consumable price for a Spell at a Tier. Tier 0 has
  # no surcharge, so it is priced as half the Tier-1 price (Tier 0 = 0.5).
  def full_consumable_price(spell, tier, catalog)
    if tier.to_i <= 0
      catalog_price("Scroll of #{spell}", 1, catalog) * 0.5
    else
      catalog_price("Scroll of #{spell}", tier, catalog)
    end
  end

  def catalog_price(item, tier, catalog)
    Equipment::Pricing.unit_price(Equipment::Stack.normalize('item' => item, 'tier' => tier), catalog)
  rescue StandardError
    0
  end

  def tier_row(spell, tier, potion, oil, catalog)
    { tier: tier,
      scroll: price_for(spell, 'scroll', tier, catalog),
      potion: potion ? price_for(spell, 'potion', tier, catalog) : nil,
      oil:    oil ? price_for(spell, 'oil', tier, catalog) : nil }
  end

  def spell_tiers(spell_entry)
    t = spell_entry['tier']
    return t.map(&:to_i) if t.is_a?(Array) && !t.empty?
    return [t.to_i] if t.is_a?(Integer)
    [0]
  end

  def allowed_tiers(defn)
    t = defn['tier']
    return t.map(&:to_i) if t.is_a?(Array) && !t.empty?
    return [t.to_i] if t.is_a?(Integer)
    [0]
  end

  # The Tier-resolved display name ("Potion of Heal" at Tier 0 → "Potion of
  # Heal Petty Wounds"), via the same bridge the sheet uses.
  def display_label(item, tier, catalog)
    stack = Equipment::Stack.normalize('item' => item, 'tier' => tier)
    (CreatureSheet.item_display_name(stack, catalog) rescue item)
  end
end
