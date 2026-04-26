# Sinatra routes and helpers that back the reusable roll_stub partial.
# Loaded from app.rb after Sinatra and DICE_SYSTEM are initialized.
#
# Rows are rendered in the canonical order defined by
# docs/dice_resolution/dice_resolution_glossary.md: Reroll Operation
# (Luck) is applied before Value Adjustment (Insight) when both are
# present for the same Roll.

helpers do
  # Render the roll_stub partial inline. Callers pass the check
  # metadata plus optional luck/insight button labels and per-click
  # amounts; leave an amount at 0 to suppress that button pair.
  def roll_stub(check_name:, dice_count:, tn:, starting_value:,
                luck_bonus_name: nil, luck_penalty_name: nil, luck_amount: 0,
                insight_bonus_name: nil, insight_penalty_name: nil, insight_amount: 0)
    erb :"stubs/_roll_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      check_name: check_name,
      dice_count: dice_count,
      tn: tn,
      starting_value: starting_value,
      luck_bonus_name: luck_bonus_name,
      luck_penalty_name: luck_penalty_name,
      luck_amount: luck_amount,
      insight_bonus_name: insight_bonus_name,
      insight_penalty_name: insight_penalty_name,
      insight_amount: insight_amount
    }
  end

  # Build the response payload for every /roll_stub/* endpoint. Rows
  # are always returned in canonical order — Rolled, then Luck, then
  # Insight — omitting slots that have not been applied yet.
  def roll_stub_response(token, state)
    original = state['original_dice']
    tn = state['tn']
    starting_value = state['starting_value']
    rows = [{ 'label' => 'Rolled', 'dice' => original }]
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

  # Summary line shown under the stub's title: "TN 5, 6 dice" plus an
  # optional "N starting successes/failures" clause when the starting
  # value is non-zero.
  def roll_stub_params_line(tn, dice_count, starting_value)
    parts = ["TN #{tn}", "#{dice_count} dice"]
    if starting_value > 0
      word = starting_value == 1 ? 'success' : 'successes'
      parts << "#{starting_value} starting #{word}"
    elsif starting_value < 0
      n = -starting_value
      word = n == 1 ? 'failure' : 'failures'
      parts << "#{n} starting #{word}"
    end
    parts.join(', ')
  end
end

# Render the roll_stub partial in response to an AJAX request from a
# parent stub (e.g. melee_attack_stub) that needs to inject a freshly
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
  session[:roll_stub] ||= {}
  session[:roll_stub][token] = {
    'original_dice' => dice,
    'tn' => tn,
    'starting_value' => starting_value,
    'luck_dice' => nil,
    'insight_dice' => nil
  }
  roll_stub_response(token, session[:roll_stub][token]).to_json
end

post '/roll_stub/reroll' do
  content_type :json
  token = params[:token].to_s
  reroll_count = params[:reroll_count].to_i
  state = (session[:roll_stub] || {})[token]
  halt 404, { error: 'unknown roll token' }.to_json unless state
  # Luck always rerolls against the original dice (canonical order
  # puts Luck immediately below Initial). Any Insight that was stacked
  # on top of a previous Luck result is invalidated.
  changes = DICE_SYSTEM.rand_reroll_some_dice(state['original_dice'], reroll_count, state['tn'])
  state['luck_dice'] = dice_after_changes(state['original_dice'], changes)
  state['insight_dice'] = nil
  session[:roll_stub][token] = state
  roll_stub_response(token, state).to_json
end

post '/roll_stub/nudge' do
  content_type :json
  token = params[:token].to_s
  nudge_amount = params[:nudge_amount].to_i
  state = (session[:roll_stub] || {})[token]
  halt 404, { error: 'unknown roll token' }.to_json unless state
  # Insight nudges against whichever row is above it: Luck's result
  # if Luck has been applied, otherwise the original dice. Each click
  # discards the previous insight result.
  base = state['luck_dice'] || state['original_dice']
  changes = DICE_SYSTEM.apply_nudge(base, nudge_amount, state['tn'])
  state['insight_dice'] = dice_after_changes(base, changes)
  session[:roll_stub][token] = state
  roll_stub_response(token, state).to_json
end
