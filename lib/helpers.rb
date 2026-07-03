require 'socket'
require 'securerandom'
require 'time'

LOOPBACK_ADDRS = %w[127.0.0.1 ::1 ::ffff:127.0.0.1].freeze

# A per-process id, regenerated on each server start. Used to scope
# client-side UI state (the Roster Sidebar's collapsed/expanded groups)
# so it persists across navigation within one server run but resets to
# the default — all groups collapsed — whenever the server restarts.
SERVER_BOOT_ID = SecureRandom.hex(8)

helpers do
  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end

  # For an image URL path that points at a WebP file, return the URL of a
  # sibling JPG/PNG fallback if one exists on disk (same basename), else
  # nil. Older browsers (Safari 12 / iOS 12) cannot decode WebP, so the
  # chronicle image markup serves the fallback to them via <picture>.
  # Returns nil for non-WebP images (a plain <img> already works there).
  def image_fallback_src(url_path)
    s = url_path.to_s
    return nil unless s.downcase.end_with?('.webp')
    base = s.sub(/\.webp\z/i, '')
    %w[.jpg .jpeg .png].each do |ext|
      candidate = base + ext
      disk = File.join(settings.public_folder, candidate)
      return candidate if File.file?(disk)
    end
    nil
  end

  def dm_host?
    LOOPBACK_ADDRS.include?(request.ip)
  end

  # The record for the device making this request. The server hands
  # every device a random UUID in a long-lived cookie and remembers it
  # in the DeviceRegistry; this resolves (and lazily creates) that
  # record, stamping last_seen. Memoized per request.
  def current_device
    @current_device ||= begin
      device_id = request.cookies[DeviceRegistry::COOKIE]
      unless device_id && DeviceRegistry.instance.find(device_id)
        device_id = SecureRandom.uuid
        response.set_cookie(DeviceRegistry::COOKIE,
                            value:    device_id,
                            path:     '/',
                            httponly: true,
                            expires:  Time.now + (60 * 60 * 24 * 365 * 5))
      end
      DeviceRegistry.instance.touch(device_id, request.user_agent)
    end
  end

  def current_device_id
    current_device['device_id']
  end

  # The Character id this device defaults to on the Character Sheets
  # page, or nil when the device has no assignment.
  def assigned_character_id
    current_device['character_id']
  end

  # Eight-character preview of a device id for the assignment stub —
  # enough to tell devices apart without showing a full UUID.
  def assignment_short_id(device_id)
    s = device_id.to_s
    s.length > 8 ? s[0, 8] : s
  end

  # The browser User-Agent recorded for a device, or a dash when none has
  # been captured yet. Shown in the device table so the DM can see exactly
  # what each connecting device is running.
  def assignment_user_agent(ua)
    s = ua.to_s.strip
    s.empty? ? '—' : s
  end

  # Human-friendly "last seen" timestamp for the assignment stub.
  def assignment_format_seen(iso)
    return '—' if iso.to_s.empty?
    Time.parse(iso.to_s).strftime('%Y-%m-%d %H:%M')
  rescue ArgumentError
    iso.to_s
  end

  def viewing_as_player?
    dm_host? && session[:view_as_player]
  end

  def dm_view?
    dm_host? && !session[:view_as_player]
  end

  def server_address
    Socket.ip_address_list
          .find { |a| a.ipv4? && !a.ipv4_loopback? }
          &.ip_address || '127.0.0.1'
  end

  # The Encounter Phase options for the DM's menu dropdown, as
  # [symbol, label] pairs in the order they appear.
  def encounter_phases
    [[:combat,    'Combat'],
     [:looting,   'Looting'],
     [:traveling, 'Traveling'],
     [:social,    'Social Encounter'],
     [:downtime,  'Downtime']]
  end

  # The actual (party) Phase — what players see and what the menu dropdown
  # sets. The DM's own view may diverge via a private override (below).
  def current_encounter_phase
    Encounter.state.phase
  end

  # A DM-only, session-local Phase override. When set, the DM's Encounter
  # view renders this Phase instead of the party's, letting the DM prepare a
  # Phase without changing what players see. Ignored for any non-DM viewer,
  # and cleared whenever the actual (party) Phase changes. Returns the
  # override symbol, or nil when the DM is following the party.
  def dm_phase_override
    return nil unless dm_view?
    sym = session[:dm_phase_override].to_s
    sym = sym.empty? ? nil : sym.to_sym
    encounter_phases.any? { |val, _| val == sym } ? sym : nil
  end

  # The Phase the current viewer should render: the DM's private override
  # when one is set, otherwise the shared party Phase.
  def effective_encounter_phase
    dm_phase_override || Encounter.state.phase
  end

  def menu_items
    [
      { label: 'Home',             href: '/',                 dm_only: false },
      { label: 'Sheets',           href: '/character-sheets', dm_only: false },
      { label: 'Encounter',        href: '/encounter',        dm_only: false },
      { label: 'Store',            href: '/store',            dm_only: false },
      { label: 'Notes',            href: '/notes',            dm_only: false },
      { label: 'Compendium',       href: '/compendium',       dm_only: false },
      { label: 'DM',               href: '/dm',               dm_only: true  },
      { label: 'Status',           href: '/status',           dm_only: true  }
    ]
  end

  # Roll a freshly-spawned Creature's `equipment_table` (if any) and place
  # the resulting Stacks — gear, ammunition, pocket change — onto the
  # Creature, then reconcile the loadout so equipped items post their
  # Effects. Called after Spawn Creature From Template so each spawn gets a
  # randomized kit. No-op when the Creature has no equipment_table.
  def equip_spawned_creature(creature_id)
    accessor = Creatures.lookup(creature_id)
    return unless accessor
    table = accessor.equipment_table
    return if table.nil? || table.to_s.empty?

    # Seed the roll with the spawn's resolved race so race-aware loadouts
    # (e.g. the Slaver) can branch on `when: { race: orc }`.
    rolled = Equipment.instance.roll_loot_table(table.to_s, vars: { 'race' => accessor.race })
    return if rolled.equal?(Equipment::ERROR)

    owner = "creature:#{creature_id}"
    Array(rolled).each { |stack| Equipment.instance.add_item(owner, stack) }
    Equipment.instance.reconcile_loadout(owner)
  end
end
