module Equipment
  # Shops and the Game Day counter. Mixed into Instance.
  #
  # Generic Shops use population-scaled stocking from the Generic Shop
  # catalog (`shops.yaml`): per-item Quantity grows with population and
  # items below their `min_pop` are not stocked; the Shop's purchasing
  # budget also scales with population. Specific Shops keep a persistent
  # Inventory refreshed from a Loot Table Template. See
  # equipment_design.md "Generic Shop stocking", "Visit Generic Shop",
  # "Refresh Specific Shop", and "Advance Time".
  module Shops
    # ===== Visit Generic Shop =====
    # Returns the Active Generic Shop Owner ID for the current Game Day,
    # materializing population-scaled stock on the first visit of the
    # day (the first visit's population stands for the rest of the day).
    def visit_generic_shop(shop_id, population:)
      owner = "generic_shop:#{shop_id}"
      active = @active_generic[shop_id]
      return owner if active && active[:day] == @game_day && @store.exists?(owner)

      defn = generic_shop_def(shop_id)
      return ERROR unless defn

      write_inventory(owner, generic_stock(defn, population))
      @active_generic[shop_id] = { day: @game_day, population: population }
      owner
    end

    def active_generic_day(shop_id)
      a = @active_generic[shop_id]
      a && a[:day]
    end

    # The population-scaled Inventory a Generic Shop materializes: a Gold
    # Stack for its purchasing budget, then each stockable item.
    #
    #   gold     = base_gold + floor(gold_per_sqrt_pop * sqrt(pop))
    #   quantity = qty_base  + floor(qty_per_kpop * pop / 1000)
    def generic_stock(defn, population)
      defn = defn.transform_keys(&:to_s)
      stacks = []

      gold = defn['base_gold'].to_i + (defn['gold_per_sqrt_pop'].to_f * Math.sqrt(population)).floor
      stacks << Stack.normalize('item' => 'Gold', 'quantity' => gold) if gold > 0

      Array(defn['stock']).each do |raw|
        entry = raw.transform_keys(&:to_s)
        next if population < entry['min_pop'].to_i
        qty = entry['qty_base'].to_i + (entry['qty_per_kpop'].to_f * population / 1000).floor
        next if qty <= 0
        payload = { 'item' => entry['item'], 'quantity' => qty }
        payload['tier'] = entry['tier'] if entry.key?('tier')
        # Magical stock: an entry may carry `properties` (the same shape the
        # inventory data files use — a string, or {name, subtype}) so a Shop
        # can sell, say, a Flaming Long sword. Unit Price falls back to the
        # catalog Property cost when none is stored on the Stack.
        payload['properties'] = entry['properties'] if entry.key?('properties')
        stacks << Stack.normalize(payload)
      end
      stacks
    end

    # ===== Refresh Specific Shop =====
    # Each existing Stack flips a d2: 1 removes it, 2 keeps it with a
    # Quantity rerolled uniformly in [1, current]. Then the Shop
    # Template (a Loot Table) is rolled and merged in.
    def refresh_specific_shop(shop_id)
      owner = "shop:#{shop_id}"
      kept = []
      read_inventory(owner).each do |stack|
        next if @rng.rand(1..2) == 1
        stack.quantity = @rng.rand(1..[stack.quantity, 1].max)
        kept << stack
      end
      write_inventory(owner, kept)

      template = specific_shop_def(shop_id)[:template]
      Array(roll_or_empty(template)).each { |s| add_item(owner, s) }
      cleanup(owner)
      read_inventory(owner)
    end

    # ===== Advance Time =====
    # Increments the Game Day and expires every Active Generic Shop
    # generated on an earlier day.
    def advance_time
      @game_day += 1
      expired = @active_generic.select { |_id, a| a[:day] < @game_day }.keys
      expired.each do |sid|
        @store.delete("generic_shop:#{sid}")
        @active_generic.delete(sid)
      end
      @game_day
    end

    # ===== Shop Purchase =====
    # A Shop refuses a buy it cannot afford. Generic Shop budgets are
    # finite and population-scaled (held as a Gold Stack in their stock).
    def shop_can_buy?(owner_id, price)
      get_total_wealth(owner_id) >= price
    end

    private

    def generic_shop_def(shop_id)
      @generic_shops ||= ShopCatalog.load.generic_shops
      @generic_shops[shop_id] || @generic_shops[shop_id.to_s]
    end

    def specific_shop_def(shop_id)
      (@shops[shop_id] || @shops[shop_id.to_s] || {}).transform_keys(&:to_sym)
    end

    def roll_or_empty(template)
      return [] unless template
      result = roll_loot_table(template)
      result.equal?(ERROR) ? [] : result
    end
  end
end
