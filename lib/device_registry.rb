require_relative 'data_dir'
require 'json'
require 'time'
require 'fileutils'
require 'monitor'

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
# The records persist to a JSON file under data/ (gitignored). The
# registry starts empty; rows appear only as real devices connect (the
# DM's own machine first, then each player device on its first request).
class DeviceRegistry
  COOKIE    = 'crimson_device_id'.freeze
  DATA_PATH = DataDir.path('devices.json').freeze

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
    @records = File.exist?(@data_path) ? read_records : []
    # Requests run on several threads at once (every phone polls, and so
    # does the DM's page): one at a time changes and saves the records.
    @lock = Monitor.new
  end

  # All records, newest activity first, as defensive copies.
  def list
    @lock.synchronize { @records.map(&:dup) }.sort_by { |r| r['last_seen'].to_s }.reverse
  end

  def find(device_id)
    @records.find { |r| r['device_id'] == device_id }
  end

  # Returns the record for device_id, creating it on first sight and
  # stamping last_seen either way. This is the per-request entry point.
  # The browser's User-Agent string is recorded when supplied so the DM
  # can see what each connecting device is running (a diagnostic aid for
  # device-specific display problems).
  def touch(device_id, user_agent = nil)
    @lock.synchronize do
      rec = find(device_id) || create(device_id)
      rec['last_seen'] = Time.now.iso8601
      rec['user_agent'] = user_agent unless user_agent.nil? || user_agent.to_s.empty?
      persist!
      rec
    end
  end

  def create(device_id)
    @lock.synchronize do
      rec = blank_record(device_id)
      @records << rec
      persist!
      rec
    end
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
    @lock.synchronize do
      rec = find(device_id) || create(device_id)
      rec['character_id'] = normalize_character_id(character_id)
      persist!
      rec
    end
  end

  def unassign_character(device_id)
    assign_character(device_id, nil)
  end

  # The Android app identifies itself with its own id, the same for every
  # install on that phone (APP_ID). The first time it uses that id, its old
  # server-issued id (+from+, if the app still had one) is renamed to it, so
  # its Character assignment carries over; otherwise a fresh record.
  APP_ID = /\A[0-9a-f]{16}\z/

  def adopt(device_id, from: nil)
    @lock.synchronize do
      return find(device_id) if find(device_id)
      old = from && find(from.to_s)
      if old
        old['device_id'] = device_id
        persist!
        old
      else
        create(device_id)
      end
    end
  end

  # Forget a device (the DM's Remove on the Status page). True when removed.
  def remove(device_id)
    @lock.synchronize do
      before = @records.length
      @records.reject! { |r| r['device_id'] == device_id }
      persist! if @records.length != before
      @records.length != before
    end
  end

  # Forget every device with no Character, except +keep+ (the DM's own).
  # Returns how many were removed.
  def remove_unassigned(keep: nil)
    @lock.synchronize do
      before = @records.length
      @records.reject! { |r| r['character_id'].nil? && r['device_id'] != keep }
      persist! if @records.length != before
      before - @records.length
    end
  end

  private

  def blank_record(device_id)
    { 'device_id' => device_id, 'character_id' => nil, 'last_seen' => Time.now.iso8601,
      'user_agent' => nil }
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
    tmp = "#{@data_path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
    File.write(tmp, JSON.pretty_generate(@records))
    File.rename(tmp, @data_path)
  end
end
