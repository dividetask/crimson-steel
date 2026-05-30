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

  # ---- Check Resolution Builder blob for an attack -------------------
  #
  # Precompute the entire decoupled builder blob (check_resolution_builder_stub.md):
  # target / weapon+dice / defense steps whose options carry patches that
  # mutate the seed Rolls, so the Builder runs without calling back. Per the
  # design, attacker TN folds in Competency + Unaware (per target) + Flatfooted
  # (only when no defense is declared); the defender's Roll + dice are baked
  # per (target, weapon, defense). The blob is large by design.
  def attack_builder_blob(attacker)
    acc      = Creatures.lookup(attacker[:creature_id]) rescue nil
    die      = DiceResolution.config.die_size
    base_tn  = DiceResolution.config.base_target_number
    atk_pool = (encounter_state.combat_pool_remaining(attacker[:id]) rescue 0) || 0

    weapons = equipped_weapons(attacker[:creature_id]).map do |w|
      attr = w[:ranged] ? :dex : :str
      ri   = roll_inputs_for(acc, 'martial', attribute_override: attr)
      w.merge(dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier])
    end

    targets = encounter_state.combatants.reject { |c| c[:id] == attacker[:id] }.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      { id: c[:id], name: tracker_name(c), unaware: !c[:performed_this_turn],
        pool: (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0,
        martial: roll_inputs_for(tacc, 'martial',   attribute_override: :str),
        dodge:   roll_inputs_for(tacc, 'dex_save', attribute_override: :dex) }
    end

    rolls = [
      { id: 'attacker', side: 'supporting', creature_name: tracker_name(attacker),
        roll_name: 'Attack', die_size: die, tn: base_tn, starting_value: 0, dice_count: 2, excluded: false },
      { id: 'defender', side: 'opposing', creature_name: '—',
        roll_name: 'Defense', die_size: die, tn: base_tn, starting_value: 0, dice_count: 0, excluded: true }
    ]

    target_step = { key: 'target', label: 'Target',
                    options: targets.map { |t| { value: t[:id], key: t[:id], label: t[:name],
                                                 patch: { set_name: [{ id: 'defender', creature_name: t[:name] }] } } } }

    action_opts = []
    weapons.each do |w|
      speed   = [w[:speed].to_i, 1].max
      cap     = w[:dice_cap]
      aff_max = [cap, atk_pool / speed].min
      disp    = w[:display_name]
      grp     = w[:item_type]
      # One button per weapon (max affordable dice), then one per die choice.
      action_opts << { value: "#{w[:item_type]}|#{aff_max}", key: w[:item_type], group: grp,
                       label: disp, summary: "#{disp} — #{aff_max}d", disabled: aff_max < 2,
                       patch: { set_dice: [{ id: 'attacker', count: aff_max }] } }
      (2..cap).each do |n|
        action_opts << { value: "#{w[:item_type]}|#{n}", key: w[:item_type], group: grp,
                         label: "#{n}d", summary: "#{disp} — #{n}d", disabled: n * speed > atk_pool,
                         patch: { set_dice: [{ id: 'attacker', count: n }] } }
      end
    end
    action_step = { key: 'action', label: 'Weapon & dice', options: action_opts }

    defense_map = {}
    targets.each do |t|
      weapons.each do |w|
        comp = w[:competency] ? [w[:competency]] : []
        tn_none     = DiceResolution.compute_target_number(comp + Encounter::Attack.attacker_bonuses(no_defense: true,  unaware: t[:unaware]))
        tn_declared = DiceResolution.compute_target_number(comp + Encounter::Attack.attacker_bonuses(no_defense: false, unaware: t[:unaware]))
        opts = [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                  patch: { set_tn: [{ id: 'attacker', tn: tn_none[:tn], starting_value: tn_none[:starting_value] }],
                           set_excluded: [{ id: 'defender', excluded: true }] } }]
        (w[:ranged] ? %w[dodge block] : %w[dodge block parry]).each do |d|
          di   = d == 'dodge' ? t[:dodge] : t[:martial]
          dcmp = di[:competency_modifier] ? [di[:competency_modifier]] : []
          dtn  = DiceResolution.compute_target_number(dcmp)
          cap  = di[:dice_cap].to_i
          mk = lambda do |dice, label, summary|
            { value: "#{d}|#{dice}", group: d, label: label, summary: summary,
              patch: { set_tn: [{ id: 'attacker', tn: tn_declared[:tn], starting_value: tn_declared[:starting_value] },
                                { id: 'defender', tn: dtn[:tn], starting_value: dtn[:starting_value] }],
                       set_dice: [{ id: 'defender', count: dice }],
                       set_name: [{ id: 'defender', roll_name: d.capitalize }],
                       set_excluded: [{ id: 'defender', excluded: false }] } }
          end
          if d == 'dodge'
            opts << mk.call(cap, 'Dodge', "Dodge — #{cap}d")            # full Dice Cap, no pool
          else
            aff = [cap, t[:pool]].min
            opts << mk.call(aff, d.capitalize, "#{d.capitalize} — #{aff}d")  # name = max affordable
            (2..aff).each { |n| opts << mk.call(n, "#{n}d", "#{d.capitalize} — #{n}d") }
          end
        end
        defense_map["#{t[:id]}|#{w[:item_type]}"] = opts
      end
    end
    defense_step = { key: 'defense', label: 'Target&rsquo;s defense', options_by: %w[target action], options_map: defense_map }

    { title: "#{tracker_name(attacker)} attacks", stub_id: "attack-#{attacker[:id]}",
      rolls: rolls, steps: [target_step, action_step, defense_step] }
  end

  # Fill in the weapon damage / Speed / attack kind for a resolve payload
  # from the chosen weapon (the client carries only `weapon_type`), so the
  # combat damage logic stays server-side.
  def enrich_attack_payload!(payload)
    wt  = payload['weapon_type']
    atk = payload['attacker'] || {}
    return unless wt && atk['id']
    combatant = encounter_state.combatant(atk['id'].to_i) or return
    w = equipped_weapons(combatant[:creature_id]).find { |x| x[:item_type] == wt } or return
    acc = Creatures.lookup(combatant[:creature_id]) rescue nil
    payload['attack_kind'] ||= w[:ranged] ? 'ranged' : 'melee'
    atk['speed'] = w[:speed]
    payload['attacker'] = atk
    payload['weapon'] = { 'damage_types' => w[:damage_types], 'threshold' => w[:threshold],
                          'base_damage' => evaluate_weapon_damage(w[:damage_formula], acc) }
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
# attack_builder precomputes the whole Check Resolution Builder blob for an
# attack (Target / Weapon+dice / Defense steps, each option carrying a patch);
# the Builder resolves it client-side and posts the picked choices + Successes
# to resolve_attack, which recomputes the weapon damage from the chosen weapon,
# spends Combat Pool, and applies damage.

# The Check Resolution Builder for the Acting Combatant's attack, rendered as
# an HTML fragment the turn-action panel injects.
get '/encounter/attack_builder' do
  require_dm!
  attacker = encounter_state.combatant(params[:attacker_id].to_i)
  return encounter_error(404, 'unknown attacker') unless attacker
  erb :_check_builder, layout: false, locals: { builder: attack_builder_blob(attacker) }
end

post '/encounter/resolve_attack' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  enrich_attack_payload!(payload)
  result = encounter_state.resolve_attack_payload(payload)
  encounter_response(result)
end
