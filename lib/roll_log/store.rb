require 'json'
require 'fileutils'

module RollLog
  # Append-only log of player Skill Rolls, persisted to data/roll_log.json.
  # Players POST each Roll here from the compact roll stub so the DM sees every
  # roll — and its full history — on the DM Page. Newest entries surface first.
  class Store
    DATA_PATH   = File.expand_path('../../data/roll_log.json', __dir__)
    MAX_ENTRIES = 1000

    attr_reader :data_path

    def self.load(data_path: DATA_PATH)
      raw = File.exist?(data_path) ? (JSON.parse(File.read(data_path)) rescue {}) : {}
      new(raw, data_path: data_path)
    end

    def initialize(raw = {}, data_path: DATA_PATH)
      @data_path = data_path
      @entries   = Array((raw['entries'] rescue nil)).map { |e| normalize(e) }
      @next_id   = Integer((raw['next_id'] rescue nil) || (max_id + 1))
    end

    # Every Roll, newest first. `limit` caps the count returned.
    def recent(limit = nil)
      sorted = @entries.sort_by { |e| -e['id'] }
      limit ? sorted.first(limit) : sorted
    end

    def add(attrs)
      entry = normalize(attrs)
      entry['id'] = @next_id
      @next_id += 1
      @entries << entry
      @entries = @entries.last(MAX_ENTRIES)
      persist!
      entry
    end

    def clear!
      @entries = []
      persist!
    end

    def to_h
      { 'entries' => @entries, 'next_id' => @next_id }
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, JSON.pretty_generate(to_h))
      File.rename(tmp, @data_path)
    end

    private

    def normalize(entry)
      e = stringify(entry)
      {
        'id'                 => (e['id'] ? Integer(e['id']) : nil),
        'creature_id'        => e['creature_id'],
        'creature_name'      => (e['creature_name'] || '').to_s,
        'roll_name'          => (e['roll_name'] || '').to_s,
        'ranks'              => e['ranks'].to_i,
        'tn'                 => e['tn'].to_i,
        'base_tn'            => (e['base_tn'].nil? ? nil : e['base_tn'].to_i),
        'bonus_penalty_list' => normalize_bpl(e['bonus_penalty_list']),
        'dice_count'         => e['dice_count'].to_i,
        'starting_value'     => e['starting_value'].to_i,
        'dice'               => Array(e['dice']).map { |d| d.nil? ? nil : d.to_i },
        'dois'               => e['dois'].to_i,
        'critical_count'     => e['critical_count'].to_i,
        'at'                 => (e['at'] || 0).to_i
      }
    end

    def stringify(h)
      h.respond_to?(:transform_keys) ? h.transform_keys(&:to_s) : {}
    end

    # The TN Bonus/Penalty list as `[type, amount]` pairs (type String,
    # amount Integer) — the shape DiceResolution.with_ascendancy expects when
    # the Log page rebuilds the TN math. Anything malformed is dropped.
    def normalize_bpl(list)
      Array(list).filter_map do |pair|
        type, amount = pair
        next if type.nil? || amount.nil?
        [type.to_s, amount.to_i]
      end
    end

    def max_id
      @entries.map { |e| e['id'].to_i }.max || 0
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
