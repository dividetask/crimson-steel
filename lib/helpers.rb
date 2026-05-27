require 'socket'

LOOPBACK_ADDRS = %w[127.0.0.1 ::1 ::ffff:127.0.0.1].freeze

helpers do
  def dm_host?
    LOOPBACK_ADDRS.include?(request.ip)
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

  def menu_items
    [
      { label: 'Home',             href: '/',                 dm_only: false },
      { label: 'Character Sheets', href: '/character-sheets', dm_only: false },
      { label: 'Scene',            href: '/scene',            dm_only: false },
      { label: 'Store',            href: '/store',            dm_only: false },
      { label: 'Notes',            href: '/notes',            dm_only: false },
      { label: 'Social',           href: '/social',           dm_only: false },
      { label: 'Compendium',       href: '/compendium',       dm_only: false },
      { label: 'Status',           href: '/status',           dm_only: true  }
    ]
  end
end
