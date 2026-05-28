module Equipment
  # Loot Archive: a persistent narrative record of Ground Piles the
  # party has formally encountered and who claimed what. Mixed into
  # Instance. See equipment_design.md "Open / Claim / Close Loot
  # Archive".
  module Archive
    # Snapshots a Ground Pile into a new Archive Entry (each item
    # `claimed_by: nil`). The pile stays in place. Returns the Entry ID.
    def open_loot_archive(ground_id, label: nil, notes_ref: nil)
      items = read_inventory(ground_id).map { |s| { stack: s.dup_identity, claimed_by: nil } }
      id = (@archive_seq += 1)
      @archives[id] = {
        id: id, ground_id: ground_id, label: label,
        notes_ref: notes_ref, closed: false, items: items
      }
      id
    end

    # Atomically marks one item record claimed and transfers the
    # matching Stack out of the Ground Pile into the claimer.
    def claim_from_loot_archive(archive_id, item_ref, claimer_owner_id)
      entry = @archives[archive_id]
      return ERROR unless entry
      record = resolve_archive_item(entry, item_ref)
      return ERROR if record.nil? || !record[:claimed_by].nil?

      inv = read_inventory(entry[:ground_id])
      idx = inv.find_index { |s| s.same_identity?(record[:stack]) }
      return ERROR if idx.nil?

      dest = transfer_stack(entry[:ground_id], claimer_owner_id, idx)
      return ERROR if dest.equal?(ERROR)

      record[:claimed_by] = claimer_owner_id
      dest
    end

    # Marks the Entry closed and removes the corresponding Ground Pile.
    def close_loot_archive(archive_id)
      entry = @archives[archive_id]
      return ERROR unless entry
      entry[:closed] = true
      @store.delete(entry[:ground_id]) if @store.exists?(entry[:ground_id])
      nil
    end

    private

    def resolve_archive_item(entry, ref)
      items = entry[:items]
      if ref.is_a?(Integer)
        ref.between?(0, items.size - 1) ? items[ref] : nil
      else
        target = Stack.normalize(ref)
        items.find { |rec| rec[:stack].same_identity?(target) }
      end
    end
  end
end
