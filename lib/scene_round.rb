require 'json'
require 'fileutils'

# Scene Round — the DM Page's out-of-combat round counter. A lightweight
# analogue of the Combat Tracker's Round label for scenes run outside of
# initiative (chases, hazards, timed downtime): the DM steps it forward a
# round at a time, and each step advances the Chronicle Timestamp by one
# Round (6 seconds), exactly as a Combat Round wrap does. Persisted to
# data/scene_round.json so the count survives a server restart, like Combat.
module SceneRound
  # One Round of canonical time, in Chronicle Round units (a Round is the
  # atomic time step; the Advance Time controls treat 10 Rounds = 1 minute).
  ROUNDS_PER_STEP = 1

  class Store
    DATA_PATH = File.expand_path('../data/scene_round.json', __dir__)

    attr_reader :data_path

    def self.load(data_path: DATA_PATH)
      raw = File.exist?(data_path) ? (JSON.parse(File.read(data_path)) rescue {}) : {}
      new(raw, data_path: data_path)
    end

    def initialize(raw = {}, data_path: DATA_PATH)
      @data_path = data_path
      @round     = Integer((raw['round'] rescue nil) || 1)
      @round     = 1 if @round < 1
    end

    def round
      @round
    end

    # Advance to the next Round. Returns the new Round number.
    def next!
      @round += 1
      persist!
      @round
    end

    # Reset the scene back to Round 1 (does not touch the Chronicle clock).
    def reset!
      @round = 1
      persist!
      @round
    end

    def to_h
      { 'round' => @round }
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

  def reset!
    @store = nil
  end
end
