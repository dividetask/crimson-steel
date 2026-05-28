module Equipment
  # In-memory holder of non-Creature Owner Inventories (Party, Ground
  # Piles, Shops). Creature Inventories are NOT held here — they are
  # read and written through the injected Creature accessor. Each Owner
  # tracks the Source File it was loaded from so mutations write back
  # to the same file. See equipment_design.md "Owner Record" and
  # "Source-file tracking".
  class Store
    Owner = Struct.new(:owner_id, :source_file, :inventory)

    def initialize
      @owners = {}
    end

    def exists?(owner_id)
      @owners.key?(owner_id)
    end

    def owner(owner_id)
      @owners[owner_id]
    end

    def inventory(owner_id)
      o = @owners[owner_id]
      o && o.inventory
    end

    # Replaces (or creates) an Owner's Inventory. A freshly created
    # Owner records the supplied Source File; an existing Owner keeps
    # the file it was loaded from.
    def set_inventory(owner_id, stacks, source_file)
      o = @owners[owner_id]
      if o
        o.inventory = stacks
      else
        @owners[owner_id] = Owner.new(owner_id, source_file, stacks)
      end
      stacks
    end

    def delete(owner_id)
      @owners.delete(owner_id)
    end

    def ids
      @owners.keys
    end
  end
end
