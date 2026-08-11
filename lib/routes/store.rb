# Store page — the Equipment Provisioning stub.
#
# Page (DM + Player):
#   GET  /store — sections for provisioning Creatures with gear:
#                 Weapons, Armor (incl. Shields), and Alchemy. Each
#                 section has a Recipient dropdown over the Creature
#                 roster (enemies hidden from players). Adding items
#                 builds a client-side Shopping Cart; nothing hits the
#                 server until the cart's Purchase button is pressed.
#                 See docs/common/ui/equipment_provision_stub.md.
#
#   POST /store/checkout — JSON-in / JSON-out. Resolve a whole cart of
#                 lines at once. A line whose recipient is a Player
#                 Character is charged its own wealth first, then the
#                 Party wallet covers any remainder; a non-PC recipient
#                 (NPC / enemy) is provisioned for free. Each line's Item
#                 is added to the recipient's Inventory via Equipment's
#                 *Add Item*. Prices and PC-status are recomputed
#                 server-side — the client cart is never trusted for cost.
#
# Potions (one Item per potion-capable Spell, Tier-colored) are deferred
# until the Abilities domain is wired into Equipment.

require 'json'
require 'live_roster'
require 'store_magic_weapons'
require 'store_magical_armor'
require 'store_spell_items'

get '/store' do
  cat        = Equipment.catalog
  @viewer    = viewer_role
  @creatures = provision_roster(@viewer)
  @players   = player_creatures.map { |c| { id: c[:id], name: c[:name] } }
  @weapons   = mundane_items('Weapon', cat)
  @armor     = mundane_items('Armor', cat)
  @alchemy   = ['Acid jar', "Alchemist's fire"].map { |n| catalog_item(n, cat) }
  @magical   = guidance_items(cat)
  @magical_weapons = magical_weapon_builder(cat)
  @magical_armor   = magical_armor_builder(cat)
  @spell_items     = StoreSpellItems.builder(cat)
  # The shared Party wallet, shown at the top-right of the Store.
  @party_gold = (Equipment.instance.get_total_wealth('party') rescue 0)
  erb :store
end

post '/store/checkout' do
  content_type :json
  payload = (JSON.parse(request.body.read) rescue nil)
  lines   = payload.is_a?(Hash) ? payload['lines'] : nil
  unless lines.is_a?(Array) && !lines.empty?
    halt 400, JSON.generate(ok: false, type: 'error', message: 'Your cart is empty.')
  end

  inst    = Equipment.instance
  cat     = Equipment.catalog
  # Only recipients the current viewer is allowed to provision (players
  # never see — or get to equip — enemies).
  allowed = provision_roster(viewer_role).map { |c| c[:id].to_s }

  done   = []
  errors = []
  lines.each do |ln|
    next unless ln.is_a?(Hash)
    item = ln['item'].to_s
    cid  = ln['recipient_id'].to_s
    qty  = (Integer(ln['quantity']) rescue 0)
    next if qty <= 0

    if cat.category_of(item).nil?
      errors << "#{qty}× #{item} (unknown item)"
      next
    end
    unless allowed.include?(cid)
      errors << "#{qty}× #{item} (invalid recipient)"
      next
    end

    # A magical-weapon line carries `properties` (a list of {name, subtype})
    # and a `tier`; a magical-armor line carries a `tier` with no properties;
    # a Scroll/Potion line is a spell-form Consumable (detected server-side).
    # The server validates eligibility and re-derives the price (never
    # trusting the client). Guidance Items carry a +N Bonus only, and the Tier
    # is re-derived from the catalog. Everything else is mundane.
    if ln['properties'].is_a?(Array) && !ln['properties'].empty?
      built = magical_weapon_fields(item, ln['properties'], ln['tier'], cat)
      if built[:error]
        errors << "#{qty}× #{item} (#{built[:error]})"
        next
      end
      fields = built[:fields].merge('quantity' => qty)
      label  = built[:label]
    elsif StoreSpellItems.spell_form_item?(item, cat)
      form  = item.start_with?('Potion') ? 'potion' : item.start_with?('Oil') ? 'oil' : 'scroll'
      spell = item.sub(/\A(Scroll|Potion|Oil) of /, '')
      built = StoreSpellItems.fields(spell, form, ln['tier'], cat)
      if built[:error]
        errors << "#{qty}× #{item} (#{built[:error]})"
        next
      end
      fields = built[:fields].merge('quantity' => qty)
      label  = built[:label]
    elsif !ln['tier'].to_s.strip.empty?
      built = magical_armor_fields(item, ln['tier'], cat)
      if built[:error]
        errors << "#{qty}× #{item} (#{built[:error]})"
        next
      end
      fields = built[:fields].merge('quantity' => qty)
      label  = built[:label]
    else
      bonus = guidance_bonus_arg(ln)
      if guidance_item?(item, cat)
        tier = guidance_tier_for(item, bonus, cat)
        if tier.nil?
          errors << "#{qty}× #{item} (invalid bonus +#{bonus})"
          next
        end
      elsif bonus
        errors << "#{qty}× #{item} (not a magical item)"
        next
      end

      fields = { 'item' => item, 'quantity' => qty }
      fields['guidance_bonus'] = bonus if bonus
      fields['tier'] = tier if bonus
      label = bonus ? "+#{bonus} #{item}" : item
    end

    name  = creature_name(cid)
    owner = "character:#{cid}"
    # Scroll/Potion/Oil lines are priced by the Store's own rule (Scroll = half
    # the Potion/Oil price; Tier 0 = half Tier 1) so the charge matches the
    # builder's shown price; everything else uses the catalog Unit Price.
    unit =
      if StoreSpellItems.spell_form_item?(fields['item'], cat)
        StoreSpellItems.line_price(fields['item'], fields['tier'], cat)
      else
        Equipment::Pricing.unit_price(Equipment::Stack.normalize(fields), cat)
      end
    cost  = unit * qty

    # A "Give" line hands the item over for free — but only the DM may gift, so
    # the flag is honored solely on a DM (loopback) request; a player's line is
    # always charged normally.
    gift = truthy(ln['gift']) && dm_view?

    if player_character?(cid) && !gift
      unless charge_pc_then_party(inst, owner, cost)
        errors << "#{qty}× #{label} for #{name} (not enough wealth)"
        next
      end
      inst.add_item(owner, Equipment::Stack.normalize(fields))
      done << "#{qty}× #{label} → #{name} (#{store_fmt_price(cost)} gp)"
    else
      # Non-PC recipients (NPCs, enemies) — and DM gifts to a PC — are free.
      inst.add_item(owner, Equipment::Stack.normalize(fields))
      done << "#{qty}× #{label} → #{name} (#{gift && player_character?(cid) ? 'gift' : 'free'})"
    end
  end

  parts = []
  parts << "Bought #{done.join('; ')}." unless done.empty?
  parts << "Skipped #{errors.join('; ')}." unless errors.empty?
  parts << 'Nothing to buy.' if parts.empty?
  JSON.generate(ok: errors.empty?, type: errors.empty? ? 'success' : 'error', message: parts.join(' '))
end

helpers do
  # The Creature roster for the Recipient dropdowns. Player Characters
  # are listed first (in roster order), then everyone else. Each entry
  # carries `pc` so the client can tell paid recipients from free ones.
  #
  # Visibility:
  #   Enemies — hidden from players; the DM sees them all (unchanged).
  #   NPCs    — hidden from players entirely (only the DM may pick an NPC
  #             recipient), and the DM sees only NPCs that are active in the
  #             current Scene (their Chronicle Creature Reference is active).
  #             Inactive NPCs are dropped from the roster for everyone.
  #   PCs     — always shown.
  def provision_roster(viewer)
    active_npcs = LiveRoster.scene_active_creature_ids
    roster = Creatures.list.filter_map do |(id, name)|
      a     = Creatures.lookup(id)
      group = a&.group.to_s
      next if viewer == :player && group == 'enemy'
      if group == 'npc'
        next if viewer == :player            # players never see NPC recipients
        next unless active_npcs.include?(id)  # DM: only Scene-active NPCs
      end
      pc = !!(a && (a.group == 'pc' || Array(a.tags).include?('player_character')))
      { id: id, name: name, pc: pc }
    end
    # Stable partition: PCs first, then the rest, each keeping roster order.
    pcs, others = roster.partition { |c| c[:pc] }
    pcs + others
  end

  # Every Item Type in a Category, priced as a mundane (Tier 0) Stack.
  # Skipped: Natural attacks (Bite, claws, Unarmed — `natural: true`), which
  # are innate Creature abilities rather than ownable gear; and unique items
  # (`no_store: true`), which the DM places and are never bought or sold.
  # Neither ever appears in the Store.
  def mundane_items(category, catalog)
    catalog.item_types_in_category(category)
           .reject { |name| d = catalog.definition_of(name) || {}; d['natural'] || d['no_store'] }
           .map { |name| catalog_item(name, catalog) }
  end

  def catalog_item(name, catalog)
    price = Equipment::Pricing.unit_price(Equipment::Stack.normalize('item' => name), catalog)
    { name: name, price: price, icon: item_icon_web_path(name) }
  end

  # The four Guidance Items (Cloak of Resistance, Belts, Headband) for the
  # Magical Items section. Each carries the per-Bonus options the card's
  # `+N` dropdown offers — the catalog's parallel `guidance_bonus` / `tier`
  # arrays drive both the Tier (rule (a): the catalog array is authoritative)
  # and the live Unit Price.
  def guidance_items(catalog)
    catalog.item_types_in_category('Item').filter_map do |name|
      defn = catalog.definition_of(name) || {}
      next unless defn.key?('guidance_bonus')
      options = Array(defn['guidance_bonus']).zip(Array(defn['tier'])).map do |bonus, tier|
        stack = Equipment::Stack.normalize('item' => name, 'guidance_bonus' => bonus, 'tier' => tier)
        { bonus: bonus, tier: tier, price: Equipment::Pricing.unit_price(stack, catalog) }
      end
      { name: name, icon: item_icon_web_path(name),
        attribute: defn['guidance_attribute'], options: options }
    end
  end

  def guidance_item?(name, catalog)
    defn = catalog.definition_of(name) || {}
    defn.key?('guidance_bonus')
  end

  # The Store's "Magical Weapons" picker data + per-line validation live in
  # the pure StoreMagicWeapons module (so they're unit-testable).
  def magical_weapon_builder(catalog) = StoreMagicWeapons.builder(catalog)

  def magical_weapon_fields(item, props, tier_raw, catalog)
    StoreMagicWeapons.fields(item, props, tier_raw, catalog)
  end

  # The Store's "Magical Armor" picker data + per-line validation live in the
  # pure StoreMagicalArmor module (so they're unit-testable). Magical Armor is
  # a tiered base Armor with no Properties — the layout mirrors Magical
  # Weapons minus the Property dimension.
  def magical_armor_builder(catalog) = StoreMagicalArmor.builder(catalog)

  def magical_armor_fields(item, tier_raw, catalog)
    StoreMagicalArmor.fields(item, tier_raw, catalog)
  end

  # The catalog Tier paired with the given Bonus for a Guidance Item, or
  # nil when the Bonus is not one the item offers. Rule (a): the per-item
  # `tier` array is the source of truth (e.g. a +5 Cloak is Tier 5).
  def guidance_tier_for(name, bonus, catalog)
    return nil if bonus.nil?
    defn = catalog.definition_of(name) || {}
    idx = Array(defn['guidance_bonus']).index(bonus)
    idx && Array(defn['tier'])[idx]
  end

  # The Bonus a checkout line requests, as a positive Integer, or nil when
  # the line carries no (or a non-positive / unparseable) bonus.
  def guidance_bonus_arg(line)
    raw = line['guidance_bonus']
    return nil if raw.nil? || raw.to_s.strip.empty?
    n = (Integer(raw) rescue nil)
    n && n.positive? ? n : nil
  end

  # Web path to an Item Type's icon, or nil when no icon ships for that
  # Item. The Item Icon Map (docs/common/equipment/item_icons.yaml) is
  # consulted first; an unmapped Item falls back to the slug convention
  # (lowercased name, runs of non-alphanumerics collapsed to "_"). Either
  # way the file must exist under public/item_images/ to be returned.
  def item_slug(name)
    name.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
  end

  def item_icon_web_path(name, _seen = [])
    return nil if name.nil? || name.to_s.empty?
    key = name.to_s
    return nil if _seen.include?(key)
    exists = ->(f) { f && !f.to_s.empty? && File.exist?(File.join(settings.public_folder, 'item_images', f)) }

    # 1. Explicit Item Icon Map entry (when the mapped file ships).
    mapped = ItemIcons.map[key]
    return "/item_images/#{mapped}" if exists.call(mapped)

    # 2. Slug-convention file ("Long sword" → long_sword.svg).
    slug = item_slug(key)
    return "/item_images/#{slug}.svg" if exists.call("#{slug}.svg")

    # 3. Spell-/poison-form base icon: a Wand / Scroll / Potion / Oil / Vial of
    # <X> with no per-spell art borrows its base form's icon (every
    # "Wand of X" → wand.svg, every "Vial of X" → vial.svg).
    if (base = spell_form_base_slug(key)) && exists.call("#{base}.svg")
      return "/item_images/#{base}.svg"
    end

    # 4. Inherited base Type's icon: a Unique Item (or any `inherits_from:`
    # Type) with no icon of its own borrows the generic base's image
    # (Ring of Parry → Ring → ring.svg).
    defn   = (Equipment.catalog.definition_of(key) rescue nil)
    parent = defn && defn['inherits_from']
    return item_icon_web_path(parent, _seen + [key]) if parent && !parent.to_s.empty?

    nil
  end

  # The base slug for a spell-form / poison-form Item Type ("Wand of Entangle"
  # → "wand", "Vial of Sleep Venom" → "vial"), or nil for any other Item.
  def spell_form_base_slug(name)
    m = name.to_s.match(/\A(Wand|Scroll|Potion|Oil|Vial) of /)
    m && m[1].downcase
  end

  # Charge a Player Character for `cost`: spend its own wealth first,
  # then draw the remainder from the Party wallet. Returns false (and
  # spends nothing) when the combined wealth can't cover it.
  def charge_pc_then_party(inst, owner, cost)
    return true if cost <= 0
    from_pc   = [cost, inst.get_total_wealth(owner)].min
    remainder = cost - from_pc
    return false if remainder.positive? && remainder > inst.get_total_wealth('party')

    inst.debit_wealth(owner, from_pc)     if from_pc.positive?
    inst.debit_wealth('party', remainder) if remainder.positive?
    true
  end

  def player_character?(cid)
    a = creature_for(cid)
    !!(a && (a.group == 'pc' || Array(a.tags).include?('player_character')))
  end

  def creature_name(cid)
    creature_for(cid)&.name || "Creature #{cid}"
  end

  def creature_for(cid)
    Creatures.lookup(Integer(cid)) rescue (Creatures.lookup(cid) rescue nil)
  end

  # A checkout line's `gift` flag, tolerant of JSON's true / "true" / 1.
  def truthy(v)
    v == true || v.to_s == 'true' || v.to_s == '1'
  end

  # Gold is integer-valued by convention; fractional prices show two
  # decimals, trimming a trailing ".00".
  def store_fmt_price(n)
    return n.to_s if n.is_a?(Integer)
    n == n.to_i ? n.to_i.to_s : format('%.2f', n)
  end
end
