# Device tracking + Character assignment.
#
# Every (non-static) request runs through the before filter so any
# device that connects is recorded in the DeviceRegistry the first time
# it is seen and has its last_seen stamped on return. Identity is purely
# the per-device cookie; DM-vs-player is still derived from the request
# origin (see lib/helpers.rb).
before do
  current_device
end

# DM assigns (or clears) the player Character a device defaults to on
# the Character Sheets page. Gated on the real DM host so a player
# device cannot reassign itself or anyone else.
post '/devices/assign' do
  halt 403 unless dm_host?
  device_id = params[:device_id].to_s.strip
  halt 400 if device_id.empty?

  character_id = params[:character_id].to_s.strip
  if character_id.empty?
    DeviceRegistry.instance.unassign_character(device_id)
  else
    DeviceRegistry.instance.assign_character(device_id, character_id.to_i)
  end

  redirect(request.referer || '/status?view=devices')
end
