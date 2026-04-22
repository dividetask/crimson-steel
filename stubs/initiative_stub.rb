# Reusable initiative-track stub. Renders a sorted list of combat
# turns with initiative, name, and HP. The same partial is used for
# the player-facing scene view and the DM scene view; the dm_view
# flag controls how much enemy detail is exposed.
#
# Each turn is a hash with: combat_id, name, initiative, hp, hp_max,
# group ("PC" or anything else, e.g. "Enemy"). The list is rendered
# in the order given, so the caller decides sort order.

helpers do
  def initiative_stub(turns:, current_combat_id: nil, dm_view: false)
    erb :"stubs/_initiative_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      turns: turns || [],
      current_combat_id: current_combat_id,
      dm_view: dm_view
    }
  end

  # Bucket an HP fraction into a CSS class. Players see enemy HP only
  # through this lens — full bar means roughly full, empty means
  # roughly dead — so the DM never has to read out exact numbers.
  def initiative_hp_bucket(hp_now, hp_max)
    return :down if hp_now.to_i <= 0
    return :good if hp_max.to_i <= 0
    pct = (hp_now.to_f / hp_max) * 100.0
    if    pct >= 75 then :good
    elsif pct >= 50 then :warn
    elsif pct >= 25 then :orange
    else                 :bad
    end
  end
end
