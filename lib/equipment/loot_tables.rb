require 'yaml'

module Equipment
  # Read-only catalog of Loot Tables and reusable Option Lists, loaded
  # from `loot_tables.yaml` (plus any `loot_tables-*.yaml`). Duplicate
  # Loot Table IDs across files raise at load. See equipment_design.md
  # "Add Loot Table / Remove Loot Table" and the glossary.
  class LootTables
    DEFAULT_GLOB = File.expand_path(
      '../../docs/common/equipment/loot_tables*.{yaml,yml}', __dir__
    )

    attr_reader :tables, :option_lists

    def initialize(tables: {}, option_lists: {})
      @tables = tables
      @option_lists = option_lists
    end

    def self.load(glob = DEFAULT_GLOB)
      tables = {}
      option_lists = {}
      Dir.glob(glob).sort.each do |path|
        data = YAML.safe_load_file(path) || {}
        (data['loot_tables'] || {}).each do |id, table|
          raise ArgumentError, "duplicate Loot Table id #{id.inspect} (in #{File.basename(path)})" if tables.key?(id)
          tables[id] = table
        end
        (data['option_lists'] || {}).each { |id, list| option_lists[id] = list }
      end
      new(tables: tables, option_lists: option_lists)
    end

    def table(id)       ; @tables[id.to_s]       ; end
    def option_list(id) ; @option_lists[id.to_s] ; end
  end
end
