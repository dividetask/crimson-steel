require 'yaml'
require_relative 'record'

module Creatures
  # Loads + indexes every `creatures_data_*.{yaml,json}` file under
  # docs/common/creatures/. Each file's `characters` list is
  # validated and normalized through Creatures::Record; the merged
  # set is keyed by integer id. Loader is strict — a malformed
  # record aborts the load with a descriptive error.
  module Dataset
    DEFAULT_GLOB = File.expand_path(
      '../../docs/common/creatures/creatures_data_*.{yaml,yml,json}', __dir__
    )

    module_function

    # Returns the loaded dataset hash: { id (Integer) => record }.
    def all
      load! unless defined?(@records) && @records
      @records
    end

    def get(id)
      all[Integer(id)]
    end

    def ids_in_load_order
      load! unless defined?(@order) && @order
      @order
    end

    def load!(glob = DEFAULT_GLOB)
      @records = {}
      @order   = []
      Dir.glob(glob).sort.each do |path|
        data = YAML.safe_load_file(path) || {}
        characters = data['characters'] || []
        characters.each do |raw|
          rec = Creatures::Record.normalize(raw, source: File.basename(path))
          if @records.key?(rec[:id])
            raise ArgumentError, "Creature id #{rec[:id]} appears in multiple " \
                                 "creatures_data_* files (second sighting in #{File.basename(path)})"
          end
          @records[rec[:id]] = rec
          @order << rec[:id]
        end
      end
      self
    end

    def reset!
      @records = nil
      @order = nil
    end

    # Used by Spawn Creature From Template. Allocates a fresh id
    # one past the current maximum across the dataset.
    def next_id
      load! unless defined?(@records) && @records
      max = @records.keys.max || 0
      max + 1
    end

    def insert!(record)
      @records ||= {}
      @order   ||= []
      raise ArgumentError, "Creature id #{record[:id]} already exists" \
        if @records.key?(record[:id])
      @records[record[:id]] = record
      @order << record[:id]
    end

    def delete!(id)
      i = Integer(id)
      return false unless @records&.key?(i)
      @records.delete(i)
      @order.delete(i)
      true
    end
  end
end
