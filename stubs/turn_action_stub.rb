# Turn Action stub — DM-only menu of per-turn action panels.
#
# Left column is a vertical list of buttons (configurable in
# combat_config.yaml's `Turn Action Buttons`). Right column is
# all panels rendered up-front and shown / hidden by JS — no
# fetch round-trips. Default panel is the first button in the
# list.
#
# Panels currently wired:
#   start_of_turn  placeholder roll-and-confirm flow
#   attack         existing attack_stub
#   move           generic confirm stub, posts /combat/move
#   cast / item / special  "coming soon" placeholders
#   end_turn       generic confirm stub, posts /combat/end_turn
#
# Adding a new button: add the key to `Turn Action Buttons`,
# add an entry in TURN_ACTION_BUTTON_LABELS for the menu label,
# and render its panel in views/stubs/_turn_action_stub.erb.

require 'yaml'

helpers do
  TURN_ACTION_BUTTON_LABELS = {
    'start_of_turn' => 'Start of Turn',
    'attack'        => 'Attack',
    'move'          => 'Move',
    'cast'          => 'Cast',
    'item'          => 'Item',
    'special'       => 'Special',
    'end_turn'      => 'End Turn'
  }.freeze

  TURN_ACTION_DEFAULT_BUTTONS  = TURN_ACTION_BUTTON_LABELS.keys.freeze
  TURN_ACTION_DEFAULT_MOVE_COST = 4

  TURN_ACTION_CONFIG_PATHS = [
    File.expand_path('../data/combat_rules.yaml',                __dir__),
    File.expand_path('../data/combat_config.yaml',               __dir__),
    File.expand_path('../docs/combat/combat_config.yaml.example', __dir__)
  ].freeze

  def turn_action_config
    @turn_action_config ||= begin
      raw = TURN_ACTION_CONFIG_PATHS.lazy
              .map { |p| File.exist?(p) ? (YAML.safe_load_file(p) || {}) : nil }
              .find { |d| d }
      raw ||= {}
      buttons = Array(raw['Turn Action Buttons']).map(&:to_s).reject(&:empty?)
      buttons = TURN_ACTION_DEFAULT_BUTTONS.dup if buttons.empty?
      {
        'buttons'   => buttons,
        'move_cost' => (raw['Move Cost'] || TURN_ACTION_DEFAULT_MOVE_COST).to_i
      }
    end
  end

  def turn_action_button_label(key)
    TURN_ACTION_BUTTON_LABELS[key.to_s] || key.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')
  end

  # Render the Turn Action stub. Caller passes the same dummy
  # attack-stub data the test page uses so the Attack panel
  # renders something even when no real attacker / target wiring
  # exists yet.
  def turn_action_stub(active_combatant:, attacker:, targets:, ally_reactions: [], luck_sources: [])
    cfg = turn_action_config
    erb :"stubs/_turn_action_stub", layout: false, locals: {
      stub_id:          SecureRandom.hex(4),
      buttons:          cfg['buttons'],
      move_cost:        cfg['move_cost'],
      active_combatant: active_combatant,
      attacker:         attacker,
      targets:          targets,
      ally_reactions:   ally_reactions,
      luck_sources:     luck_sources
    }
  end
end

post '/combat/start_of_turn' do
  halt 403, 'forbidden' unless current_user&.dm?
  # Placeholder — real start-of-turn pipeline (reset combat dice,
  # apply shock, acid counter, afflictions, expire conditions)
  # lands when Conditions / Effects / damage_types are wired.
  redirect(request.referer || '/combat')
end

post '/combat/move' do
  halt 403, 'forbidden' unless current_user&.dm?
  # Placeholder — action-dice deduction lands once the Combat
  # state file is being written from the page.
  redirect(request.referer || '/combat')
end

post '/combat/end_turn' do
  halt 403, 'forbidden' unless current_user&.dm?
  turns = DATA.combat_state['turns'] || []
  if turns.any?
    current = NOTES_STATE.current_turn || DATA.combat_state['current_turn']
    idx     = turns.find_index { |t| t['combat_id'] == current } || -1
    NOTES_STATE.current_turn = turns[(idx + 1) % turns.length]['combat_id']
  end
  redirect(request.referer || '/combat')
end
