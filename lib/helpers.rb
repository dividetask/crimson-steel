require 'socket'

LOOPBACK_ADDRS = %w[127.0.0.1 ::1 ::ffff:127.0.0.1].freeze

helpers do
  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end

  def dm_host?
    LOOPBACK_ADDRS.include?(request.ip)
  end

  def viewing_as_player?
    dm_host? && session[:view_as_player]
  end

  def dm_view?
    dm_host? && !session[:view_as_player]
  end

  # The current viewer's role, derived purely from the request origin
  # (and the DM's View-As toggle). Used by the shared layout.
  def viewer_role
    dm_view? ? :dm : :player
  end

  # Name of the Character a player viewer is "playing", shown in the menu.
  # The Creatures domain that backed this is not currently coded, so there
  # is no name to surface and the menu omits the label.
  def viewing_creature_name
    nil
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

  # The Phase shown as selected in the menu dropdown. The Encounter domain
  # that tracked live Phase is not currently coded, so this falls back to
  # the first option; changing it posts to the (not-yet-implemented)
  # Encounter route.
  def current_encounter_phase
    :combat
  end

  def menu_items
    [
      { label: 'Home',             href: '/',                 dm_only: false },
      { label: 'Character Sheets', href: '/character-sheets', dm_only: false },
      { label: 'Encounter',        href: '/encounter',        dm_only: false },
      { label: 'Store',            href: '/store',            dm_only: false },
      { label: 'Notes',            href: '/notes',            dm_only: false },
      { label: 'Compendium',       href: '/compendium',       dm_only: false },
      { label: 'Status',           href: '/status',           dm_only: true  }
    ]
  end
end
