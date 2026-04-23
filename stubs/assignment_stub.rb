# Character assignment stub. Lists known devices and lets the DM pick
# a character for each one. Rendering is DM-scoped — players never see
# the device list. The form posts to /user/assign_character with a
# device_id target; the app endpoint enforces the DM check.

helpers do
  def assignment_stub(devices:, characters:, current_device_id: nil,
                      assign_action: '/user/assign_character')
    # Defense in depth: the caller is expected to gate the stub on
    # dm? but we refuse to render if the viewing request is not a
    # DM, so a forgotten guard cannot leak the device list.
    return '' unless @current_user&.dm?
    erb :"stubs/_assignment_stub", layout: false, locals: {
      devices: devices || [],
      characters: characters || [],
      current_device_id: current_device_id,
      assign_action: assign_action
    }
  end

  def assignment_short_id(device_id)
    return '' if device_id.nil?
    s = device_id.to_s
    s.length > 8 ? s[0, 8] : s
  end

  def assignment_format_seen(ts)
    return '&mdash;' if ts.to_s.empty?
    begin
      t = Time.parse(ts.to_s)
      t.strftime('%Y-%m-%d %H:%M')
    rescue ArgumentError
      ts.to_s
    end
  end
end
