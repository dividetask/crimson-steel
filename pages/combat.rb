# /combat — round-by-round combat tracker page.
#
# Layout (top to bottom):
#   1. Combat Tracker page header.
#   2. Initiative stub (existing; renders the active combatant
#      list with HP / pool / conditions).
#   3. Turn Action stub (DM only) — left-column button menu
#      driving a right-column panel that handles the active
#      combatant's per-turn actions.
#   4. Minimal character stub for the active combatant. Always
#      shown when the active combatant is a PC; DM-only when
#      they're an enemy; hidden entirely when no combatant is
#      active.

get '/combat' do
  turns        = DATA.combat_state['turns'] || []
  current_id   = NOTES_STATE.current_turn || DATA.combat_state['current_turn']
  current_turn = turns.find { |t| t['combat_id'] == current_id }
  char_id      = current_turn&.dig('char_id')

  pc_entry = char_id ? DATA.pc_objects.find { |p| p[:character].id == char_id } : nil
  @active_character = pc_entry&.dig(:character)
  @active_dummy     = pc_entry&.dig(:dummy) || {}
  @active_is_pc     = !pc_entry.nil?
  @active_label     = current_turn&.dig('name')

  @turns        = turns
  @current_turn = current_id
  @round        = DATA.combat_state['round']

  erb :"pages/combat"
end
