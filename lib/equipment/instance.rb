module Equipment
  # Pairs the Catalog + Store with the injected sibling-domain
  # collaborators (Conditions, Combat, Abilities, and the Creature
  # accessor) and exposes the public entry points documented in
  # equipment_design.md. Operations mutate Owner Inventories in place
  # and write the reconciled list back to the Owner's storage.
  #
  # Collaborators are optional; when absent the cross-domain calls are
  # skipped (inventory-only behavior). Tests inject recorded-call stubs.
  class Instance
    include Magical
    include LootRolling
    include CombatLoot
    include Archive
    include Consumption
    include Shops

    attr_reader :catalog, :store, :rng

    attr_reader :game_day

    def initialize(catalog: Catalog.load, store: Store.new, creature_accessor: nil,
                   conditions: nil, combat: nil, abilities: nil, creatures: nil,
                   loot: nil, shops: {}, generic_shops: nil, game_day: 0, rng: Random.new)
      @catalog = catalog
      @store = store
      @creature_accessor = creature_accessor
      @conditions = conditions
      @combat = combat
      @abilities = abilities
      @creatures = creatures
      @loot = loot
      @shops = shops
      @generic_shops = generic_shops
      @game_day = game_day
      @rng = rng
      @archives = {}
      @archive_seq = 0
      @active_generic = {}
    end

    # ===== Restock =====
    def restock(owner_id)
      inv = read_inventory(owner_id)
      understocked = inv.select { |s| s.restock_target && s.quantity < s.restock_target }
      cost = understocked.sum { |s| (s.restock_target - s.quantity) * Pricing.unit_price(s, @catalog) }
      return ERROR if to_r(cost) > total_wealth_r(owner_id)

      debit_wealth(owner_id, cost) if cost > 0
      inv = read_inventory(owner_id)
      inv.each { |s| s.quantity = s.restock_target if s.restock_target && s.quantity < s.restock_target }
      write_inventory(owner_id, inv)
      cost
    end

    def loot_archive(id)
      @archives[id]
    end

    def loot
      @loot ||= LootTables.load
    end

    # ===== Get Inventory =====
    def get_inventory(owner_id)
      read_inventory(owner_id)
    end

    # ===== Add Item =====
    def add_item(owner_id, stack)
      stack = hydrate(Stack.normalize(stack))
      inv = read_inventory(owner_id)
      existing = inv.find { |s| s.same_identity?(stack) }
      result =
        if existing
          existing.merge!(stack)
        else
          inv << stack
          stack
        end
      write_inventory(owner_id, inv)
      result
    end

    # ===== Remove Item =====
    def remove_item(owner_id, ref, quantity: nil)
      inv = read_inventory(owner_id)
      idx = resolve_index(inv, ref)
      return ERROR unless idx
      stack = inv[idx]
      qty = quantity.nil? ? stack.quantity : quantity
      return ERROR if qty < 0 || qty > stack.quantity
      stack.quantity -= qty
      write_inventory(owner_id, inv)
      stack.quantity
    end

    # ===== Adjust Stack Quantity =====
    def adjust_stack_quantity(owner_id, ref, new_quantity)
      return ERROR if new_quantity < 0
      inv = read_inventory(owner_id)
      idx = resolve_index(inv, ref)
      return ERROR unless idx
      inv[idx].quantity = new_quantity
      write_inventory(owner_id, inv)
      new_quantity
    end

    # ===== Transfer Stack =====
    def transfer_stack(from_owner_id, to_owner_id, ref, quantity: nil)
      inv = read_inventory(from_owner_id)
      idx = resolve_index(inv, ref)
      return ERROR unless idx
      stack = inv[idx]
      qty = quantity.nil? ? stack.quantity : quantity
      return ERROR if qty <= 0 || qty > stack.quantity

      moved = stack.with_quantity(qty)
      stack.quantity -= qty
      write_inventory(from_owner_id, inv)
      add_item(to_owner_id, moved)
    end

    # ===== Cleanup =====
    def cleanup(owner_id)
      inv = read_inventory(owner_id)
      kept = inv.reject { |s| s.quantity <= 0 && s.restock_target.nil? }
      if kept.empty? && ground_owner?(owner_id) && @store.exists?(owner_id)
        @store.delete(owner_id)
      else
        write_inventory(owner_id, kept)
      end
      kept
    end

    # ===== Equip / Unequip =====
    def equip_stack(owner_id, ref)   ; set_equipped(owner_id, ref, true)  ; end
    def unequip_stack(owner_id, ref) ; set_equipped(owner_id, ref, false) ; end

    # ===== Reconcile Loadout =====
    def reconcile_loadout(owner_id)
      prefix = "equipment:#{owner_id}:"
      @conditions&.remove_effects_by_prefix(prefix)
      posted = []
      weapon_counts = Hash.new(0)

      read_inventory(owner_id).each do |stack|
        next unless stack.equipped
        category = @catalog.category_of(stack.item_type)
        index = 0
        if category == 'Weapon'
          index = weapon_counts[stack.item_type]
          weapon_counts[stack.item_type] += 1
        end
        key = stable_stack_key(stack, category, index)
        effects = stack_effects(stack)
        base = "equipment:#{owner_id}:#{key}"
        effects.each_with_index do |eff, i|
          sid = effects.size > 1 ? "#{base}:#{i}" : base
          @conditions&.apply_effect(eff.merge(source_id: sid))
          posted << sid
        end
      end
      posted
    end

    # The Active Effects every equipped Stack would post (Guidance Bonus +
    # Property effects), without touching Conditions. Lets read-only
    # consumers (the character sheet, modifier aggregation) see a
    # Creature's equipped Guidance / Property bonuses regardless of
    # whether the loadout has been reconciled into Conditions this
    # session. Returns a list of { target_key:, bonus_type:, amount:, ... }.
    def equipped_effects(owner_id)
      read_inventory(owner_id).select(&:equipped).flat_map { |s| stack_effects(s) }
    rescue StandardError
      []
    end

    # ===== Detail-fetchers =====
    def get_item_details(arg, ref = nil)
      stack = resolve_stack(arg, ref) or return ERROR
      Details.item_details(stack, @catalog)
    end

    def get_weapon_details(arg, ref = nil)
      stack = resolve_stack(arg, ref) or return ERROR
      Details.weapon_details(stack, @catalog)
    end

    def get_armor_details(arg, ref = nil)
      stack = resolve_stack(arg, ref) or return ERROR
      Details.armor_details(stack, @catalog)
    end

    # ===== Is Item-Only? =====
    def is_item_only?(spell_name)
      return false unless @abilities.respond_to?(:item_only?)
      !!@abilities.item_only?(spell_name)
    end

    # ===== Total Wealth / Debit Wealth =====
    def get_total_wealth(owner_id)
      from_r(total_wealth_r(owner_id))
    end

    def debit_wealth(owner_id, amount)
      return ERROR if amount < 0
      amount_r = to_r(amount)
      return 0 if amount_r.zero?
      return ERROR if amount_r > total_wealth_r(owner_id)

      inv = read_inventory(owner_id)
      remaining = amount_r

      inv.select { |s| currency?(s) }.sort_by { |s| value_r(s) }.each do |s|
        break if remaining <= 0
        v = value_r(s)
        next if v <= 0
        qty = to_r(s.quantity)
        spend = [remaining / v, qty].min
        s.quantity = from_r(qty - spend)
        remaining -= spend * v
      end

      if remaining > 0
        inv.select { |s| gem?(s) }.sort_by { |s| value_r(s) }.each do |g|
          v = value_r(g)
          while g.quantity > 0 && remaining > 0
            g.quantity -= 1
            remaining -= v
          end
          break if remaining <= 0
        end
      end

      overpay = remaining < 0 ? -remaining : Rational(0)
      write_inventory(owner_id, inv)

      refund = from_r(overpay)
      add_item(owner_id, Stack.normalize('item' => 'Gold', 'quantity' => refund)) if overpay > 0
      refund
    end

    private

    # ---- Owner routing -------------------------------------------------

    def creature_owner?(owner_id)
      owner_id.start_with?('creature:', 'character:')
    end

    def ground_owner?(owner_id)
      owner_id.start_with?('ground:')
    end

    def creature_id(owner_id)
      owner_id.split(':', 2).last
    end

    def read_inventory(owner_id)
      if creature_owner?(owner_id)
        return [] unless @creature_accessor
        Array(@creature_accessor.get_inventory(creature_id(owner_id))).map { |s| Stack.normalize(s) }
      else
        @store.inventory(owner_id) || []
      end
    end

    def write_inventory(owner_id, stacks)
      if creature_owner?(owner_id)
        @creature_accessor&.set_inventory(creature_id(owner_id), stacks)
      else
        @store.set_inventory(owner_id, stacks, default_source_file(owner_id))
      end
      stacks
    end

    def default_source_file(owner_id)
      case owner_id
      when /\Aground:/        then 'loot.yaml'
      when /\A(generic_)?shop:/ then 'shops.yaml'
      else 'equipment_data.yaml'
      end
    end

    # ---- Stack reference resolution ------------------------------------

    def resolve_index(inv, ref)
      if ref.is_a?(Integer)
        ref.between?(0, inv.size - 1) ? ref : nil
      else
        target = Stack.normalize(ref)
        inv.find_index { |s| s.same_identity?(target) }
      end
    end

    def resolve_stack(arg, ref)
      if ref.nil? && arg.is_a?(Stack)
        arg
      else
        inv = read_inventory(arg)
        idx = resolve_index(inv, ref)
        idx && inv[idx]
      end
    end

    # Fill any nil Property `cost` from the catalog so identity and
    # pricing are stable for the lifetime of the Stack.
    def hydrate(stack)
      stack.properties.each do |p|
        p[:cost] = @catalog.property_cost(p[:name]) if p[:cost].nil?
      end
      stack
    end

    # ---- Equip helpers -------------------------------------------------

    def equippable?(stack)
      %w[Weapon Armor Item].include?(@catalog.category_of(stack.item_type))
    end

    def set_equipped(owner_id, ref, value)
      inv = read_inventory(owner_id)
      idx = resolve_index(inv, ref)
      return ERROR unless idx
      stack = inv[idx]
      return ERROR unless equippable?(stack)

      target =
        if stack.quantity > 1 && stack.equipped != value
          stack.quantity -= 1
          copy = stack.with_quantity(1)
          copy.equipped = value
          inv << copy
          copy
        else
          stack.equipped = value
          stack
        end

      inv = remerge(inv)
      write_inventory(owner_id, inv)
      reconcile_loadout(owner_id)
      inv.find { |s| s.same_identity?(target) } || target
    end

    def remerge(inv)
      out = []
      inv.each do |s|
        existing = out.find { |o| o.same_identity?(s) }
        existing ? existing.merge!(s) : out << s
      end
      out
    end

    def stable_stack_key(stack, category, index)
      if category == 'Weapon'
        "#{stack.item_type}:hand:#{index}"
      else
        slot = (@catalog.definition_of(stack.item_type) || {})['slot'] || 'body'
        "#{stack.item_type}:#{slot}"
      end
    end

    # The Active Effects an equipped Stack posts: its Guidance Bonus
    # (if any) followed by each Property's declared static effects.
    def stack_effects(stack)
      effects = []
      defn = @catalog.definition_of(stack.item_type) || {}

      if defn.key?('guidance_bonus') && stack.guidance_bonus
        effects << { target_key: defn['guidance_attribute'],
                     bonus_type: 'Guidance', amount: stack.guidance_bonus }
      end

      stack.properties.each do |p|
        pdef = @catalog.property(p[:name]) || {}
        property_effect_entries(pdef, p[:subtype]).each do |e|
          effects << {
            target_key: e['target_key'], bonus_type: e['bonus_type'],
            amount: e['amount'], ends_on_round: e['ends_on_round'],
            metadata: e['metadata'] || {}
          }.compact
        end
      end
      effects
    end

    def property_effect_entries(pdef, subtype)
      list = pdef['effects']
      case list
      when Array then list
      when Hash  then Array(subtype && list[subtype.to_s])
      else []
      end
    end

    # ---- Wealth helpers ------------------------------------------------

    def wealth_stack?(stack)
      cat = @catalog.category_of(stack.item_type)
      cat == 'Currency' || cat == 'Gem'
    end

    def currency?(stack) ; @catalog.category_of(stack.item_type) == 'Currency' ; end
    def gem?(stack)      ; stack.item_type == 'Gem'                            ; end

    def value_in_gold(stack)
      if gem?(stack)
        stack.value_in_gold || 0
      else
        c = @catalog.currency[stack.item_type]
        (c && c['value_in_gold']) || 0
      end
    end

    def value_r(stack) ; to_r(value_in_gold(stack)) ; end

    def total_wealth_r(owner_id)
      read_inventory(owner_id).sum(Rational(0)) do |s|
        wealth_stack?(s) ? to_r(s.quantity) * value_r(s) : Rational(0)
      end
    end

    def to_r(x)   ; x.is_a?(Rational) ? x : Rational(x.to_s) ; end
    def from_r(r) ; r.denominator == 1 ? r.numerator : r.to_f ; end
  end
end
