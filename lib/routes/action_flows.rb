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
  def flow_prompt_view(flow, t, viewer_ids = [t['owner_id']])
    what = "#{flow.actor_name} #{flow_verb(flow)}: #{flow.summary}."
    title, body =
      case t['step']
      when 'defense'      then ['Choose your defense', what]
      when 'ally_defense' then ["Shield #{flow.name_of(flow.target_id)}?", what]
      when /\Aluck:/      then ['Use your Luck?', what]
      when /\Aroll:/      then ["Roll #{t.dig('roll', 'name')}", what]
      else [t['step'].to_s, what]
      end
    view = { flow_id: flow.id, task_id: t['id'], kind: t['kind'], step: t['step'], title: title, body: body,
             status: t['status'], summary: t['summary'] }
    if t['kind'] == 'roll'
      view[:roll] = t['roll'].slice('name', 'dice_count', 'tn', 'starting_value', 'positive_reroll', 'negative_reroll')
      view[:result] = t['value'] if t['value'] && !flow.dm_pending?(t)
      # Everyone's roll in this action, so the player sees the whole picture
      # (and each phone can show the others' dice rolling as they arrive).
      # A DM roll the DM has not approved yet is shown as not rolled.
      view[:all_rolls] = flow.public_roll_overview.map { |r| r.merge(color: roll_color(r[:owner_id])) }
      view[:headline] = flow.headline(viewer_ids)
    else
      view[:options] = flow.options_for(t)
    end
    view
  end

  # One line per stage task for the attacker's own status view.
  def flow_status_view(flow)
    { flow_id: flow.id, kind: flow.kind, stage: flow.stage, summary: flow.summary, blocking: flow.blocking?,
      pool_cost: flow.declared_pool_cost,
      tasks: flow.stage_tasks.map do |t|
        hidden = flow.dm_pending?(t)
        { step: t['step'], owner: t['owner_name'], status: hidden ? 'waiting' : t['status'], summary: hidden ? nil : t['summary'] }
      end }
  end

  # The dice colour of a Roll's owner: a player Character's own colour, or
  # the DM's for everyone else (docs/project/dice_colors.md).
  def roll_color(owner_id)
    c = owner_id && encounter_state.combatants.find { |x| x[:id] == owner_id }
    who = c && creature_is_pc?(c[:creature_id]) ? c[:creature_id] : DiceColors::DM
    DiceColors.instance.hex_for(who)
  end

  # Prompts waiting on this device's Character (its turn or not).
  def my_prompts(acc)
    mine = my_combatant_ids(acc)
    action_flows.active.flat_map do |f|
      # A roll the DM made for the player and has not approved yet is the
      # DM's business: it is not on the player's phone at all until approved.
      tasks = f.open_tasks.select { |t| t['kind'] != 'declare' && mine.include?(t['owner_id']) && !f.dm_pending?(t) }
      # A player's roll stays on screen (read-only once approved) until the DM
      # commits the action, so they see everyone else's dice land too.
      if %w[roll resolve].include?(f.stage)
        f.stage_tasks('roll').each { |t| tasks << t if mine.include?(t['owner_id']) && !tasks.include?(t) && !f.dm_pending?(t) }
      end
      tasks.map { |t| flow_prompt_view(f, t, mine) }
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

  # Create a Cast or Item flow from a player's request (+opt+ is the turn
  # option). Returns [flow, error].
  def start_cast_flow(combatant, opt, dice, target_id)
    item = opt[:kind] == 'item'
    blob = item ? item_builder_blob(combatant) : cast_builder_blob(combatant)
    spell_key = opt[:key].sub(/\A(cast|item):/, '')
    step = ->(k) { blob[:steps].find { |st| st[:key] == k } }
    spell = Array(step.call('spell')[:options]).find { |o| o[:value].to_s == spell_key && o[:kind] != 'info' }
    return [nil, 'unknown spell'] unless spell
    return [nil, 'not enough Mana'] if spell[:disabled]

    dice_opts = Array(step.call('dice')[:options_map][spell_key]).reject { |o| o[:kind] == 'info' }
    n = opt[:dice].empty? ? opt[:pool_cost].to_i : dice.to_i
    dice_opt = dice_opts.find { |o| o[:value].to_s.split('|').last.to_i == n } ||
               (opt[:dice].empty? ? dice_opts.first : nil)
    return [nil, 'choose a dice count'] unless dice_opt
    return [nil, 'not enough Combat Pool'] if dice_opt[:disabled]

    target_opts = Array(step.call('target')[:options_map][spell_key])
    target =
      case opt[:target]
      when 'creature'
        t = target_opts.find { |o| o[:value].to_s == target_id.to_s }
        return [nil, 'choose a target'] unless t
        t[:value].to_s
      else
        (target_opts.first || {})[:value].to_s
      end
    where = case opt[:target]
            when 'creature' then " at #{flow_names[target.to_i]}"
            when 'self' then ' on yourself'
            when 'object' then ' on an object'
            when 'area' then ' (the DM places it on the map)'
            else ''
            end
    n_text = opt[:dice].empty? ? '' : " \u2014 #{n} dice"
    flow = ActionFlow.new(kind: opt[:kind], actor_id: combatant[:id], actor_name: tracker_name(combatant),
                          turn_key: PlayerRequests.turn_key(encounter_state, combatant[:id]), blob: blob,
                          declare: [['spell', spell[:value]], ['dice', dice_opt[:value]], ['target', target]],
                          summary: "#{opt[:name]}#{n_text}#{where}", pool_cost: n, names: flow_names)
    [action_flows.add(flow), nil]
  end

  # Create a Special Ability flow. A channeled Ability (Bardic Performance)
  # rolls its check on the performer's phone; any other (e.g. Rage) is just
  # approved and confirmed by the DM. Returns [flow, error].
  def start_special_flow(combatant, opt, dice)
    name = opt[:key].sub('special:', '')
    declare = []
    blob = nil
    cost = opt[:pool_cost].to_i
    summary = opt[:name]
    unless opt[:dice].empty?
      blob = special_builder_blob(combatant, name)
      perf = blob[:steps].find { |st| st[:key] == 'performance' }
      declare << ['performance', perf[:options].first[:value]] if perf
      n = dice.to_i
      choice = opt[:dice].find { |d| d[:dice] == n }
      return [nil, 'choose a dice count'] unless choice
      return [nil, 'not enough Combat Pool'] unless choice[:affordable]
      declare << ['dice', n]
      cost = n
      summary = "#{opt[:name]} \u2014 #{n} dice"
    end
    flow = ActionFlow.new(kind: 'special', actor_id: combatant[:id], actor_name: tracker_name(combatant),
                          turn_key: PlayerRequests.turn_key(encounter_state, combatant[:id]), blob: blob,
                          declare: declare, summary: summary, pool_cost: cost, ability: name, names: flow_names)
    [action_flows.add(flow), nil]
  end

  # The player's own action in progress that holds up their other actions
  # (it waits on other players or dice), or nil.
  def blocking_flow(combatant)
    action_flows.active.find { |f| f.actor_id == combatant[:id] && f.blocking? }
  end

  # How each kind reads in a sentence ("Ash casts at you: …").
  def flow_verb(flow)
    { 'attack' => 'attacks', 'cast' => 'casts', 'item' => 'uses an item', 'special' => 'uses an ability' }[flow.kind]
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

# The DM approves a plain player request and applies it: a Move spends its
# Combat Pool cost; End Turn advances the turn. (Other plain requests are
# resolved by hand and dismissed.) DM only.
post '/encounter/player_requests/:id/apply' do
  halt 403 unless dm_view?
  acting = encounter_state.acting_combatant_id
  key = PlayerRequests.turn_key(encounter_state, acting)
  req = PlayerRequests.instance.for_turn(acting, key).find { |r| r['id'] == params[:id] }
  halt 404 unless req
  case req['key']
  when 'move'
    result = encounter_state.apply_move(acting)
    session[:flow_error] = result[:error] if result.is_a?(Hash) && result[:error]
  when 'end_turn'
    PlayerRequests.instance.remove(params[:id])
    new_id = encounter_state.advance_turn
    begin_turn_side_effects!(new_id) if new_id
    redirect(request.referer || '/encounter')
  end
  PlayerRequests.instance.remove(params[:id])
  redirect(request.referer || '/encounter')
end
