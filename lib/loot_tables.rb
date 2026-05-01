require 'yaml'
require_relative 'dice_system' # for DefaultRandomSource

# LootTables — rolls an item-drop table to produce a list of Item
# Stacks.
#
# Loads tables and option lists from a YAML file (and any
# loot_tables-*.yaml siblings, all merged into one registry; duplicate
# IDs across files raise). Supports the four Roll Row shapes
# documented in equipment_design.md:
#
#   1. Guaranteed             — { item:|items: }
#   2. Independent Chance     — { chance, item:|items: }
#   3. Weighted Choice        — { options: [...] | "<list_name>" }
#   4. Gated Weighted Choice  — { chance, options: [...] | "<list_name>" }
#
# Plus Roll Variables (`as:` / `key:` / `when:`), Option Lists with
# `from:` recursion, and Dice Expressions in `quantity` fields.
#
# Inline magical rows (`item: { magical: {...} }`) are routed to the
# optional `magical_item_generator` callable supplied at construction
# — when none is configured, encountering one raises so the gap is
# obvious rather than silent.
#
# Each call to #roll uses a fresh Roll Variables scope. The random
# source is injectable for deterministic tests.
class LootTables
  attr_reader :tables, :option_lists

  def initialize(config_path:, random_source: nil, magical_item_generator: nil)
    @random_source           = random_source || DefaultRandomSource.new
    @magical_item_generator  = magical_item_generator
    @tables, @option_lists   = load_files(config_path)
  end

  # Returns a list of Item Stacks for one rolled instance of the
  # named table. Each call builds its own Roll Variable scope; the
  # variables don't persist across calls.
  def roll(table_name)
    table = @tables[table_name.to_s]
    raise ArgumentError, "Unknown loot table: #{table_name}" unless table
    vars   = {}
    stacks = []
    Array(table['rolls']).each do |row|
      stacks.concat(roll_row(row, vars))
    end
    stacks
  end

  # Pure helper exposed for tests and other modules. Evaluates a
  # dice expression string ("2d6 + 3") or returns a numeric input
  # unchanged. Supports NdM dice terms, integer constants, and +/-
  # joiners.
  def evaluate_dice_expression(expr)
    return expr.to_i if expr.is_a?(Numeric)
    s = expr.to_s.gsub(/\s+/, '')
    return 0 if s.empty?
    total = 0
    s.scan(/[+-]?(?:\d*d\d+|\d+)/i).each do |term|
      sign = term.start_with?('-') ? -1 : 1
      body = term.sub(/\A[+-]/, '')
      if body =~ /\A(\d*)d(\d+)\z/i
        count = ::Regexp.last_match(1).empty? ? 1 : ::Regexp.last_match(1).to_i
        sides = ::Regexp.last_match(2).to_i
        val = (1..count).sum { @random_source.rand_int(1, sides) }
        total += sign * val
      else
        total += sign * body.to_i
      end
    end
    total
  end

  private

  def load_files(primary_path)
    tables       = {}
    option_lists = {}
    paths = [primary_path] + sibling_paths(primary_path)
    paths.uniq.each do |path|
      next unless File.exist?(path)
      data = YAML.load_file(path) || {}
      merge_registry!(tables, data['loot_tables'] || {}, path, 'loot table')
      merge_registry!(option_lists, data['option_lists'] || {}, path, 'option list')
    end
    [tables, option_lists]
  end

  def sibling_paths(primary_path)
    dir   = File.dirname(primary_path)
    base  = File.basename(primary_path, '.yaml')
    Dir.glob(File.join(dir, "#{base}-*.yaml"))
  end

  def merge_registry!(dst, incoming, path, kind)
    incoming.each do |id, definition|
      raise ArgumentError, "Duplicate #{kind} id '#{id}' (in #{path})" if dst.key?(id)
      dst[id] = definition
    end
  end

  # Returns the list of stacks produced by this row (possibly empty).
  # Updates `vars` with `as:` publication when applicable.
  def roll_row(row, vars)
    return [] unless gate_passes?(row['when'], vars)

    if row.key?('options')
      stacks, winning_key = roll_weighted_row(row, vars)
    elsif row.key?('chance')
      stacks, winning_key = roll_chance_row(row)
    else
      stacks      = resolve_item_payload(row)
      winning_key = row['key']
    end

    stacks = stacks.map { |s| s.merge('equipped' => true) } if row['equipped']
    vars[row['as']] = winning_key if row.key?('as')
    stacks
  end

  def roll_weighted_row(row, vars)
    options = resolve_options(row['options'])
    if row.key?('chance')
      # Gated Weighted Choice: roll the gate first, then weighted.
      return [[], nil] unless roll_chance(row['chance'])
    end
    pick_weighted(options, vars)
  end

  def roll_chance_row(row)
    if roll_chance(row['chance'])
      [resolve_item_payload(row), row['key']]
    else
      [[], nil]
    end
  end

  # Walks a list of options computing a cumulative-probability sample.
  # Remainder (sum < 1) means nothing drops.
  def pick_weighted(options, vars)
    threshold = roll_unit_interval
    cumulative = 0.0
    options.each do |opt|
      cumulative += opt['chance'].to_f
      next unless threshold < cumulative
      return resolve_option(opt, vars)
    end
    [[], nil]
  end

  def resolve_option(opt, vars)
    if opt.key?('from')
      sub_options = resolve_options(opt['from'])
      return pick_weighted(sub_options, vars)
    end
    [resolve_item_payload(opt), opt['key']]
  end

  def resolve_options(options)
    return options if options.is_a?(Array)
    list_name = options.to_s
    list = @option_lists[list_name]
    raise ArgumentError, "Unknown option list: #{list_name}" unless list
    list
  end

  # Either a single `item:` or a list `items:`. Each spec resolves
  # to one Item Stack with quantity rolled.
  def resolve_item_payload(payload)
    if payload.key?('items')
      Array(payload['items']).map { |spec| resolve_item_spec(spec) }
    elsif payload.key?('item')
      [resolve_item_spec(payload['item'])]
    else
      []
    end
  end

  def resolve_item_spec(spec)
    if spec.is_a?(Hash) && spec.key?('magical')
      raise NotImplementedError, 'Inline magical row encountered but no magical_item_generator configured' unless @magical_item_generator
      stack = @magical_item_generator.call(spec['magical'])
      return stack
    end
    raise ArgumentError, "Item spec must be a hash with `item:`" unless spec.is_a?(Hash) && spec.key?('item')
    stack = spec.dup
    stack['item_type'] = stack.delete('item')
    stack['quantity'] = evaluate_dice_expression(stack['quantity']) if stack.key?('quantity')
    stack['quantity'] ||= 1
    stack
  end

  def gate_passes?(when_clause, vars)
    return true if when_clause.nil? || when_clause.empty?
    when_clause.all? { |var_name, expected| vars[var_name] == expected }
  end

  def roll_chance(chance)
    return true if chance.nil? || chance.to_f >= 1.0
    return false if chance.to_f <= 0.0
    roll_unit_interval < chance.to_f
  end

  def roll_unit_interval
    @random_source.rand_int(0, 9_999) / 10_000.0
  end
end
