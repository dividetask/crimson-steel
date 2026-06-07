require 'yaml'
require_relative 'dataset'
require_relative 'dice_expression'

module Creatures
  # Spawn Creature From Template + Delete Creature + Random
  # Encounter Table loading + Roll Random Encounter.
  #
  # Random Encounter Row shapes recognized:
  #   Guaranteed             — { spawn: [SpawnRef, ...] }
  #   Independent Chance     — { chance: 0..1, spawn: [...], as: var }
  #   Gated Independent Chance — { when: {...}, chance: 0..1, spawn: [...], as: var }
  #
  # Weighted Choice / Gated Weighted Choice rows are not yet
  # implemented — none of the shipped random_encounter_tables.yaml entries
  # use them. They mirror Equipment's Loot Roll Row shape; the
  # Equipment domain hasn't landed yet.
  module RandomEncounter
    TABLES_PATH = File.expand_path(
      '../../docs/common/creatures/random_encounter_tables.yaml', __dir__
    )

    module_function

    # ---- Spawn / Delete -------------------------------------------------

    def spawn_from_template(template_id, name_override: nil, loot_table: nil, rng: Random.new)
      template = Dataset.get(Integer(template_id))
      raise ArgumentError, "no template Creature with id #{template_id}" unless template

      new_id = Dataset.next_id
      copy = deep_dup(template)
      copy[:id] = new_id
      copy[:name] = name_override if name_override
      copy[:loot_table] = loot_table if loot_table
      # Resolve a weighted race_table (if any) to a concrete race on the
      # spawn, then clear the table so the instance is a fixed-race Creature.
      unless Array(copy[:race_table]).empty?
        copy[:race] = weighted_pick(copy[:race_table], rng)[:race]
        copy[:race_table] = []
      end
      # Resolve a weighted class_table (if any) to a single concrete class,
      # replacing the template's classes, then clear the table.
      unless Array(copy[:class_table]).empty?
        chosen = weighted_pick(copy[:class_table], rng)
        copy[:classes] = {
          chosen[:class] => { level: chosen[:level], skills: chosen[:skills], choices: chosen[:choices] }
        }
        copy[:class_table] = []
      end
      # Record the template this instance was cloned from so the Roster
      # Sidebar / Character Sheets can group spawned Creatures under their
      # source. A spawned instance is NOT itself a template — drop the
      # `enemy_template` tag so it isn't listed as a selectable template.
      copy[:spawned_from] = Integer(template_id)
      copy[:tags] = Array(copy[:tags]).reject { |t| t == 'enemy_template' }

      Dataset.insert!(copy)
      new_id
    end

    # Weighted pick over a table of entries carrying a `:chance`
    # (race_table / class_table). Chances are absolute and conventionally
    # sum to 1; any leftover probability falls through to the last entry.
    # Returns the chosen entry.
    def weighted_pick(table, rng)
      u = rng.rand
      acc = 0.0
      table.each do |e|
        acc += e[:chance].to_f
        return e if u < acc
      end
      table.last
    end

    def delete_creature(id)
      Dataset.delete!(id)
    end

    # ---- Random Encounter Tables -----------------------------------------------

    def tables
      @tables ||= (YAML.safe_load_file(TABLES_PATH) || {})
    end

    def reset!
      @tables = nil
    end

    # Validates table refs against the current Dataset. Raises on
    # any Spawn Ref whose template_id doesn't exist. Use at boot
    # after the dataset has been loaded.
    def validate_tables!
      tables.each do |table_id, table|
        (table['rolls'] || []).each do |row|
          (row['spawn'] || []).each do |spawn|
            tid = Integer(spawn['template_id'])
            unless Dataset.get(tid)
              raise ArgumentError, "Random Encounter Table #{table_id.inspect} row references missing template_id #{tid}"
            end
          end
        end
      end
      true
    end

    # Roll Random Encounter. Returns the list of newly-spawned Creature IDs
    # in roll order. The optional `seed` makes the result
    # reproducible (used by tests and replayable encounter rolls).
    def roll_random_encounter(table_id, seed: nil)
      table = tables[table_id.to_s]
      raise ArgumentError, "no Random Encounter Table #{table_id.inspect}" unless table

      rng = seed.nil? ? Random.new : Random.new(seed)
      vars = {}
      new_ids = []

      Array(table['rolls']).each do |row|
        next unless when_matches?(row['when'], vars)

        fired = true
        if row.key?('chance')
          chance = row['chance'].to_f
          fired = rng.rand < chance
        end

        next unless fired

        # Publish the `as` variable when the row fires.
        vars[row['as']] = true if row['as']

        Array(row['spawn']).each do |sref|
          count = DiceExpression.eval(sref['count'] || 1, rng)
          count.times do
            new_ids << spawn_from_template(
              Integer(sref['template_id']),
              name_override: sref['name_override'],
              loot_table:    sref['loot_table'],
              rng:           rng
            )
          end
        end
      end

      new_ids
    end

    def when_matches?(filter, vars)
      return true if filter.nil? || filter.empty?
      filter.all? { |k, v| vars[k] == v }
    end

    # ---- helpers --------------------------------------------------------

    def deep_dup(obj)
      case obj
      when Hash  then obj.transform_values { |v| deep_dup(v) }
      when Array then obj.map { |v| deep_dup(v) }
      else obj.dup rescue obj
      end
    end
  end
end
