# Sinatra routes and helpers that back the reusable roll_stub partial.
# Loaded from app.rb after Sinatra and DICE_SYSTEM are initialized.
#
# Rows are rendered in the canonical order defined by
# docs/dice_resolution/dice_resolution_glossary.md: Reroll Operation
# (Luck) is applied before Value Adjustment (Insight) when both are
# present for the same Roll.

# Process-local store of in-flight roll state, keyed by the random
# token returned to the client. Bypasses session storage so that
# concurrent rolls from one client (e.g. multi_roll's Roll All) don't
# clobber each other through racy session-cookie writes.
ROLL_STUB_STATES = {}

helpers do
  # Render the roll_stub partial inline. luck_amount and insight_amount
  # are signed: positive values reroll/nudge upward, negative downward.
  # Pass 0 to suppress the row entirely. Pass show_confirm: false when
  # embedded inside a parent stub (e.g. multi_roll_stub) that owns its
  # own batched Confirm. bare_row: true emits just the inner <tr>
  # (without a wrapping <table>/<thead>) so a parent table can stack
  # several rolls under one set of column headers. stub_id may be
  # supplied by a parent that needs to address this child after render.
  def roll_stub(check_name:, dice_count:, tn:, starting_value:,
                character_name: nil,
                luck_amount: 0, luck_label: nil,
                insight_amount: 0, insight_label: nil,
                show_confirm: true,
                bare_row: false,
                stub_id: nil)
    erb :"stubs/_roll_stub", layout: false, locals: {
      stub_id: stub_id || SecureRandom.hex(4),
      check_name: check_name,
      character_name: character_name,
      dice_count: dice_count,
      tn: tn,
      starting_value: starting_value,
      luck_amount: luck_amount,
      luck_label: luck_label,
      insight_amount: insight_amount,
      insight_label: insight_label,
      show_confirm: show_confirm,
      bare_row: bare_row
    }
  end

  # Build the response payload for every /roll_stub/* endpoint. Rows
  # are always returned in canonical order — Initial, then Luck, then
  # Insight — omitting slots that have not been applied yet.
  def roll_stub_response(token, state)
    original = state['original_dice']
    tn = state['tn']
    starting_value = state['starting_value']
    rows = [{ 'label' => 'Initial', 'dice' => original }]
    rows << { 'label' => 'Luck',    'dice' => state['luck_dice']    } if state['luck_dice']
    rows << { 'label' => 'Insight', 'dice' => state['insight_dice'] } if state['insight_dice']
    current = rows.last['dice']
    result = DICE_SYSTEM.compute_results(current, tn, starting_value)
    {
      token: token,
      tn: tn,
      starting_value: starting_value,
      rows: rows,
      successes: result['degree_of_individual_success'],
      criticals: result['critical_count']
    }
  end

  def dice_after_changes(base, changes)
    base.each_with_index.map { |v, i| changes[i].nil? ? v : changes[i] }
  end

  def roll_stub_params_line(tn, dice_count, starting_value)
    line = "#{dice_count} dice @ TN #{tn}"
    if starting_value > 0
      word = starting_value == 1 ? 'success' : 'successes'
      line += ", #{starting_value} starting #{word}"
    elsif starting_value < 0
      n = -starting_value
      word = n == 1 ? 'failure' : 'failures'
      line += ", #{n} starting #{word}"
    end
    line
  end

  # Format a signed amount with its ability name, e.g. "+2 Bardic
  # Inspiration" or "-1 Unsettling Words". Used both on the luck reroll
  # button and the static insight label.
  def roll_stub_modifier_text(amount, label)
    sign = amount.to_i >= 0 ? '+' : '-'
    "#{sign}#{amount.to_i.abs} #{label}"
  end
end

# Render the roll_stub partial in response to an AJAX request from a
# parent stub (e.g. attack_stub) that needs to inject a freshly
# parameterised roll into its flow. Returns the partial HTML; the caller
# is responsible for placing it in the DOM.
post '/roll_stub/render' do
  content_type :html
  roll_stub(
    check_name:         params[:check_name].to_s,
    dice_count:         params[:dice_count].to_i,
    tn:                 params[:tn].to_i,
    starting_value:     params[:starting_value].to_i,
    luck_bonus_name:    params[:luck_bonus_name],
    luck_penalty_name:  params[:luck_penalty_name],
    luck_amount:        params[:luck_amount].to_i,
    insight_bonus_name: params[:insight_bonus_name],
    insight_penalty_name: params[:insight_penalty_name],
    insight_amount:     params[:insight_amount].to_i
  )
end

post '/roll_stub/roll' do
  content_type :json
  dice_count = params[:dice_count].to_i
  tn = params[:tn].to_i
  starting_value = params[:starting_value].to_i
  dice = DICE_SYSTEM.rand_roll_dice(dice_count)
  token = SecureRandom.hex(8)
  ROLL_STUB_STATES[token] = {
    'original_dice' => dice,
    'tn' => tn,
    'starting_value' => starting_value,
    'luck_dice' => nil,
    'insight_dice' => nil
  }
  roll_stub_response(token, ROLL_STUB_STATES[token]).to_json
end

post '/roll_stub/reroll' do
  content_type :json
  token = params[:token].to_s
  reroll_count = params[:reroll_count].to_i
  state = ROLL_STUB_STATES[token]
  halt 404, { error: 'unknown roll token' }.to_json unless state
  # Luck always rerolls against the original dice (canonical order
  # puts Luck immediately below Initial). Any Insight that was stacked
  # on top of a previous Luck result is invalidated.
  changes = DICE_SYSTEM.rand_reroll_some_dice(state['original_dice'], reroll_count, state['tn'])
  state['luck_dice'] = dice_after_changes(state['original_dice'], changes)
  state['insight_dice'] = nil
  roll_stub_response(token, state).to_json
end

post '/roll_stub/nudge' do
  content_type :json
  token = params[:token].to_s
  nudge_amount = params[:nudge_amount].to_i
  state = ROLL_STUB_STATES[token]
  halt 404, { error: 'unknown roll token' }.to_json unless state
  # Insight nudges against whichever row is above it: Luck's result
  # if Luck has been applied, otherwise the original dice. Each click
  # discards the previous insight result.
  base = state['luck_dice'] || state['original_dice']
  changes = DICE_SYSTEM.apply_nudge(base, nudge_amount, state['tn'])
  state['insight_dice'] = dice_after_changes(base, changes)
  roll_stub_response(token, state).to_json
end
