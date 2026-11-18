# Player-driven attacks (docs/project/action_flow.md, lib/action_flow.rb).
#
# Players (Android app, lib/routes/api.rb identification): the attacker asks
# for an attack with a target; every Combatant with a choice answers its prompt
# on its own phone (defense, ally shield, Luck, then the dice). The DM approves
# each answer — or answers on the owner's behalf — on the Encounter page's
# "Player actions" panel, then finishes the attack in the pre-filled Attack
# builder, which commits through the usual /encounter/resolve_attack.

helpers do
  def action_flows = ActionFlows.instance

  def flow_names
    encounter_state.combatants.to_h { |c| [c[:id], tracker_name(c)] }
  end

  # Combatant ids played by this device's assigned Character.
  def my_combatant_ids(acc)
    encounter_state.combatants.select { |c| c[:creature_id].to_s == acc.id.to_s }.map { |c| c[:id] }
  end

  # A prompt for a phone: what is asked, the options (grouped), or the roll.
  def flow_prompt_view(flow, t)
    attack = flow.stage_tasks('declare').first['summary']
    title, body =
      case t['step']
      when 'defense'      then ['Choose your defense', "#{flow.attacker_name} attacks you: #{attack}."]
      when 'ally_defense' then ["Shield #{flow.name_of(flow.target_id)}?", "#{flow.attacker_name} attacks #{flow.name_of(flow.target_id)}: #{attack}."]
      when /\Aluck:/      then ['Use your Luck?', "#{flow.attacker_name} attacks #{flow.name_of(flow.target_id)}: #{attack}."]
      when /\Aroll:/      then ["Roll #{t.dig('roll', 'name')}", "#{flow.attacker_name}'s attack: #{attack}."]
      else [t['step'].to_s, attack]
      end
    view = { flow_id: flow.id, task_id: t['id'], kind: t['kind'], step: t['step'], title: title, body: body,
             status: t['status'], summary: t['summary'] }
    if t['kind'] == 'roll'
      view[:roll] = t['roll'].slice('name', 'dice_count', 'tn', 'starting_value', 'positive_reroll', 'negative_reroll')
      view[:result] = t['value'] if t['value']
    else
      view[:options] = flow.options_for(t)
    end
    view
  end

  # One line per stage task for the attacker's own status view.
  def flow_status_view(flow)
    { flow_id: flow.id, stage: flow.stage, summary: flow.stage_tasks('declare').first['summary'],
      pool_cost: flow.declared_pool_cost,
      tasks: flow.stage_tasks.map { |t| { step: t['step'], owner: t['owner_name'], status: t['status'], summary: t['summary'] } } }
  end

  # Prompts waiting on this device's Character (its turn or not).
  def my_prompts(acc)
    mine = my_combatant_ids(acc)
    action_flows.active.flat_map do |f|
      f.open_tasks.select { |t| t['kind'] != 'declare' && mine.include?(t['owner_id']) }.map { |t| flow_prompt_view(f, t) }
    end
  end

  def flow_and_task!(flow_id, task_id)
    f = action_flows.find(flow_id)
    halt 404, JSON.generate(ok: false, error: 'unknown action') unless f && f.active?
    t = f.task(task_id)
    halt 404, JSON.generate(ok: false, error: 'unknown step') unless t
    [f, t]
  end

  # Run a DM action on a flow, then go back to the page. A refused action
  # (e.g. approving twice) is shown once on the panel.
  def flow_dm_action(&block)
    halt 403 unless dm_view?
    f = action_flows.find(params[:id])
    halt 404 unless f
    begin
      action_flows.synchronize { block.call(f) }
    rescue ArgumentError => e
      session[:flow_error] = e.message
    end
    redirect(request.referer || '/encounter')
  end

  # Create an attack flow from a player's request. Returns [flow, error].
  def start_attack_flow(combatant, weapon_type, dice, target_id)
    blob = attack_builder_blob(combatant)
    action_value = "#{weapon_type}|#{dice.to_i}"
    action = Array(blob[:steps].find { |s| s[:key] == 'action' }&.dig(:options))
             .find { |o| o[:value].to_s == action_value && !o[:auto] }
    return [nil, 'choose a weapon and dice count'] unless action
    return [nil, 'not enough Combat Pool'] if action[:disabled]
    targets = Array(blob[:steps].find { |s| s[:key] == 'target' }&.dig(:options))
    return [nil, 'choose a target'] unless targets.any? { |o| o[:value].to_s == target_id.to_s }

    flow = ActionFlow.new(attacker_id: combatant[:id], attacker_name: tracker_name(combatant),
                          turn_key: PlayerRequests.turn_key(encounter_state, combatant[:id]), blob: blob,
                          target_id: target_id.to_i, action_value: action_value, names: flow_names)
    [action_flows.add(flow), nil]
  end
end

# --- Player (Android app) ---------------------------------------------------------

get '/api/prompts' do
  acc = api_character!
  prompts = my_prompts(acc)
  api_json(ok: true, count: prompts.count { |p| p[:status] == 'waiting' }, prompts: prompts)
end

# Answer a prompt. Body: { "value": "<option value>" } for a choice, or
# { "roll": { "dice": [...], "rerolled": [... or null], "final": [...] } }.
post '/api/prompts/:flow_id/:task_id' do
  acc = api_character!
  body = (JSON.parse(request.body.read) rescue nil)
  api_error(400, 'invalid payload') unless body.is_a?(Hash)
  f = action_flows.find(params[:flow_id])
  api_error(404, 'unknown action') unless f && f.active?
  action_flows.synchronize do
    t = f.task(params[:task_id])
    api_error(404, 'unknown step') unless t
    api_error(403, 'not your step') unless my_combatant_ids(acc).include?(t['owner_id'])
    api_error(409, 'already approved') if t['status'] == 'approved'
    begin
      f.submit(t['id'], t['kind'] == 'roll' ? body['roll'] : body['value'])
    rescue ArgumentError => e
      api_error(422, e.message)
    end
  end
  api_json(ok: true, prompts: my_prompts(acc))
end

# --- DM -----------------------------------------------------------------------------


post '/encounter/flows/:id/tasks/:task_id/approve' do
  flow_dm_action { |f| f.approve(params[:task_id]) }
end

post '/encounter/flows/:id/tasks/:task_id/reject' do
  flow_dm_action { |f| f.reject(params[:task_id]) }
end

post '/encounter/flows/:id/tasks/:task_id/decide' do
  flow_dm_action { |f| f.decide(params[:task_id], params[:value].to_s) }
end

post '/encounter/flows/:id/tasks/:task_id/roll' do
  flow_dm_action { |f| f.roll_for(params[:task_id]) }
end

post '/encounter/flows/:id/cancel' do
  flow_dm_action(&:cancel!)
end

# The pre-fill for the DM's Attack builder (choices in step order + roll results).
get '/encounter/flows/:id/prefill' do
  require_dm!
  f = action_flows.find(params[:id])
  halt 404, JSON.generate(ok: false, error: 'unknown action') unless f && f.active?
  content_type :json
  JSON.generate(ok: true, **f.prefill)
end

# The Player actions panel alone, for the Encounter page to refresh itself.
get '/encounter/flows_panel' do
  halt 403 unless dm_view?
  erb :_action_flows, layout: false, locals: { flows: action_flows.active, acting_id: encounter_state.acting_combatant_id }
end
