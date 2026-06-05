require 'json'
require 'time'
require 'fileutils'

# Tracks every device that has connected to the server and remembers,
# for each one, which player Character the DM has assigned to it.
#
# Each device is recognized by a random UUID the server hands out in a
# long-lived cookie (see lib/helpers.rb#current_device). The registry
# stores only the minimum needed to recognize a returning device and to
# answer "which Character does this device drive by default?":
#
#   { "device_id" => "<uuid>", "character_id" => <int|nil>,
#     "last_seen" => "<iso8601>" }
#
# DM-vs-player identity is deliberately NOT stored here. Per CLAUDE.md
# that is derived from the request's origin (loopback = DM); the same
# physical machine is always the DM regardless of its device record.
#
# The records persist to a JSON file under data/ (gitignored). A fresh
# registry seeds a couple of demo devices so the Status -> Devices stub
# has something to show before any real player has connected.
class DeviceRegistry
  COOKIE    = 'crimson_device_id'.freeze
  DATA_PATH = File.expand_path('../data/devices.json', __dir__).freeze

  # Seeded into a brand-new registry. The ids are intentionally
  # human-readable; the assignment stub shortens ids to eight
  # characters, so these render as "demo-pho" and "demo-tab".
  DEMO_DEVICE_IDS = %w[demo-phone demo-tablet].freeze

  class << self
    # Process-wide registry pointed at the default data file. Routes and
    # helpers go through this; specs build their own with a temp path.
    def instance
      @instance ||= new
    end

    # Test seam — drop the memoized instance so a spec can rebuild it.
    def reset!
      @instance = nil
    end
  end

  attr_reader :data_path

  def initialize(data_path = DATA_PATH)
    @data_path = data_path
    if File.exist?(@data_path)
      @records = read_records
    else
      @records = DEMO_DEVICE_IDS.map { |id| blank_record(id) }
      persist!
    end
  end

  # All records, newest activity first, as defensive copies.
  def list
    @records.map(&:dup).sort_by { |r| r['last_seen'].to_s }.reverse
  end

  def find(device_id)
    @records.find { |r| r['device_id'] == device_id }
  end

  # Returns the record for device_id, creating it on first sight and
  # stamping last_seen either way. This is the per-request entry point.
  def touch(device_id)
    rec = find(device_id) || create(device_id)
    rec['last_seen'] = Time.now.iso8601
    persist!
    rec
  end

  def create(device_id)
    rec = blank_record(device_id)
    @records << rec
    persist!
    rec
  end

  # The Character id this device defaults to, or nil when unassigned.
  def character_id_for(device_id)
    rec = find(device_id)
    rec && rec['character_id']
  end

  # Assign a player Character to a device (creating the record if the
  # DM is assigning a device that has not been seen yet). Pass nil to
  # clear the assignment.
  def assign_character(device_id, character_id)
    rec = find(device_id) || create(device_id)
    rec['character_id'] = normalize_character_id(character_id)
    persist!
    rec
  end

  def unassign_character(device_id)
    assign_character(device_id, nil)
  end

  private

  def blank_record(device_id)
    { 'device_id' => device_id, 'character_id' => nil, 'last_seen' => Time.now.iso8601 }
  end

  def normalize_character_id(value)
    return nil if value.nil? || value.to_s.strip.empty?
    Integer(value)
  end

  def read_records
    raw = JSON.parse(File.read(@data_path))
    raw.is_a?(Array) ? raw : []
  rescue JSON::ParserError
    []
  end

  def persist!
    FileUtils.mkdir_p(File.dirname(@data_path))
    tmp = "#{@data_path}.tmp"
    File.write(tmp, JSON.pretty_generate(@records))
    File.rename(tmp, @data_path)
  end
end
