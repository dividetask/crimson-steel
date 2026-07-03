module Encounter
  # Player-facing visibility rules for the Combat Tracker rows built by
  # `build_tracker_row`. A non-player Combatant's vitals are the DM's to see:
  # players never see its Mana or Conditions, and see its HP numbers / Magic
  # Toxicity only through a cleric's See Injury ability. (Combat Pool stays
  # visible to players.)
  #
  # Only the party's own Player Characters (`row[:is_pc] == true`) render in
  # full to players — every other Combatant (enemy or NPC) is redacted. The
  # DM always sees everything.
  #
  # See docs/common/ui/encounter_initiative_stub.md ("Player visibility of
  # non-player vitals").
  module Visibility
    module_function

    # Return `rows` with each non-Player-Character row redacted for a non-DM
    # viewer.
    #   viewer      — :dm or :player.
    #   sees_injury — true when the viewer's assigned Character has the
    #                 `see_injury` ability (See Injury). Only meaningful
    #                 for a :player viewer.
    # The DM sees the rows unchanged. For a player, Player-Character rows pass
    # through untouched and every other row is redacted (a copy — the
    # originals the caller may still hold, e.g. the acting row, are left
    # intact).
    def redact_rows(rows, viewer:, sees_injury: false)
      return rows if viewer == :dm
      rows.map { |row| redact_row(row, sees_injury: sees_injury) }
    end

    # Redact a single non-Player-Character row. Player-Character rows are
    # returned unchanged. Mana and Conditions are always hidden from players
    # (Combat Pool stays visible). The HP bar stays visible as a rough health
    # gauge, but its raw numbers are hidden unless the viewer has See Injury;
    # Magic Toxicity is hidden outright unless the viewer has See Injury. The
    # cannot-act highlight is cleared too, so a creature's incapacitation is
    # not leaked through row styling.
    def redact_row(row, sees_injury: false)
      return row if row[:is_pc]
      hidden = row.dup
      hidden[:mana]        = nil
      hidden[:badges]      = []
      hidden[:can_act]     = true
      unless sees_injury
        # Keep the HP hash (the bar reads its segment widths from it) but
        # flag it so the raw current/max numbers and tooltip are withheld.
        hidden[:hp]       = row[:hp] && row[:hp].merge(hide_numbers: true)
        hidden[:toxicity] = nil
      end
      hidden
    end
  end
end
