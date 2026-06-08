module Equipment
  # End-of-Combat hand-off, dropping, and pile distribution. Mixed into
  # Instance. See equipment_design.md "Collect Combat Loot", "Drop
  # Stack", and "Distribute Loot Pile".
  module CombatLoot
    # entries: list of { combatant_id, creature_id, ally, loot_table? }.
    # location: the Ground Pile location to gather into (the caller's
    # choice — the Encounter uses the active Map, so loot left behind when
    # the party changes Maps is no longer surfaced). Moves each non-ally
    # Combatant's Inventory (+ optional rolled Loot Table) into the single
    # Ground Pile `ground:<location>`. Returns the pile Owner ID, or nil
    # when there is nothing to collect.
    def collect_combat_loot(entries, location:)
      non_ally = entries.map { |e| symbolize(e) }.reject { |e| e[:ally] }
      return nil if non_ally.empty?

      pile = "ground:#{location}"
      non_ally.each do |entry|
        owner = "creature:#{entry[:creature_id]}"
        read_inventory(owner).each do |stack|
          next if stack.quantity <= 0
          moved = stack.with_quantity(stack.quantity)
          moved.equipped = false
          add_item(pile, moved)
        end
        write_inventory(owner, [])

        if entry[:loot_table]
          rolled = roll_loot_table(entry[:loot_table])
          Array(rolled).each { |s| s.equipped = false; add_item(pile, s) } unless rolled.equal?(ERROR)
        end
      end
      pile
    end

    # Transfer a Quantity from an Owner onto a Ground Pile at a location.
    def drop_stack(owner_id, ref, location, quantity: nil)
      transfer_stack(owner_id, "ground:#{location}", ref, quantity: quantity)
    end

    # assignments: list of { stack_ref, target_owner_id }. target is nil
    # / "skip" (leave on pile), "party", or "character:<id>" /
    # "creature:<id>". Atomic on validation: a bad reference or unknown
    # Creature rejects the whole call before any transfer.
    def distribute_loot_pile(pile_owner_id, assignments)
      return ERROR unless @store.exists?(pile_owner_id)
      inv = read_inventory(pile_owner_id)

      resolved = assignments.map do |raw|
        a = symbolize(raw)
        idx = resolve_index(inv, a[:stack_ref])
        return ERROR if idx.nil?
        target = a[:target_owner_id]
        return ERROR if assigned?(target) && creature_owner?(target) && !creature_exists?(target)
        [idx, target]
      end

      results = resolved.map do |(idx, target)|
        assigned?(target) ? transfer_stack(pile_owner_id, target, idx) : nil
      end

      cleanup(pile_owner_id)
      results
    end

    # Remove a Ground Pile and every remaining Stack on it wholesale —
    # the loot-pile stub's "Delete Pile". Returns true, or ERROR when the
    # owner is not an existing Ground Pile. (Distribute leaves Skipped
    # Stacks behind; this discards them when the DM gives up on the pile.)
    def delete_ground_pile(owner_id)
      return ERROR unless ground_owner?(owner_id) && @store.exists?(owner_id)
      @store.delete(owner_id)
      true
    end

    private

    def assigned?(target)
      !(target.nil? || target == 'skip')
    end

    def creature_exists?(owner_id)
      return true unless @creature_accessor.respond_to?(:exists?)
      @creature_accessor.exists?(creature_id(owner_id))
    end

    def symbolize(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
