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
      when /\Aluck:/      then ['Use your luck?', what]
      when /\Aroll:/      then ["Roll #{t.dig('roll', 'name')}", what]
      else [t['step'].to_s, what]
      end
    visible = t['kind'] != 'roll' || flow.visible_to?(t, viewer_ids)
    # A DM roll not yet approved: the owner still sees their Roll button.
    status = visible ? t['status'] : 'waiting'
    view = { flow_id: flow.id, task_id: t['id'], kind: t['kind'], step: t['step'], title: title, body: body,
             status: status, summary: visible ? t['summary'] : nil,
             # "Garroth Vask Attacks Wolf with Great Sword" — the prompt's heading.
             action_line: flow.title_line(viewer_ids), luck_remaining: t['luck_amount'] }
    if t['kind'] == 'roll'
      view[:roll] = t['roll'].slice('name', 'dice_count', 'tn', 'starting_value', 'positive_reroll', 'negative_reroll')
      view[:result] = t['value'] if t['value'] && visible
      # Everyone's roll in this action, so the player sees the whole picture
      # (and each phone can show the others' dice rolling as they arrive).
      # A roll the DM has not approved is shown as not rolled.
      view[:all_rolls] = flow.public_roll_overview(viewer_ids).map do |r|
        r.except(:claimed, :by).merge(color: roll_color(r[:owner_id]))
      end
      view[:headline] = flow.headline(viewer_ids)
    else
      view[:options] = flow.options_for(t)
    end
    view
  end

  # One line per step for the actor's own status view (nothing the DM has
  # not shared).
  def flow_status_view(flow)
    mine = [flow.actor_id]
    { flow_id: flow.id, kind: flow.kind, stage: flow.stage, summary: flow.summary, blocking: flow.blocking?,
      pool_cost: flow.declared_pool_cost,
      tasks: flow.tasks.reject { |t| t['kind'] == 'declare' }.map do |t|
        shown = t['kind'] != 'roll' || flow.visible_to?(t, mine)
        { step: t['step'], owner: t['owner_name'], status: shown ? t['status'] : 'waiting', summary: shown ? t['summary'] : nil }
      end }
  end

  # The dice colour of a Roll's owner: a player Character's own colour, or
  # the DM's for everyone else (docs/project/dice_colors.md).
  def roll_color(owner_id)
    c = owner_id && encounter_state.combatants.find { |x| x[:id] == owner_id }
    who = c && creature_is_pc?(c[:creature_id]) ? c[:creature_id] : DiceColors::DM
    DiceColors.instance.hex_for(who)
  end

  # A Combatant whose Character is assigned to a phone: its choices and dice
  # go to that phone. Everyone else's are the DM's.
  def claimed_combatant?(combatant_id)
    c = encounter_state.combatants.find { |x| x[:id] == combatant_id.to_i }
    return false unless c && creature_is_pc?(c[:creature_id])
    DeviceRegistry.instance.list.any? { |d| d['character_id'].to_s == c[:creature_id].to_s }
  end

  # Prompts waiting on this device's Character (its turn or not), from the
  # builders open on the DM's page.
  def my_prompts(acc)
    mine = my_combatant_ids(acc)
    # A prompt stays until the builder moves on, closes, or the action ends —
    # however long the player takes (a DM page in a background tab syncs
    # less often, but its prompts stay).
    action_flows.active.select { |f| f.stage == 'builder' }.flat_map do |f|
      tasks = f.tasks.select do |t|
        next false unless mine.include?(t['owner_id'])
        t['kind'] == 'choice' || (t['kind'] == 'roll' && t['claimed'])
      end
      tasks.map { |t| flow_prompt_view(f, t, mine) }
    end
  end

  # Actions whose Rolls the DM shared (Confirm) in the last minutes: every
  # phone in combat throws their dice once, as if just rolled.
  def shared_actions(acc)
    mine = my_combatant_ids(acc)
    action_flows.recent_shared.map do |f|
      { flow_id: f.id, version: f.shared_version, action_line: f.title_line(mine),
        rolls: f.public_roll_overview(mine).select { |r| r[:final] }.map do |r|
          r.except(:claimed, :by).merge(color: roll_color(r[:owner_id]))
        end }
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

  # An action with a die roll still waiting on this player (theirs to roll
  # on the phone — or one the DM rolled but has not approved, which the
  # player may still roll over), or nil. Until it is rolled the player cannot
  # ask for anything else.
  def blocking_flow(combatant)
    action_flows.active.find do |f|
      f.stage == 'builder' && f.roll_tasks.any? do |t|
        t['claimed'] && t['owner_id'] == combatant[:id] && (t['status'] == 'waiting' || f.dm_pending?(t))
      end
    end
  end

  # What a player may ask for right now: everything on their own turn; on
  # anyone else's, only Free actions (Rage…) — never End Turn.
  def api_available_options(mine, my_turn)
    return [] unless mine && api_in_combat?
    opts = api_turn_options(mine)
    my_turn ? opts : opts.select { |o| o[:category] == 'free' && o[:kind] != 'end_turn' }
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


# Approve a player's request. An Ability with no builder (Rage…) is used at
# once — on anyone's turn, from any page. Anything else opens in its builder
# on the Encounter page (the panel opens it by itself); approved from another
# page (the DM notice), the DM is taken there.
post '/encounter/flows/:id/tasks/:task_id/approve' do
  halt 403 unless dm_view?
  f = action_flows.find(params[:id])
  halt 404 unless f
  begin
    action_flows.synchronize { f.approve(params[:task_id]) }
    if f.kind == 'special' && f.blob.nil?
      result = encounter_state.use_special_payload('combatant_id' => f.actor_id, 'ability' => f.ability.to_s)
      if result[:ok]
        Conditions.store.persist!
        f.done!
      else
        session[:flow_error] = "#{f.ability}: #{result[:error]}"
      end
    end
  rescue ArgumentError => e
    session[:flow_error] = e.message
  end
  redirect(params[:go] == 'encounter' && f.active? ? '/encounter' : (request.referer || '/encounter'))
end

post '/encounter/flows/:id/cancel' do
  flow_dm_action(&:cancel!)
end

# --- The DM's builder (public/js/ui/liveSync.js) ----------------------------------------

helpers do
  def live_json!
    halt 403, JSON.generate(ok: false, error: 'DM only') unless dm_view?
    content_type :json
    body = (JSON.parse(request.body.read) rescue nil)
    halt 400, JSON.generate(ok: false, error: 'invalid payload') unless body.is_a?(Hash)
    body
  end

  def live_flow!(id)
    f = action_flows.find(id)
    halt 404, JSON.generate(ok: false, error: 'unknown action') unless f && f.active?
    f
  end
end

# The builder's state, about once a second while it is on screen. Creates the
# flow on the first sync of a builder the DM opened (no flow_id yet). Answers
# with a player's pick for the current step and where every Roll stands.
post '/encounter/live/sync' do
  s = live_json!
  f = s['flow_id'].to_s.empty? ? nil : action_flows.find(s['flow_id'])
  f = nil if f && !f.active?
  if f.nil?
    return JSON.generate(ok: true, flow_id: nil) if s['idle']
    actor = encounter_state.combatants.find { |c| c[:id] == s['actor_id'].to_i }
    halt 404, JSON.generate(ok: false, error: 'unknown combatant') unless actor
    kind = ActionFlow::KINDS.include?(s['kind'].to_s) ? s['kind'].to_s : 'attack'
    f = action_flows.add(ActionFlow.new(kind: kind, actor_id: actor[:id], actor_name: tracker_name(actor),
                                        turn_key: PlayerRequests.turn_key(encounter_state, actor[:id]), blob: nil,
                                        names: flow_names, dm_started: true))
  end
  action_flows.synchronize { f.sync!(s, claimed: ->(cid) { claimed_combatant?(cid) }) }
  # A builder the DM closed without committing: nothing was spent.
  f.cancel! if s['idle'] && f.dm_started?
  JSON.generate(ok: true, **f.builder_view)
end

# The DM is leaving the Encounter page (sent as the page closes): its builders
# are closed now, so the notice on the other pages shows their actions as in
# progress at once. Nothing else changes.
post '/encounter/live/left' do
  halt 403 unless dm_view?
  open = action_flows.active.select { |f| f.stage == 'builder' && !f.last_sync.nil? }
  action_flows.synchronize { open.each(&:page_left!) }
  JSON.generate(ok: true)
end

# The DM's Encounter page just loaded: the actions in progress in a builder,
# which the page reopens where they were (public/js/ui/liveSync.js). Their
# phone prompts stayed up meanwhile.
get '/encounter/live/open' do
  halt 403, JSON.generate(ok: false, error: 'DM only') unless dm_view?
  content_type :json
  open = action_flows.active.select { |f| f.stage == 'builder' && !f.last_sync.nil? }
  JSON.generate(ok: true, flows: open.map { |f| { flow_id: f.id, kind: f.kind, actor_id: f.actor_id } })
end

# Where an open builder's action stands (a phone's answer, every Roll), fetched
# when the page hears that something changed. Counts as the builder being open.
get '/encounter/live/:id' do
  halt 403, JSON.generate(ok: false, error: 'DM only') unless dm_view?
  content_type :json
  f = live_flow!(params[:id])
  f.touch!
  JSON.generate(ok: true, **f.builder_view)
end

# DM rolls a player's Roll for them (only the DM sees it until approved).
post '/encounter/live/:id/rolls/:task_id/roll' do
  live_json!
  f = live_flow!(params[:id])
  begin
    action_flows.synchronize { f.roll_for(params[:task_id]) }
  rescue ArgumentError => e
    halt 422, JSON.generate(ok: false, error: e.message)
  end
  JSON.generate(ok: true, **f.builder_view)
end

# DM approves a Roll: now every phone sees it.
post '/encounter/live/:id/rolls/:task_id/approve' do
  live_json!
  f = live_flow!(params[:id])
  begin
    action_flows.synchronize { f.approve(params[:task_id]) }
  rescue ArgumentError => e
    halt 422, JSON.generate(ok: false, error: e.message)
  end
  JSON.generate(ok: true, **f.builder_view)
end

# Confirm in the builder: share every Roll. Body: { rolls: { roll_id => { dice, rerolled, final } } }
# for the Rolls the builder rolled itself (Roll All).
post '/encounter/live/:id/share' do
  s = live_json!
  f = live_flow!(params[:id])
  begin
    action_flows.synchronize { f.share!(s['rolls'].is_a?(Hash) ? s['rolls'] : {}) }
  rescue ArgumentError => e
    halt 422, JSON.generate(ok: false, error: e.message)
  end
  JSON.generate(ok: true, **f.builder_view)
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
