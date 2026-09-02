require 'fileutils'
require 'json'
require_relative '../data_paths'

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
    DATA_PATH    = DataPaths.path('conditions_data.json')
    EXAMPLE_PATH = File.expand_path('../../docs/common/conditions/conditions_data.example.json', __dir__)

    attr_reader :data_path, :catalog

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH, catalog: nil)
      path = DataPaths.source(data_path, example_path)
      raw = path ? JSON.parse(File.read(path)) : {}
      new(raw, data_path: data_path, catalog: catalog)
    end

    def initialize(raw = {}, data_path: DATA_PATH, catalog: nil)
      @data_path = data_path
      @catalog   = catalog || Catalog.load
      @states    = {}
      (raw['creatures'] || {}).each do |id, state_hash|
        @states[id.to_s] = State.load(state_hash)
      end
      @zone_effects = (raw['zone_effects'] || []).map { |z| normalize_zone_effect(z) }
    end

    # ---------- Zone Effects (module-level, not per-Creature) ----------
    #
    # A Zone Effect is a spatial Effect (a spell's area, a hazard) paired
    # with an Atlas Zone by a shared `source_id`. Conditions owns the
    # mechanical record (triggers + expiry); Atlas owns the footprint. See
    # conditions_design.md → Zone Effect. The Atlas Zone is placed by the
    # orchestrating caller, which passes the resulting `atlas_zone_id` here.

    # Create (or replace, by source_id) a Zone Effect.
    def create_zone_effect(source_id:, atlas_zone_id:, triggers: {}, ends_on_round: nil, metadata: {})
      rec = normalize_zone_effect('source_id' => source_id, 'atlas_zone_id' => atlas_zone_id,
                                  'triggers' => triggers, 'ends_on_round' => ends_on_round,
                                  'metadata' => metadata)
      @zone_effects.reject! { |z| z[:source_id] == rec[:source_id] }
      @zone_effects << rec
      rec
    end

    # Remove a Zone Effect by source_id; returns the removed record or nil.
    def remove_zone_effect(source_id:)
      removed = @zone_effects.find { |z| z[:source_id] == source_id.to_s }
      @zone_effects.delete(removed) if removed
      removed
    end

    def zone_effect(source_id:)
      @zone_effects.find { |z| z[:source_id] == source_id.to_s }
    end

    # Active Zone Effects — those not expired as of `current_round` (when
    # supplied). A null `ends_on_round` never expires here.
    def list_zone_effects(current_round: nil)
      @zone_effects.reject { |z| current_round && z[:ends_on_round] && z[:ends_on_round] <= current_round }
    end

    # Drop every Zone Effect whose `ends_on_round` has passed; returns them.
    def clear_expired_zone_effects(current_round)
      expired = @zone_effects.select { |z| z[:ends_on_round] && z[:ends_on_round] <= current_round }
      @zone_effects -= expired
      expired
    end

    # Remove a caster's Zone Effects that have expired as of current_round —
    # the start-of-turn auto-expiry. A caster owns a Zone Effect when its
    # metadata `caster_id` matches. Returns the removed records so the caller
    # can drop the paired Atlas Zones.
    def expire_zone_effects_for(caster_id, current_round)
      removable = @zone_effects.select do |z|
        owner = z[:metadata] && (z[:metadata]['caster_id'] || z[:metadata][:caster_id])
        owner.to_s == caster_id.to_s && z[:ends_on_round] && z[:ends_on_round] <= current_round
      end
      @zone_effects -= removable
      removable
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
      h = { 'creatures' => out }
      h['zone_effects'] = @zone_effects.map { |z| stringify_zone_effect(z) } unless @zone_effects.empty?
      h
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, JSON.pretty_generate(to_h))
      File.rename(tmp, @data_path)
    end

    private

    # Coerce a raw (string- or symbol-keyed) Zone Effect into the canonical
    # symbol-keyed record. Triggers are stored opaquely (Combat builds the
    # Saving Throw from them).
    def normalize_zone_effect(z)
      z = z.transform_keys(&:to_s) if z.respond_to?(:transform_keys)
      trig = (z['triggers'] || {})
      trig = trig.transform_keys(&:to_s) if trig.respond_to?(:transform_keys)
      {
        source_id:     z.fetch('source_id').to_s,
        atlas_zone_id: z['atlas_zone_id'],
        triggers: {
          on_create:      trig['on_create'],
          on_enter:       trig['on_enter'],
          on_end_of_turn: trig['on_end_of_turn']
        },
        ends_on_round: z['ends_on_round']&.then { |r| Integer(r) },
        metadata: z['metadata'] || {}
      }
    end

    def stringify_zone_effect(z)
      {
        'source_id'     => z[:source_id],
        'atlas_zone_id' => z[:atlas_zone_id],
        'triggers' => {
          'on_create'      => z[:triggers][:on_create],
          'on_enter'       => z[:triggers][:on_enter],
          'on_end_of_turn' => z[:triggers][:on_end_of_turn]
        }.compact,
        'ends_on_round' => z[:ends_on_round],
        'metadata'      => z[:metadata]
      }.compact
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
