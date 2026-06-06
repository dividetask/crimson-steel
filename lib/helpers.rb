require 'socket'
require 'securerandom'
require 'time'

LOOPBACK_ADDRS = %w[127.0.0.1 ::1 ::ffff:127.0.0.1].freeze

helpers do
  def h(text)
    Rack::Utils.escape_html(text.to_s)
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
      DeviceRegistry.instance.touch(device_id)
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

  # The Phase currently in effect (drives which Encounter stubs show).
  def current_encounter_phase
    Encounter.state.phase
  end

  def menu_items
    [
      { label: 'Home',             href: '/',                 dm_only: false },
      { label: 'Character Sheets', href: '/character-sheets', dm_only: false },
      { label: 'Encounter',        href: '/encounter',        dm_only: false },
      { label: 'Store',            href: '/store',            dm_only: false },
      { label: 'Notes',            href: '/notes',            dm_only: false },
      { label: 'Social',           href: '/social',           dm_only: false },
      { label: 'Compendium',       href: '/compendium',       dm_only: false },
      { label: 'Status',           href: '/status',           dm_only: true  }
    ]
  end
end
