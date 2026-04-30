require 'yaml'

# Equipment — sole owner of inventory data.
#
# This first cut covers the MVP shape: per-owner inventories, the four
# Owner kinds, Stack Identity / Merge / Cleanup, item add / remove /
# adjust / transfer, item-definition lookup across the catalog
# sections, per-category Unit Price formulas (Weapon, Armor, Ammunition,
# Consumable, Guidance, Currency, Gem) including Tier Surcharge
# overrides and the Innately Usable multiplier, Total Wealth and
# Debit Wealth (cheapest-first), and the three detail-fetchers.
#
# Loot tables, magical-item generation, shops with refresh, the Game
# Day counter, atomic Restock, and the Loot Archive are deferred to
# follow-up commits — see docs/TODO.md.
class Equipment
  STACK_IDENTITY_FIELDS = %w[
    item_type tier properties stored_spell durability_damage name equipped value_in_gold guidance_bonus
  ].freeze

  ITEM_CATEGORIES = %w[Weapon Armor Ammunition Currency Gem Item Consumable].freeze

  attr_reader :inventories, :equipment_config

  def initialize(config_path:)
    @equipment_config = YAML.load_file(config_path) || {}
    @inventories = {}
  end

  # ---------- Inventory ops ---------------------------------------

  def get_inventory(owner_id)
    Array(@inventories[owner_id.to_s]).map(&:dup)
  end

  def add_item(owner_id, stack)
    owner = owner_id.to_s
    @inventories[owner] ||= []
    incoming = normalize_stack(stack)
    if (idx = find_matching_stack_index(@inventories[owner], incoming))
      @inventories[owner][idx]['quantity'] = @inventories[owner][idx]['quantity'].to_f + incoming['quantity'].to_f
    else
      @inventories[owner] << incoming
    end
    incoming
  end

  def remove_item(owner_id, stack_index)
    owner = owner_id.to_s
    return nil unless @inventories[owner]
    @inventories[owner].delete_at(stack_index)
  end

  def adjust_stack_quantity(owner_id, stack_index, delta)
    owner = owner_id.to_s
    stack = @inventories.dig(owner, stack_index)
    return nil unless stack
    stack['quantity'] = stack['quantity'].to_f + delta.to_f
    stack
  end

  def transfer_item(from_owner, stack_index, to_owner, quantity)
    src = @inventories.dig(from_owner.to_s, stack_index)
    return nil unless src
    quantity = [quantity.to_f, src['quantity'].to_f].min
    return nil if quantity <= 0
    src['quantity'] = src['quantity'].to_f - quantity
    transferred = src.dup
    transferred['quantity'] = quantity
    add_item(to_owner, transferred)
    cleanup_zero_quantity(from_owner)
    transferred
  end

  def cleanup_zero_quantity(owner_id)
    owner = owner_id.to_s
    return unless @inventories[owner]
    @inventories[owner] = @inventories[owner].reject { |s| s['quantity'].to_f <= 0 }
  end

  # ---------- Stack identity / merge ------------------------------

  def stack_identity_tuple(stack)
    STACK_IDENTITY_FIELDS.map { |f| stack[f] }
  end

  def stacks_match?(a, b)
    stack_identity_tuple(a) == stack_identity_tuple(b)
  end

  def find_matching_stack_index(inventory, stack)
    inventory.find_index { |s| stacks_match?(s, stack) }
  end

  def merge_inventory_stacks(stacks)
    stacks.each_with_object([]) do |stack, out|
      idx = find_matching_stack_index(out, stack)
      if idx
        out[idx] = out[idx].dup
        out[idx]['quantity'] = out[idx]['quantity'].to_f + stack['quantity'].to_f
      else
        out << stack.dup
      end
    end
  end

  # ---------- Item definitions ------------------------------------

  def item_definition(item_type)
    %w[Currency Weapons Armor Ammunition Items].each do |section|
      section_data = @equipment_config[section] || {}
      return section_data[item_type] if section_data.is_a?(Hash) && section_data.key?(item_type)
    end
    return { 'category' => 'Gem' } if item_type == 'Gem'
    nil
  end

  def category_for(item_type)
    return 'Currency'  if (@equipment_config['Currency']    || {}).key?(item_type)
    return 'Weapon'    if (@equipment_config['Weapons']     || {}).key?(item_type)
    return 'Armor'     if (@equipment_config['Armor']       || {}).key?(item_type)
    return 'Ammunition' if (@equipment_config['Ammunition'] || {}).key?(item_type)
    return 'Gem'       if item_type == 'Gem'
    if (item = (@equipment_config['Items'] || {})[item_type])
      return item['category'] || 'Item'
    end
    nil
  end

  # ---------- Pricing --------------------------------------------

  def property_cost(category, property_name, subtype = nil)
    section = category == 'Armor' ? 'Armor Properties' : 'Weapon Properties'
    properties = @equipment_config[section] || {}
    prop = properties[property_name]
    return 0 unless prop
    cost = prop['cost'] || 0
    return cost.to_f unless subtype
    sub_costs = prop['subtype_costs'] || {}
    (sub_costs[subtype] || cost).to_f
  end

  def tier_surcharge_for(item_type, tier)
    return 0 if tier.to_i <= 0
    definition = item_definition(item_type) || {}
    if definition['tier_surcharge']
      return (definition['tier_surcharge'][tier] || definition['tier_surcharge'][tier.to_s] || 0).to_f
    end
    defaults = (@equipment_config.dig('Tier Pricing', 'default_tier_surcharges') || {})
    (defaults[tier] || defaults[tier.to_s] || 0).to_f
  end

  def default_bonus_surcharge(bonus)
    table = (@equipment_config.dig('Tier Pricing', 'default_bonus_surcharges') || {})
    (table[bonus] || table[bonus.to_s] || 0).to_f
  end

  def innately_usable_multiplier
    (@equipment_config.dig('Tier Pricing', 'innately_usable_price_multiplier') || 1.0).to_f
  end

  def ammunition_divisor
    (@equipment_config.dig('Tier Pricing', 'ammunition_divisor') || 100).to_f
  end

  def consumable_divisor
    (@equipment_config.dig('Tier Pricing', 'consumable_divisor') || 10).to_f
  end

  def item_unit_price(stack)
    item_type = stack['item_type']
    tier = stack['tier'].to_i
    properties = Array(stack['properties'])
    category = category_for(item_type) || 'Item'
    definition = item_definition(item_type) || {}
    base_price = (definition['base_price'] || 0).to_f
    surcharge = tier_surcharge_for(item_type, tier)
    property_cost_total = properties.sum do |prop|
      property_cost(category, prop.is_a?(Hash) ? prop['name'] : prop, prop.is_a?(Hash) ? prop['subtype'] : nil)
    end

    price =
      case category
      when 'Currency'
        (definition['value_in_gold'] || 0).to_f * stack['quantity'].to_f
      when 'Gem'
        (stack['value_in_gold'] || 0).to_f
      when 'Ammunition'
        bundle = (definition['bundle_size'] || 1).to_f
        (base_price / bundle) + ((surcharge + property_cost_total) / ammunition_divisor)
      when 'Consumable'
        base_price + ((surcharge + property_cost_total) / consumable_divisor)
      else
        if definition['guidance_bonus']
          # Guidance items: Default Tier Surcharge[Tier] + Default Bonus Surcharge[Bonus]
          tier_term = tier_surcharge_for(item_type, tier)
          bonus_term = default_bonus_surcharge(stack['guidance_bonus'].to_i)
          tier_term + bonus_term
        else
          base_price + surcharge + property_cost_total
        end
      end

    price *= innately_usable_multiplier if definition['innately_usable']
    price
  end

  # ---------- Wealth ---------------------------------------------

  def total_wealth_in_gold(owner_id)
    Array(@inventories[owner_id.to_s]).sum do |stack|
      cat = category_for(stack['item_type'])
      next 0 unless cat == 'Currency' || cat == 'Gem'
      value = (cat == 'Currency') ?
        (item_definition(stack['item_type'])['value_in_gold'] || 0).to_f :
        (stack['value_in_gold'] || 0).to_f
      value * stack['quantity'].to_f
    end
  end

  def can_afford?(owner_id, amount)
    total_wealth_in_gold(owner_id) + 1e-9 >= amount.to_f
  end

  def debit_wealth(owner_id, amount)
    raise ArgumentError, 'amount must be positive' if amount.to_f <= 0
    raise ArgumentError, 'insufficient wealth' unless can_afford?(owner_id, amount)
    owner = owner_id.to_s
    remaining = amount.to_f
    spend_log = []

    # Coins cheapest-first.
    currency_order = (@equipment_config['Currency'] || {}).sort_by { |_, c| c['value_in_gold'].to_f }
    currency_order.each do |item_type, currency_def|
      next if remaining <= 0
      stack = @inventories[owner]&.find { |s| s['item_type'] == item_type }
      next unless stack
      value = currency_def['value_in_gold'].to_f
      max_units = (remaining / value)
      units_to_spend = [stack['quantity'].to_f, max_units].min
      next if units_to_spend <= 0
      stack['quantity'] -= units_to_spend
      remaining -= units_to_spend * value
      spend_log << { 'item_type' => item_type, 'units' => units_to_spend, 'value' => value }
    end

    # Then gems, cheapest-first.
    if remaining > 0
      gem_stacks = Array(@inventories[owner]).select { |s| s['item_type'] == 'Gem' }
                                              .sort_by { |s| s['value_in_gold'].to_f }
      gem_stacks.each do |stack|
        break if remaining <= 0
        value = stack['value_in_gold'].to_f
        next if value <= 0
        # Spend whole gems, refunding overpayment as Gold.
        gems_needed = (remaining / value).ceil
        gems_to_spend = [stack['quantity'].to_f, gems_needed].min
        next if gems_to_spend <= 0
        stack['quantity'] -= gems_to_spend
        spent_value = gems_to_spend * value
        spend_log << { 'item_type' => 'Gem', 'units' => gems_to_spend, 'value' => value }
        if spent_value > remaining
          # Overpayment refund in Gold.
          refund = spent_value - remaining
          credit_wealth(owner, refund)
          remaining = 0
        else
          remaining -= spent_value
        end
      end
    end

    cleanup_zero_quantity(owner)
    spend_log
  end

  def credit_wealth(owner_id, amount)
    return if amount.to_f <= 0
    add_item(owner_id, { 'item_type' => 'Gold', 'quantity' => amount.to_f })
  end

  # ---------- Detail fetchers --------------------------------------

  def get_item_details(stack)
    category = category_for(stack['item_type'])
    {
      'item_type'         => stack['item_type'],
      'category'          => category,
      'definition'        => item_definition(stack['item_type']),
      'tier'              => stack['tier'].to_i,
      'properties'        => Array(stack['properties']),
      'equipped'          => stack['equipped'] == true,
      'durability_damage' => stack['durability_damage'].to_i,
      'display_name'      => display_name(stack),
      'unit_price'        => item_unit_price(stack),
      'slot'              => (item_definition(stack['item_type']) || {})['slot'],
      'value_in_gold'     => stack['value_in_gold'] || (item_definition(stack['item_type']) || {})['value_in_gold'],
      'guidance_bonus'    => stack['guidance_bonus'],
      'guidance_attribute' => (item_definition(stack['item_type']) || {})['guidance_attribute']
    }
  end

  def get_weapon_details(stack)
    raise ArgumentError, 'Not a weapon' unless category_for(stack['item_type']) == 'Weapon'
    base = get_item_details(stack)
    definition = base['definition'] || {}
    tags = Array(definition['tags'])
    base.merge(
      'damage_formula' => definition['damage_formula'] || resolve_tag_damage(tags) || category_default_damage(definition),
      'damage_types'   => Array(definition['damage_types'] || ['physical']),
      'tags'           => tags,
      'bleed'          => definition['bleed'],
      'threshold'      => definition['threshold'],
      'ammo_type'      => definition['ammo_type']
    )
  end

  def get_armor_details(stack)
    raise ArgumentError, 'Not armor' unless category_for(stack['item_type']) == 'Armor'
    base = get_item_details(stack)
    definition = base['definition'] || {}
    material = definition['material']
    materials = @equipment_config['Materials'] || {}
    material_def = material ? materials[material] : nil
    base_hardness = (material_def && material_def['hardness'].to_i) || (definition['hardness'].to_i)
    tier = stack['tier'].to_i
    resilience_increment = (definition['resilience_increment'] || 0).to_i
    base.merge(
      'damage_reduction'    => definition['damage_reduction'],
      'material'            => material,
      'base_hardness'       => base_hardness,
      'effective_hardness'  => base_hardness + 2 * tier,
      'hit_points_formula'  => material_def && material_def['hit_points_formula'] || definition['hit_points_formula'],
      'thickness'           => definition['thickness'],
      'resilience_increment' => resilience_increment,
      'computed_resilience' => tier * resilience_increment
    )
  end

  def display_name(stack)
    return stack['name'] if stack['name'] && !stack['name'].empty?
    item_type = stack['item_type']
    tier = stack['tier'].to_i
    naming = @equipment_config['Naming Convention'] || {}
    hidden_for = Array(naming['tier_hidden_for'])
    category = category_for(item_type)
    parts = []
    if tier >= 1 && !hidden_for.include?(category) && !hidden_for.include?(item_type)
      tier_format = naming['tier_prefix_format'] || '+{tier}'
      parts << tier_format.gsub('{tier}', tier.to_s)
    end
    property_displays = Array(stack['properties']).map do |prop|
      property_display(category, prop)
    end.compact
    prefixes = property_displays.select { |d| d['position'] == 'prefix' }.map { |d| d['word'] }
    suffixes = property_displays.select { |d| d['position'] == 'suffix' }.map { |d| d['word'] }
    parts.concat(prefixes)
    parts << item_type
    parts.concat(suffixes)
    parts.join(' ')
  end

  # ---------- Equip-time wiring -----------------------------------

  # Returns the deterministic source-id namespace prefix for a
  # Character. Equipment is the sole writer to source IDs starting
  # with this prefix; conditions.remove_effects_by_prefix(prefix)
  # cleans them all out for a loadout swap.
  def equipment_source_prefix(owner_id)
    "equipment:#{owner_id}:"
  end

  def equipment_source_id(owner_id, stable_stack_key)
    "#{equipment_source_prefix(owner_id)}#{stable_stack_key}"
  end

  private

  def normalize_stack(stack)
    s = stack.dup
    s['quantity'] = (s['quantity'] || 1).to_f
    s['tier'] = (s['tier'] || 0).to_i
    s['durability_damage'] = (s['durability_damage'] || 0).to_i
    s['properties'] ||= []
    s
  end

  def category_default_damage(definition)
    cat = (definition['category'] || '').to_s
    table = @equipment_config['Weapon Categories'] || {}
    (table[cat] || {})['damage_formula']
  end

  def resolve_tag_damage(tags)
    table = @equipment_config['Weapon Tags'] || {}
    tags.each do |tag|
      tag_def = table[tag]
      next unless tag_def && tag_def['damage_formula']
      return tag_def['damage_formula']
    end
    nil
  end

  def property_display(category, prop)
    section = category == 'Armor' ? 'Armor Properties' : 'Weapon Properties'
    properties = @equipment_config[section] || {}
    name = prop.is_a?(Hash) ? prop['name'] : prop
    subtype = prop.is_a?(Hash) ? prop['subtype'] : nil
    definition = properties[name]
    return nil unless definition
    display = definition['display']
    display = display[subtype] if subtype && display.is_a?(Hash) && display.key?(subtype)
    return nil unless display.is_a?(Hash)
    naming = @equipment_config['Naming Convention'] || {}
    {
      'word'     => display['word'],
      'position' => display['position'] || naming['default_property_position'] || 'prefix'
    }
  end
end
