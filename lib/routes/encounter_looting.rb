# Encounter looting helpers: post-combat loot rows and the ground loot pile.
# Extracted from routes/encounter.rb. Sinatra accumulates `helpers do` blocks
# across files, so these mix into the same app instance as the rest.
helpers do
  def loot_pile_location
    id = Atlas.state.active_map_id
    id.nil? ? 'loot' : "map_#{id}"
  end

  def combat_pile_owner
    "ground:#{loot_pile_location}"
  end

  def post_combat_rows
    cat  = Equipment.catalog
    inst = Equipment.instance
    rows = encounter_state.combatants.filter_map do |c|
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next unless acc
      next if Array(acc.tags).include?('player_character')
      inv = inst.get_inventory("creature:#{c[:creature_id]}")
      { combatant_id: c[:id],
        creature_id:  c[:creature_id],
        name:         tracker_name(c),
        npc:          ((acc.group rescue nil).to_s == 'npc'),
        loot_table:   acc.record[:loot_table],
        loot:         inv.map { |s| { name: CreatureSheet.item_display_name(s, cat), quantity: s.quantity } } }
    end
    rows.sort_by.with_index { |r, i| [r[:npc] ? 0 : 1, i] }
  end

  def combine_loot(rows)
    totals = {}
    order  = []
    rows.each do |r|
      r[:loot].each do |it|
        order << it[:name] unless totals.key?(it[:name])
        totals[it[:name]] = totals.fetch(it[:name], 0) + it[:quantity]
      end
    end
    { items:  order.map { |n| { name: n, quantity: totals[n] } },
      random: rows.any? { |r| r[:loot_table] } }
  end

  def loot_pile_view(pile_owner_id)
    return nil if pile_owner_id.nil?
    inst  = Equipment.instance
    stacks = inst.get_inventory(pile_owner_id)
    return nil if stacks.nil? || stacks.empty?
    cat = Equipment.catalog
    rows = stacks.each_with_index.map do |stack, i|
      { ref:      i,
        name:     CreatureSheet.item_display_name(stack, cat),
        icon:     item_icon_web_path(stack.item_type),
        quantity: stack.quantity }
    end
    { owner_id: pile_owner_id, rows: rows }
  end

  def combat_creature_options
    seen = {}
    encounter_state.combatants.each do |c|
      next if seen.key?(c[:creature_id])
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next unless acc
      seen[c[:creature_id]] = acc.name
    end
    seen.map { |id, name| { id: id, name: name } }
  end

  def combat_creature?(creature_id)
    combat_creature_options.any? { |c| c[:id].to_s == creature_id.to_s }
  end

  def encounter_row_snapshot(creature_id)
    {
      creature_id: creature_id.to_s,
      copy_count:  encounter_state.copy_count(creature_id),
      in_combat:   encounter_state.includes_creature?(creature_id),
      pc_excluded: encounter_state.pc_excluded?(creature_id)
    }
  end
end
