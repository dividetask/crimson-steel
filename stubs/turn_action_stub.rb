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

  combatant = COMBAT.combatants.find { |c| c['id'].to_i == params[:combat_id].to_i }
  halt 400, 'unknown combatant' unless combatant

  char = CHARACTER_LOOKUP.call(combatant['char_id'])
  halt 400, 'unknown character' unless char

  conditions = CONDITIONS_REGISTRY&.for_character(combatant['char_id'])
  halt 500, 'conditions registry unavailable' unless conditions

  # Order matches the pipeline documented in the start-of-turn stub
  # view and in views/stubs/_turn_action_stub.erb.

  # 1. Reset action dice to action_dice_max for this combatant.
  COMBAT.reset_action_dice(combatant['id'])

  # 2. Consume Shock against the freshly reset pool.
  shock_to_consume = conditions.shock
  if shock_to_consume > 0
    consumed = conditions.consume_shock(shock_to_consume)
    COMBAT.spend_action_dice(combatant['id'], consumed)
  end

  # 3. Resolve the Acid Counter: halve, deal halved value as Minor HP.
  conditions.resolve_acid_turn_start

  # 4. Resolve afflictions using the rolls the player already made.
  rolls_raw = params[:rolls].to_s
  rolls = rolls_raw.empty? ? [] : (JSON.parse(rolls_raw) rescue [])
  affliction_results = []
  rolls.each do |r|
    name = r['affliction'].to_s
    next unless conditions.afflictions.key?(name)
    result = conditions.apply_affliction_save_outcome(
      name,
      successes:     r['successes'].to_i,
      failures:      r['failures'].to_i,
      creature_tier: char.tier,
      current_round: COMBAT.round
    )
    affliction_results << { 'name' => name, 'result' => result }
  end

  # 5. Clear any effects whose ends_on_round has passed.
  conditions.clear_expired_effects(COMBAT.round)

  CONDITIONS_REGISTRY.save!

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
