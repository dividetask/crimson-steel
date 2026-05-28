require 'fileutils'
require 'json'

module Conditions
  # Per-Creature Conditions store, keyed by Creature ID. Mirrors the
  # Chronicle::Store / Encounter::State persistence pattern: load order
  # is the data file first, falling back to the example. Holds one
  # Conditions::State per Creature and a shared Catalog; mutations are
  # persisted back to disk.
  #
  # States are created lazily — a Creature with no recorded Conditions
  # resolves to a fresh empty State (full HP, no afflictions) and is
  # only written out once something mutates it.
  class Store
    DATA_PATH    = File.expand_path('../../data/conditions_data.json', __dir__)
    EXAMPLE_PATH = File.expand_path('../../docs/common/conditions/conditions_data.example.json', __dir__)

    attr_reader :data_path, :catalog

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH, catalog: nil)
      path = File.exist?(data_path) ? data_path : example_path
      raw = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      new(raw, data_path: data_path, catalog: catalog)
    end

    def initialize(raw = {}, data_path: DATA_PATH, catalog: nil)
      @data_path = data_path
      @catalog   = catalog || Catalog.load
      @states    = {}
      (raw['creatures'] || {}).each do |id, state_hash|
        @states[id.to_s] = State.load(state_hash)
      end
    end

    # ---------- Reads ----------

    # The stored State for a Creature, or a fresh empty State when the
    # Creature has none recorded. The returned State is the live object
    # (mutations stick); call persist! afterward to write them out.
    def state_for(creature_id)
      id = creature_id.to_s
      @states[id] ||= State.new
    end

    def state?(creature_id)
      @states.key?(creature_id.to_s)
    end

    # A Conditions::Instance pairing this Creature's State with the
    # shared Catalog, for running the documented operations.
    def instance_for(creature_id)
      Instance.new(state: state_for(creature_id), catalog: @catalog)
    end

    # ---------- Persistence ----------

    def to_h
      out = {}
      @states.each do |id, state|
        h = state.to_h
        out[id] = h unless h.empty?
      end
      { 'creatures' => out }
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, JSON.pretty_generate(to_h))
      File.rename(tmp, @data_path)
    end
  end

  module_function

  def store
    @store ||= Store.load
  end

  # Test seam — swap the live store. Pass nil to lazy-reload.
  def store=(s)
    @store = s
  end

  def reset!
    @store = nil
  end
end
