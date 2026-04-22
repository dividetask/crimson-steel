# Reusable initiative-track stub. Renders a row per combatant with set-turn
# button (DM only), initiative string, name, segmented HP bar, combat pool
# with shock/pain badges, and a conditions cell. The same partial is used
# for the player-facing scene view and the DM combat tracker; dm_view
# controls how much enemy detail is exposed and whether the set-turn
# column is rendered.
#
# Each turn is a hash with: combat_id, name, initiative (string of digits
# and 'X' where X=10), hp, hp_max, minor_damage, moderate_damage,
# major_damage, combat_pool, combat_pool_max, shock, pain, conditions
# (array of {name, value}), group ("PC" or anything else, e.g. "Enemy").

helpers do
  def initiative_stub(turns:, current_combat_id: nil, dm_view: false, set_turn_action: '/combat/set_turn')
    erb :"stubs/_initiative_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      turns: turns || [],
      current_combat_id: current_combat_id,
      dm_view: dm_view,
      set_turn_action: set_turn_action
    }
  end

  # Build the segments for the HP bar in render order. Each segment is
  # [css_class, percentage]; percentages always sum to 100 even when
  # hp_max is 0 (degenerate case shows full "missing" / dark red).
  def initiative_hp_segments(hp_now, hp_max, minor, moderate, major)
    hp_now = [hp_now.to_i, 0].max
    hp_max = hp_max.to_i
    if hp_max <= 0
      return [['init-bar-major', 100.0]]
    end
    minor    = [minor.to_i, 0].max
    moderate = [moderate.to_i, 0].max
    major    = [major.to_i, 0].max
    # If the explicit damage breakdown undercounts the missing total
    # (e.g. damage applied directly to current_hp without classifying
    # it), pad the remainder onto the lightest bucket so the bar still
    # adds up.
    missing = hp_max - hp_now
    explicit = minor + moderate + major
    minor += (missing - explicit) if missing > explicit
    pct = ->(n) { (n.to_f / hp_max) * 100.0 }
    [
      ['init-bar-good',  pct.call(hp_now)],
      ['init-bar-minor', pct.call(minor)],
      ['init-bar-mod',   pct.call(moderate)],
      ['init-bar-major', pct.call(major)]
    ].reject { |_, p| p <= 0 }
  end

  # Short label + tooltip for a condition name. Anything not in the
  # table renders as a humanized form of the key.
  def initiative_condition_label(name)
    case name.to_s
    when 'bleed'        then ['Bleed',  'Loses HP at the start of each turn']
    when 'poison'       then ['Poison', 'Take damage and weaken until cleared']
    when 'major_damage' then ['Major',  'Has taken major damage']
    else
      label = name.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')
      [label, label]
    end
  end
end
