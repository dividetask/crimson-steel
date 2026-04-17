require_relative 'tools'

# Templates: enemy archetypes that can be rolled into concrete character
# instances. A template holds the baseline character stats, an optional list
# of probabilistic variants (independent rolls that can adjust race / ability
# scores / class levels / loot), and a reference to a gear table that defines
# what items and gold the creature tends to carry.
#
# Supporting data types:
#   - Variant: { id, chance, overrides, classes_add, gear, gear_patch }
#   - GearTable: { id, rolls: [...], gold }
#   - Roll row shapes inside a GearTable's `rolls` array:
#       * guaranteed: { slot, item }
#       * independent yes/no: { slot, chance, item }
#       * weighted choice: { slot, options: [{ chance, item }, ...] }
#         Remainder of 1.0 = nothing rolled in that slot.
#       * gated weighted choice: { slot, chance, options: [...] }
#         First roll `chance` to decide if we drop into the table at all;
#         if yes, weighted choice among options (remainder still = nothing).
#         Useful for tiered loot (e.g. 25% chance of a tier-0 potion, and
#         which tier-0 potion is itself a weighted roll).
#
# Instantiation writes the resolved character into characters.json with a
# fresh integer id so each spawned copy has its own stats, items, and gold.
module Templates
  module_function

  FILENAME = 'templates.json'.freeze
  GLOB_PATTERN = 'template-*.json'.freeze

  # Load and merge all template files: templates.json (primary) plus any
  # template-*.json files. Creature templates, gear tables, and option
  # lists all share a single namespace across files so a creature in
  # one file can reference a gear table or option list from another.
  # Each creature is tagged with `_source` (display label derived from
  # the filename) so views can group enemies by source file.
  def load_raw(rng: nil)
    data_dir = File.join(File.dirname(__FILE__), 'data')
    primary = Tools.load_json(FILENAME)
    primary = {} unless primary.is_a?(Hash)

    creatures = (primary['creatures'] || []).each { |c| c['_source'] ||= 'General' }
    gear = primary['gear_tables'] || []
    lists = (primary['option_lists'] || {}).dup

    Dir.glob(File.join(data_dir, GLOB_PATTERN)).sort.each do |path|
      extra = JSON.parse(File.read(path)) rescue next
      next unless extra.is_a?(Hash)
      label = source_label(File.basename(path))
      (extra['creatures'] || []).each { |c| c['_source'] ||= label }
      creatures += (extra['creatures'] || [])
      gear += (extra['gear_tables'] || [])
      (extra['option_lists'] || {}).each { |k, v| lists[k] = v }
    end

    { 'creatures' => creatures, 'gear_tables' => gear, 'option_lists' => lists }
  end

  # Derive a human-readable group label from a template filename.
  # "template-slave-lords.json" -> "Slave Lords"
  # "template-potions.json"     -> "Potions"
  def source_label(filename)
    filename.sub(/\Atemplate-/, '').sub(/\.json\z/, '').tr('-', ' ').split.map(&:capitalize).join(' ')
  end

  def creatures; (load_raw['creatures'] || []); end

  # Returns creatures grouped by source file as an ordered array of
  # [label, [creature, ...]] pairs. Preserves per-file insertion order.
  def creatures_grouped
    creatures.group_by { |c| c['_source'] || 'General' }.to_a
  end

  def gear_tables
    (load_raw['gear_tables'] || []).each_with_object({}) { |gt, h| h[gt['id']] = gt }
  end

  # Named weighted-option lists. Rows in a gear table can set
  # `options: "tier_one_potions"` instead of an inline array; the roller
  # resolves the string via this hash. Useful for DRY loot references.
  def option_lists; load_raw['option_lists'] || {}; end

  # Find a creature template by its string id.
  def find(template_id)
    creatures.find { |c| c['id'].to_s == template_id.to_s }
  end

  # Return a plain character hash suitable for CharacterSheet preview --
  # strips template-only fields (variants, gear) and substitutes a synthetic
  # id so combat_status / equipment ownership lookups don't collide.
  def preview_character(template)
    base = deep_dup(template)
    base.delete('variants')
    base.delete('gear')
    base['id'] = "template:#{template['id']}"
    base['group'] ||= 'Enemies'
    base['player'] ||= 'DM'
    base
  end

  # Instantiate a template: roll variants, resolve gear, return a concrete
  # character hash (with a caller-supplied id) plus the gold amount.
  # `rng` lets callers inject a seeded Random for deterministic tests.
  def instantiate(template_id, new_id:, rng: Random.new, tables: nil, lists: nil)
    template = find(template_id)
    raise ArgumentError, "unknown template: #{template_id}" unless template

    tables ||= gear_tables
    lists ||= option_lists
    character = deep_dup(template)
    variants = character.delete('variants') || []
    gear_ref = character.delete('gear')
    character['id'] = new_id
    character['group'] ||= 'Enemies'
    character['player'] ||= 'DM'

    applied_variants = []
    resolved_gear_ref = gear_ref
    gear_patches = []
    variants.each do |variant|
      chance = (variant['chance'] || 0).to_f
      next unless rng.rand < chance
      apply_variant!(character, variant)
      applied_variants << variant['id']
      resolved_gear_ref = variant['gear'] if variant.key?('gear')
      gear_patches << variant['gear_patch'] if variant['gear_patch']
    end

    gear_table = GearTable.resolve(resolved_gear_ref, tables)
    gear_patches.each { |patch| gear_table = GearTable.apply_patch(gear_table, patch) }

    items, gold = GearTable.roll(gear_table, rng: rng, lists: lists)
    character['items'] = (character['items'] || []) + items
    character['gold'] = gold if gold
    character['applied_variants'] = applied_variants unless applied_variants.empty?
    character
  end

  # Mutates character in place: apply variant overrides, classes_add, and
  # any name adjustments.
  def apply_variant!(character, variant)
    overrides = variant['overrides'] || {}
    overrides.each do |key, value|
      case key
      when 'ability_scores'
        character['ability_scores'] ||= {}
        value.each do |attr, adjustment|
          character['ability_scores'][attr] = adjust_score(character['ability_scores'][attr], adjustment)
        end
      else
        character[key] = value
      end
    end
    (variant['classes_add'] || []).each do |extra_class|
      character['classes'] ||= []
      character['classes'] << deep_dup(extra_class)
    end
    if variant['name_suffix']
      character['name'] = "#{character['name']}#{variant['name_suffix']}"
    elsif overrides['name']
      character['name'] = overrides['name']
    end
  end

  # Adjustment values may be:
  #   * an Integer -> replaces the score outright
  #   * a String like "+2" / "-1" -> added to the existing score
  def adjust_score(current, adjustment)
    if adjustment.is_a?(String) && adjustment =~ /\A[+-]\d+\z/
      current.to_i + adjustment.to_i
    else
      adjustment.to_i
    end
  end

  # Deep copy via JSON round-trip. Templates and gear tables are pure JSON
  # structures, so this is safe and avoids a separate Marshal dependency.
  def deep_dup(obj)
    JSON.parse(JSON.generate(obj))
  end
end

module GearTable
  module_function

  # Resolve a gear reference (string id, inline hash, or nil) into a concrete
  # gear-table hash. Returns an empty table for nil / unknown ids.
  def resolve(ref, tables)
    return { 'rolls' => [], 'gold' => nil } if ref.nil?
    if ref.is_a?(String)
      table = tables[ref]
      warn "GearTable: unknown gear table '#{ref}'" unless table
      Templates.deep_dup(table || { 'rolls' => [], 'gold' => nil })
    else
      Templates.deep_dup(ref)
    end
  end

  # Apply a shallow patch to a resolved gear table. Patches may:
  #   * `gold`       -> replace the gold expression outright
  #   * `gold_bonus` -> append the expression onto the existing gold formula
  #                     (e.g. "+2d6" or "2d6" both work; useful for "this
  #                     variant rolls the base gold plus some extra")
  #   * `rolls`      -> hash keyed by slot id; each value replaces (or, with
  #                     nil, removes) the matching slot's roll definition.
  def apply_patch(table, patch)
    return table unless patch.is_a?(Hash)
    patched = Templates.deep_dup(table)
    patched['gold'] = patch['gold'] if patch.key?('gold')
    if patch.key?('gold_bonus') && !patch['gold_bonus'].nil?
      bonus = patch['gold_bonus'].to_s.strip
      bonus = "+#{bonus}" unless bonus.start_with?('+', '-')
      patched['gold'] = [patched['gold'], bonus].compact.reject { |s| s.to_s.empty? }.join(' ')
    end
    if patch['rolls'].is_a?(Hash)
      rolls = (patched['rolls'] || []).dup
      patch['rolls'].each do |slot, replacement|
        idx = rolls.find_index { |r| r['slot'] == slot }
        if replacement.nil?
          rolls.delete_at(idx) if idx
        elsif idx
          rolls[idx] = replacement.merge('slot' => slot)
        else
          rolls << replacement.merge('slot' => slot)
        end
      end
      patched['rolls'] = rolls
    end
    patched
  end

  # Evaluate a gear table: returns [items, gold]. `rng` should be a Random.
  # `lists` is the named-option-list hash used to resolve string `options`
  # references (see Templates.option_lists).
  def roll(table, rng: Random.new, lists: {})
    items = []
    (table['rolls'] || []).each do |row|
      item = roll_row(row, rng, lists)
      items << item if item
    end
    gold = roll_gold(table['gold'], rng)
    [items, gold]
  end

  # Returns the item hash that was rolled, or nil if nothing was rolled.
  def roll_row(row, rng, lists = {})
    options = row['options']
    options = lists[options] if options.is_a?(String)
    if options.is_a?(Array)
      # Gated weighted choice: outer `chance` decides if we drop into the
      # table at all. Without a `chance`, the weighted roll always happens
      # (with remainder = nothing).
      return nil if row.key?('chance') && rng.rand >= row['chance'].to_f
      roll_weighted(options, rng, lists)
    elsif row.key?('chance')
      ((rng.rand < row['chance'].to_f) ? Templates.deep_dup(row['item']) : nil)
    elsif row.key?('item')
      Templates.deep_dup(row['item'])
    end
  end

  # Walk the options in order, summing chances. A single uniform sample
  # against the cumulative total picks one option; remainder -> nothing.
  # An option whose body is `{chance, from: "other_list"}` recursively
  # rolls from another option list when picked -- useful for overflow
  # (e.g. "5% chance of a tier-1 slot actually grabs from tier-2").
  def roll_weighted(options, rng, lists = {})
    total = options.sum { |o| o['chance'].to_f }
    warn "GearTable: weighted options sum > 1.0 (got #{total})" if total > 1.0 + 1e-9
    pick = rng.rand
    running = 0.0
    options.each do |opt|
      running += opt['chance'].to_f
      if pick < running
        if opt['from'].is_a?(String)
          sub = lists[opt['from']] || []
          return roll_weighted(sub, rng, lists)
        end
        item = Templates.deep_dup(opt['item'])
        item['bonus'] = opt['bonus'] if opt.key?('bonus')
        return item
      end
    end
    nil
  end

  # Evaluate a dice expression (e.g. "2d6 + 5") into an integer.
  # Supports NdM, +/- modifiers, and plain integers. Returns nil when
  # the expression is missing.
  def roll_gold(expr, rng)
    return nil if expr.nil? || expr.to_s.strip.empty?
    return expr.to_i if expr.is_a?(Integer)
    total = 0
    tokens = expr.to_s.gsub(/\s+/, '').scan(/[+-]?(?:\d+d\d+|\d+)/)
    tokens.each do |token|
      sign = token.start_with?('-') ? -1 : 1
      body = token.sub(/\A[+-]/, '')
      if body.include?('d')
        count, sides = body.split('d').map(&:to_i)
        rolled = count.times.sum { rng.rand(sides) + 1 }
        total += sign * rolled
      else
        total += sign * body.to_i
      end
    end
    total
  end
end
