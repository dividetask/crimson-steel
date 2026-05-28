module Equipment
  # Shops and the Game Day counter. Mixed into Instance. A Shop
  # definition (supplied via the `shops:` constructor argument) carries
  # at least a `template:` — the Loot Table the Shop draws from on
  # first stock and on Refresh. See equipment_design.md "Refresh
  # Specific Shop", "Visit Generic Shop", and "Advance Time".
  module Shops
    # ===== Refresh Specific Shop =====
    # Each existing Stack flips a d2: 1 removes it, 2 keeps it with a
    # Quantity rerolled uniformly in [1, current]. Then the Shop
    # Template is rolled and merged in.
    def refresh_specific_shop(shop_id)
      owner = "shop:#{shop_id}"
      kept = []
      read_inventory(owner).each do |stack|
        next if @rng.rand(1..2) == 1
        stack.quantity = @rng.rand(1..[stack.quantity, 1].max)
        kept << stack
      end
      write_inventory(owner, kept)

      template = shop_def(shop_id)[:template]
      Array(roll_or_empty(template)).each { |s| add_item(owner, s) }
      cleanup(owner)
      read_inventory(owner)
    end

    # ===== Visit Generic Shop =====
    # Returns the Active Generic Shop Owner ID for the current Game Day,
    # rolling fresh stock from the Template on first visit of the day.
    def visit_generic_shop(shop_id)
      owner = "generic_shop:#{shop_id}"
      return owner if @active_generic[shop_id] == @game_day && @store.exists?(owner)

      template = shop_def(shop_id)[:template]
      write_inventory(owner, Array(roll_or_empty(template)))
      @active_generic[shop_id] = @game_day
      owner
    end

    def active_generic_day(shop_id)
      @active_generic[shop_id]
    end

    # ===== Advance Time =====
    # Increments the Game Day and expires every Active Generic Shop
    # generated on an earlier day.
    def advance_time
      @game_day += 1
      expired = @active_generic.select { |_id, day| day < @game_day }.keys
      expired.each do |sid|
        @store.delete("generic_shop:#{sid}")
        @active_generic.delete(sid)
      end
      @game_day
    end

    # ===== Shop Purchase =====
    # A Specific Shop refuses a buy it cannot afford; a Generic Shop has
    # unlimited Wealth.
    def shop_can_buy?(owner_id, price)
      get_total_wealth(owner_id) >= price
    end

    private

    def shop_def(shop_id)
      (@shops[shop_id] || @shops[shop_id.to_s] || {}).transform_keys(&:to_sym)
    end

    def roll_or_empty(template)
      return [] unless template
      result = roll_loot_table(template)
      result.equal?(ERROR) ? [] : result
    end
  end
end
