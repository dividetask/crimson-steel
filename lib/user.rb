require 'json'
require 'time'
require 'fileutils'
require 'securerandom'

# Per-device user tracking. The server gives each visiting device a
# random UUID cookie and keeps a tiny record per device: the UUID, an
# optional assigned character id, and whether the device is the DM.
# That is enough to remember the device on return visits without
# recording anything personally identifying. No passwords, no accounts.
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
      'is_dm' => false,
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

  def any_dm?
    @records.any? { |r| r['is_dm'] }
  end

  def dm_record
    @records.find { |r| r['is_dm'] }
  end

  # Promote a device to DM. When no DM exists yet this always succeeds;
  # otherwise pass force: true to overwrite the current DM.
  def set_dm(device_id, force: false)
    rec = find(device_id) or return false
    return true if rec['is_dm']
    return false if any_dm? && !force
    @records.each { |r| r['is_dm'] = false }
    rec['is_dm'] = true
    save!
    true
  end

  def clear_dm(device_id)
    rec = find(device_id) or return false
    rec['is_dm'] = false
    save!
    true
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
  attr_reader :device_id, :record

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
    new(device_id, rec, store)
  end

  def initialize(device_id, record, store)
    @device_id = device_id
    @record = record
    @store = store
  end

  def dm?
    @record['is_dm'] == true
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

  def claim_dm!(force: false)
    return false unless @store.set_dm(@device_id, force: force)
    @record['is_dm'] = true
    true
  end

  def release_dm!
    @store.clear_dm(@device_id)
    @record['is_dm'] = false
  end
end
