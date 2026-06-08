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
  # Start of Turn pane (turn_action_stub.md): one Conditions Save
  # Resolution Stub per Affliction due this Round for the Acting Combatant,
  # plus the Active Effects that the finalize step will clear.
  acting_combatant = @acting_row ? @encounter_state.combatant(@acting_row[:combatant_id]) : nil
  @acting_saves = acting_combatant ? start_of_turn_saves(acting_combatant) : []
  # Main Actions the Acting Combatant has left this turn (-1 before their first
  # turn). Shown in the Turn Action header; tracked, not enforced.
  @acting_main_actions = @acting_row ? @encounter_state.main_actions_remaining(@acting_row[:combatant_id]) : nil

  # Acting Combatant's Character Sheet (creatures_minimal_stub.md): shown
  # under the Map during Combat. Built only when the Acting Combatant is a
  # Player Character — an NPC / monster turn shows no sheet, so enemy stats
  # never leak to players. Sourced from the live Creatures domain via the
  # CreatureSheet bridge, the same source the Character Sheets page uses.
  @acting_sheet = nil
  if @combat_active && @acting_row && creature_is_pc?(@acting_row[:creature_id])
    sheet_accessor = Creatures.lookup(@acting_row[:creature_id]) rescue nil
    @acting_sheet = sheet_accessor ? CreatureSheet.build(sheet_accessor) : nil
  end

  # Special pane (turn_action_stub.md → Special): the Acting Combatant's
  # usable non-Spell, non-Reaction Abilities, computed at render time.
  @acting_special = (@viewer == :dm && @acting_row) ? (@encounter_state.special_options(@acting_row[:combatant_id]) rescue []) : []

  # Bardic Inspiration (and any reservoir-mode Performance): the live
  # Reservoirs a DM can discharge to grant Luck. DM-only; off-turn, since a
  # discharge is a Reaction (turn_action_stub.md → Special).
  @inspirations = if @viewer == :dm
                    @encounter_state.combatants.flat_map do |c|
                      Array(c[:concentration]).select { |e| e[:mode] == 'reservoir' && e[:reservoir].to_i.positive? }
                                              .map { |e| { combatant_id: c[:id], name: tracker_name(c),
                                                           spell_name: e[:spell_name], reservoir: e[:reservoir] } }
                    end
                  else
                    []
                  end

  # Atlas map (atlas_stub.md): the DM always sees the embedded map; players
  # see it only while Combat is active. The canvas is fed a JSON render
  # snapshot, and the DM toolbar lists the available Maps and the Combatants
  # the *Place Token* control can drop onto the Active Map. The DM may browse
  # a non-active (e.g. archived) Map view-only via `?map=<id>`.
  view_map_id = (@viewer == :dm && !params[:map].to_s.empty?) ? params[:map].to_i : nil
  @atlas_snapshot  = atlas_map_snapshot(@viewer, map_id: view_map_id)
  @atlas_maps      = Atlas.state.list_maps(include_archived: true)
  @atlas_active_id = Atlas.state.active_map_id
  @atlas_placeable = atlas_placeable_combatants

  # Encounter Phase (the DM's menu dropdown) — the view selector that
  # decides which stubs render below. See encounter.erb.
  @phase = @encounter_state.phase

  # Post-combat cleanup (equipment_post_combat_creatures_stub.md): DM-only,
  # shown in the Looting Phase whenever non-PC Combatants are still on the
  # roster (the just-ended fight's enemies). Loots + clears them on Confirm.
  @post_combat_rows = (@viewer == :dm && @phase == :looting) ? post_combat_rows : []

  # Loot pile (equipment_loot_pile_stub.md): both viewers, in the Looting
  # Phase, against the active Map's Ground Pile. Players get a Claim button
  # (to their own Creature); everyone gets a Give dropdown over the combat
  # participants. The DM has no viewing Creature, so no Claim.
  if @phase == :looting
    @loot_pile              = loot_pile_view(combat_pile_owner)
    @loot_give_options      = combat_creature_options
    @loot_claim_creature_id = viewing_creature_id
  else
    @loot_pile = nil
  end

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
    # A Combatant added to the encounter starts with NO Initiative — the DM
    # rolls it manually (the roster's roll-initiative control, or *Start
    # Combat* which rolls everyone). We deliberately do not auto-roll here.
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

  # ---- Looting (post-combat creatures + loot pile stubs) -------------
  #
  # equipment_post_combat_creatures_stub.md / equipment_loot_pile_stub.md.
  # Both stubs are shown only in the Looting Phase. The post-combat stub
  # (DM-only) loots and clears the non-PC Combatants into the active Map's
  # Ground Pile; the loot-pile stub (DM + players) distributes that pile.

  # The Ground Pile location for the active Map (e.g. "map_3"), or nil
  # when no Map is active. The pile is named after the Map, so loot left
  # unlooted when the party changes Maps is no longer surfaced.
  def loot_pile_location
    id = Atlas.state.active_map_id
    id.nil? ? nil : "map_#{id}"
  end

  # The Ground Pile Owner ID for the active Map's loot pile, or nil when
  # no Map is active.
  def combat_pile_owner
    loc = loot_pile_location
    loc.nil? ? nil : "ground:#{loc}"
  end

  # The non-PC Combatants of the current roster — every Combatant whose
  # Creature is not tagged player_character. These are the rows the
  # post-combat cleanup stub offers to loot and delete, each carrying a
  # preview of the gear it would hand over (its current Inventory; a
  # loot_table adds random items on top). A dangling creature_id (record
  # lost on restart) is skipped.
  def post_combat_rows
    cat  = Equipment.catalog
    inst = Equipment.instance
    encounter_state.combatants.filter_map do |c|
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next unless acc
      next if Array(acc.tags).include?('player_character')
      inv = inst.get_inventory("creature:#{c[:creature_id]}")
      { combatant_id: c[:id],
        creature_id:  c[:creature_id],
        name:         tracker_name(c),
        loot_table:   acc.record[:loot_table],
        loot:         inv.map { |s| { name: Equipment::DisplayName.call(s, cat), quantity: s.quantity } } }
    end
  end

  # Aggregate the loot every row would contribute into one list (quantities
  # summed by name, first-seen order), plus whether any contributor rolls a
  # Loot Table. The stub server-renders this for the default (all rows set
  # to Loot); postCombatLoot.js refines it live as the toggles change.
  def combine_loot(rows)
    totals = {}
    order  = []
    rows.each do |r|
      r[:loot].each do |it|
        order << it[:name] unless totals.key?(it[:name])
        totals[it[:name]] = totals.fetch(it[:name], 0) + it[:quantity]
      end
    end
    { items:  order.map { |n| { name: n, quantity: totals[n] } },
      random: rows.any? { |r| r[:loot_table] } }
  end

  # The loot-pile view model for a Ground Pile, or nil when the pile has
  # nothing to show (nothing looted yet, or it was fully distributed —
  # Equipment's Cleanup deletes a pile the moment it empties, so an empty
  # Inventory means the pile is gone). One card per Stack, styled like the
  # Inventory stub: index (the action ref), display name, icon, quantity.
  def loot_pile_view(pile_owner_id)
    return nil if pile_owner_id.nil?
    inst  = Equipment.instance
    stacks = inst.get_inventory(pile_owner_id)
    return nil if stacks.nil? || stacks.empty?
    cat = Equipment.catalog
    rows = stacks.each_with_index.map do |stack, i|
      { ref:      i,
        name:     Equipment::DisplayName.call(stack, cat),
        icon:     item_icon_web_path(stack.item_type),
        quantity: stack.quantity }
    end
    { owner_id: pile_owner_id, rows: rows }
  end

  # The Creatures that were involved in this combat — the current Combatant
  # roster, deduped by Creature ID — used to populate the loot "Give"
  # dropdown. A dangling creature_id (record lost on restart) is skipped.
  def combat_creature_options
    seen = {}
    encounter_state.combatants.each do |c|
      next if seen.key?(c[:creature_id])
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next unless acc
      seen[c[:creature_id]] = acc.name
    end
    seen.map { |id, name| { id: id, name: name } }
  end

  # Whether a Creature ID is one of the combat participants (a valid "Give"
  # target). Never trust a posted creature id without this check.
  def combat_creature?(creature_id)
    combat_creature_options.any? { |c| c[:id].to_s == creature_id.to_s }
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
      # Current HP may go negative (damage beyond Max) — show the real value;
      # the bar widths clamp at zero in the stub, but the number does not.
      row[:hp] = {
        max:      max_hp,
        minor:    dmg[:minor] || 0,
        moderate: dmg[:moderate] || 0,
        major:    dmg[:major] || 0,
        current:  max_hp - dmg.values.sum
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
    # Named Active Effects (Conditions like Rage) — shown across from the name.
    inst.active_effect_names.each do |name|
      badges << { kind: 'effect', label: name.to_s.split(/[_\s]+/).map(&:capitalize).join(' ') }
    end
    # Bardic Inspiration / reservoir Performances, and Luck Points granted.
    Array(combatant[:concentration]).each do |e|
      next unless e[:mode] == 'reservoir' && e[:reservoir].to_i.positive?
      badges << { kind: 'luck', label: "#{e[:spell_name]}: #{e[:reservoir]}" }
    end
    badges << { kind: 'luck', label: "Luck: #{combatant[:luck_points]}" } if combatant[:luck_points].to_i.positive?
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

  # ---- Start of Turn pane (turn_action_stub.md) ----------------------
  #
  # One Conditions Save Resolution Stub `save` blob per Affliction due this
  # Round for the Acting Combatant (the same shape Status builds in
  # lib/status/sample_conditions.rb; see conditions_save_resolution_stub.md).
  # We pass the Creature's own `save_modifiers` (its Save Competency plus any
  # Always-On Save bonuses that apply against the Affliction's category — a
  # Dwarf's racial poison resistance, a Cloak of Resistance, ...); the stub
  # itself adds the Potency Save Penalty and the Inflicter Tier Penalty and
  # computes the TN, so every modifier is listed in its TN breakdown. The
  # `resolve` key tells the stub's Confirm where to POST the rolled DoIS so
  # it actually resolves the Affliction (vs. the Status page's display-only
  # demo).
  def start_of_turn_saves(combatant)
    return [] unless combatant
    inst  = Conditions.store.instance_for(combatant[:creature_id])
    return [] unless encounter_state.current_abs_round

    acc     = Creatures.lookup(combatant[:creature_id]) rescue nil
    divisor = inst.catalog.potency_divisor
    die     = DiceResolution.config.die_size
    tier    = (acc&.tier rescue 0) || 0
    cname   = tracker_name(combatant)

    encounter_state.pending_afflictions(combatant[:id]).filter_map do |name|
      rule = (inst.catalog.affliction(name) rescue nil)
      next nil unless rule && rule['effect']
      entry   = inst.state.afflictions[name] || {}
      potency = entry[:potency].to_i
      attr    = (rule['save'] || 'con').to_s

      ri  = roll_inputs_for(acc, "#{attr}_save", attribute_override: attr.to_sym)
      # The Creature's own Save Bonuses/Penalties: the Save Competency plus
      # any Always-On Save modifiers that apply against this Affliction's
      # category (a Dwarf's +1 racial poison resistance, a Cloak of
      # Resistance, ...). The save stub adds the Potency Save Penalty and the
      # Inflicter Tier Penalty and computes the TN itself, listing each.
      save_mods = []
      save_mods << ri[:competency_modifier] if ri[:competency_modifier]
      if acc
        category = (rule['category'] || 'other').to_s
        CreatureModifiers.save_modifiers(acc, attr, descriptors: [category]).each { |pair| save_mods << pair }
      end

      {
        creature:   { id: combatant[:creature_id], name: cname, tier: tier },
        affliction: { name: name, rule: rule, potency: potency,
                      inflicter_tier: entry[:inflicting_tier].to_i },
        save_dice: ri[:dice_cap].to_i, save_modifiers: save_mods, die_size: die,
        potency_divisor: divisor,
        reroll_sources: nil, mass_reroll_sources: nil, nudge_sources: nil,
        stub_id: "sot-#{combatant[:id]}-#{name}",
        resolve: { url: '/encounter/resolve_affliction',
                   combatant_id: combatant[:id], affliction: name }
      }
    end
  end

  # Active Effects on the Acting Combatant that *Clear Expired Effects*
  # will remove this Round (`ends_on_round <= current Round`): plain
  # Active Effects, an expiring Temporary HP pool, and expiring named-
  # effect mechanics. Surfaced so the Start of Turn pane can name exactly
  # what Submit will clear instead of a vague "clears expired effects".
  def expiring_effects_for(combatant)
    return [] unless combatant
    inst  = Conditions.store.instance_for(combatant[:creature_id])
    round = encounter_state.current_abs_round
    return [] unless round
    st  = inst.state
    out = []

    st.effects.each do |e|
      next unless e[:ends_on_round] && e[:ends_on_round] <= round
      out << { label: effect_label(e), ends_on_round: e[:ends_on_round] }
    end

    thp = st.temporary_hit_points
    if thp && thp[:ends_on_round] && thp[:ends_on_round] <= round
      out << { label: "Temporary HP (#{thp[:amount]})", ends_on_round: thp[:ends_on_round] }
    end

    st.named_effect_mechanics.each do |m|
      next unless m[:ends_on_round] && m[:ends_on_round] <= round
      name = (m[:effect_name] || m[:kind]).to_s
      out << { label: name.split(/[_:]/).map(&:capitalize).join(' '), ends_on_round: m[:ends_on_round] }
    end

    out
  end

  # A short DM-facing label for an Active Effect entry: a metadata name if
  # present, otherwise the source prefix with its Bonus Type and amount.
  def effect_label(e)
    meta = e[:metadata] || {}
    name = meta['name'] || meta[:name]
    return name.to_s unless name.to_s.empty?
    base = e[:source_id].to_s.split(/[_:]/).first.to_s
    base = 'Effect' if base.empty?
    amt  = e[:amount]
    if amt.is_a?(Integer)
      "#{base.capitalize} (#{e[:bonus_type]} #{amt >= 0 ? '+' : ''}#{amt})"
    else
      "#{base.capitalize} (#{e[:bonus_type]})"
    end
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
    rows = inv.select { |s| s.equipped && (it = cat.item_type(s.item_type)) && it[:category] == 'Weapon' }
              .map { |s| weapon_row(Equipment::Details.weapon_details(s, cat), s.item_type) }
    # Race / Class Natural Attacks (e.g. a beast's Bite) — granted weapons
    # offered as attacks but never carried as inventory.
    acc = Creatures.lookup(creature_id) rescue nil
    natural = (acc ? CreatureSheet.granted_natural_weapons(acc) : []).map do |name|
      weapon_row(Equipment::Details.weapon_details(Equipment::Stack.normalize('item' => name), cat), name)
    end
    # Everyone can attack Unarmed (Speed 0) — always offered, never carried.
    rows + natural + [weapon_row(Equipment::Details.weapon_details(Equipment::Stack.normalize('item' => 'Unarmed'), cat), 'Unarmed')]
  end

  def weapon_row(wd, item_type)
    ranged = (wd[:definition] && wd[:definition]['category'] == 'Ranged')
    natural = !!(wd[:definition] && wd[:definition]['natural'])
    { item_type: item_type, display_name: wd[:display_name], ranged: ranged, natural: natural,
      speed: wd[:speed], damage_types: wd[:damage_types], threshold: wd[:threshold],
      bleed: wd[:bleed], damage_formula: wd[:damage_formula], affliction: wd[:affliction],
      affliction_potency: wd[:affliction_potency], damage_riders: wd[:damage_riders],
      tier_advantage: wd[:tier_advantage] }
  end

  # The defender's weapons usable to Parry: equipped melee weapons, excluding
  # natural attacks (Unarmed, claws, bite, …). You cannot Parry with a natural
  # attack without a special ability — and no such ability is wired yet, so
  # natural weapons are simply never offered as a Parry option.
  def equipped_melee_weapons(creature_id)
    equipped_weapons(creature_id).reject { |w| w[:ranged] || w[:natural] }
  end

  # A target holding any Flatfooted-Suppressor ability (Uncanny Dodge, ...)
  # cannot be caught Flatfooted or Unaware.
  def flatfooted_immune?(accessor)
    return false unless accessor
    names = (accessor.granted_abilities.map { |g| g[:name].to_s } rescue [])
    (names & Encounter::Config.flatfooted_suppressors).any?
  rescue StandardError
    false
  end

  def equipped_shield?(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.any? do |s|
      next false unless s.equipped
      it = cat.item_type(s.item_type)
      it && it[:category] == 'Armor' && (it[:definition] || {})['category'] == 'Shield'
    end
  rescue StandardError
    false
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

  # ---- Action Builder blob for an attack -------------------
  #
  # Precompute the entire decoupled builder blob (action_builder_stub.md):
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
    atk_tier = (acc&.tier rescue 0) || 0
    # Inherent / Ascendancy Tier modifiers on the attack check read the
    # Creatures Tier Minimum Inherent Bonus table.
    inh_table = (Creatures::Config.tier_minimum_inherent_bonus rescue [])

    # Display the character's own Bonus/Penalty list (natural signs). TNs are
    # NOT computed here — the builder hands raw Bonus lists to Check Resolution,
    # which applies cross-side propagation and computes every TN itself.
    fmt_mods = ->(list) { list.map { |type, amt| "#{amt >= 0 ? '+' : ''}#{amt} #{type}" }.join(' ') }

    weapons = equipped_weapons(attacker[:creature_id]).map do |w|
      attr = w[:ranged] ? :dex : :str
      ri   = roll_inputs_for(acc, 'martial', attribute_override: attr)
      w.merge(dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier])
    end
    # Spiritual Weapon: while the caster channels it, the floating weapon strikes
    # each turn with a number of dice equal to its (persistent) Reservoir — a
    # force attack that costs no Combat Pool and does not consume the Reservoir.
    sw = Array(attacker[:concentration]).find { |e| e[:spell_name].to_s == 'Spiritual Weapon' && e[:reservoir].to_i.positive? }
    if sw
      weapons << { item_type: 'spiritual_weapon', display_name: 'Spiritual Weapon', ranged: true,
                   speed: 0, damage_types: ['force'], threshold: 0, bleed: 0, base_damage: 0,
                   dice_cap: sw[:reservoir].to_i, competency: nil }
    end

    atk_tier = (acc&.tier rescue nil)

    targets = encounter_state.combatants.reject { |c| c[:id] == attacker[:id] }.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      { id: c[:id], name: tracker_name(c), unaware: encounter_state.unaware?(c[:id]),
        # Uncanny Dodge (et al.) make the target immune to Flatfooted / Unaware.
        flatfooted_immune: flatfooted_immune?(tacc),
        # A target that cannot act (incapacitated / paralyzed / dying) is
        # Helpless: it offers no defense and attacks against it gain the more
        # severe Helpless advantage (supersedes Flatfooted / Unaware).
        helpless: !(encounter_state.creature_can_act?(c[:id]) rescue true),
        is_pc: creature_is_pc?(c[:creature_id]), tier: (tacc&.tier rescue 0) || 0,
        pool: (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0,
        martial: roll_inputs_for(tacc, 'martial',   attribute_override: :str),
        dodge:   roll_inputs_for(tacc, 'dex_save', attribute_override: :dex),
        # Parry uses one of the defender's melee weapons; Block needs a shield.
        parry_weapons: equipped_melee_weapons(c[:creature_id]),
        has_shield:    equipped_shield?(c[:creature_id]) }
    end

    # Seed Rolls carry raw inputs (base TN + each side's own Bonus list + dice).
    # `tn`/`starting_value` start at the base for the initial render; Check
    # Resolution recomputes them (with cross-side propagation) as steps resolve.
    rolls = [
      { id: 'attacker', side: 'supporting', creature_name: tracker_name(attacker),
        roll_name: 'Attack', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 2, speed: 0, excluded: false,
        tier: atk_tier },
      { id: 'defender', side: 'opposing', creature_name: '—',
        roll_name: 'Defense', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true,
        tier: nil },
      # A Shield of Faith caster defending the target — a second Opposing Roll,
      # hidden until the defender chooses it (fueled by Reservoir dice).
      { id: 'shield', side: 'opposing', creature_name: '—',
        roll_name: 'Shield of Faith', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true,
        tier: nil }
    ]

    # Map of defender Combatant id -> the caster shielding them (Shield of Faith)
    # and their available Reservoir dice, so the defense step can offer the
    # caster's block as an Opposing Roll.
    shields = {}
    encounter_state.granted_actions.select { |g| g[:source].to_s == 'Shield of Faith' && g[:defends] }.each do |g|
      cc = encounter_state.combatant(g[:combatant_id]) or next
      res = Array(cc[:concentration]).find { |e| e[:mode] == 'reservoir' && e[:spell_name].to_s == 'Shield of Faith' }
      next unless res && res[:reservoir].to_i >= 2
      cacc = Creatures.lookup(cc[:creature_id]) rescue nil
      shields[g[:defends]] = { caster_id: g[:combatant_id], caster_name: tracker_name(cc),
                               reservoir: res[:reservoir].to_i, dice_cap: g[:dice_cap].to_i,
                               tier: (cacc&.tier rescue nil) }
    end

    # Header quick-picks (next to "Target"): one button per enemy of the
    # attacker. Enemies are the Combatants on the opposite side of the
    # PC / non-PC line — if the attacker is a Player Character its enemies are
    # the non-PCs, and vice versa.
    attacker_pc   = creature_is_pc?(attacker[:creature_id])
    enemy_targets = targets.select { |t| t[:is_pc] != attacker_pc }
    target_step = { key: 'target', label: 'Target',
                    header_options: enemy_targets.map { |t| { value: t[:id], label: t[:name] } },
                    options: targets.map { |t| { value: t[:id], key: t[:id], label: t[:name],
                                                 patch: { set_name: [{ id: 'defender', creature_name: t[:name] }],
                                                          set_tier: [{ id: 'defender', tier: t[:tier] }] } } } }

    action_opts = []
    action_quick = []
    weapons.each do |w|
      cap   = w[:dice_cap]
      speed = [w[:speed].to_i, 0].max
      disp  = w[:display_name]
      grp   = w[:item_type]
      # The weapon's intrinsic attack Bonuses (Competency etc.). These are
      # handed to Check Resolution raw — the builder does not compute the TN.
      bpl   = w[:competency] ? [w[:competency]] : []
      set_atk = lambda do |dice|
        { set_dice: [{ id: 'attacker', count: dice }], set_speed: [{ id: 'attacker', speed: speed }],
          set_bpl: [{ id: 'attacker', bonus_penalty_list: bpl }] }
      end
      # Cost to roll n dice = flat weapon Speed + n; grey out unaffordable.
      # Spiritual Weapon rolls Reservoir dice (free), so its dice aren't pool-gated.
      free    = w[:item_type] == 'spiritual_weapon'
      aff = ->(n) { free || speed + n <= atk_pool }
      aff_max = (2..cap).select { |n| aff.call(n) }.max
      max_opt = { value: "#{w[:item_type]}|#{aff_max || cap}", key: w[:item_type], group: grp,
                  label: "#{disp} (speed #{speed})", summary: "#{disp} — #{aff_max || cap} dice",
                  disabled: aff_max.nil?, patch: set_atk.call(aff_max || cap) }
      action_opts << max_opt
      (2..cap).each do |n|
        action_opts << { value: "#{w[:item_type]}|#{n}", key: w[:item_type], group: grp,
                         label: n.to_s, summary: "#{disp} — #{n} dice",
                         disabled: !aff.call(n), patch: set_atk.call(n) }
      end
      action_opts << { kind: 'info', group: grp, value: "#{grp}|info",
                       label: (bpl.empty? ? 'no bonuses' : fmt_mods.call(bpl)) }
      # Header quick-pick: one button per weapon that selects it at max dice.
      action_quick << { value: max_opt[:value], label: disp, disabled: aff_max.nil? }
    end
    action_step = { key: 'action', label: 'Weapon & dice', options: action_opts, header_options: action_quick }

    defense_map = {}
    defense_header_map = {}
    targets.each do |t|
      weapons.each do |w|
        comp = w[:competency] ? [w[:competency]] : []
        # Tier modifiers on the attack check: the attacker's (Glory-adjusted)
        # Inherent Bonus on both branches, plus an Ascendancy penalty equal to
        # the un-rolled defender's Inherent on the No-defense branch (a defended
        # branch lets the defender's Inherent propagate instead). The defender's
        # own Inherent rides its defense Roll (see `def_tier`).
        atk_tier_none = Encounter::Attack.attacker_tier_bonuses(
          attacker_tier: atk_tier, defender_tier: t[:tier], tier_advantage: w[:tier_advantage],
          inherent_table: inh_table, no_defense: true
        )
        atk_tier_def = Encounter::Attack.attacker_tier_bonuses(
          attacker_tier: atk_tier, defender_tier: t[:tier], tier_advantage: w[:tier_advantage],
          inherent_table: inh_table, no_defense: false
        )
        def_tier = Encounter::Attack.defender_tier_bonuses(defender_tier: t[:tier], inherent_table: inh_table)
        # Raw attacker Bonus lists (no TN math here), each carrying its tier
        # modifiers. Flatfooted applies whenever the defender is NOT Dodging —
        # so no defence and Block / Parry all keep it; only Dodge sheds it (the
        # per-branch list is built in the branch loop). Unaware applies only on
        # the no-defence branch (declaring a defence proves awareness). Uncanny
        # Dodge (et al.) via `flatfooted_immune` sheds both. `atk_declared_bpl`
        # backs the Shield of Faith branch (a caster defends; the shielded
        # target itself is not Dodging, so it stays Flatfooted unless immune).
        atk_none_bpl     = comp + atk_tier_none + Encounter::Attack.attacker_bonuses(
          flatfooted: !t[:flatfooted_immune], unaware: t[:unaware] && !t[:flatfooted_immune], helpless: t[:helpless])
        atk_declared_bpl = comp + atk_tier_def + Encounter::Attack.attacker_bonuses(
          flatfooted: !t[:flatfooted_immune], unaware: false, helpless: t[:helpless])
        # No defense first (attacker keeps Flatfooted), then one group per
        # Defensive Action: a name button carrying the defence Speed (Dodge /
        # Block = 0, Parry = weapon Speed), a button per die choice, and a
        # trailing line showing the defender's own Bonuses. Check Resolution
        # propagates the attacker's Bonuses onto the defender Roll (and vice
        # versa) and computes both TNs.
        opts = [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                  patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_none_bpl }],
                           set_excluded: [{ id: 'defender', excluded: true }] } }]
        # Header quick-picks: "No defense" first, then one button per
        # Defensive Action (top-right, like the weapon buttons), each
        # selecting that defence at the MINIMUM dice (the Reaction Action
        # Minimum) — Defensive Actions all cost pool.
        headers = [{ value: 'none', label: 'No defense' }]
        # Eligible Defensive Action branches against this attack:
        #   Dodge — always (uses dex_save inputs; pool-costed, Speed 0).
        #   Block — only when the defender has a Shield equipped; any attack.
        #   Parry — melee attacks only, one branch per equipped melee weapon
        #           ("Parry with <weapon>"); costs that weapon's Speed + dice.
        # A Helpless target (incapacitated / paralyzed / dying) cannot Dodge,
        # Block, or Parry — only "No defense" is offered.
        branches = []
        unless t[:helpless]
          # Dodge borrows the dex_save proficiency for its Dice Cap/Modifiers but
          # is a pool-costed Defensive Action (not a Saving Throw): Speed 0, dice
          # chosen from the Reaction Minimum up to the remaining pool.
          branches << { key: 'dodge', group: 'dodge', name: 'Dodge', inputs: t[:dodge], speed: 0, save: false }
          if t[:has_shield]
            branches << { key: 'block', group: 'block', name: 'Block', inputs: t[:martial], speed: 0, save: false }
          end
          unless w[:ranged]
            t[:parry_weapons].each do |pw|
              branches << { key: "parry:#{pw[:item_type]}", group: "parry:#{pw[:item_type]}",
                            name: "Parry with #{pw[:display_name]}", inputs: t[:martial],
                            speed: [pw[:speed].to_i, 0].max, save: false }
            end
          end
        end

        branches.each do |b|
          di    = b[:inputs]
          # The defender's own Competency plus its Inherent Tier Bonus — the
          # latter propagates onto the attacker's TN per Check Resolution, which
          # is how a higher-Tier defender makes the attack harder.
          dcmp  = (di[:competency_modifier] ? [di[:competency_modifier]] : []) + def_tier
          cap   = di[:dice_cap].to_i
          dspd  = b[:speed]
          # Flatfooted sticks unless this defence is a Dodge; declaring a
          # defence proves awareness, so Unaware never applies here.
          atk_branch_bpl = comp + Encounter::Attack.attacker_bonuses(
            flatfooted: (b[:key] != 'dodge') && !t[:flatfooted_immune], unaware: false, helpless: t[:helpless])
          # A Dodge's Competency helps the defender's own Roll but is NOT
          # propagated onto the attacker as a penalty — Check Resolution's
          # per-Roll `no_propagate` field carries that (the defender's Inherent
          # still crosses as Ascendancy). Other defences propagate normally.
          def_no_prop = b[:key] == 'dodge' ? ['Competency'] : []
          mk = lambda do |dice, label, disabled|
            { value: "#{b[:key]}|#{dice}", group: b[:group], label: label,
              summary: "#{b[:name]} — #{dice} dice", disabled: disabled,
              patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_branch_bpl },
                                 { id: 'defender', bonus_penalty_list: dcmp }],
                       set_no_propagate: [{ id: 'defender', types: def_no_prop }],
                       set_dice:  [{ id: 'defender', count: dice }],
                       set_speed: [{ id: 'defender', speed: dspd }],
                       set_name:  [{ id: 'defender', roll_name: b[:name] }],
                       set_excluded: [{ id: 'defender', excluded: false }] } }
          end
          name_label = "#{b[:name]} (speed #{dspd})"
          if b[:save]
            # Dodge is a Saving Throw: it always spends the full Dice Cap and
            # costs no Combat Pool, so there is no dice count to ask for — one
            # option only, both in the body and as the quick-pick.
            opts << mk.call(cap, "#{b[:name]} (max #{cap})", cap < 2)
            headers << { value: "#{b[:key]}|#{cap}", label: b[:name], disabled: cap < 2 }
          else
            aff_max = (2..cap).select { |n| dspd + n <= t[:pool] }.max
            opts << mk.call(aff_max || cap, name_label, aff_max.nil?)
            (2..cap).each { |n| opts << mk.call(n, n.to_s, dspd + n > t[:pool]) }
            hmin = Encounter::Config.reaction_action_minimum
            headers << { value: "#{b[:key]}|#{hmin}", label: b[:name],
                         disabled: (hmin > cap || dspd + hmin > t[:pool]) }
          end
          opts << { kind: 'info', group: b[:group], value: "#{b[:group]}|info",
                    label: (dcmp.empty? ? 'no bonuses' : fmt_mods.call(dcmp)) }
        end
        # Shield of Faith: a caster shielding this target blocks the attack as a
        # separate Opposing Roll, spending Reservoir dice (no Combat Pool, and
        # the target's own Defense Roll stays excluded).
        sh = shields[t[:id]]
        if sh
          # Up to the caster's casting-skill Dice Cap, and never more dice than
          # Reservoir remains (1 Reservoir die spent per die rolled).
          dcap = sh[:dice_cap].to_i.positive? ? sh[:dice_cap].to_i : sh[:reservoir]
          cap = [sh[:reservoir], dcap].min
          mk_sh = lambda do |dice|
            { value: "shield:#{sh[:caster_id]}|#{dice}", group: 'shield', label: dice.to_s,
              summary: "Shield of Faith — #{dice} dice",
              patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_declared_bpl }],
                       set_dice: [{ id: 'shield', count: dice }],
                       set_tier: [{ id: 'shield', tier: sh[:tier] }],
                       set_name: [{ id: 'shield', roll_name: "Shield of Faith (#{sh[:caster_name]})" }],
                       set_excluded: [{ id: 'defender', excluded: true }, { id: 'shield', excluded: false }] } }
          end
          (2..cap).each { |n| opts << mk_sh.call(n) }
          headers << { value: "shield:#{sh[:caster_id]}|2", label: "Shield (#{sh[:caster_name]})", disabled: cap < 2 }
          opts << { kind: 'info', group: 'shield', value: 'shield|info',
                    label: "Shield of Faith by #{sh[:caster_name]} — up to #{cap} Reservoir dice" }
        end
        defense_map["#{t[:id]}|#{w[:item_type]}"] = opts
        defense_header_map["#{t[:id]}|#{w[:item_type]}"] = headers
      end
    end
    defense_step = { key: 'defense', label: 'Target&rsquo;s defense',
                     options_by: %w[target action], options_map: defense_map,
                     header_options_by: %w[target action], header_options_map: defense_header_map }

    steps = [target_step, action_step, defense_step]

    # Luck (before the dice): one step per source that can spend Luck on this
    # attack as a Reaction — see #luck_steps.
    steps.concat(luck_steps(actor_id: attacker[:id],
                            targets: [{ roll_id: 'attacker', label: tracker_name(attacker) },
                                      { roll_id: 'defender', label: 'Defender' }]))

    { title: "#{tracker_name(attacker)} attacks", stub_id: "attack-#{attacker[:id]}",
      rolls: rolls, steps: steps }
  end

  # Luck steps (turn_action_stub.md → Luck; mechanics per dice/check
  # resolution). One step per source that may spend Luck on this Check as a
  # Reaction: every *other* Combatant holding a Bardic Inspiration Reservoir,
  # plus the DM (player id null) whenever the DM holds DM Luck. Each step is a
  # `dynamic: 'luck'` table the client fills from the live Rolls — per Roll the
  # source may grant a bonus (Bardic Inspiration: reroll low dice) up to
  # min(source Luck, that Roll's dice), and, when allowed, a penalty
  # (Unsettling Words: reroll high dice). A Bard may impose a penalty only when
  # it knows Unsettling Words; the DM may always apply either. Bonuses (and
  # penalties) do not stack — only the highest of each per Roll takes effect
  # (dice_resolution_design.md → Reroll / TN per-Type stacking), and each die is
  # rerolled at most once.
  def luck_steps(actor_id:, targets:)
    steps = []
    encounter_state.combatants.each do |c|
      next if c[:id] == actor_id # a Reaction can't fire on your own action
      entry = Array(c[:concentration]).find { |e| e[:mode] == 'reservoir' && e[:reservoir].to_i.positive? }
      next unless entry
      steps << luck_step("#{c[:id]}", c[:id], tracker_name(c), entry[:reservoir].to_i,
                         bard_has_unsettling_words?(c[:creature_id]), targets)
    end
    if encounter_state.dm_luck_points.to_i.positive?
      steps << luck_step('dm', nil, 'DM', encounter_state.dm_luck_points.to_i, true, targets)
    end
    steps
  end

  def luck_step(sid, source_id, label, amount, penalty, targets)
    { key: "luck:#{sid}", label: 'Luck', dynamic: 'luck', heading: label,
      header_options: [{ value: "#{sid}|none", label: 'No luck' }],
      luck: { source: { id: source_id, sid: sid, label: label, amount: amount, penalty: penalty },
              targets: targets } }
  end

  # A Creature is a Player Character when its tags include 'player_character'
  # (creatures_design.md). Used to tell the attacker's enemies apart.
  def creature_is_pc?(creature_id)
    acc = Creatures.lookup(creature_id) rescue nil
    !!(acc && Array(acc.tags).include?('player_character'))
  rescue StandardError
    false
  end

  # Whether a Creature knows Unsettling Words (lets it discharge Bardic
  # Inspiration as a Luck penalty on an enemy, not only a bonus on an ally).
  def bard_has_unsettling_words?(creature_id)
    acc = Creatures.lookup(creature_id) rescue nil
    return false unless acc.respond_to?(:granted_abilities)
    acc.granted_abilities.any? { |g| g[:name].to_s == 'unsettling_words' }
  rescue StandardError
    false
  end

  # Fill in the weapon damage / Speed / attack kind for a resolve payload
  # from the chosen weapon (the client carries only `weapon_type`), so the
  # combat damage logic stays server-side.
  def enrich_attack_payload!(payload)
    wt  = payload['weapon_type']
    atk = payload['attacker'] || {}
    return unless wt && atk['id']
    # Spiritual Weapon is a virtual force weapon: its dice come from the
    # Reservoir (charged at cast), so it costs no Combat Pool and the Reservoir
    # is not spent. Damage is force, scaling with the net Successes (base 0).
    if wt == 'spiritual_weapon'
      payload['attack_kind'] ||= 'ranged'
      atk['speed'] = 0
      payload['attacker'] = atk
      payload['weapon'] = { 'damage_types' => ['force'], 'threshold' => 0, 'bleed' => 0, 'base_damage' => 0 }
      payload['free_attacker_pool'] = true
      return
    end
    combatant = encounter_state.combatant(atk['id'].to_i) or return
    w = equipped_weapons(combatant[:creature_id]).find { |x| x[:item_type] == wt } or return
    acc = Creatures.lookup(combatant[:creature_id]) rescue nil
    payload['attack_kind'] ||= w[:ranged] ? 'ranged' : 'melee'
    atk['speed'] = w[:speed]
    payload['attacker'] = atk
    payload['weapon'] = { 'damage_types' => w[:damage_types], 'threshold' => w[:threshold],
                          'bleed' => w[:bleed], 'affliction' => w[:affliction],
                          'affliction_potency' => w[:affliction_potency],
                          'base_damage' => evaluate_weapon_damage(w[:damage_formula], acc),
                          'damage_riders' => w[:damage_riders], 'tier_advantage' => w[:tier_advantage] }
  end

  # ---- Action Builder blob for a Cast (turn_action_stub.md → Cast)
  #
  # Same decoupled builder pattern as the Attack flow (attack_builder_blob): a
  # Target step, a "Spell & dice" action step (one group per known Spell, dice
  # bounded by the Combat Pool and the casting skill's Dice Cap), and a
  # choice-dependent Defense step — Dodge / Block for an attack-roll Spell, the
  # target's Saving Throw for a Save Spell, nothing for a utility Spell. The
  # caster Roll folds in the casting-skill Competency and the Spell Tier's
  # inherent Bonus; the Builder resolves it client-side and the choices +
  # Successes come back to /encounter/resolve_cast.
  def cast_builder_blob(caster)
    acc      = Creatures.lookup(caster[:creature_id]) rescue nil
    die      = DiceResolution.config.die_size
    base_tn  = DiceResolution.config.base_target_number
    pool     = (encounter_state.combat_pool_remaining(caster[:id]) rescue 0) || 0
    mana_max = (acc&.max_mana rescue nil)
    mana_spent = (Conditions.store.instance_for(caster[:creature_id]).state.mana_spent rescue 0)
    mana_left  = mana_max ? [mana_max - mana_spent, 0].max : nil

    spells = (CreatureSheet.spells(acc) rescue []).flat_map do |g|
      cost = mana_cost_for_tier(g[:tier])
      Array(g[:names]).map do |name|
        v     = (Abilities.lookup(name) rescue nil) || {}
        skill = (Array(v['skills']).first || Encounter::Cast::DEFAULT_CAST_SKILL)
        ri    = roll_inputs_for(acc, skill)
        # Area footprint (Hash, or the first footprint Aspect of an Aspect-list
        # area like Grease). Area Spells are placed on the map, not targeted.
        raw   = (Abilities.catalog.ability(name) rescue nil) || {}
        ra    = raw['area']
        area  = ra.is_a?(Array) ? ra.find { |x| x.is_a?(Hash) } : ra
        act   = (Abilities.resolve_activation(v) rescue nil)
        # A reservoir/auto channel pours its cast dice into a Reservoir — those
        # casts ask for a dice count but roll nothing (a Save/attack_roll on such
        # a Spell governs its per-turn channel, not the cast). A casting check is
        # rolled only for a non-reservoir Save / attack-roll / damage Spell.
        channel_mode = v.dig('channel', 'mode').to_s
        fills_reservoir = %w[reservoir auto].include?(channel_mode) &&
                          v.dig('reservoir', 'fill', 'source').to_s == 'channel_dice'
        requires_roll = !fills_reservoir &&
                        !!(v['attack_roll'] || Array(v['save']).first || Array(v['damage_type']).compact.first)
        # The Combat Pool dice a cast costs at minimum — its Action category's
        # Action Minimum (Main 4 / Bonus 2 / Free 0), not a flat 2. A no-roll,
        # no-Reservoir Spell costs exactly this and asks nothing; a rolled or
        # Reservoir Spell asks for a count from here up to the Dice Cap.
        action_min = Encounter::Special.action_cost(act && act[:alias])
        { name: name, tier: g[:tier], mana_cost: cost, skill: skill,
          dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier],
          damage_type: Array(v['damage_type']).compact.first, school: v['school'],
          attack_roll: !!v['attack_roll'], save: Array(v['save']).first,
          area: (area.is_a?(Hash) ? area : nil),
          requires_roll: requires_roll,
          reservoir: fills_reservoir,
          action_min: action_min,
          long_cast: !!(act && act[:kind].to_s == 'real_time' && act[:minutes].to_i >= 1),
          affordable: mana_left.nil? || cost <= mana_left }
      end
    end
    # Hide Spells that take a minute or longer to cast — they aren't cast in the
    # heat of combat.
    spells = spells.reject { |sp| sp[:long_cast] }

    targets = encounter_state.combatants.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      { id: c[:id], creature_id: c[:creature_id],
        name: tracker_name(c) + (c[:id] == caster[:id] ? ' (self)' : ''),
        pool: (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0,
        tier: (tacc&.tier rescue nil),
        dodge:   roll_inputs_for(tacc, 'dex_save', attribute_override: :dex),
        martial: roll_inputs_for(tacc, 'martial',  attribute_override: :str),
        has_shield: equipped_shield?(c[:creature_id]),
        saves: %i[str dex con int wis cha].each_with_object({}) { |a, h| h[a] = roll_inputs_for(tacc, "#{a}_save", attribute_override: a) } }
    end

    rolls = [
      { id: 'caster', side: 'supporting', creature_name: tracker_name(caster),
        roll_name: 'Cast', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 2, speed: 0, excluded: false,
        tier: (acc&.tier rescue nil) },
      { id: 'target', side: 'opposing', creature_name: '—',
        roll_name: 'Defense', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true,
        tier: nil }
    ]

    # Step 1 — Spell, grouped by Tier (a Tier-colored "Tier N" header, then that Tier's
    # spells underneath). Tiers with no known spell are skipped. Picking a spell
    # sets the caster Roll's Bonuses (casting-skill Competency + the Tier's
    # inherent Bonus); the dice count is the next step.
    spell_opts = []
    spells.group_by { |sp| sp[:tier].to_i }.sort_by { |tier, _| tier }.each_with_index do |(tier, group_spells), gi|
      hdr = "tier-#{tier}-h"
      grp = "tier-#{tier}"
      br  = gi.zero? ? '' : '<br>'
      spell_opts << { kind: 'info', group: hdr, value: "#{hdr}|label", label: %(#{br}<span class="cb-tier-head tier-#{tier}">Tier #{tier}</span>) }
      group_spells.each do |sp|
        bpl = []
        bpl << sp[:competency] if sp[:competency]
        bpl << ['Inherent', sp[:tier].to_i] if sp[:tier].to_i.positive?
        spell_opts << { value: sp[:name], key: sp[:name], group: grp,
                        label: sp[:name], summary: sp[:name],
                        disabled: !sp[:affordable],
                        cast: { roll: sp[:requires_roll], reservoir: sp[:reservoir] },
                        patch: { set_bpl:   [{ id: 'caster', bonus_penalty_list: bpl }],
                                 set_speed: [{ id: 'caster', speed: 0 }],
                                 set_name:  [{ id: 'caster', roll_name: "Cast #{sp[:name]}" }] } }
      end
    end
    spell_step = { key: 'spell', label: 'Spell', options: spell_opts }

    # Step 2 — Dice for the cast, choice-dependent on the picked spell. A spell
    # whose dice count is *variable* (a rolled cast, or a Reservoir pour) asks
    # for a count from its Action Minimum up to the casting-skill Dice Cap; a
    # spell whose count is *known* (a no-roll, no-Reservoir buff costs exactly
    # its Action Minimum) skips the step — the option is auto-applied with no
    # button. Either way each die is spent from the Combat Pool, so counts past
    # the remaining Pool are disabled.
    # Shaped like the Attack weapon step: each rolled spell's Dice options lead
    # with a "<casting skill> (max N)" quick-pick (selects the max affordable
    # dice), then a button per count, plus a top-right header quick-pick for the
    # max. A no-roll, known-count buff keeps its single auto-applied option.
    dice_map = {}
    header_map = {}
    spells.each do |sp|
      cap = sp[:dice_cap]
      min = sp[:action_min].to_i
      if sp[:requires_roll] || sp[:reservoir]
        if cap < min
          dice_map[sp[:name]] = [{ kind: 'info', group: 'dice', value: 'dice|none', label: 'no dice available' }]
          next
        end
        skill_label = Encounter::Special.pretty_skill(sp[:skill])
        aff_max     = [cap, pool].min
        lead_off    = aff_max < min
        set = ->(n) { { set_dice: [{ id: 'caster', count: n }] } }
        opts = [{ value: "#{sp[:name]}|#{aff_max}", key: aff_max, group: 'dice',
                  label: "#{skill_label} (max #{aff_max})", summary: "#{skill_label} — #{aff_max} dice",
                  disabled: lead_off, patch: set.call(aff_max) }]
        (min..cap).each do |n|
          opts << { value: "#{sp[:name]}|#{n}", key: n, group: 'dice', label: n.to_s,
                    summary: "#{n} dice", disabled: n > pool, patch: set.call(n) }
        end
        dice_map[sp[:name]]   = opts
        header_map[sp[:name]] = [{ value: "#{sp[:name]}|#{aff_max}", label: "Max (#{aff_max})", disabled: lead_off }]
      else
        # Known dice count — auto-applied (the builder skips the step) when the
        # caster can afford it; otherwise shown as a blocked option.
        affordable = min <= pool
        opt = { value: "#{sp[:name]}|#{min}", key: min, group: 'dice',
                label: "#{min} dice", summary: "#{min} dice",
                disabled: !affordable,
                patch: { set_dice: [{ id: 'caster', count: min }] } }
        opt[:auto] = true if affordable
        dice_map[sp[:name]] = [opt]
      end
    end
    dice_step = { key: 'dice', label: 'Dice', options_by: %w[spell], options_map: dice_map,
                  header_options_by: %w[spell], header_options_map: header_map }

    # Step 3 — Target, choice-dependent on the Spell. A normal Spell lists the
    # Combatants; an **area Spell** instead offers a single "Place on the map"
    # action — the client arms the Atlas, the DM clicks to drop the footprint,
    # and the creatures it covers become the affected set (no single Target).
    combatant_target_opts = targets.map do |t|
      { value: t[:id], key: t[:id], label: t[:name],
        patch: { set_name: [{ id: 'target', creature_name: t[:name] }],
                 set_tier: [{ id: 'target', tier: t[:tier] }] } }
    end
    target_map = {}
    spells.each do |sp|
      target_map[sp[:name]] =
        if sp[:area]
          [{ value: 'place', key: 'place', group: 'place', label: 'Place on the map',
             summary: 'Place the spell effect on the Atlas',
             place: { shape: sp[:area]['shape'], size: sp[:area]['size'], save: !!sp[:save] } }]
        else
          combatant_target_opts
        end
    end
    target_step = { key: 'target', label: 'Target', options_by: %w[spell], options_map: target_map }

    # Step 4 — the target's Defense, choice-dependent on (target, spell): the
    # target's Saving Throw for a Save spell, Dodge / Block for an attack-roll
    # spell, nothing for a utility spell. A true Saving Throw (a Save spell)
    # always spends the full Dice Cap — no dice choice; the pool-costed
    # Defensive Actions (Dodge / Block) pick dice from the pool.
    defense_map = {}
    targets.each do |t|
      spells.each do |sp|
        opts = []
        if sp[:attack_roll]
          opts << { value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                    patch: { set_excluded: [{ id: 'target', excluded: true }] } }
          opts.concat(cast_defense_branch('dodge', 'Dodge', t[:dodge], speed: 0, save: false, pool: t[:pool]))
          opts.concat(cast_defense_branch('block', 'Block', t[:martial], speed: 0, save: false, pool: t[:pool])) if t[:has_shield]
        elsif sp[:save]
          attr = sp[:save]['attribute'].to_s
          # Always-On Save bonuses (Cloak) plus the spell's School as the
          # descriptor context, so an Elf/Satyr's +1 enchantment resistance
          # applies to enchantment-school Save spells.
          tacc  = Creatures.lookup(t[:creature_id]) rescue nil
          extra = tacc ? CreatureModifiers.save_modifiers(tacc, attr, descriptors: [sp[:school]].compact) : []
          opts.concat(cast_defense_branch("save:#{attr}", "#{attr_label(attr)} save",
                                          t[:saves][attr.to_sym] || t[:dodge], speed: 0, save: true,
                                          pool: t[:pool], extra_bpl: extra))
        end
        defense_map["#{t[:id]}|#{sp[:name]}"] = opts
      end
    end
    # Area Spells resolve in the placed footprint, not against a single defender,
    # so their "defense" step is a single Confirm that excludes the lone Target
    # Roll (the caught creatures are resolved at commit).
    spells.select { |sp| sp[:area] }.each do |sp|
      defense_map["place|#{sp[:name]}"] = [
        { value: 'area', key: 'area', group: 'area', label: 'Resolve in the area',
          summary: 'Apply to the creatures in the footprint',
          patch: { set_excluded: [{ id: 'target', excluded: true }] } }
      ]
    end
    defense_step = { key: 'defense', label: 'Target&rsquo;s defense', options_by: %w[target spell], options_map: defense_map }

    steps = [spell_step, dice_step, target_step, defense_step]
    steps.concat(luck_steps(actor_id: caster[:id],
                            targets: [{ roll_id: 'caster', label: tracker_name(caster) },
                                      { roll_id: 'target', label: 'Defender' }]))

    { title: "#{tracker_name(caster)} casts", stub_id: "cast-#{caster[:id]}",
      rolls: rolls, steps: steps }
  end

  # One Defensive Action / Saving Throw branch for the Cast Defense step (mirror
  # of the Attack builder's defense branches). A true Saving Throw (a Save
  # spell, `save: true`) always spends the full Dice Cap, so it is a *single*
  # option with no dice choice. The pool-costed Defensive Actions (Dodge /
  # Block, `save: false`) show a button per affordable die count plus a trailing
  # Bonus note.
  def cast_defense_branch(key, name, inputs, speed:, save:, pool:, extra_bpl: [])
    di   = inputs || { dice_cap: 0 }
    dcmp = di[:competency_modifier] ? [di[:competency_modifier]] : []
    dcmp += Array(extra_bpl)
    cap  = di[:dice_cap].to_i
    mk = lambda do |dice, label, disabled|
      { value: "#{key}|#{dice}", group: key, label: label, summary: "#{name} — #{dice} dice", disabled: disabled,
        patch: { set_bpl: [{ id: 'target', bonus_penalty_list: dcmp }],
                 set_dice: [{ id: 'target', count: dice }],
                 set_speed: [{ id: 'target', speed: speed }],
                 set_name: [{ id: 'target', roll_name: name }],
                 set_excluded: [{ id: 'target', excluded: false }] } }
    end
    # A Saving Throw always spends the full Dice Cap — there is nothing to ask,
    # so this is a single `auto`-applied option (no button): the builder seeds
    # the Save at the Dice Cap and moves on.
    if save
      o = mk.call(cap, name, cap.zero?)
      o[:summary] = name
      o[:auto] = true
      return [o]
    end

    out = []
    aff_max = (2..cap).select { |n| speed + n <= pool }.max
    out << mk.call(aff_max || cap, "#{name} (speed #{speed})", aff_max.nil?)
    (2..cap).each { |n| out << mk.call(n, n.to_s, speed + n > pool) }
    out << { kind: 'info', group: key, value: "#{key}|info",
             label: (dcmp.empty? ? 'no bonuses' : dcmp.map { |type, amt| "#{amt >= 0 ? '+' : ''}#{amt} #{type}" }.join(' ')) }
    out
  end

  # Tier → UI color name (ui_conventions.md → Tier Colors).
  TIER_COLORS = %w[red orange yellow green blue purple].freeze
  def tier_color(tier)
    TIER_COLORS[tier.to_i] || "tier #{tier}"
  end

  def attr_label(attr)
    { 'str' => 'Strength', 'dex' => 'Dexterity', 'con' => 'Constitution',
      'int' => 'Intelligence', 'wis' => 'Wisdom', 'cha' => 'Charisma' }[attr.to_s] || attr.to_s
  end

  # The per-Tier Mana Cost (abilities_config.yaml → Mana Cost Per Tier).
  def mana_cost_for_tier(tier)
    tbl = (Abilities.catalog.config.mana_cost_per_tier rescue {})
    (tbl[tier] || tbl[tier.to_s] || tbl[tier.to_i] || 0).to_i
  end

  # Fill a Cast payload's server-known fields before resolution: the spell's
  # Tier / per-Tier Mana Cost / casting skill. Full Effect resolution is the
  # Abilities domain's job (`Abilities.resolve_spell`, Piece A) — when that
  # engine is present we fold its result (effects, polarity, toxicity, save,
  # sustain) onto the payload; until then the cast still spends Combat Pool /
  # Mana and registers any sustain the client declared.
  def enrich_cast_payload!(payload)
    spell  = (payload['spell'] ||= {})
    spell['name'] ||= payload['spell_name']
    caster = payload['caster'] || {}

    if spell['tier'].nil? && spell['name']
      info = (CreatureSheet.spell_info(spell['name']) rescue nil)
      spell['tier'] = info[:tier] if info
    end
    spell['mana_cost'] ||= mana_cost_for_tier(spell['tier']) unless spell['tier'].nil?

    if Abilities.respond_to?(:resolve_spell) && spell['name']
      resolved = (Abilities.resolve_spell(spell['name'], tier: spell['tier']) rescue nil)
      apply_resolved_spell!(payload, resolved) if resolved
    end
    # Fall back to the default casting skill only if neither the client nor the
    # resolved Variant supplied one.
    spell['cast_skill'] ||= Encounter::Cast::DEFAULT_CAST_SKILL
  end

  # Fold an Abilities.resolve_spell result (`{ effects:, polarity: }`) onto the
  # Cast payload. resolve_spell is the Equipment Consume-Item projection, so its
  # Effects use that shape (severity-keyed cure/damage, temp_hp, mana, explicit
  # damage); cast_effects_from_consumption translates them into the Cast
  # Effect kinds resolve_cast_payload routes. The casting skill, attack-roll /
  # Save handling, and a Channeled-spell sustain are read from the resolved
  # Variant.
  #
  # Still evaluated at success: 0 by resolve_spell (see the team note): a Spell
  # that states its own damage formula does not yet scale with the casting roll.
  def apply_resolved_spell!(payload, resolved)
    r = (resolved.transform_keys(&:to_s) rescue {})
    spell = (payload['spell'] ||= {})
    spell['polarity'] = r['polarity'] unless r['polarity'].nil?

    variant = (Abilities.lookup(spell['name']) rescue nil)
    spell['cast_skill'] ||= (Array(variant && variant['skills']).first || Encounter::Cast::DEFAULT_CAST_SKILL)

    effects = cast_effects_from_consumption(r['effects'])
    # Buff Spells carry a `modifiers:` list (Magic Weapon, Magic Vestments,
    # Expeditious Retreat, Resistance, Protection from Poison, …). Carry it
    # through as a `modifiers` cast Effect; resolve_cast_payload evaluates the
    # amounts against the caster and applies them as timed Active Effects.
    if variant && Array(variant['modifiers']).any?
      effects += [{ 'kind' => 'modifiers', 'modifiers' => variant['modifiers'],
                    'duration' => variant['duration'] }]
    end

    # Area Spells (Obscuring Mist, Darkness, Web, Create Pit, Silence) carry an
    # `area` footprint placed on the map at commit time. For an Aspect-list area
    # (Grease: object vs. area), use the first footprint Aspect.
    raw_entry = (Abilities.catalog.ability(spell['name']) rescue nil) || {}
    raw_area  = raw_entry['area']
    area_hash = raw_area.is_a?(Array) ? raw_area.find { |x| x.is_a?(Hash) } : raw_area
    # Each creature caught in the footprint gets the area's on-enter Effect (its
    # Save is DM-adjudicated in this pass; the per-creature opposed Save roll is
    # the follow-up that uses the Check Resolution Spread rule).
    if area_hash.is_a?(Hash) && (oe = Array(area_hash['on_enter']).first)
      fx = oe['fail'].to_s
      effects += [{ 'kind' => 'effect', 'name' => fx }] unless fx.empty? || fx == '0'
    end
    Array(payload['targets']).each { |t| t['effects'] = effects }

    if area_hash.is_a?(Hash)
      spell['area'] = area_hash
      spell['duration'] = variant['duration'] || raw_entry['duration']
    end

    # Damage routing for the Cast path. An attack-roll Spell resolves as a spell
    # attack — net the casting check against the target's Block / Dodge, damage
    # from the net Successes. A Save-based damage Spell with no explicit damage
    # Effect deals the default Spell damage (floor(casting stat / 4) + Tier +
    # Successes); a Spell that states its own damage formula keeps it.
    if variant && variant['attack_roll']
      spell['attack_roll'] = true
      spell['damage_type'] ||= Array(variant['damage_type']).compact.first
      spell['casting_attribute'] ||= (Proficiencies.attribute_for(spell['cast_skill']) || :cha).to_s
    elsif variant && Array(variant['damage_type']).compact.any? && effects.none? { |e| e['kind'] == 'damage' }
      spell['default_damage'] = true
      spell['damage_type'] ||= Array(variant['damage_type']).compact.first
      spell['casting_attribute'] ||= (Proficiencies.attribute_for(spell['cast_skill']) || :cha).to_s
    end

    # Save directive: a damage Spell's Save is for half (the default Spell-damage
    # rule); otherwise honor the Variant's success outcome (`halved` / negate).
    save_meta = variant && Array(variant['save']).first
    if save_meta
      on_success = spell['default_damage'] ? 'halved' : (save_meta['success'].to_s == 'halved' ? 'halved' : 'none')
      Array(payload['targets']).each do |t|
        next unless t['save']
        t['save']['on_success'] ||= on_success
      end
    end

    if payload['sustain'].nil? && variant && variant['channel']
      sustain = Encounter::Cast.sustain_spec(channel: variant['channel'], reservoir: variant['reservoir'])
      payload['sustain'] = sustain if sustain
    end
  end

  # Translate Equipment-shaped consumption Effects into Cast Effect kinds:
  #   { 'damage' => { amount, type } }                 -> { kind: damage }
  #   { 'temp_hp' => n } / { 'mana' => n }             -> { kind: temp_hp/mana }
  #   { minor/moderate/major_damage: ... } (signed)    -> heal (cures are
  #     negated by resolve_spell) or, if positive, summed damage.
  # Drop an area Spell's footprint on the active Map as a Zone, paired with a
  # Conditions Zone Effect. Anchored at the (first) target's Token. Returns the
  # placement, or nil when there's no active Map / Token / area — it is skipped
  # silently so the cast still succeeds. Atlas.place_zone persists the Map; the
  # Zone Effect carries the area's triggers for later on-enter resolution.
  def place_spell_area_zone!(payload)
    spell = payload['spell'] || {}
    area  = spell['area']
    return nil unless area.is_a?(Hash)
    map_id = Atlas.state.active_map_id
    return nil unless map_id
    caster = payload['caster'] || {}
    source_id = "encounter:zone:#{spell['name']}:#{caster['id']}"
    # Anchor at the placed map point (area Spells), else at the first target's
    # Token (legacy single-target anchoring).
    placement = payload['placement']
    anchor =
      if placement && placement['x'] && placement['y']
        { 'type' => 'point', 'x' => placement['x'].to_i, 'y' => placement['y'].to_i }
      else
        target = Array(payload['targets']).first or return nil
        combatant = encounter_state.combatant(target['id'].to_i) or return nil
        { 'type' => 'target', 'creature_id' => combatant[:creature_id] }
      end
    zone_id = Atlas.state.place_zone(map_id: map_id, source_id: source_id,
                                     shape: area['shape'], size: area['size'],
                                     anchor: anchor, texture: area['texture'])
    return nil unless zone_id.is_a?(Integer)
    # Expiry: the caster's casting-skill rank drives `rank`-based durations;
    # the Zone auto-expires at the caster's start of turn once this Round passes.
    cacc  = (Creatures.lookup(combatant_for_id_creature(caster['id'])) rescue nil)
    rank  = (cacc&.ranks_for(spell['cast_skill']) rescue 0) || 0
    rounds = duration_in_rounds(spell['duration'], rank)
    ends   = rounds && encounter_state.current_round ? encounter_state.current_round + rounds : nil
    Conditions.store.create_zone_effect(
      source_id: source_id, atlas_zone_id: zone_id, ends_on_round: ends,
      triggers: { on_create: area['on_create'], on_enter: area['on_enter'],
                  on_end_of_turn: area['on_end_of_turn'] },
      metadata: { 'caster_id' => caster['id'] }
    )
    { source_id: source_id, atlas_zone_id: zone_id, map_id: map_id,
      shape: area['shape'], size: area['size'], ends_on_round: ends }
  end

  # The Creature ID behind a Combatant ID (for caster lookups).
  def combatant_for_id_creature(combatant_id)
    c = encounter_state.combatant(combatant_id.to_i)
    c && c[:creature_id]
  end

  # A Spell `duration` expressed in absolute Rounds, or nil when it does not
  # convert (permanent / concentration / instant). Turns count as Rounds;
  # minutes/hours convert via Timekeeping's Round Length (seconds per Round).
  def duration_in_rounds(duration, rank)
    return nil if duration.nil?
    s = duration.to_s.strip
    binds = { 'rank' => rank.to_i }
    rl = (Timekeeping.config.round_length.to_f rescue 6.0)
    rl = 6.0 if rl <= 0
    if (m = s.match(/\A(.+?)\s+turns?\z/))
      (Abilities::Formula.evaluate(m[1], binds).to_i rescue nil)
    elsif (m = s.match(/\A(.+?)\s+minutes?\z/))
      n = (Abilities::Formula.evaluate(m[1], binds).to_f rescue nil)
      n && (n * 60 / rl).ceil
    elsif (m = s.match(/\A(.+?)\s+hours?\z/))
      n = (Abilities::Formula.evaluate(m[1], binds).to_f rescue nil)
      n && (n * 3600 / rl).ceil
    end
  end

  # Remove a caster's expired Zones at their start of turn — drop the
  # Conditions Zone Effect and the paired Atlas Zone. Returns removed source_ids.
  def expire_caster_zones!(combatant_id)
    round = encounter_state.current_round or return []
    removed = Conditions.store.expire_zone_effects_for(combatant_id, round)
    removed.each { |z| Atlas.state.remove_zone(z[:atlas_zone_id]) if z[:atlas_zone_id] }
    removed.map { |z| z[:source_id] }
  end

  # The route-level side effects of a Combatant beginning its turn: expire its
  # timed Zones (spell areas) and persist the Conditions store (begin_turn_for
  # has already refilled the pool, granted Main Actions, and cleared expired
  # Effects in memory). Called for the first Combatant at Start Combat and for
  # each Combatant the turn advances to.
  def begin_turn_side_effects!(combatant_id)
    expire_caster_zones!(combatant_id)
    Conditions.store.persist!
  end

  # A Spell whose Reservoir discharge `defends: target` (Shield of Faith) hangs
  # a shield over the chosen ally: grant the caster a reaction tied to that
  # Combatant, so attacks against the ally can surface the caster's block as an
  # opposing Roll. The Reservoir itself is registered by the cast's sustain.
  def grant_defend_reaction!(payload)
    spell = payload['spell'] || {}
    v = (Abilities.lookup(spell['name'].to_s) rescue nil) || {}
    return unless v.dig('reservoir', 'discharge', 'defends').to_s == 'target'
    caster = payload['caster'] || {}
    ally = Array(payload['targets']).first or return
    # The block may roll up to the caster's Dice Cap in the casting skill, each
    # die costing one Reservoir die — store the cap so the attack builder can
    # bound the block.
    skill = (spell['cast_skill'] || Encounter::Cast::DEFAULT_CAST_SKILL).to_s
    cacc  = (Creatures.lookup(combatant_for_id_creature(caster['id'])) rescue nil)
    cap   = (roll_inputs_for(cacc, skill)[:dice_cap].to_i rescue 0)
    # Replace any prior shield from the same caster+spell on a new cast.
    encounter_state.revoke_action { |g| g[:source] == spell['name'].to_s && g[:combatant_id] == caster['id'] }
    encounter_state.grant_action({ combatant_id: caster['id'], name: spell['name'], source: spell['name'],
                                   spell_name: spell['name'], defends: ally['id'],
                                   cast_skill: skill, dice_cap: cap })
  end

  def cast_effects_from_consumption(effects)
    Array(effects).flat_map do |raw|
      e = (raw.transform_keys(&:to_s) rescue raw)
      if e.key?('damage')
        d = (e['damage'] || {}).transform_keys(&:to_s)
        [{ 'kind' => 'damage', 'amount' => d['amount'].to_i,
           'damage_type' => (d['type'] || 'physical'), 'threshold' => 0 }]
      elsif e.key?('temp_hp')
        [{ 'kind' => 'temp_hp', 'amount' => e['temp_hp'].to_i }]
      elsif e.key?('mana')
        [{ 'kind' => 'mana', 'amount' => e['mana'].to_i }]
      elsif %w[minor_damage moderate_damage major_damage].any? { |k| e.key?(k) }
        sev = { 'minor' => e['minor_damage'].to_i, 'moderate' => e['moderate_damage'].to_i,
                'major' => e['major_damage'].to_i }
        if sev.values.all? { |v| v <= 0 }
          heal = sev.each_with_object({}) { |(k, v), h| h[k] = -v if v.negative? }
          [{ 'kind' => 'heal', 'severity_map' => heal }]
        else
          [{ 'kind' => 'damage', 'amount' => sev.values.select(&:positive?).sum,
             'damage_type' => 'physical', 'threshold' => 0 }]
        end
      else
        []
      end
    end
  end

  # ---- Special Performance builder (turn_action_stub.md → Special) ----
  #
  # A channeled Special Ability (a Bard's Bardic Performance) rolls a
  # Performance check the same way Attack rolls. For a **check-based** channel
  # — its Reservoir fills from `check_successes` (Bardic Inspiration) — the
  # roll is a real skill Check, so the channel dice are bounded by the
  # Performance skill's **Dice Cap** (Main Action Minimum up to
  # min(Dice Cap, Combat Pool Remaining)). For a `channel_dice` / fire channel
  # the dice pour straight into the effect and the Dice Cap does not apply
  # (abilities_design.md). When several Performance skills are trained the
  # builder adds a step to pick which one (its Dice Cap + Competency govern the
  # roll). This reuses the Action Builder; the host posts the confirmed
  # Successes + dice to /encounter/use_special.

  def special_builder_blob(combatant, ability_name)
    acc     = Creatures.lookup(combatant[:creature_id]) rescue nil
    die     = DiceResolution.config.die_size
    base_tn = DiceResolution.config.base_target_number
    pool    = (encounter_state.combat_pool_remaining(combatant[:id]) rescue 0) || 0
    min     = Encounter::Config.main_action_minimum

    raw   = Abilities.catalog.ability(ability_name)
    ratio = (raw && raw.dig('reservoir', 'fill', 'ratio')) || 1
    # A check-based channel (fill source check_successes, e.g. Bardic
    # Inspiration) rolls a real skill Check, so it obeys the skill's Dice Cap.
    check_channel = Encounter::Special.check_channel?(raw)
    skills = Encounter::Special.check_skills(acc, raw)

    rolls = [{ id: 'performance', side: 'supporting', creature_name: tracker_name(combatant),
               roll_name: ability_name, die_size: die, tn: base_tn, starting_value: 0,
               base_tn: base_tn, bonus_penalty_list: [], dice_count: min, speed: 0, excluded: false }]

    # Channel dice shaped like the Attack weapon step: a leading
    # "<skill> (max N)" quick-pick that selects the maximum dice, then a button
    # per die count, plus a top-right header quick-pick for the max. Dice are
    # capped at the chosen skill's Dice Cap for a Check channel, otherwise up to
    # Combat Pool Remaining.
    dice_for = lambda do |skill_label, dice_cap|
      upper = (check_channel && dice_cap.to_i.positive?) ? [dice_cap.to_i, pool].min : pool
      upper = [upper, min].max
      set   = ->(n) { { set_dice: [{ id: 'performance', count: n }] } }
      opts  = [{ value: upper, key: 'dice', group: 'dice', label: "#{skill_label} (max #{upper})",
                 summary: "#{skill_label} — #{upper} dice", patch: set.call(upper) }]
      (min..upper).each { |n| opts << { value: n, key: 'dice', group: 'dice', label: n.to_s,
                                        summary: "#{n} dice", patch: set.call(n) } }
      { options: opts, header: { value: upper, label: "Max (#{upper})" } }
    end

    steps = []
    perform_skill = nil
    if check_channel && skills.length > 1
      # Several trained Performance skills — ask which (its Competency rides the
      # Roll; its Dice Cap bounds the choice-dependent Dice step).
      perf_opts = skills.map do |s|
        { value: s[:key], key: s[:key], label: s[:label], summary: s[:label],
          patch: { set_bpl: [{ id: 'performance', bonus_penalty_list: (s[:competency] ? [s[:competency]] : []) }] } }
      end
      steps << { key: 'performance', label: 'Performance', options: perf_opts }
      dice_map = {}
      header_map = {}
      skills.each do |s|
        d = dice_for.call(s[:label], s[:dice_cap])
        dice_map[s[:key]]   = d[:options]
        header_map[s[:key]] = [d[:header]]
      end
      steps << { key: 'dice', label: 'Channel dice', options_by: %w[performance], options_map: dice_map,
                 header_options_by: %w[performance], header_options_map: header_map }
    else
      skill = skills.first
      perform_skill = skill && skill[:key]
      rolls[0][:bonus_penalty_list] = (skill && skill[:competency]) ? [skill[:competency]] : []
      d = dice_for.call((skill ? skill[:label] : ability_name), skill ? skill[:dice_cap] : 0)
      steps << { key: 'dice', label: 'Channel dice', options: d[:options], header_options: [d[:header]] }
    end

    steps.concat(luck_steps(actor_id: combatant[:id],
                            targets: [{ roll_id: 'performance', label: tracker_name(combatant) }]))

    { title: "#{tracker_name(combatant)} — #{ability_name}", stub_id: "special-#{combatant[:id]}",
      reservoir_ratio: ratio, perform_skill: perform_skill, rolls: rolls, steps: steps }
  end

  # Server-side backstop for a check-based channel (Bardic Inspiration): the
  # rolled dice are a skill Check, so they may not exceed the best qualifying
  # Performance skill's Dice Cap. Returns an error string when the requested
  # dice exceed it, else nil. (The builder already bounds the offered options;
  # this guards a payload that bypasses the UI.)
  def channel_dice_cap_error(payload)
    raw = Abilities.catalog.ability(payload['ability'].to_s) or return nil
    return nil unless Encounter::Special.check_channel?(raw)
    dice = payload['dice'].to_i
    return nil unless dice.positive?
    combatant = encounter_state.combatant(payload['combatant_id'].to_i) or return nil
    acc = (Creatures.lookup(combatant[:creature_id]) rescue nil)
    cap = Encounter::Special.check_skills(acc, raw).map { |s| s[:dice_cap] }.max.to_i
    return nil unless cap.positive?
    dice > cap ? "Performance check cannot roll more than the Dice Cap (#{cap})" : nil
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
  # Tracker shows the ▶ marker on the acting Combatant immediately, and
  # begin that first Combatant's turn (refill its Combat Pool, grant its
  # Main Actions, clear expired Effects / Zones) — the same turn-start the
  # next Combatant gets on End Turn.
  first = encounter_state.acting_combatants.first
  if first
    encounter_state.set_acting_combatant(first[:id])
    encounter_state.begin_turn_for(first[:id])
    begin_turn_side_effects!(first[:id])
  end
  redirect back || '/encounter'
end

post '/encounter/end_combat' do
  require_dm!
  encounter_state.end_combat
  redirect back || '/encounter'
end

# Set the Encounter Phase (the DM's menu dropdown). A pure view selector —
# it changes which stubs the Encounter page shows and nothing else (it does
# not start or stop Combat mechanics). DM-only.
post '/encounter/set_phase' do
  require_dm!
  encounter_state.set_phase(params[:phase])
  redirect back || '/encounter'
end

# Post-Combat Cleanup (equipment_post_combat_creatures_stub.md). DM-only.
# For each non-PC Combatant the DM left on "Loot", move its Inventory (and
# any rolled Loot Table) into the combat Ground Pile via Equipment's
# *Collect Combat Loot*; for each left on "Delete", remove the Combatant
# and delete the Creature record. Rows toggled to Ignore / Keep are
# untouched. The pile that results is rendered by the loot-pile stub.
post '/encounter/post_combat_cleanup' do
  require_dm!
  rows     = post_combat_rows
  location = loot_pile_location

  loot_entries = rows.filter_map do |row|
    next unless params["loot_#{row[:combatant_id]}"].to_s != 'ignore'
    entry = { combatant_id: row[:combatant_id], creature_id: row[:creature_id], ally: false }
    entry[:loot_table] = row[:loot_table] if row[:loot_table]
    entry
  end

  # Collect first (reads the Creatures' Inventories), then delete — so a
  # looted-and-deleted Creature still hands over its gear. Loot is gathered
  # into the active Map's Ground Pile; without an active Map there is
  # nowhere to pile it, so we only delete.
  Equipment.instance.collect_combat_loot(loot_entries, location: location) if location && !loot_entries.empty?

  rows.each do |row|
    next if params["delete_#{row[:combatant_id]}"].to_s == 'keep'
    encounter_state.remove_combatant(row[:combatant_id])
    Creatures.delete(row[:creature_id]) rescue nil
  end

  redirect back || '/encounter'
end

# Loot (equipment_loot_pile_stub.md → the bottom "Loot" button). DM and
# players. Each pile Stack carries a `flag_<ref>` checkbox: when set to
# "discard" the Stack stays on the pile; otherwise it goes to the Party's
# Sell Pile. Runs Equipment's *Distribute Loot Pile* (party / skip), which
# transfers the Sell-Pile Stacks and cleans the pile up if it empties.
post '/encounter/loot_pile/loot' do
  pile = params[:pile_owner_id].to_s
  inst = Equipment.instance
  stacks = inst.get_inventory(pile)
  unless pile.empty? || stacks.nil? || stacks.empty?
    assignments = stacks.each_index.map do |i|
      keep = params["flag_#{i}"].to_s == 'discard'
      { stack_ref: i, target_owner_id: keep ? 'skip' : 'party' }
    end
    inst.distribute_loot_pile(pile, assignments)
  end
  redirect back || '/encounter'
end

# Claim (equipment_loot_pile_stub.md → per-item Claim, players only). Move
# the quantity in that Stack's box from the pile to the viewing player's
# own Creature. The DM has no viewing Creature, so this is a no-op for them.
post '/encounter/loot_pile/claim' do
  cid  = viewing_creature_id
  pile = params[:pile_owner_id].to_s
  idx  = params[:index].to_i
  inst = Equipment.instance
  stack = inst.get_inventory(pile)[idx]
  if cid && stack
    qty = inventory_quantity(params["qty_#{idx}"], stack.quantity)
    inst.transfer_stack(pile, "creature:#{cid}", idx, quantity: qty)
    inst.cleanup(pile)
  end
  redirect back || '/encounter'
end

# Give (equipment_loot_pile_stub.md → per-item Give). Move the quantity in
# that Stack's box from the pile to the combat Creature chosen in that
# Stack's dropdown. The target must be a combat participant.
post '/encounter/loot_pile/give' do
  pile   = params[:pile_owner_id].to_s
  idx    = params[:index].to_i
  target = params["give_#{idx}"].to_s
  inst   = Equipment.instance
  stack  = inst.get_inventory(pile)[idx]
  if stack && combat_creature?(target)
    qty = inventory_quantity(params["qty_#{idx}"], stack.quantity)
    inst.transfer_stack(pile, "creature:#{target}", idx, quantity: qty)
    inst.cleanup(pile)
  end
  redirect back || '/encounter'
end

# Delete Pile (equipment_loot_pile_stub.md → Delete Pile). DM-only.
# Discards the pile and any remaining (e.g. Skipped) Stacks wholesale.
post '/encounter/loot_pile/delete' do
  require_dm!
  Equipment.instance.delete_ground_pile(params[:pile_owner_id].to_s)
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
  # advance_turn begins the incoming Combatant's turn server-side (Combat
  # Pool refill, Main Actions, expired-Effect clear); the route adds the
  # turn-start side effects (expire the new Combatant's timed Zones) and
  # persists Conditions.
  new_id = encounter_state.advance_turn
  begin_turn_side_effects!(new_id) if new_id
  redirect back || '/encounter'
end

# Move (turn_action_stub.md → Move): spend the Move Cost in Combat Pool dice.
post '/encounter/move' do
  require_dm!
  encounter_state.apply_move(params[:combatant_id].to_i)
  redirect back || '/encounter'
end

# Resolve one Affliction Save (the Conditions Save Resolution Stub's
# Confirm in the Start of Turn pane). Applies the rolled DoIS through
# Conditions' *Resolve Affliction* and persists the store. JSON-in via
# form fields, JSON-out.
post '/encounter/resolve_affliction' do
  require_dm!
  result = encounter_state.resolve_affliction_save(
    params[:combatant_id].to_i, params[:affliction].to_s, params[:dois].to_i
  )
  return encounter_error(404, 'unknown combatant or affliction') unless result
  Conditions.store.persist!
  encounter_response(ok: true, affliction: params[:affliction].to_s, result: result)
end

# Discharge a Bardic Inspiration Reservoir (turn_action_stub.md → Special):
# spend `amount` reservoir dice and grant that many Luck Points to the target
# Combatant. A Reaction, so it fires off-turn from the tracker.
post '/encounter/discharge_inspiration' do
  require_dm!
  encounter_state.discharge_luck_reservoir(
    params[:combatant_id].to_i, params[:target_id].to_i, params[:amount].to_i,
    spell_name: (params[:spell_name].to_s.empty? ? 'Bardic Inspiration' : params[:spell_name])
  )
  redirect back || '/encounter'
end

# ---- Attack pipeline endpoints (turn_action_stub.md) -----------------
#
# attack_builder precomputes the whole Action Builder blob for an
# attack (Target / Weapon+dice / Defense steps, each option carrying a patch);
# the Builder resolves it client-side and posts the picked choices + Successes
# to resolve_attack, which recomputes the weapon damage from the chosen weapon,
# spends Combat Pool, and applies damage.

# The Action Builder for the Acting Combatant's attack, rendered as
# an HTML fragment the turn-action panel injects.
get '/encounter/attack_builder' do
  require_dm!
  attacker = encounter_state.combatant(params[:attacker_id].to_i)
  return encounter_error(404, 'unknown attacker') unless attacker
  erb :_action_builder, layout: false, locals: { builder: attack_builder_blob(attacker) }
end

post '/encounter/resolve_attack' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  enrich_attack_payload!(payload)
  result = encounter_state.resolve_attack_payload(payload)
  # A committed attack mutated the target's Conditions (HP damage, bleed) —
  # persist the Conditions store so the damage survives a restart. A preview
  # (commit:false) mutates nothing, so there's nothing to write. A commit also
  # spends one of the attacker's Main Actions (Attack is a Main Action).
  if result[:committed]
    Conditions.store.persist!
    encounter_state.spend_main_action(payload.dig('attacker', 'id').to_i)
  end
  encounter_response(result)
end

# ---- Cast pipeline endpoints (turn_action_stub.md → Cast) ------------
#
# cast_builder serves the spell-picker blob (known spells + per-Tier Mana
# Cost + targets); the Cast pane resolves the casting check + target Saves
# client-side and POSTs the choices + Successes to resolve_cast, which
# spends Combat Pool, debits Mana, applies Magic Toxicity, routes the spell's
# Effects, and registers any Concentration / Long Cast Entry.

get '/encounter/cast_builder' do
  require_dm!
  caster = encounter_state.combatant(params[:caster_id].to_i)
  return encounter_error(404, 'unknown caster') unless caster
  erb :_action_builder, layout: false, locals: { builder: cast_builder_blob(caster) }
end

# One opposing Save Roll per creature caught in an area Spell's footprint —
# the Spread Opposers. Rendered as roll-group <tbody>s the cast builder swaps
# into its dice table after the DM places the effect on the map.
get '/encounter/cast_area_rolls' do
  require_dm!
  return encounter_error(404, 'unknown caster') unless encounter_state.combatant(params[:caster_id].to_i)
  v    = (Abilities.lookup(params[:spell].to_s) rescue nil) || {}
  raw  = (Abilities.catalog.ability(params[:spell].to_s) rescue nil) || {}
  ra   = raw['area']
  area = ra.is_a?(Array) ? ra.find { |x| x.is_a?(Hash) } : ra
  save = Array(v['save']).first || (area.is_a?(Hash) ? Array(area['on_enter']).first : nil)
  attr = save && save['attribute'].to_s
  die     = DiceResolution.config.die_size
  base_tn = DiceResolution.config.base_target_number
  rolls = Array(params[:affected]).filter_map do |cid|
    c   = encounter_state.combatant(cid.to_i) or next
    acc = Creatures.lookup(c[:creature_id]) rescue nil
    ri  = attr ? roll_inputs_for(acc, "#{attr}_save", attribute_override: attr.to_sym) : {}
    bpl = ri[:competency_modifier] ? [ri[:competency_modifier]] : []
    { id: "save-#{c[:id]}", side: 'opposing', creature_name: tracker_name(c),
      roll_name: (attr ? "#{attr_label(attr)} save" : 'Save'),
      die_size: die, tn: base_tn, starting_value: 0, base_tn: base_tn,
      bonus_penalty_list: bpl, dice_count: ri[:dice_cap].to_i, speed: 0, excluded: false,
      tier: (acc&.tier rescue nil) }
  end
  erb :_roll_stub, layout: false, locals: { rolls: rolls, wrapper: false }
end

post '/encounter/resolve_cast' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  enrich_cast_payload!(payload)
  result = encounter_state.resolve_cast_payload(payload)
  # A committed cast mutated Conditions (HP / mana / toxicity / temp HP /
  # active effects) — persist so it survives a restart. A preview mutates
  # nothing. An area Spell also drops a Zone on the active Map.
  if result[:committed]
    zone = (place_spell_area_zone!(payload) rescue nil)
    result = result.merge(zone: zone) if zone
    grant_defend_reaction!(payload) rescue nil
    Conditions.store.persist!
    encounter_state.spend_main_action(payload.dig('caster', 'id').to_i) # Cast is a Main Action
  end
  encounter_response(result)
end

# The Performance-check builder for a channeled Special Ability (Bardic
# Performance), rendered as the Action Builder fragment the
# turn-action Special pane injects — the same flow as Attack.
get '/encounter/special_builder' do
  require_dm!
  combatant = encounter_state.combatant(params[:combatant_id].to_i)
  return encounter_error(404, 'unknown combatant') unless combatant
  ability = params[:ability].to_s
  erb :_action_builder, layout: false, locals: { builder: special_builder_blob(combatant, ability) }
end

# Use a Special action (turn_action_stub.md → Special): a non-Spell,
# non-Reaction Ability — a Bard's Bardic Performance and the like. Spends
# Mana / Combat Pool and begins-or-continues the Performance (or applies a
# self Active Effect). Mutates Conditions, so persist its store on success.
post '/encounter/use_special' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  cap_err = channel_dice_cap_error(payload)
  return encounter_error(400, cap_err) if cap_err
  result = encounter_state.use_special_payload(payload)
  Conditions.store.persist! if result[:ok]
  encounter_response(result)
end
