# Creature inventory management — the Inventory stub under a Character
# Sheet (docs/common/ui/equipment_inventory_stub.md).
#
# The stub is keyed to the Creature shown on the Character Sheets page and
# only appears for a real Creature (PC / NPC / spawned instance) — never
# for an enemy_template stat block. Three sections:
#   Equipped  — equipped Stacks; Unequip each.
#   Inventory — unequipped Stacks; Equip (if equippable) or Discard to the
#               Sell Pile.
#   Sell Pile — the shared Party Inventory (unclaimed items); Claim to the
#               shown Creature, or Equip (claim one + equip).
#
# Every viewer may use it (answer 3). Each action is a form POST that
# mutates through the Equipment domain and redirects back to the sheet.
# Endpoints (DM + Player):
#   POST /inventory/equip        — equip an unequipped Stack
#   POST /inventory/unequip      — unequip an equipped Stack
#   POST /inventory/discard      — move qty from the Creature to the Party
#   POST /inventory/claim        — move qty from the Party to the Creature
#   POST /inventory/claim_equip  — move one from the Party and equip it

helpers do
  # A template (an enemy_template stat block) — never a concrete character.
  # The enemy_template tag is the template marker, but group is authoritative:
  # a promoted NPC keeps group 'npc' even if a stray enemy_template tag lingers
  # from before promotion, and is not a template.
  def creature_template?(rec)
    return false if %w[npc pc].include?(rec[:group].to_s)
    Array(rec[:tags]).include?('enemy_template')
  end

  # A Creature whose inventory may be managed: it exists and is not a
  # template stat block (templates are shared and have no real inventory).
  def manageable_creature?(id)
    a = Creatures.lookup(id) rescue nil
    !!(a && !creature_template?(a.record))
  end

  # The spawn-time Roll Tables declared on a template, for the roll-tables
  # stub shown above the sheet. Returns nil for anything that is not a
  # template — a Player, an NPC, or a spawned instance — even if it retains
  # vestigial table fields (e.g. equipment_table kept on a spawn for loadout
  # rolls). Each table is the record's own normalized shape; the equipment
  # loadout is expanded into readable rows.
  def roll_tables_data(id)
    rec = (Creatures.lookup(id).record rescue nil) or return nil
    return nil unless creature_template?(rec)
    data = {}
    data[:equipment]        = equipment_loadout_summary(rec[:equipment_table]) if rec[:equipment_table]
    data[:race]             = rec[:race_table]   unless Array(rec[:race_table]).empty?
    data[:classes]          = rec[:class_table]  unless Array(rec[:class_table]).empty?
    data[:skills]           = Array(rec[:skill_table])
    data.delete(:skills) if data[:skills].empty?
    data[:tier_advancement] = rec[:tier_advancement_table] if rec[:tier_advancement_table]
    data.empty? ? nil : data
  end

  # Flatten an Equipment Loot Table into displayable rows: each row lists
  # the item(s) it can grant, with per-option chances, the gating `when`,
  # and whether the result is equipped. Option lists referenced by name
  # are resolved. Returns { id:, rows: [...] }, or nil for an unknown id.
  def equipment_loadout_summary(table_id)
    lt    = (Equipment::LootTables.load rescue nil) or return { id: table_id, rows: [] }
    table = lt.table(table_id) or return { id: table_id, rows: [] }
    rows = Array(table['rolls']).map do |row|
      opts = row['options']
      items =
        if opts.is_a?(String)
          Array(lt.option_list(opts)).map { |o| { name: o.dig('item', 'item'), chance: o['chance'] } }
        elsif opts.is_a?(Array)
          opts.map { |o| { name: o.dig('item', 'item'), chance: o['chance'] } }
        elsif row['item']
          [{ name: row.dig('item', 'item'), qty: row.dig('item', 'quantity') }]
        else
          []
        end
      { equipped: row['equipped'], when: row['when'], chance: row['chance'],
        items: items.reject { |i| i[:name].to_s.empty? } }
    end
    { id: table_id, rows: rows }
  end

  # Equippable: every Weapon and Armor, plus an Item only when it
  # declares an equipment Slot. Items without a Slot (Rations, Bedroll,
  # Whetstone) are carried but not worn/wielded; Consumables, Ammunition,
  # Currency, and Gems are never equippable.
  def item_equippable?(item_type, catalog = Equipment.catalog)
    defn = catalog.definition_of(item_type) || {}
    case catalog.category_of(item_type)
    when 'Weapon', 'Armor' then true
    # Ritual books and other inscribable books are carried for their
    # inscribed Ritual list, not worn — never equippable.
    when 'Item'            then !defn['inscribable'] && !defn['slot'].to_s.empty?
    else false
    end
  end

  # The inscribed Ritual names for a Stack (an inscribable book), resolved
  # to display names, or nil for a non-book Stack. Empty list = an empty
  # book. Used to render the "(N rituals)" count and the click-to-open
  # list in the inventory stub.
  def inscribed_ritual_names(stack, catalog = Equipment.catalog)
    defn = catalog.definition_of(stack.item_type) || {}
    return nil unless defn['inscribable']
    Array(stack.inscribed_spells).map { |key| ritual_display_name(key) }
  end

  # A spell key (often snake_case) resolved to its catalog display name,
  # falling back to a Title-cased form, then the raw key.
  def ritual_display_name(key)
    title = key.to_s.split(/[_\s]+/).map(&:capitalize).join(' ')
    entry = (Abilities.catalog.ability(title) || Abilities.catalog.ability(key.to_s) rescue nil)
    entry ? title : (title.empty? ? key.to_s : title)
  rescue StandardError
    key.to_s
  end

  # Build the three sections the inventory stub renders for one Creature.
  # Each row carries the Stack's index in its owner Inventory (the ref the
  # action forms submit) plus display fields.
  def inventory_stub_data(creature_id)
    cat   = Equipment.catalog
    inst  = Equipment.instance
    owner = "creature:#{creature_id}"

    creature_rows = inst.get_inventory(owner).each_with_index.map do |s, i|
      inventory_row(s, i, cat)
    end
    party_rows = inst.get_inventory('party').each_with_index.map do |s, i|
      inventory_row(s, i, cat)
    end

    # Only equippable items belong in the Equipped section. A stored
    # `equipped: true` on a non-equippable Stack (e.g. a Ritual book left
    # over in a persisted data file) is shown as carried, not equipped.
    shown_equipped = ->(r) { r[:equipped] && r[:equippable] }

    {
      creature_id: creature_id,
      equipped:    creature_rows.select { |r| shown_equipped.call(r) },
      inventory:   creature_rows.reject { |r| shown_equipped.call(r) },
      sell:        party_rows
    }
  end

  def inventory_row(stack, index, catalog = Equipment.catalog)
    {
      index:      index,
      name:       (CreatureSheet.item_display_name(stack, catalog) rescue Equipment::DisplayName.call(stack, catalog)),
      icon:       item_icon_web_path(stack.item_type),
      category:   catalog.category_of(stack.item_type),
      quantity:   stack.quantity,
      equipped:   stack.equipped,
      equippable: item_equippable?(stack.item_type, catalog),
      rituals:    inscribed_ritual_names(stack, catalog)
    }
  end

  # Redirect target after an inventory mutation: back to the acting
  # Creature's sheet, preserving the detail mode.
  def inventory_redirect(creature_id, detail)
    d = detail == 'full' ? 'full' : 'minimal'
    "/character-sheets?creature_id=#{creature_id}&detail=#{d}"
  end

  # Parsed, clamped move quantity for discard / claim. Defaults to the
  # whole stack when absent; clamped to [1, available].
  def inventory_quantity(param, available)
    n = (Integer(param) rescue available)
    n = available if n > available
    n < 1 ? 1 : n
  end

  # Like inventory_quantity but does NOT clamp to what is available: the loot
  # pile's Give lets the DM hand out more than the pile holds. Defaults to the
  # available amount when the field is blank/invalid; minimum 1.
  def loot_give_quantity(param, available)
    n = (Integer(param) rescue available)
    n < 1 ? 1 : n
  end
end

post '/inventory/equip' do
  cid = params[:creature_id].to_s
  if manageable_creature?(cid)
    inst  = Equipment.instance
    owner = "creature:#{cid}"
    stack = inst.get_inventory(owner)[params[:index].to_i]
    # The Equipment domain treats any Item as equippable; this stub
    # additionally requires an Item to declare a Slot (Rations / Bedroll /
    # Whetstone have none and stay carried).
    inst.equip_stack(owner, params[:index].to_i) if stack && item_equippable?(stack.item_type)
  end
  redirect inventory_redirect(cid, params[:detail])
end

post '/inventory/unequip' do
  cid = params[:creature_id].to_s
  if manageable_creature?(cid)
    Equipment.instance.unequip_stack("creature:#{cid}", params[:index].to_i)
  end
  redirect inventory_redirect(cid, params[:detail])
end

post '/inventory/discard' do
  cid = params[:creature_id].to_s
  if manageable_creature?(cid)
    inst  = Equipment.instance
    owner = "creature:#{cid}"
    idx   = params[:index].to_i
    stack = inst.get_inventory(owner)[idx]
    if stack
      qty = inventory_quantity(params[:quantity], stack.quantity)
      inst.transfer_stack(owner, 'party', idx, quantity: qty)
      inst.cleanup(owner)
    end
  end
  redirect inventory_redirect(cid, params[:detail])
end

post '/inventory/claim' do
  cid = params[:creature_id].to_s
  if manageable_creature?(cid)
    inst  = Equipment.instance
    idx   = params[:index].to_i
    stack = inst.get_inventory('party')[idx]
    if stack
      qty = inventory_quantity(params[:quantity], stack.quantity)
      inst.transfer_stack('party', "creature:#{cid}", idx, quantity: qty)
      inst.cleanup('party')
    end
  end
  redirect inventory_redirect(cid, params[:detail])
end

# Claim a single copy from the Sell Pile and equip it on the Creature.
post '/inventory/claim_equip' do
  cid = params[:creature_id].to_s
  if manageable_creature?(cid)
    inst  = Equipment.instance
    owner = "creature:#{cid}"
    idx   = params[:index].to_i
    stack = inst.get_inventory('party')[idx]
    if stack && item_equippable?(stack.item_type)
      dest = inst.transfer_stack('party', owner, idx, quantity: 1)
      inst.cleanup('party')
      inst.equip_stack(owner, dest) unless Equipment.error?(dest)
    end
  end
  redirect inventory_redirect(cid, params[:detail])
end
