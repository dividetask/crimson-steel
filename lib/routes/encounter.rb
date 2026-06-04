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
  @acting_expiring_effects = acting_combatant ? expiring_effects_for(acting_combatant) : []

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
    # Everyone in the roster should have an Initiative — roll one for any
    # Combatant still missing it (e.g. PCs just auto-added above), leaving
    # already-rolled Combatants untouched.
    if encounter_state.combatants.any? { |c| c[:initiative_string].to_s.empty? }
      encounter_state.reroll_initiative(missing_only: true)
    end
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
  # save_tn folds in the Competency Modifier and the Potency Save Penalty
  # (a Competency Penalty of floor(potency / Potency Divisor)) the same way
  # Conditions' *Resolve Affliction* does. The `resolve` key tells the
  # stub's Confirm where to POST the rolled DoIS so it actually resolves
  # the Affliction (vs. the Status page's display-only demo).
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
      bpl = []
      bpl << ri[:competency_modifier] if ri[:competency_modifier]
      penalty = potency / divisor
      bpl << ['Competency', -penalty] if penalty.positive?
      tn = DiceResolution.compute_target_number(bpl)[:tn]

      {
        creature:   { id: combatant[:creature_id], name: cname, tier: tier },
        affliction: { name: name, rule: rule, potency: potency,
                      inflicter_tier: entry[:inflicting_tier].to_i },
        save_dice: ri[:dice_cap].to_i, save_tn: tn, die_size: die,
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
    # Everyone can attack Unarmed (Speed 0) — always offered, never carried.
    rows + [weapon_row(Equipment::Details.weapon_details(Equipment::Stack.normalize('item' => 'Unarmed'), cat), 'Unarmed')]
  end

  def weapon_row(wd, item_type)
    ranged = (wd[:definition] && wd[:definition]['category'] == 'Ranged')
    natural = !!(wd[:definition] && wd[:definition]['natural'])
    { item_type: item_type, display_name: wd[:display_name], ranged: ranged, natural: natural,
      speed: wd[:speed], damage_types: wd[:damage_types], threshold: wd[:threshold],
      bleed: wd[:bleed], damage_formula: wd[:damage_formula] }
  end

  # The defender's weapons usable to Parry: equipped melee weapons, excluding
  # natural attacks (Unarmed, claws, bite, …). You cannot Parry with a natural
  # attack without a special ability — and no such ability is wired yet, so
  # natural weapons are simply never offered as a Parry option.
  def equipped_melee_weapons(creature_id)
    equipped_weapons(creature_id).reject { |w| w[:ranged] || w[:natural] }
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

    # Display the character's own Bonus/Penalty list (natural signs). TNs are
    # NOT computed here — the builder hands raw Bonus lists to Check Resolution,
    # which applies cross-side propagation and computes every TN itself.
    fmt_mods = ->(list) { list.map { |type, amt| "#{amt >= 0 ? '+' : ''}#{amt} #{type}" }.join(' ') }

    weapons = equipped_weapons(attacker[:creature_id]).map do |w|
      attr = w[:ranged] ? :dex : :str
      ri   = roll_inputs_for(acc, 'martial', attribute_override: attr)
      w.merge(dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier])
    end

    atk_tier = (acc&.tier rescue nil)

    targets = encounter_state.combatants.reject { |c| c[:id] == attacker[:id] }.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      { id: c[:id], name: tracker_name(c), unaware: encounter_state.unaware?(c[:id]),
        is_pc: creature_is_pc?(c[:creature_id]),
        tier: (tacc&.tier rescue nil),
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
        tier: nil }
    ]

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
      aff_max = (2..cap).select { |n| speed + n <= atk_pool }.max
      max_opt = { value: "#{w[:item_type]}|#{aff_max || cap}", key: w[:item_type], group: grp,
                  label: "#{disp} (speed #{speed})", summary: "#{disp} — #{aff_max || cap} dice",
                  disabled: aff_max.nil?, patch: set_atk.call(aff_max || cap) }
      action_opts << max_opt
      (2..cap).each do |n|
        action_opts << { value: "#{w[:item_type]}|#{n}", key: w[:item_type], group: grp,
                         label: n.to_s, summary: "#{disp} — #{n} dice",
                         disabled: speed + n > atk_pool, patch: set_atk.call(n) }
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
        # Raw attacker Bonus lists for each branch (no TN math here): with no
        # defence the attacker keeps Flatfooted (+ Unaware if applicable); a
        # declared defence suppresses both.
        atk_none_bpl     = comp + Encounter::Attack.attacker_bonuses(no_defense: true,  unaware: t[:unaware])
        atk_declared_bpl = comp + Encounter::Attack.attacker_bonuses(no_defense: false, unaware: t[:unaware])
        # No defense first (attacker keeps Flatfooted), then one group per
        # Defensive Action: a name button carrying the defence Speed (Dodge /
        # Block = 0, Parry = weapon Speed), a button per die choice, and a
        # trailing line showing the defender's own Bonuses. Check Resolution
        # propagates the attacker's Bonuses onto the defender Roll (and vice
        # versa) and computes both TNs.
        opts = [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                  patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_none_bpl }],
                           set_excluded: [{ id: 'defender', excluded: true }] } }]
        # Header quick-picks: one button per Defensive Action (top-right, like
        # the weapon buttons), each selecting that defence at the MINIMUM dice
        # (the Reaction Action Minimum) — Defensive Actions all cost pool.
        headers = []
        # Eligible Defensive Action branches against this attack:
        #   Dodge — always (uses dex_save inputs; pool-costed, Speed 0).
        #   Block — only when the defender has a Shield equipped; any attack.
        #   Parry — melee attacks only, one branch per equipped melee weapon
        #           ("Parry with <weapon>"); costs that weapon's Speed + dice.
        branches = []
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

        branches.each do |b|
          di    = b[:inputs]
          dcmp  = di[:competency_modifier] ? [di[:competency_modifier]] : []
          cap   = di[:dice_cap].to_i
          dspd  = b[:speed]
          mk = lambda do |dice, label, disabled|
            { value: "#{b[:key]}|#{dice}", group: b[:group], label: label,
              summary: "#{b[:name]} — #{dice} dice", disabled: disabled,
              patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_declared_bpl },
                                 { id: 'defender', bonus_penalty_list: dcmp }],
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
    combatant = encounter_state.combatant(atk['id'].to_i) or return
    w = equipped_weapons(combatant[:creature_id]).find { |x| x[:item_type] == wt } or return
    acc = Creatures.lookup(combatant[:creature_id]) rescue nil
    payload['attack_kind'] ||= w[:ranged] ? 'ranged' : 'melee'
    atk['speed'] = w[:speed]
    payload['attacker'] = atk
    payload['weapon'] = { 'damage_types' => w[:damage_types], 'threshold' => w[:threshold],
                          'bleed' => w[:bleed], 'base_damage' => evaluate_weapon_damage(w[:damage_formula], acc) }
  end

  # ---- Check Resolution Builder blob for a Cast (turn_action_stub.md → Cast)
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
        { name: name, tier: g[:tier], mana_cost: cost, skill: skill,
          dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier],
          damage_type: Array(v['damage_type']).compact.first,
          attack_roll: !!v['attack_roll'], save: Array(v['save']).first,
          affordable: mana_left.nil? || cost <= mana_left }
      end
    end

    targets = encounter_state.combatants.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      { id: c[:id], name: tracker_name(c) + (c[:id] == caster[:id] ? ' (self)' : ''),
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
    spells.group_by { |sp| sp[:tier].to_i }.sort_by { |tier, _| tier }.each do |tier, group_spells|
      hdr = "tier-#{tier}-h"
      grp = "tier-#{tier}"
      spell_opts << { kind: 'info', group: hdr, value: "#{hdr}|label", label: %(<span class="cb-tier-head tier-#{tier}">Tier #{tier}</span>) }
      group_spells.each do |sp|
        bpl = []
        bpl << sp[:competency] if sp[:competency]
        bpl << ['Inherent', sp[:tier].to_i] if sp[:tier].to_i.positive?
        spell_opts << { value: sp[:name], key: sp[:name], group: grp,
                        label: sp[:name], summary: sp[:name],
                        disabled: !sp[:affordable],
                        patch: { set_bpl:   [{ id: 'caster', bonus_penalty_list: bpl }],
                                 set_speed: [{ id: 'caster', speed: 0 }],
                                 set_name:  [{ id: 'caster', roll_name: "Cast #{sp[:name]}" }] } }
      end
    end
    spell_step = { key: 'spell', label: 'Spell', options: spell_opts }

    # Step 2 — Dice for the casting check, asked only after a spell is picked
    # (choice-dependent on `spell`), bounded by Combat Pool and that spell's
    # casting-skill Dice Cap.
    dice_map = {}
    spells.each do |sp|
      cap  = sp[:dice_cap]
      opts = (2..cap).map do |n|
        { value: "#{sp[:name]}|#{n}", key: n, group: 'dice', label: n.to_s, summary: "#{n} dice",
          disabled: n > pool, patch: { set_dice: [{ id: 'caster', count: n }] } }
      end
      opts = [{ kind: 'info', group: 'dice', value: 'dice|none', label: 'no dice available' }] if opts.empty?
      dice_map[sp[:name]] = opts
    end
    dice_step = { key: 'dice', label: 'Dice', options_by: %w[spell], options_map: dice_map }

    # Step 3 — Target (a save / defense cannot be rolled without one).
    target_step = { key: 'target', label: 'Target',
                    options: targets.map { |t| { value: t[:id], key: t[:id], label: t[:name],
                                                 patch: { set_name: [{ id: 'target', creature_name: t[:name] }],
                                                          set_tier: [{ id: 'target', tier: t[:tier] }] } } } }

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
          opts.concat(cast_defense_branch("save:#{attr}", "#{attr_label(attr)} save",
                                          t[:saves][attr.to_sym] || t[:dodge], speed: 0, save: true, pool: t[:pool]))
        end
        defense_map["#{t[:id]}|#{sp[:name]}"] = opts
      end
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
  def cast_defense_branch(key, name, inputs, speed:, save:, pool:)
    di   = inputs || { dice_cap: 0 }
    dcmp = di[:competency_modifier] ? [di[:competency_modifier]] : []
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
    Array(payload['targets']).each { |t| t['effects'] = effects }

    # Area Spells (Obscuring Mist, Darkness, Web, Create Pit, Silence) carry an
    # `area` footprint placed on the map at commit time. For an Aspect-list area
    # (Grease: object vs. area), use the first footprint Aspect.
    raw_entry = (Abilities.catalog.ability(spell['name']) rescue nil) || {}
    raw_area  = raw_entry['area']
    area_hash = raw_area.is_a?(Array) ? raw_area.find { |x| x.is_a?(Hash) } : raw_area
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
    target = Array(payload['targets']).first or return nil
    combatant = encounter_state.combatant(target['id'].to_i) or return nil
    caster = payload['caster'] || {}
    source_id = "encounter:zone:#{spell['name']}:#{caster['id']}"
    zone_id = Atlas.state.place_zone(map_id: map_id, source_id: source_id,
                                     shape: area['shape'], size: area['size'],
                                     anchor: { 'type' => 'target', 'creature_id' => combatant[:creature_id] },
                                     texture: area['texture'])
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
  # Performance check the same way Attack rolls: the DM picks how many dice
  # to spend — Main Action Minimum up to Combat Pool Remaining (Dice Cap does
  # not apply to channeling) — then rolls them; each Success fills the
  # Reservoir. This reuses the Check Resolution Builder; the host posts the
  # confirmed Successes + dice to /encounter/use_special.

  # The Creature's trained Performance skill key (perform_<type>), for the
  # Performance check's Competency. Nil when none is trained.
  def performance_skill_key(accessor)
    return nil unless accessor.respond_to?(:record)
    trained = accessor.record[:classes].values.flat_map { |e| Array(e[:skills]) }
    trained.map(&:to_s).find { |k| k.start_with?('perform_') && !k.end_with?('_') }
  rescue StandardError
    nil
  end

  def special_builder_blob(combatant, ability_name)
    acc     = Creatures.lookup(combatant[:creature_id]) rescue nil
    die     = DiceResolution.config.die_size
    base_tn = DiceResolution.config.base_target_number
    pool    = (encounter_state.combat_pool_remaining(combatant[:id]) rescue 0) || 0
    min     = Encounter::Config.main_action_minimum

    skill = performance_skill_key(acc)
    ri    = skill ? (Proficiencies::Compute.roll_inputs(key: skill, creature: acc) rescue {}) : {}
    comp  = ri[:competency_modifier]
    bpl   = comp ? [comp] : []

    rolls = [{ id: 'performance', side: 'supporting', creature_name: tracker_name(combatant),
               roll_name: ability_name, die_size: die, tn: base_tn, starting_value: 0,
               base_tn: base_tn, bonus_penalty_list: bpl, dice_count: min, speed: 0, excluded: false }]

    # Channel dice: Main Action Minimum up to Combat Pool Remaining (no Dice
    # Cap on channeling). Each option just sets the Performance roll's dice.
    max  = [pool, min].max
    opts = (min..max).map do |n|
      { value: n, key: n, label: n.to_s, summary: "#{n} dice",
        patch: { set_dice: [{ id: 'performance', count: n }] } }
    end

    raw   = Abilities.catalog.ability(ability_name)
    ratio = (raw && raw.dig('reservoir', 'fill', 'ratio')) || 1

    steps = [{ key: 'dice', label: 'Channel dice', options: opts }]
    steps.concat(luck_steps(actor_id: combatant[:id],
                            targets: [{ roll_id: 'performance', label: tracker_name(combatant) }]))

    { title: "#{tracker_name(combatant)} — #{ability_name}", stub_id: "special-#{combatant[:id]}",
      reservoir_ratio: ratio, rolls: rolls, steps: steps }
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

# Start of Turn finalize (turn_action_stub.md → Start of Turn): refill the
# Acting Combatant's Combat Pool and clear the Active Effects that expire
# this Round. Afflictions are resolved separately via the per-Affliction
# Conditions Save Resolution Stub (POST /encounter/resolve_affliction).
post '/encounter/start_of_turn' do
  require_dm!
  encounter_state.resolve_start_of_turn(params[:combatant_id].to_i)
  # Auto-expire the caster's timed Zones (spell areas) at their start of turn.
  expire_caster_zones!(params[:combatant_id].to_i)
  Conditions.store.persist!
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
  # A committed attack mutated the target's Conditions (HP damage, bleed) —
  # persist the Conditions store so the damage survives a restart. A preview
  # (commit:false) mutates nothing, so there's nothing to write.
  Conditions.store.persist! if result[:committed]
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
  erb :_check_builder, layout: false, locals: { builder: cast_builder_blob(caster) }
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
    Conditions.store.persist!
  end
  encounter_response(result)
end

# The Performance-check builder for a channeled Special Ability (Bardic
# Performance), rendered as the Check Resolution Builder fragment the
# turn-action Special pane injects — the same flow as Attack.
get '/encounter/special_builder' do
  require_dm!
  combatant = encounter_state.combatant(params[:combatant_id].to_i)
  return encounter_error(404, 'unknown combatant') unless combatant
  ability = params[:ability].to_s
  erb :_check_builder, layout: false, locals: { builder: special_builder_blob(combatant, ability) }
end

# Use a Special action (turn_action_stub.md → Special): a non-Spell,
# non-Reaction Ability — a Bard's Bardic Performance and the like. Spends
# Mana / Combat Pool and begins-or-continues the Performance (or applies a
# self Active Effect). Mutates Conditions, so persist its store on success.
post '/encounter/use_special' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  result = encounter_state.use_special_payload(payload)
  Conditions.store.persist! if result[:ok]
  encounter_response(result)
end
