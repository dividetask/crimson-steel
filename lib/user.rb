require 'json'
require 'time'
require 'fileutils'
require 'securerandom'

# Per-device user tracking. The server gives each visiting device a
# random UUID cookie and keeps the bare minimum needed to remember the
# device on return: the UUID and an optional assigned character id.
# DM status is not stored — it is derived from the request itself
# (see User.dm_request?), matching the before-refactor behavior where
# whichever device runs the server is the DM.
class UserStore
  DEVICE_COOKIE = 'crimson_device_id'.freeze

  def initialize(path)
    @path = path
    FileUtils.mkdir_p(File.dirname(@path))
    @records = File.exist?(@path) ? JSON.parse(File.read(@path)) : []
  end

  def save!
    File.write(@path, JSON.pretty_generate(@records))
  end

  def find(device_id)
    @records.find { |r| r['device_id'] == device_id }
  end

  def create(device_id)
    rec = {
      'device_id' => device_id,
      'character_id' => nil,
      'first_seen' => Time.now.iso8601,
      'last_seen' => Time.now.iso8601
    }
    @records << rec
    save!
    rec
  end

  def touch(rec)
    rec['last_seen'] = Time.now.iso8601
    save!
  end

  def list
    @records.map(&:dup)
  end

  def assign_character(device_id, character_id)
    rec = find(device_id) or return false
    rec['character_id'] = character_id
    save!
    true
  end

  def unassign_character(device_id)
    rec = find(device_id) or return false
    rec['character_id'] = nil
    save!
    true
  end
end

# Per-request wrapper built by User.identify at the start of every
# request. Reads the cookie, creates a record on first visit, and
# exposes a small role-aware API for routes and views.
class User
  LOCAL_IPS = %w[127.0.0.1 ::1 localhost].freeze

  attr_reader :device_id, :record

  # Whichever device shares an IP with the server is the DM. No state
  # is stored about which device that is — it is just a property of
  # the request.
  def self.dm_request?(request)
    LOCAL_IPS.include?(request.ip)
  end

  def self.identify(request, response, store)
    device_id = request.cookies[UserStore::DEVICE_COOKIE]
    unless device_id && store.find(device_id)
      device_id = SecureRandom.uuid
      response.set_cookie(UserStore::DEVICE_COOKIE,
                          value: device_id,
                          path: '/',
                          httponly: true,
                          expires: Time.now + (60 * 60 * 24 * 365 * 5))
    end
    rec = store.find(device_id) || store.create(device_id)
    store.touch(rec)
    new(device_id, rec, store, dm: dm_request?(request))
  end

  def initialize(device_id, record, store, dm:)
    @device_id = device_id
    @record = record
    @store = store
    @dm = dm
  end

  def dm?
    @dm
  end

  def character_id
    @record['character_id']
  end

  def assigned?
    !character_id.nil?
  end

  def assign_character(character_id)
    @store.assign_character(@device_id, character_id)
    @record['character_id'] = character_id
  end

  def unassign_character
    @store.unassign_character(@device_id)
    @record['character_id'] = nil
  end
end
