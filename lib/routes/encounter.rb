# Encounter page + mutation endpoints.
#
# Page (DM + Player):
#   GET  /encounter — shows the active scene of play: timekeeping,
#                     the Combat Tracker (when Combat is active or the
#                     viewer is the DM), and Chronicle notes (hidden
#                     from players once Combat starts).
#
# Mutation endpoints (DM only; JSON-in, JSON-out):
#   POST /encounter/add                — Add Combatant by Creature ID
#   POST /encounter/spawn_and_add      — Spawn from template + Add Combatant
#   POST /encounter/remove_by_creature — Remove the most recently added
#                                        Combatant whose creature_id matches
#   POST /encounter/set_pc_active      — Toggle a PC's `excluded_pcs` membership
#   POST /encounter/set_npc_active     — Toggle an NPC's roster presence
#   POST /encounter/start_combat       — Enter Combat mode
#   POST /encounter/end_combat         — Leave Combat mode
#   POST /random_encounters/roll/:id   — Roll a Random Encounter and add the
#                                        spawned Creatures to the roster
#
# Mutation endpoints return `{ ok: true, ... }` on success,
# `{ ok: false, error: "..." }` on failure.

get '/encounter' do
  @store      = Chronicle.store
  @viewer     = viewer_role
  @viewing_id = viewing_creature_id
  @timestamp  = @store.timestamp
  @encounter_state = Encounter.state
  reconcile_player_combatants!
  @combat_active   = @encounter_state.combat_active?

  if @viewer == :dm
    @active_entries = @store.list_entries(active_only: true)
  else
    @active_entries = @store.list_entries(active_only: true, visible_to: @viewing_id)
  end

  @active_entries = @active_entries.sort_by { |e| e['scene_position'] || 9999 }
  @chapters       = @store.list_chapters
  @current_chapter = @store.current_chapter
  @player_creatures = player_creatures

  # Build the Combat Tracker rows from the live Combatant roster, always
  # sorted by Initiative (descending; un-rolled combatants last, then by
  # Combat ID) — whether or not Combat is active.
  acting_id = @encounter_state.acting_combatant_id
  @round_label = @encounter_state.round_label
  rows = @encounter_state.combatants.map { |c| build_tracker_row(c, acting_id) }
  @tracker_rows = rows.sort_by do |r|
    [r[:initiative].to_s.empty? ? 1 : 0, invert_init(r[:initiative].to_s), r[:combatant_id]]
  end

  # Turn Action panel context (turn_action_stub.md): the Acting
  # Combatant's tracker row plus its Dead? state, for the DM-only panel
  # below the tracker.
  @acting_row  = @tracker_rows.find { |r| r[:acting] }
  @acting_dead = @acting_row ? @encounter_state.creature_dead?(@acting_row[:combatant_id]) : false

  erb :encounter
end

helpers do
  def encounter_state
    Encounter.state
  end

  # Render-time reconciliation: every non-excluded Player Character
  # belongs in the active Combat, so make sure each is a Combatant
  # before we render the roster or tracker. Players therefore always
  # appear unless explicitly marked Absent.
  def reconcile_player_combatants!
    pc_ids = Creatures.player_controlled.map { |pc| pc[:id] }
    encounter_state.reconcile_pcs(pc_ids)
  end

  def require_dm!
    halt 403, { 'Content-Type' => 'application/json' }, JSON.generate(ok: false, error: 'DM only') unless dm_view?
  end

  def encounter_response(payload)
    [200, { 'Content-Type' => 'application/json' }, JSON.generate(payload)]
  end

  def encounter_error(status, msg)
    [status, { 'Content-Type' => 'application/json' }, JSON.generate(ok: false, error: msg)]
  end

  # Build the JSON snapshot the JS uses to update the sidebar row.
  def encounter_row_snapshot(creature_id)
    {
      creature_id: creature_id.to_s,
      copy_count:  encounter_state.copy_count(creature_id),
      in_combat:   encounter_state.includes_creature?(creature_id),
      pc_excluded: encounter_state.pc_excluded?(creature_id)
    }
  end

  # Assemble one Combat Tracker row for a Combatant, pulling vitals
  # from the Creatures Accessor and live state from the Conditions
  # store. Columns whose owning domain is not wired yet (Initiative,
  # Combat Pool) carry nil and render as a dash. Resilient to a
  # dangling creature_id (e.g. a spawned Creature lost on restart).
  def build_tracker_row(combatant, acting_id)
    creature = Creatures.lookup(combatant[:creature_id]) rescue nil
    name = if !combatant[:name].to_s.empty?
             combatant[:name]
           elsif creature
             creature.name
           else
             "Creature ##{combatant[:creature_id]}"
           end

    init = combatant[:initiative_string].to_s
    row = {
      combatant_id: combatant[:id],
      creature_id:  combatant[:creature_id],
      name:         name,
      initiative:   init.empty? ? nil : init,
      combat_pool:  nil,
      acting:       (combatant[:id] == acting_id),
      can_act:      true,
      hp:           nil, mana: nil, toxicity: nil,
      badges:       []
    }
    return row unless creature

    pool_max = (encounter_state.get_combat_pool(combatant[:id]) rescue nil)
    if pool_max
      row[:combat_pool] = { remaining: [pool_max - combatant[:combat_pool_spent], 0].max, max: pool_max }
    end

    inst  = Conditions.store.instance_for(combatant[:creature_id])
    state = inst.state

    max_hp = (creature.max_hit_points rescue nil)
    if max_hp
      dmg = state.hp_damage
      row[:hp] = {
        max:      max_hp,
        minor:    dmg[:minor] || 0,
        moderate: dmg[:moderate] || 0,
        major:    dmg[:major] || 0,
        current:  [max_hp - dmg.values.sum, 0].max
      }
    end

    max_mana = (creature.max_mana rescue nil)
    row[:mana] = { remaining: [max_mana - state.mana_spent, 0].max, max: max_mana } if max_mana

    cha = (creature.attribute_value(:cha) rescue nil)
    tier = (creature.tier rescue nil)
    if cha && tier
      row[:toxicity] = { value: state.magic_toxicity, threshold: inst.toxicity_threshold(cha, tier) }
    end

    badges = []
    badges << { kind: 'shock', label: "#{state.shock} Shock" } if state.shock.positive?
    badges << { kind: 'pain',  label: "#{state.acid_counter} Pain" } if state.acid_counter.positive?
    inst.affliction_badges.each do |a|
      badges << { kind: a[:category], label: "#{a[:name].to_s.capitalize}: #{a[:potency]}" }
    end
    badges << { kind: 'major', label: "Major: #{state.hp_damage[:major]}" } if (state.hp_damage[:major] || 0).positive?
    row[:badges] = badges

    if max_hp
      row[:can_act] = inst.can_act?(
        max_hit_points: max_hp,
        attribute_scores: creature_attribute_scores(creature),
        toxicity_threshold: (row.dig(:toxicity, :threshold) || 0)
      )
    end

    row
  end

  def creature_attribute_scores(creature)
    %i[str dex con int wis cha].each_with_object({}) do |a, h|
      h[a] = (creature.attribute_value(a) rescue 0)
    end
  end

  # Invert a Dice Result String so an ascending sort orders highest
  # initiative first (mirrors the State's internal comparator).
  def invert_init(str)
    str.bytes.map { |b| (255 - b).chr }.join
  end

  # ---- Attack pipeline glue (gather live domain data) ----------------

  # Display name for a Combatant: stored override → live Creature name
  # → "Creature #<id>".
  def tracker_name(combatant)
    return combatant[:name] unless combatant[:name].to_s.empty?
    creature = Creatures.lookup(combatant[:creature_id]) rescue nil
    creature ? creature.name : "Creature ##{combatant[:creature_id]}"
  end

  def equipment_owner(creature_id) = "creature:#{creature_id}"

  # Equipped weapons for a Creature, with the details the attack
  # pipeline needs (resolved from Equipment, damage formula left as a
  # string — evaluated per-attacker in build_attack).
  def equipped_weapons(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.select { |s| s.equipped && (it = cat.item_type(s.item_type)) && it[:category] == 'Weapon' }
       .map do |s|
      wd = Equipment::Details.weapon_details(s, cat)
      ranged = (wd[:definition] && wd[:definition]['category'] == 'Ranged')
      { item_type: s.item_type, display_name: wd[:display_name], ranged: ranged,
        speed: wd[:speed], damage_types: wd[:damage_types], threshold: wd[:threshold],
        bleed: wd[:bleed], damage_formula: wd[:damage_formula] }
    end
  end

  # Evaluate a weapon damage formula (e.g. "str / 4 - 2") against the
  # attacker's Effective Attributes. Combat owns this evaluation per
  # equipment_design.md. Clamped at zero.
  def evaluate_weapon_damage(formula, accessor)
    return 0 if formula.nil? || formula.to_s.strip.empty?
    binds = %i[str dex con int wis cha].each_with_object({}) { |a, h| h[a] = (accessor.attribute_value(a) rescue 0) }
    [(Abilities::Formula.evaluate(formula, binds).to_i rescue 0), 0].max
  end

  # Proficiencies *Compute Roll inputs* for an attack/defense
  # proficiency, tolerant of a creature with no live record.
  def roll_inputs_for(accessor, key, attribute_override: nil)
    return { dice_cap: 0, competency_modifier: nil } unless accessor
    Proficiencies::Compute.roll_inputs(key: key, creature: accessor, attribute_override: attribute_override)
  rescue StandardError
    { dice_cap: 0, competency_modifier: nil }
  end
end

post '/encounter/add' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  combatant = encounter_state.add_combatant(creature_id, name_override: params[:name])
  encounter_response(ok: true, combatant: combatant, row: encounter_row_snapshot(creature_id))
end

post '/encounter/spawn_and_add' do
  require_dm!
  template_id = params[:template_id]
  return encounter_error(400, 'template_id is required') if template_id.nil? || template_id.to_s.empty?

  begin
    new_creature_id = Creatures.spawn_from_template(Integer(template_id))
  rescue ArgumentError => e
    return encounter_error(404, e.message)
  end

  combatant = encounter_state.add_combatant(new_creature_id)
  encounter_response(
    ok: true,
    combatant: combatant,
    spawned_creature_id: new_creature_id,
    row: encounter_row_snapshot(template_id)
  )
end

post '/encounter/remove_by_creature' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  removed = encounter_state.remove_last_combatant_by_creature_id(creature_id)
  if removed
    encounter_response(ok: true, removed: removed, row: encounter_row_snapshot(creature_id))
  else
    encounter_response(ok: false, error: 'no matching combatant', row: encounter_row_snapshot(creature_id))
  end
end

post '/encounter/set_pc_active' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  active = params[:active].to_s == 'true' || params[:active] == true || params[:active] == '1'
  if active
    encounter_state.remove_pc_exclusion(creature_id)
    # Auto-add the PC to the roster when activated, unless already present.
    encounter_state.add_combatant(creature_id) unless encounter_state.includes_creature?(creature_id)
  else
    encounter_state.add_pc_exclusion(creature_id) # also drops any matching Combatants
  end
  encounter_response(ok: true, active: active, row: encounter_row_snapshot(creature_id))
end

post '/encounter/set_npc_active' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  active = params[:active].to_s == 'true' || params[:active] == true || params[:active] == '1'
  if active
    encounter_state.add_combatant(creature_id) unless encounter_state.includes_creature?(creature_id)
  else
    encounter_state.remove_all_combatants_by_creature_id(creature_id)
  end
  encounter_response(ok: true, active: active, row: encounter_row_snapshot(creature_id))
end

# Delete a spawned Creature: drop every Combatant referencing it and
# delete the underlying Creature record (the sidebar's spawned-row
# `−` button). Used for instances cloned from a template.
post '/encounter/delete_creature' do
  require_dm!
  creature_id = params[:creature_id]
  return encounter_error(400, 'creature_id is required') if creature_id.nil? || creature_id.to_s.empty?

  encounter_state.remove_all_combatants_by_creature_id(creature_id)
  deleted = (Creatures.delete(Integer(creature_id)) rescue false)
  encounter_response(ok: true, deleted: deleted, creature_id: creature_id.to_s)
end

# Re-rendered Roster Sidebar fragment. The client fetches this after a
# mutation so spawned-creature rows and counts update without a full
# page reload.
get '/encounter/roster_sidebar' do
  halt 404 unless dm_view?
  reconcile_player_combatants!
  detail = params[:detail] == 'full' ? 'full' : 'minimal'
  erb :_creatures_roster_sidebar, layout: false,
      locals: { roster: LiveRoster.build, current_creature_id: params[:creature_id], detail: detail }
end

post '/encounter/start_combat' do
  require_dm!
  reconcile_player_combatants!
  encounter_state.start_combat
  encounter_state.reroll_initiative # roll initiative for everyone on start
  # Point the turn at the top of the initiative order so the Combat
  # Tracker shows the ▶ marker on the acting Combatant immediately.
  first = encounter_state.acting_combatants.first
  encounter_state.set_acting_combatant(first[:id]) if first
  redirect back || '/encounter'
end

post '/encounter/end_combat' do
  require_dm!
  encounter_state.end_combat
  redirect back || '/encounter'
end

post '/encounter/reroll_initiative' do
  require_dm!
  st = encounter_state
  # If anyone still lacks an Initiative String, this only rolls the
  # missing ones (leaving rolled Combatants untouched). Only once every
  # Combatant has rolled does Roll Init reroll the whole field.
  any_missing = st.combatants.any? { |c| c[:initiative_string].to_s.empty? }
  st.reroll_initiative(missing_only: any_missing)
  redirect back || '/encounter'
end

# Set one Combatant's Initiative String directly (DM double-click
# inline editor). The raw value is parsed down to valid die-result
# characters, sorted descending; re-sorting on render moves the
# Combatant to its new initiative slot.
post '/encounter/set_initiative' do
  require_dm!
  encounter_state.set_initiative(params[:combatant_id].to_i, params[:value].to_s)
  redirect back || '/encounter'
end

# Set the Acting Combatant directly (the per-row "Set" button — the
# GM override for whose turn it is).
post '/encounter/set_acting' do
  require_dm!
  encounter_state.set_acting_combatant(params[:combatant_id].to_i)
  redirect back || '/encounter'
end

# End Turn (turn_action_stub.md → End Turn): advance to the next Acting
# Combatant. Encounter's Advance Turn runs Per-Turn Cleanup on the
# outgoing Combatant, skips Combatants who cannot act, and advances the
# Time Tick / Round on wrap.
post '/encounter/advance_turn' do
  require_dm!
  encounter_state.advance_turn
  redirect back || '/encounter'
end

# ---- Attack pipeline endpoints (turn_action_stub.md) -----------------
#
# attack_options + attack_check build the attack's Roll data; the client
# resolves it through the Check Resolution stub and posts the result to
# resolve_attack, which spends Combat Pool and applies damage.

# Options for the turn-action panel: the attacker's equipped weapons —
# each carrying its martial Dice Cap (Strength for melee, Dexterity for
# ranged) and evaluated base damage so the panel can offer a per-weapon
# dice strip — plus the available targets.
get '/encounter/attack_options' do
  require_dm!
  attacker = encounter_state.combatant(params[:attacker_id].to_i)
  return encounter_error(404, 'unknown attacker') unless attacker
  acc = Creatures.lookup(attacker[:creature_id]) rescue nil
  weapons = equipped_weapons(attacker[:creature_id]).map do |w|
    attr = w[:ranged] ? :dex : :str
    w.merge(
      dice_cap:    roll_inputs_for(acc, 'martial', attribute_override: attr)[:dice_cap],
      base_damage: evaluate_weapon_damage(w[:damage_formula], acc)
    )
  end
  targets = encounter_state.combatants.reject { |c| c[:id] == attacker[:id] }
                           .map { |c| { combatant_id: c[:id], name: tracker_name(c) } }
  encounter_response(
    ok: true,
    attacker: { combatant_id: attacker[:id], name: tracker_name(attacker) },
    weapons:  weapons,
    targets:  targets
  )
end

# Render the attack's Roll(s) as a Check Resolution Stub fragment
# (turn_action_stub.md → Attack, step "Roll"). Builds the attacker's Roll
# (and the declared defender's Opposing Roll) in the shape _check_stub
# consumes — Dice Cap, Competency + Attacker Bonuses folded into a TN /
# Starting Value via DiceResolution.compute_target_number — then hands off
# to the shared Check engine (RollController / RollsWrapper) to resolve.
# The dice counts are the DM's picks (Combat-Pool-bounded on the client).
post '/encounter/attack_check' do
  require_dm!
  attacker = encounter_state.combatant(params[:attacker_id].to_i)
  target   = encounter_state.combatant(params[:target_id].to_i)
  return encounter_error(404, 'unknown attacker or target') unless attacker && target

  weapon = equipped_weapons(attacker[:creature_id]).find { |w| w[:item_type] == params[:weapon] }
  return encounter_error(404, 'attacker has no such equipped weapon') unless weapon

  acc_atk     = Creatures.lookup(attacker[:creature_id]) rescue nil
  attack_attr = weapon[:ranged] ? :dex : :str
  atk         = roll_inputs_for(acc_atk, 'martial', attribute_override: attack_attr)
  declared    = !(params[:defense].to_s.empty? || params[:defense] == 'none')
  unaware     = !target[:performed_this_turn]
  die         = DiceResolution.config.die_size

  atk_bpl = []
  atk_bpl << atk[:competency_modifier] if atk[:competency_modifier]
  atk_bpl.concat(Encounter::Attack.attacker_bonuses(no_defense: !declared, unaware: unaware))
  atk_tn = DiceResolution.compute_target_number(atk_bpl)

  supporting = [{
    creature_name: tracker_name(attacker),
    roll_name: "Attack (#{weapon[:display_name]})",
    dice_count: [params[:dice].to_i, 0].max, tn: atk_tn[:tn], starting_value: atk_tn[:starting_value],
    reroll: nil, nudge: nil, die_size: die, dois: nil, critical_count: nil
  }]

  opposing = []
  if declared
    choice  = params[:defense]
    acc_def = Creatures.lookup(target[:creature_id]) rescue nil
    di = choice == 'dodge' ? roll_inputs_for(acc_def, 'dex_save', attribute_override: :dex)
                           : roll_inputs_for(acc_def, 'martial', attribute_override: :str)
    def_bpl = []
    def_bpl << di[:competency_modifier] if di[:competency_modifier]
    def_tn  = DiceResolution.compute_target_number(def_bpl)
    # Dodge rolls the full Dice Cap (a Saving Throw, no pool); Parry / Block
    # default to the largest roll the defender's Combat Pool can afford.
    def_default =
      if choice == 'dodge'
        di[:dice_cap]
      else
        pool = (encounter_state.combat_pool_remaining(target[:id]) rescue nil)
        pool ? [di[:dice_cap], pool].min : di[:dice_cap]
      end
    def_dice = params[:def_dice] ? params[:def_dice].to_i : def_default
    opposing << {
      creature_name: tracker_name(target),
      roll_name: choice.to_s.capitalize,
      dice_count: [def_dice.to_i, 0].max,
      tn: def_tn[:tn], starting_value: def_tn[:starting_value],
      reroll: nil, nudge: nil, die_size: die, dois: nil, critical_count: nil
    }
  end

  erb :_check_stub, layout: false, locals: { check: { supporting: supporting, opposing: opposing } }
end

post '/encounter/resolve_attack' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  result = encounter_state.resolve_attack_payload(payload)
  encounter_response(result)
end
