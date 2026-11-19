# JSON API for the Android app (docs/project/android_app.md).
#
# The app is a player device: it is identified like any browser, by the
# `crimson_device_id` cookie (lib/routes/devices.rb), and shows the Character
# the DM assigned to that device on the Status page. Every endpoint answers
# for that Character only, with the same player visibility rules the web pages
# use (enemy vitals redacted, Chronicle entries filtered per Character, no DM
# descriptions).
#
# Inventory changes reuse the web routes unchanged (/inventory/equip,
# /inventory/unequip, /inventory/discard, /inventory/claim,
# /inventory/claim_equip), so the app can do exactly what the web sheet does.
# Public Skill Rolls go to the web's POST /dm/roll.
#
# A turn request (POST /api/turn/requests) spends nothing: it is listed on the
# DM's turn panel, and the DM resolves it through the normal flow.

helpers do
  # Halt with a JSON body. Accepts a Hash or bare keywords (`api_json(ok: true)`);
  # `status:` is the HTTP status, never a body field.
  def api_json(obj = {}, status: 200, **fields)
    content_type :json
    halt status, JSON.generate(obj.merge(fields))
  end

  def api_error(status, error, **extra)
    api_json({ ok: false, error: error }.merge(extra), status: status)
  end

  # The assigned Character's accessor, or halt with `unassigned`.
  def api_character!
    cid = assigned_character_id
    api_error(409, 'unassigned', device: assignment_short_id(current_device_id)) unless cid
    acc = (Creatures.lookup(cid) rescue nil)
    api_error(409, 'unassigned', device: assignment_short_id(current_device_id)) unless acc
    acc
  end

  def api_time_label(ts)
    ts  = ts.transform_keys(&:to_sym)
    cal = Timekeeping.calendar_date(ts[:day_index])
    hh, mm, = Timekeeping.time_of_day(ts[:round_of_day]).split(':')
    "#{cal[:day_of_week]}, #{cal[:day_of_month]} #{Timekeeping.month_name(cal[:month])} #{cal[:year]} · #{hh}:#{mm}"
  rescue StandardError
    nil
  end

  # A Roll the app can throw as-is: Dice Count, final TN and Starting Value
  # are computed here (Dice Resolution), so the app never re-derives them.
  def api_roll(name, dice_count, bpl, ranks: 0)
    tn = DiceResolution.compute_target_number(bpl)
    { name: name, dice_count: dice_count.to_i, tn: tn[:tn], starting_value: tn[:starting_value],
      base_tn: DiceResolution.config.base_target_number, bonus_penalty_list: bpl, ranks: ranks.to_i }
  end

  def api_competency(bonus)
    bonus.to_i.zero? ? [] : [['Competency', bonus.to_i]]
  end

  def api_sheet(acc)
    d = CreatureSheet.build(acc)
    h = d[:header]
    v = d[:vitals]
    attributes = Array(d[:attributes_table]).map do |a|
      save_tokens = Array(a.dig(:save, :tokens)).reject { |t| t[:conditional] }
                                                .map { |t| [(t[:type] || 'Resistance').to_s, t[:amount].to_i] }
      { key: a[:key].to_s, label: a[:attr], score: a[:score],
        check: api_roll("#{a[:attr]} check", a.dig(:check, :dice), api_competency(a.dig(:check, :bonus))),
        save:  api_roll("#{a[:attr]} save", a.dig(:save, :dice),
                        api_competency(a.dig(:save, :bonus)) + save_tokens, ranks: a.dig(:save, :ranks)) }
    end
    skills = CreatureSheet.all_skills(acc).map do |s|
      r = CreatureSheet.skill_roll(acc, s[:key])
      roll = r ? { name: r[:roll_name], dice_count: r[:dice_count], tn: r[:tn], starting_value: r[:starting_value],
                   base_tn: r[:base_tn], bonus_penalty_list: r[:bonus_penalty_list], ranks: r[:ranks] } : nil
      s.merge(roll: roll)
    end
    {
      ok: true,
      id: acc.id, name: h[:name], player: h[:player], summary: h[:summary],
      tier: (h[:hide_tier] ? nil : h[:tier]),
      vitals: {
        hp: v[:hp], temp_hp: v[:temp_hp].to_i, mana: v[:mana], toxicity: v[:toxicity],
        damage_reduction: v[:damage_reduction].to_i, damage_resilience: v[:damage_resilience].to_i
      },
      speed: d[:speed], initiative_dice: d.dig(:initiative, :dice_count), perception: d[:perception],
      attributes: attributes, skills: skills,
      abilities: Array(d[:abilities]).map { |a| { name: a[:name], description: a[:description].to_s } },
      spells: Array(d[:spells]).map { |g| { tier: g[:tier], names: Array(g[:names]) } },
      active_effects: Array(d[:active_effects])
    }
  end

  # --- Turn options ----------------------------------------------------------

  def api_category_for_cost(cost)
    case cost.to_i
    when Encounter::Config.free_action_minimum  then 'free'
    when Encounter::Config.bonus_action_minimum then 'bonus'
    else 'main'
    end
  end

  # The skill a turn option rolls, for the app: its name, Dice Cap and bonus
  # (the Competency Modifier's value, 0 when there is none).
  def api_skill_view(name, dice_cap, competency)
    { name: name.to_s, dice: dice_cap.to_i, bonus: (competency ? competency[1].to_i : 0) }
  end

  # The dice counts the Special builder offers for a channeled Ability.
  def special_dice_counts(combatant, ability)
    blob = special_builder_blob(combatant, ability)
    step = blob[:steps].find { |st| st[:key] == 'dice' } or return []
    opts = step[:options] || Array((step[:options_map] || {}).values.first)
    opts.reject { |o| o[:kind] == 'info' }.map { |o| o[:value].to_i }.uniq.sort
  rescue StandardError
    []
  end

  def api_dice_choices(range, pool, speed: 0)
    range.map { |n| { dice: n, pool_cost: speed + n, affordable: speed + n <= pool } }
  end

  # The player's options for their turn, built from the same server code as
  # the DM's turn menu (turn_action_stub.md): equipped weapons with their
  # Martial Dice Cap, Move, known + Wand/Ring Spells, carried Potions/Scrolls,
  # usable Special Abilities, active persistent Spells, and End Turn.
  def api_turn_options(combatant)
    es   = encounter_state
    acc  = (Creatures.lookup(combatant[:creature_id]) rescue nil)
    pool = (es.combat_pool_remaining(combatant[:id]) rescue 0) || 0
    mana = combatant_mana_left(combatant[:creature_id], acc)
    can_act = (es.creature_can_act?(combatant[:id]) rescue true)
    out = []
    end_turn = { key: 'end_turn', label: 'End Turn', name: 'End Turn', kind: 'end_turn', category: 'free',
                 detail: 'Finish your turn.', dice: [], pool_cost: 0, mana_cost: 0, disabled: false }
    return [end_turn] unless can_act && acc

    attack_weapons(combatant, acc).each do |w|
      speed = [w[:speed].to_i, 0].max
      cap   = w[:dice_cap].to_i
      out << { key: "attack:#{w[:item_type]}", label: "Attack: #{w[:display_name]}", name: w[:display_name].to_s,
               kind: 'attack', category: 'main', tier: nil, ranged: !!w[:ranged],
               skill: api_skill_view('Martial', cap, w[:competency]), speed: speed,
               detail: "Speed #{speed} + 1 per die",
               dice: api_dice_choices(2..cap, pool, speed: speed), pool_cost: nil, mana_cost: 0 }
    end

    move = Encounter::Config.move_cost
    out << { key: 'move', label: 'Move', name: 'Move', kind: 'move', category: 'main',
             detail: "Costs #{move} Combat Pool dice", dice: [], pool_cost: move, mana_cost: 0 }

    castable = lambda do |sp, kind, prefix|
      min    = sp[:action_min].to_i
      cap    = sp[:dice_cap].to_i
      rolled = sp[:requires_roll] || sp[:reservoir]
      skill  = Encounter::Special.pretty_skill(sp[:skill].to_s)
      # The Tier is not written out: the app colours the spell name by Tier
      # (ui_conventions.md → Tier Colors), so it is sent as `tier`.
      parts = []
      parts << "#{sp[:mana_cost]} mana" if sp[:mana_cost].to_i.positive?
      parts << (rolled ? '1 Combat Pool die per die rolled' : "costs #{min} Combat Pool dice")
      parts << "\u00d7#{sp[:quantity]} carried" if sp[:quantity].to_i > 1
      opt = { key: "#{prefix}:#{sp[:key]}", label: "#{kind == 'item' ? 'Use' : 'Cast'}: #{sp[:display]}",
              name: sp[:display].to_s, kind: kind, tier: sp[:tier].to_i,
              skill: (rolled ? api_skill_view(skill, cap, sp[:competency]) : nil), speed: 0,
              category: api_category_for_cost(min), detail: parts.join(" \u00b7 "),
              dice: rolled ? api_dice_choices(min..[cap, min - 1].max, pool) : [],
              pool_cost: rolled ? nil : min, mana_cost: sp[:mana_cost].to_i,
              # What the player must point it at: a creature (target picker),
              # themselves, an object, or an area the DM places on the map.
              target: (if sp[:area] then 'area'
                       elsif sp[:object_target] then 'object'
                       elsif sp[:self_only] then 'self'
                       else 'creature'
                       end) }
      opt[:disabled_reason] = 'not enough Mana' unless sp[:affordable]
      opt[:disabled_reason] ||= "Dice Cap #{cap} is below the #{min}-dice minimum" if rolled && cap < min
      opt
    end
    spells = (known_spell_castables(acc, pool, mana) + granted_item_castables(combatant, acc, pool, mana))
             .reject { |sp| sp[:long_cast] }
    spells.each { |sp| out << castable.call(sp, 'cast', 'cast') }
    consumable_castables(combatant, acc, pool).reject { |sp| sp[:long_cast] }
                                              .each { |sp| out << castable.call(sp, 'item', 'item') }

    Array((es.special_options(combatant[:id]) rescue [])).each do |s|
      cost = s[:action_cost].to_i
      # A channeled Ability (Bardic Performance) offers the DM's Special
      # builder's dice counts (its Performance Dice Cap / Combat Pool bound).
      channel = s[:channeled] ? special_dice_counts(combatant, s[:name]) : []
      opt = { key: "special:#{s[:name]}", label: s[:label].to_s, name: s[:label].to_s, kind: 'special', category: s[:activation].to_s,
              detail: s[:summary].to_s, mana_cost: s[:mana_cost].to_i,
              dice: channel.map { |n| { dice: n, pool_cost: n, affordable: n <= pool } },
              pool_cost: s[:channeled] ? nil : cost }
      opt[:category] = 'main' unless %w[main bonus free].include?(opt[:category])
      opt[:disabled_reason] = s[:disabled_reason] if s[:disabled]
      out << opt
    end

    Array((active_persistent_spells(combatant) rescue [])).each do |e|
      out << { key: "active:#{e[:spell_name]}", label: "#{e[:spell_name]} (conc)", name: "#{e[:spell_name]} (conc)", kind: 'active_spell', category: 'main',
               detail: 'Attack, retarget, refill or end this Spell — the DM picks the details.',
               dice: [], pool_cost: 0, mana_cost: 0 }
    end

    out << end_turn
    out.each { |o| o[:disabled] = !o[:disabled_reason].nil? }
    # A sound tied to the action (config/action_sounds.yml): the app offers a
    # button to play it on the device.
    out.each do |o|
      next unless %w[special cast item].include?(o[:kind])
      (snd = ActionSounds.path_for(o[:name])) && o[:sound] = snd
    end
  end

  # In Combat as the players see it: combat running and the party's Phase is
  # Combat (the same condition the web Encounter page uses for the turn panel).
  def api_in_combat?
    encounter_state.combat_active? && encounter_state.phase == :combat
  end

  # Attack targets for the player's target picker: every other Combatant,
  # enemies (the other side of the PC / non-PC line) first.
  # The player's own entry (self: true) comes last; it is offered for Spells
  # and Items (e.g. a heal), never for an Attack.
  def api_targets(mine)
    mine_pc = creature_is_pc?(mine[:creature_id])
    encounter_state.combatants.map do |c|
      pc = creature_is_pc?(c[:creature_id])
      me = c[:id] == mine[:id]
      { combatant_id: c[:id], name: me ? "#{tracker_name(c)} (you)" : tracker_name(c), enemy: !me && pc != mine_pc,
        self: me, dying: !!(encounter_state.creature_dying?(c[:id]) rescue false) }
    end.sort_by { |t| [t[:self] ? 2 : (t[:enemy] ? 0 : 1), t[:name]] }
  end

  def api_my_combatant(acc)
    encounter_state.combatants.find { |c| c[:creature_id].to_s == acc.id.to_s }
  end

  # A Combatant's status for the Initiative screen's Status rows, from its
  # redacted tracker row (Encounter::Visibility): what a player may not see
  # is marked hidden, and the app shows a "?" for it. Tier (for the name's
  # colour) is sent for Player Characters only.
  def api_status_view(r, es)
    hp = r[:hp]
    tier = r[:is_pc] ? ((Creatures.lookup(r[:creature_id]).tier rescue nil)) : nil
    {
      tier: tier.nil? ? nil : tier.to_i,
      acted: !r[:acting] && !es.turn_pending_this_round?(r[:combatant_id]),
      pool: r[:combat_pool],
      hp: hp && (hp[:hide_numbers] ? { hidden: true } : { current: hp[:current], max: hp[:max] }),
      mana: r[:is_pc] ? r[:mana] : { hidden: true },
      conditions: r[:is_pc] ? Array(r[:badges]).map { |b| b[:label].to_s } : nil
    }
  end

  def dice_colors_view(character_id)
    mine = DiceColors.instance.key_for(character_id)
    names = ->(who) { who == DiceColors::DM ? 'the DM' : ((Creatures.get(who) || {})[:name] rescue nil) || 'another player' }
    { ok: true, color: mine, hex: DiceColors.entry(mine)[:hex],
      options: DiceColors.instance.options(character_id).map do |o|
        { key: o[:key], name: o[:name], hex: o[:hex], taken_by: o[:taken_by] && names.call(o[:taken_by]) }
      end }
  end

  def api_request_view(r)
    r.slice('id', 'key', 'label', 'category', 'dice', 'pool_cost', 'mana_cost', 'at')
  end
end

# Who am I? Lets the app confirm it found a Crimson Steel server and whether
# the DM has assigned this device a Character yet.
get '/api/hello' do
  cid = assigned_character_id
  info = cid && (Creatures.get(cid) rescue nil)
  api_json(ok: true, service: LanDiscovery::SERVICE, version: LanDiscovery::VERSION,
           campaign: (Chronicle.store.campaign_name rescue nil),
           device: assignment_short_id(current_device_id),
           character: info ? { id: cid, name: info[:name] } : nil,
           dice_color: info ? DiceColors.instance.hex_for(cid) : nil)
end

# The player's dice colour and every colour on offer, with who has each
# (docs/project/dice_colors.md). Names only, never another device's id.
get '/api/dice_colors' do
  acc = api_character!
  api_json(dice_colors_view(acc.id))
end

# Body: { "color": "<key>" }. Refused (409) when someone else has it.
post '/api/dice_color' do
  acc = api_character!
  body = (JSON.parse(request.body.read) rescue nil)
  api_error(400, 'invalid payload') unless body.is_a?(Hash)
  begin
    DiceColors.instance.set(acc.id, body['color'].to_s)
  rescue ArgumentError => e
    api_error(409, e.message)
  end
  api_json(dice_colors_view(acc.id))
end

get '/api/sheet' do
  api_json(api_sheet(api_character!))
end

get '/api/inventory' do
  acc  = api_character!
  data = inventory_stub_data(acc.id)
  api_json(ok: true, creature_id: acc.id, manageable: manageable_creature?(acc.id.to_s),
           equipped: data[:equipped], inventory: data[:inventory], sell: data[:sell])
end

get '/api/initiative' do
  acc = api_character!
  es  = encounter_state
  reconcile_player_combatants!
  acting = es.acting_combatant_id
  mine   = api_my_combatant(acc)
  rows = es.combatants.map { |c| build_tracker_row(c, acting) }
  rows = rows.sort_by { |r| [r[:initiative].to_s.empty? ? 1 : 0, invert_init(r[:initiative].to_s), r[:combatant_id]] }
  rows = Encounter::Visibility.redact_rows(rows, viewer: :player, sees_injury: viewer_sees_injury?)
  my_turn = !!(mine && api_in_combat? && acting == mine[:id])

  me = nil
  if mine
    pool_max = (es.get_combat_pool(mine[:id]) rescue nil)
    v = CreatureSheet.vitals(acc, acc.tier) rescue nil
    me = { combatant_id: mine[:id],
           pool: pool_max && { remaining: (es.combat_pool_remaining(mine[:id]) rescue 0), max: pool_max },
           main_actions_remaining: (es.main_actions_remaining(mine[:id]) rescue nil),
           mana: v && v[:mana] }
  end
  key = mine && PlayerRequests.turn_key(es, mine[:id])
  api_json(
    ok: true, combat_active: api_in_combat?, round_label: es.round_label,
    acting_combatant_id: acting, my_turn: my_turn, me: me,
    order: rows.map do |r|
      { combatant_id: r[:combatant_id], name: r[:name], is_pc: r[:is_pc], acting: r[:acting],
        is_you: !!(mine && r[:combatant_id] == mine[:id]), initiative: r[:initiative] }.merge(api_status_view(r, es))
    end,
    # On their turn everything; on anyone else's, Free actions only.
    options: (offered = api_available_options(mine, my_turn)),
    # True while a die roll waits on this player: the app hides the action
    # list until it is rolled.
    busy: !!(mine && blocking_flow(mine)),
    # Who an action can target (enemies first), whenever something is offered.
    targets: (offered.empty? ? [] : api_targets(mine)),
    # Steps waiting on this player in any attack (their turn or not).
    prompts: my_prompts(acc),
    # This player's own attacks in progress.
    flows: (mine ? action_flows.active.select { |f| f.attacker_id == mine[:id] }.map { |f| flow_status_view(f) } : []),
    shared: api_in_combat? ? shared_actions(acc) : [],
    # What the DM committed lately (shown once each on every phone).
    news: api_in_combat? ? news_view(acc) : [],
    # Every action with Rolls on the table, whether or not this player rolls in it.
    actions: api_in_combat? ? action_views(acc) : [],
    requests: mine ? PlayerRequests.instance.for_turn(mine[:id], key).map { |r| api_request_view(r) } : []
  )
end

# Ask the DM for an action this turn. Body (JSON): { key, dice }.
post '/api/turn/requests' do
  acc = api_character!
  es  = encounter_state
  mine = api_my_combatant(acc)
  api_error(409, 'not_your_turn') unless mine && api_in_combat?
  my_turn = es.acting_combatant_id == mine[:id]
  body = (JSON.parse(request.body.read) rescue nil)
  api_error(400, 'invalid payload') unless body.is_a?(Hash)

  # A die roll waiting on this player comes first.
  if (busy = blocking_flow(mine))
    api_error(409, "roll your dice first (#{busy.summary})")
  end
  opt = api_turn_options(mine).find { |o| o[:key] == body['key'].to_s }
  api_error(422, 'unknown option') unless opt
  # Off their turn, only a Free action (Rage…).
  api_error(409, 'not_your_turn') unless api_available_options(mine, my_turn).any? { |o| o[:key] == opt[:key] }
  api_error(422, opt[:disabled_reason]) if opt[:disabled]

  # An attack runs as a step-by-step flow: target's defense, ally shields,
  # Luck and the dice are asked of each player in turn (lib/routes/action_flows.rb).
  if opt[:kind] == 'attack'
    api_error(422, 'choose a target') if body['target_id'].to_s.empty?
    flow, err = start_attack_flow(mine, opt[:key].sub('attack:', ''), body['dice'], body['target_id'])
    api_error(422, err) if err
    api_json(ok: true, flow: flow_status_view(flow))
  end
  # Spells, Potions / Scrolls and Special Abilities run the same way
  # (docs/project/action_flow.md).
  if %w[cast item].include?(opt[:kind])
    flow, err = start_cast_flow(mine, opt, body['dice'], body['target_id'])
    api_error(422, err) if err
    api_json(ok: true, flow: flow_status_view(flow))
  end
  if opt[:kind] == 'special'
    flow, err = start_special_flow(mine, opt, body['dice'])
    api_error(422, err) if err
    api_json(ok: true, flow: flow_status_view(flow))
  end
  dice = nil
  cost = opt[:pool_cost].to_i
  unless opt[:dice].empty?
    choice = opt[:dice].find { |d| d[:dice] == body['dice'].to_i }
    api_error(422, 'choose a dice count') unless choice
    api_error(422, 'not enough Combat Pool') unless choice[:affordable]
    dice = choice[:dice]
    cost = choice[:pool_cost]
  end
  key = PlayerRequests.turn_key(es, mine[:id])
  PlayerRequests.instance.add(combatant_id: mine[:id], creature_id: acc.id, turn_key: key,
                              key: opt[:key], label: opt[:label], category: opt[:category],
                              dice: dice, pool_cost: cost, mana_cost: opt[:mana_cost])
  api_json(ok: true, requests: PlayerRequests.instance.for_turn(mine[:id], key).map { |r| api_request_view(r) })
end

# Withdraw one of this turn's requests (the app's Undo).
post '/api/turn/requests/:id/delete' do
  acc  = api_character!
  mine = api_my_combatant(acc)
  api_error(404, 'not in combat') unless mine
  PlayerRequests.instance.remove(params[:id], combatant_id: mine[:id])
  key = PlayerRequests.turn_key(encounter_state, mine[:id])
  api_json(ok: true, requests: PlayerRequests.instance.for_turn(mine[:id], key).map { |r| api_request_view(r) })
end

# Chronicle notes visible to this Character (public text only).
get '/api/notes' do
  acc = api_character!
  store = Chronicle.store
  entries = store.list_entries(visible_to: acc.id)
                 .sort_by { |e| [e['chapter'] || 0, e['notes_position'] || 9999] }
  chapters = store.list_chapters.to_h { |c| [c[:number], c[:name]] }
  api_json(
    ok: true, current_chapter: store.current_chapter,
    chapters: store.list_chapters,
    notes: entries.map do |e|
      title = e['entry_type'] == 'creature' ? resolve_creature_for(e)[:full_title] : e['title'].to_s
      { id: e['id'], type: e['entry_type'], chapter: e['chapter'], chapter_name: chapters[e['chapter']],
        title: title, body: e['public_description'].to_s, image: e['image'], active: !!e['active'] }
    end
  )
end

# The current scene: what is active in the Chronicle right now (the same list
# the web Encounter page shows players), plus the in-game time.
get '/api/scene' do
  acc = api_character!
  store = Chronicle.store
  current = store.list_chapters.find { |c| c[:number] == store.current_chapter }
  active = store.list_entries(active_only: true, visible_to: acc.id).sort_by { |e| e['scene_position'] || 9999 }
  api_json(
    ok: true, campaign: (store.campaign_name rescue nil),
    chapter: current && current[:name], time: api_time_label(store.timestamp),
    combat_active: api_in_combat?,
    entries: active.map do |e|
      creature = e['entry_type'] == 'creature'
      { id: e['id'], type: e['entry_type'],
        title: creature ? resolve_creature_for(e)[:full_title] : e['title'].to_s,
        body: e['public_description'].to_s, image: e['image'] }
    end
  )
end

# The DM dismisses a player request from the turn panel (it was handled, or
# refused). DM only.
post '/encounter/player_requests/:id/dismiss' do
  halt 403 unless dm_view?
  PlayerRequests.instance.remove(params[:id])
  redirect(request.referer || '/encounter')
end
