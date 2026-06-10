module Equipment
  # Loot Table rolling. Mixed into Instance. Resolves the four Roll Row
  # shapes, Roll Variables (`as` / `key` / `when`), Option Lists (named
  # + recursive `from:`), Dice Expression quantities, and Inline
  # Magical Rows. See equipment_design.md "Roll Loot Table" and "Loot
  # Roll Row resolution".
  module LootRolling
    # Returns the produced Item Stacks. Persistence is the caller's job.
    def roll_loot_table(table_id, seed: nil, rng: nil, vars: {})
      rng ||= seed ? Random.new(seed) : @rng
      table = loot.table(table_id)
      return ERROR unless table

      vars = (vars || {}).transform_keys(&:to_s)
      stacks = []
      Array(table['rolls']).each do |row|
        row = row.transform_keys(&:to_s)
        next unless when_satisfied?(row['when'], vars)

        produced, key = resolve_row(row, rng)
        produced.each { |s| s.equipped = true } if row['equipped']
        stacks.concat(produced)
        vars[row['as']] = key if row.key?('as')
      end
      stacks
    end

    private

    def resolve_row(row, rng)
      if row.key?('options') && row.key?('chance')
        rng.rand < row['chance'] ? weighted_choice(row['options'], rng) : [[], nil]
      elsif row.key?('options')
        weighted_choice(row['options'], rng)
      elsif row.key?('chance')
        rng.rand < row['chance'] ? [payload_stacks(row, rng), row['key']] : [[], nil]
      else
        [payload_stacks(row, rng), row['key']]
      end
    end

    # Cumulative-probability sample over absolute chances (which sum to
    # <= 1); the leftover probability means nothing drops.
    def weighted_choice(options, rng)
      opts = options.is_a?(String) ? loot.option_list(options) : options
      opts = Array(opts).map { |o| o.transform_keys(&:to_s) }
      u = rng.rand
      acc = 0.0
      opts.each do |opt|
        acc += opt['chance'].to_f
        return resolve_option(opt, rng) if u < acc
      end
      [[], nil]
    end

    def resolve_option(opt, rng)
      if opt.key?('from')
        weighted_choice(opt['from'], rng)
      else
        [payload_stacks(opt, rng), opt['key']]
      end
    end

    # A Row or Option payload: `item:` (single) or `items:` (list).
    def payload_stacks(node, rng)
      if node.key?('items')
        Array(node['items']).flat_map { |p| payload_to_stacks(p, rng) }
      elsif node.key?('item')
        payload_to_stacks(node['item'], rng)
      else
        []
      end
    end

    def payload_to_stacks(payload, rng)
      payload = payload.transform_keys(&:to_s)
      if payload.key?('magical')
        [generate_magical_item(payload['magical'], rng)]
      else
        [stack_from_payload(payload, rng)]
      end
    end

    def stack_from_payload(payload, rng)
      qty = payload['quantity']
      qty = DiceExpression.eval(qty, rng) if qty.is_a?(String)
      Stack.normalize(payload.merge('quantity' => qty.nil? ? 1 : qty))
    end

    def when_satisfied?(when_map, vars)
      return true unless when_map
      when_map.all? { |var, expected| vars[var.to_s] == expected }
    end
  end
end
