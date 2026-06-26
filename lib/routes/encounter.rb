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

  if @viewer == :dm
    @interest_entries = @store.list_entries(entry_type: 'creature', active_only: true)
  else
    @interest_entries = @store.list_entries(entry_type: 'creature', active_only: true, visible_to: @viewing_id)
  end
  @interest_entries = @interest_entries.sort_by { |e| [e['chapter'] || 0, e['notes_position'] || 9999] }

  @chapters       = @store.list_chapters
  @current_chapter = @store.current_chapter
  @player_creatures = player_creatures

  acting_id = @encounter_state.acting_combatant_id
  @round_label = @encounter_state.round_label
  rows = @encounter_state.combatants.map { |c| build_tracker_row(c, acting_id) }
  @tracker_rows = rows.sort_by do |r|
    [r[:initiative].to_s.empty? ? 1 : 0, invert_init(r[:initiative].to_s), r[:combatant_id]]
  end

  @acting_row  = @tracker_rows.find { |r| r[:acting] }
  @acting_dead = @acting_row ? @encounter_state.creature_dead?(@acting_row[:combatant_id]) : false
  acting_combatant = @acting_row ? @encounter_state.combatant(@acting_row[:combatant_id]) : nil
  @acting_saves = acting_combatant ? start_of_turn_saves(acting_combatant) : []
  @acting_main_actions = @acting_row ? @encounter_state.main_actions_remaining(@acting_row[:combatant_id]) : nil

  @acting_sheet = nil
  if @combat_active && @acting_row && creature_is_pc?(@acting_row[:creature_id])
    sheet_accessor = Creatures.lookup(@acting_row[:creature_id]) rescue nil
    @acting_sheet = sheet_accessor ? CreatureSheet.build(sheet_accessor) : nil
  end

  @acting_special = (@viewer == :dm && @acting_row) ? (@encounter_state.special_options(@acting_row[:combatant_id]) rescue []) : []

  @acting_has_spells =
    if @acting_row
      aacc = Creatures.lookup(@acting_row[:creature_id]) rescue nil
      knows = aacc ? (CreatureSheet.spells(aacc) rescue []).any? { |g| Array(g[:names]).any? } : false
      knows || (granted_spell_items(@acting_row[:creature_id]).any? rescue false)
    else
      false
    end

  @acting_has_items =
    @acting_row ? ((consumable_spell_items(@acting_row[:creature_id]).any? ||
                    granted_spell_items(@acting_row[:creature_id]).any?) rescue false) : false

  @acting_has_active_spells =
    @acting_row ? (active_spell_strikes(@encounter_state.combatant(@acting_row[:combatant_id])).any? rescue false) : false

  @inspirations = if @viewer == :dm
                    @encounter_state.combatants.flat_map do |c|
                      Array(c[:concentration]).select { |e| e[:mode] == 'reservoir' && e[:reservoir].to_i.positive? }
                                              .map { |e| { combatant_id: c[:id], name: tracker_name(c),
                                                           spell_name: e[:spell_name], reservoir: e[:reservoir] } }
                    end
                  else
                    []
                  end

  view_map_id = (@viewer == :dm && !params[:map].to_s.empty?) ? params[:map].to_i : nil
  @atlas_snapshot  = atlas_map_snapshot(@viewer, map_id: view_map_id)
  @atlas_maps      = Atlas.state.list_maps(include_archived: true)
  @atlas_active_id = Atlas.state.active_map_id
  @atlas_placeable = atlas_placeable_combatants
  @atlas_terrain   = atlas_terrain_palette

  # The DM may privately override the Phase for their own view (see
  # effective_encounter_phase); players always render the party Phase.
  @phase             = effective_encounter_phase
  @party_phase       = @encounter_state.phase
  @dm_phase_override = dm_phase_override

  @post_combat_rows = (@viewer == :dm && @phase == :looting) ? post_combat_rows : []

  if @phase == :looting
    @loot_pile              = loot_pile_view(combat_pile_owner)
    @loot_give_options      = combat_creature_options
    @loot_claim_creature_id = viewing_creature_id
  else
    @loot_pile = nil
  end

  if @phase != :combat
    @conditions_catalog = Conditions::Catalog.load
    @downtime_cards     = downtime_cards(@viewer, @viewing_id)
    @relief_groups      = @viewer == :dm ? affliction_relief_groups : []
  else
    @downtime_cards = []
    @relief_groups  = []
  end

  erb :encounter
end

helpers do
  def encounter_state
    Encounter.state
  end

  def target_status_suffix(combatant_id, creature_id)
    parts = []
    parts << 'dying' if (encounter_state.creature_dying?(combatant_id) rescue false)
    names = (Conditions.store.instance_for(creature_id).active_effect_names rescue [])
    parts << 'paralyzed' if names.include?('paralyzed')
    parts.empty? ? '' : " (#{parts.join(', ')})"
  end

  def target_options(combatants, roll_id:, self_id: nil)
    descs = combatants.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      base = tracker_name(c)
      self_tag = (c[:id] == self_id) ? ' (self)' : ''
      { id: c[:id],
        name: base + self_tag,
        display_name: base + target_status_suffix(c[:id], c[:creature_id]) + self_tag,
        category: (creature_is_pc?(c[:creature_id]) ? 'pc' : (((tacc&.group rescue nil) == 'npc') ? 'npc' : 'enemy')),
        dying: (encounter_state.creature_dying?(c[:id]) rescue false) }
    end
    order_targets_by_category(descs).map do |t|
      { value: t[:id], key: t[:id], label: t[:display_name], dying: t[:dying], group: t[:category],
        patch: { set_name: [{ id: roll_id, creature_name: t[:name] }] } }
    end
  end

  def order_targets_by_category(targets)
    cat = { 'pc' => 0, 'npc' => 1, 'enemy' => 2 }
    targets.each_with_index.sort_by { |t, i| [cat.fetch(t[:category], 3), i] }.map(&:first)
  end

  def order_targets_by_distance(attacker, enemy_targets)
    map_id = (Atlas.state.active_map_id rescue nil) or return enemy_targets
    pos = lambda do |creature_id|
      tok = (Atlas.state.list_tokens(map_id: map_id, creature_id: creature_id).first rescue nil)
      tok && [tok[:x].to_f, tok[:y].to_f]
    end
    apos = pos.call(attacker[:creature_id]) or return enemy_targets
    enemy_targets.each_with_index.sort_by do |t, i|
      tpos = pos.call(t[:creature_id])
      [tpos ? Math.hypot(tpos[0] - apos[0], tpos[1] - apos[1]) : Float::INFINITY, i]
    end.map(&:first)
  end

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
    inst.active_effect_names.each do |name|
      badges << { kind: 'effect', label: name.to_s.split(/[_\s]+/).map(&:capitalize).join(' ') }
    end
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

  def invert_init(str)
    str.bytes.map { |b| (255 - b).chr }.join
  end

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

  def downtime_cards(viewer, viewing_id)
    rows = encounter_state.combatants.filter_map do |c|
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next nil unless acc
      is_pc  = Array(acc.tags).include?('player_character')
      is_npc = !is_pc && ((acc.group rescue nil).to_s == 'npc')
      # Enemies get no card; players see only the Player Characters.
      next nil unless is_pc || is_npc
      next nil if viewer != :dm && !is_pc
      { is_pc: is_pc, card: downtime_card_data(c[:creature_id], acc) }
    end
    ordered =
      if viewer == :dm
        # PCs first (in roster order), then the NPC allies.
        rows.partition { |r| r[:is_pc] }.flatten
      else
        # The viewing player's own card first, the rest of the party after.
        own, others = rows.partition { |r| r[:card][:id] == viewing_id }
        own + others
      end
    ordered.map { |r| r[:card] }
  end

  # The `_conditions_pc_card` locals for one Creature, read from the live
  # Creatures / Conditions / Equipment domains.
  def downtime_card_data(creature_id, acc)
    inst  = Conditions.store.instance_for(creature_id)
    race  = (acc.race || '').to_s.split('_').map(&:capitalize).join(' ')
    klass = acc.class_summary
               .map { |k, lvl| "#{k.to_s.split('_').map(&:capitalize).join(' ')} #{lvl}" }
               .join(' / ')
    {
      id:          creature_id,
      name:        acc.name,
      race:        race,
      klass:       klass,
      tier:        acc.tier,
      max_hp:      (acc.max_hit_points rescue 0),
      mana_max:    (acc.max_mana rescue 0),
      charisma:    (acc.attribute_value(:cha) rescue 0),
      consumables: downtime_consumables(creature_id),
      state:       inst.state
    }
  end

  def downtime_consumables(creature_id)
    cat  = Equipment.catalog
    inst = Equipment.instance
    inst.get_inventory("creature:#{creature_id}").filter_map do |stack|
      next nil unless cat.category_of(stack.item_type) == 'Consumable'
      next nil unless healing_consumable?(stack, cat)
      { name:     (CreatureSheet.item_display_name(stack, cat) rescue Equipment::DisplayName.call(stack, cat)),
        tier:     stack.tier,
        quantity: stack.quantity }
    end
  rescue StandardError
    []
  end

  HEAL_DAMAGE_KEYS = %w[minor_damage moderate_damage major_damage].freeze
  def healing_consumable?(stack, cat)
    defn  = cat.definition_of(stack.item_type) || {}
    spell = (stack.respond_to?(:stored_spell) ? stack.stored_spell : nil) || defn['spell']
    return false unless spell
    resolved = Abilities.resolve_spell(spell, tier: stack.tier) rescue nil
    return false unless resolved
    effects = resolved[:effects] || resolved['effects'] || []
    effects.any? do |e|
      e = e.transform_keys(&:to_s)
      e.key?('temp_hp') || HEAL_DAMAGE_KEYS.any? { |k| (v = e[k]) && v.to_i < 0 }
    end
  rescue StandardError
    false
  end

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

  def tracker_name(combatant)
    return combatant[:name] unless combatant[:name].to_s.empty?
    creature = Creatures.lookup(combatant[:creature_id]) rescue nil
    creature ? creature.name : "Creature ##{combatant[:creature_id]}"
  end

  def equipment_owner(creature_id) = "creature:#{creature_id}"

  def equipped_weapons(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    rows = inv.select { |s| s.equipped && (it = cat.item_type(s.item_type)) && it[:category] == 'Weapon' }
              .map { |s| weapon_row(Equipment::Details.weapon_details(s, cat), s.item_type) }
    # Race / Class Natural Attacks (e.g. a beast's Bite) — granted weapons
    acc = Creatures.lookup(creature_id) rescue nil
    natural = (acc ? CreatureSheet.granted_natural_weapons(acc) : []).map do |name|
      weapon_row(Equipment::Details.weapon_details(Equipment::Stack.from_catalog(name, cat), cat), name)
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

  def equipped_melee_weapons(creature_id)
    equipped_weapons(creature_id).reject { |w| w[:ranged] || w[:natural] }
  end

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

  def evaluate_weapon_damage(formula, accessor)
    return 0 if formula.nil? || formula.to_s.strip.empty?
    binds = %i[str dex con int wis cha].each_with_object({}) { |a, h| h[a] = (accessor.attribute_value(a) rescue 0) }
    [(Abilities::Formula.evaluate(formula, binds).to_i rescue 0), 0].max
  end

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

  equip_spawned_creature(new_creature_id)
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
  # The actual (party) Phase moved, so the DM moves with it: drop any private
  # override so the DM follows the new party Phase.
  session.delete(:dm_phase_override)
  redirect back || '/encounter'
end

# DM-only, session-local Phase override. Changes only the DM's own Encounter
# view — players keep seeing the party Phase. A blank or "party" value (or any
# unknown Phase) clears the override so the DM follows the party again.
post '/encounter/dm_phase' do
  require_dm!
  v = params[:phase].to_s
  if v.empty? || v == 'party' || encounter_phases.none? { |val, _| val.to_s == v }
    session.delete(:dm_phase_override)
  else
    session[:dm_phase_override] = v
  end
  redirect back || '/encounter'
end

post '/encounter/post_combat_cleanup' do
  require_dm!
  rows     = post_combat_rows
  location = loot_pile_location

  # "→ NPC" rows: promote the generated monster to a named NPC ally (rename +
  # group npc), then keep it — it is neither looted nor deleted below.
  promoted = rows.select { |row| !params["npc_#{row[:combatant_id]}"].to_s.empty? }
  promoted.each do |row|
    Creatures.promote_to_npc(row[:creature_id], params["npc_name_#{row[:combatant_id]}"]) rescue nil
    # A promoted NPC is active by default — give it an active Creature
    # Reference so it shows up (active) in Notes' Characters of Interest.
    Chronicle.store.activate_creature_reference(row[:creature_id]) rescue nil
  end
  promoted_ids = promoted.map { |r| r[:combatant_id] }

  loot_entries = rows.filter_map do |row|
    next if promoted_ids.include?(row[:combatant_id])
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
    next if promoted_ids.include?(row[:combatant_id])
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

# Give (equipment_loot_pile_stub.md → per-item Give). Hand the quantity in
# that Stack's box — and only that one Stack — to the combat Creature chosen
# in its dropdown. The target must be a combat participant. The DM may give
# more than the pile holds (the Stack floors at 0); Give never deletes Stacks
# or cleans up the pile, so an emptied Stack stays on the pile. Only Loot
# distributes everything and removes Stacks.
post '/encounter/loot_pile/give' do
  pile   = params[:pile_owner_id].to_s
  idx    = params[:index].to_i
  target = params["give_#{idx}"].to_s
  inst   = Equipment.instance
  stack  = inst.get_inventory(pile)[idx]
  if stack && combat_creature?(target)
    qty = loot_give_quantity(params["qty_#{idx}"], stack.quantity)
    inst.transfer_stack(pile, "creature:#{target}", idx, quantity: qty, allow_overdraw: true)
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

# End Turn (conditions_bulk_affliction_stub.md): the Urgent Actions panel's
# bulk commit. Rolls every due Affliction save still on the roster that the
# DM did NOT resolve by hand (a hand-Confirmed save already resolved and
# rescheduled itself, so it is no longer due), applies each through
# *Resolve Affliction*, then advances Combat by one turn (when Combat is
# active — the peaceful Phases keep an active Combat running until every
# Affliction is treated). The player-driven cures (Use-Item, cast) apply the
# instant they are taken, so nothing extra is replayed here.
post '/encounter/end_turn' do
  require_dm!
  encounter_state.combatants.each do |c|
    start_of_turn_saves(c).each do |save|
      dois = roll_affliction_save_dois(save)
      encounter_state.resolve_affliction_save(c[:id], save[:affliction][:name], dois)
    end
  end
  Conditions.store.persist!
  new_id = encounter_state.combat_active? ? encounter_state.advance_turn : nil
  begin_turn_side_effects!(new_id) if new_id
  redirect back || '/encounter'
end

# Move (turn_action_stub.md → Move): spend the Move Cost in Combat Pool dice.
post '/encounter/move' do
  require_dm!
  # JSON from the turn-action Move pane (combatant_id + the editable Combat-Pool
  # cost); falls back to a plain form post for non-JS callers.
  body = (JSON.parse(request.body.read) rescue nil)
  cid  = ((body && body['combatant_id']) || params[:combatant_id]).to_i
  cost = body && body.key?('cost') ? body['cost'] : nil
  result = encounter_state.apply_move(cid, cost: cost)
  if body
    encounter_response(result)
  else
    redirect back || '/encounter'
  end
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

# Run the out-of-combat Affliction relief simulation for one Creature: roll the
# alternating Constitution save + Heal channels round by round until the
# Affliction clears (AfflictionRelief). A preview (commit=false) rolls on a
# throwaway copy and returns the log + totals plus the RNG seed; Confirm
# (commit=true) re-runs the SAME seed on the live state, then debits each
# aider's one-time Heal mana, advances time by the rounds elapsed, and persists.
post '/encounter/resolve_affliction_run' do
  require_dm!
  combatant_id = params[:combatant_id].to_i
  name   = params[:affliction].to_s
  commit = params[:commit].to_s == 'true'
  seed   = (params[:seed].to_s.empty? ? rand(1_000_000) : params[:seed].to_i)
  aiders_in = (JSON.parse(params[:aiders].to_s) rescue []) || []

  c = encounter_state.combatants.find { |x| x[:id] == combatant_id }
  return encounter_error(404, 'unknown combatant') unless c
  acc  = (Creatures.lookup(c[:creature_id]) rescue nil)
  live = Conditions.store.instance_for(c[:creature_id])
  rule = (live.catalog.affliction(name) rescue nil)
  return encounter_error(404, 'unknown affliction') unless rule && live.state.afflictions.key?(name)

  blob = relief_affliction_blob(acc, live, name, rule, live.state.afflictions[name])
  save = blob[:save]

  aiders = Array(aiders_in).filter_map do |a|
    cid  = (a['creature_id'] || a[:creature_id]).to_i
    tier = (a['tier'] || a[:tier]).to_i
    aacc = (Creatures.lookup(cid) rescue nil) or next nil
    ac   = encounter_state.combatants.find { |x| x[:creature_id].to_i == cid }
    ri   = roll_inputs_for(aacc, 'healing')
    reusing = ac ? aider_channeling_heal?(ac) : false
    { id: cid, name: ((aacc.name rescue nil) || (ac ? tracker_name(ac) : "##{cid}")),
      spell_tier: tier, heal_dice: ri[:dice_cap].to_i, die_size: save[:die_size],
      heal_modifiers: [ri[:competency_modifier]].compact,
      mana_cost: reusing ? 0 : mana_cost_for_tier(tier) }
  end

  inst = if commit
           live
         else
           Conditions::Instance.new(state: Conditions::State.load(live.state.to_h), catalog: live.catalog)
         end

  # Stop the bleed-out at death: the threshold is the afflicted Creature's total
  # HP damage at which Conditions calls it Dead (death_multiplier × Max HP).
  max_hp = (acc&.max_hit_points rescue 0).to_i
  death_threshold = max_hp.positive? ? (live.catalog.death_multiplier * max_hp).floor : nil

  result = Encounter::AfflictionRelief.run(
    instance: inst, affliction_name: name, creature_tier: save[:creature_tier],
    save: save, aiders: aiders, creature_name: tracker_name(c),
    death_threshold: death_threshold, rng: Random.new(seed)
  )

  if commit
    result[:aider_mana].each do |cid, amt|
      next unless amt.to_i.positive?
      mm = (Creatures.lookup(cid).max_mana rescue 0) || 0
      Conditions.store.instance_for(cid).apply_mana_cost(amount: amt.to_i, mana_max: mm)
    end
    Chronicle.store.advance_time(rounds: result[:rounds]) if result[:rounds].to_i.positive?
    Conditions.store.persist!
  end

  # The Creature's HP after the relief: Max HP minus all accumulated damage
  # (can go negative when the bleed killed it).
  total_dmg = inst.state.hp_damage.values.sum
  result = result.merge(max_hp: max_hp, final_hp: (max_hp.positive? ? max_hp - total_dmg : nil))

  encounter_response(ok: true, seed: seed, commit: commit, affliction: name,
                     combatant_id: combatant_id, result: result)
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
  builder_html = erb :_action_builder, layout: false, locals: { builder: attack_builder_blob(attacker) }
  # A Roll Table Reaction (Kesser's Gambit) a bystander may answer this attack
  # with rides alongside the builder, in the same place as the Standard Shield's
  # ally block. Rendered only when an eligible channeler exists.
  channelers = roll_table_reaction_channelers(attacker[:id])
  return builder_html if channelers.empty?
  builder_html + erb(:_encounter_roll_table_stub, layout: false,
                     locals: { channelers: channelers, attacker_id: attacker[:id] })
end

# The Action Builder for the Acting Combatant's Active Spells action — the
# strikes from its active persistent Spells (Spiritual Weapon). It is the same
# Attack flow (target / weapon+dice / full Defense incl. Parry / ally Defense /
# Luck), so it resolves through the very same /encounter/resolve_attack the
# Attack pane uses; only the weapon list (the conjured strikes) differs.
get '/encounter/active_spells_builder' do
  require_dm!
  attacker = encounter_state.combatant(params[:attacker_id].to_i)
  return encounter_error(404, 'unknown attacker') unless attacker
  builder_html = erb :_action_builder, layout: false,
                     locals: { builder: attack_builder_blob(attacker, active_spells: true) }
  channelers = roll_table_reaction_channelers(attacker[:id])
  return builder_html if channelers.empty?
  builder_html + erb(:_encounter_roll_table_stub, layout: false,
                     locals: { channelers: channelers, attacker_id: attacker[:id] })
end

post '/encounter/resolve_attack' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  enrich_attack_payload!(payload)
  result = encounter_state.resolve_attack_payload(payload)
  # On a preview, surface the post-roll defender Reactions (Danger Sense /
  # Primal Tenacity) the target may use — but only when it declared no defense
  # and the hit actually landed.
  result = attach_defender_reactions(result, payload) unless result[:committed]
  # A committed attack mutated the target's Conditions (HP damage, bleed) —
  # persist the Conditions store so the damage survives a restart. A preview
  # (commit:false) mutates nothing, so there's nothing to write. A commit also
  # spends one of the attacker's Main Actions (Attack is a Main Action).
  if result[:committed]
    Conditions.store.persist!
    encounter_state.spend_main_action(payload.dig('attacker', 'id').to_i)
    # A Ring of Parry's free Parry spends its once-per-day charge on commit, so
    # the defender cannot use it again until dawn.
    if payload.dig('defense', 'choice').to_s == 'ringparry'
      def_comb = encounter_state.combatant(payload.dig('defense', 'id').to_i)
      consume_ring_parry!(def_comb[:creature_id]) if def_comb
    end
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

# item_builder serves the Item pane's builder blob (turn_action_stub.md → Item):
# the actor's carried Potions / Scrolls as castable options. The pane resolves
# the casting check + target Saves client-side and POSTs to resolve_cast with an
# `item` field, which costs no Mana, imposes Item-Form Toxicity for Potions, and
# decrements the Consumable on commit.
get '/encounter/item_builder' do
  require_dm!
  actor = encounter_state.combatant(params[:actor_id].to_i)
  return encounter_error(404, 'unknown combatant') unless actor
  erb :_action_builder, layout: false, locals: { builder: item_builder_blob(actor) }
end

# One opposing Save Roll per creature caught in an area Spell's footprint —
# the Spread Opposers. Rendered as roll-group <tbody>s the cast builder swaps
# into its dice table after the DM places the effect on the map.
get '/encounter/cast_area_rolls' do
  require_dm!
  return encounter_error(404, 'unknown caster') unless encounter_state.combatant(params[:caster_id].to_i)
  # Resolve the (possibly variant / per-Tier) Spell name to its Variant — a
  # bare `Abilities.lookup` only knows base catalog keys, so a variant name
  # (e.g. "Create Illusionary Sound") would miss the `save` and leave every
  # caught creature at zero Save dice.
  v    = resolve_named_spell(params[:spell].to_s)
  base, = spell_base_axis(params[:spell].to_s)
  raw  = (Abilities.catalog.ability(base) rescue nil) || {}
  ra   = raw['area']
  area = ra.is_a?(Array) ? ra.find { |x| x.is_a?(Hash) } : ra
  save = Array(v['save']).first || (area.is_a?(Hash) ? Array(area['on_enter']).first : nil)
  attr = save && save['attribute'].to_s
  die     = DiceResolution.config.die_size
  base_tn = DiceResolution.config.base_target_number
  inh_table = (Creatures::Config.tier_minimum_inherent_bonus rescue [])
  rolls = Array(params[:affected]).filter_map do |cid|
    c   = encounter_state.combatant(cid.to_i) or next
    acc = Creatures.lookup(c[:creature_id]) rescue nil
    ri  = attr ? roll_inputs_for(acc, "#{attr}_save", attribute_override: attr.to_sym) : {}
    bpl = ri[:competency_modifier] ? [ri[:competency_modifier]] : []
    # Each caught creature's Inherent Tier Bonus rides its Save Roll — the
    # Inherent crossing is what Check Resolution derives Ascendancy from.
    bpl += Encounter::Attack.defender_tier_bonuses(defender_tier: ((acc&.tier rescue nil) || 0), inherent_table: inh_table)
    { id: "save-#{c[:id]}", side: 'opposing', creature_name: tracker_name(c),
      roll_name: (attr ? "#{attr_label(attr)} save" : 'Save'),
      die_size: die, tn: base_tn, starting_value: 0, base_tn: base_tn,
      bonus_penalty_list: bpl, dice_count: ri[:dice_cap].to_i, speed: 0, excluded: false }
  end
  erb :_roll_stub, layout: false, locals: { rolls: rolls, wrapper: false }
end

post '/encounter/resolve_cast' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  enrich_cast_payload!(payload)
  result = encounter_state.resolve_cast_payload(payload)
  # An Item cast (Potion / Scroll) costs no Mana — flag it so the result block
  # omits the (always-zero) Mana row on both preview and commit.
  result = result.merge(consumable: true) if payload['item']
  # A committed cast mutated Conditions (HP / mana / toxicity / temp HP /
  # active effects) — persist so it survives a restart. A preview mutates
  # nothing. An area Spell also drops a Zone on the active Map.
  if result[:committed]
    zone = (place_spell_area_zone!(payload) rescue nil)
    result = result.merge(zone: zone) if zone
    grant_defend_reaction!(payload) rescue nil
    # A committed Item cast (Potion / Scroll from the Item pane) decrements the
    # Consumable by one — the Cast pipeline applied its Effects / Toxicity; only
    # the Inventory side remains.
    consumed = (consume_cast_item!(payload) rescue nil)
    result = result.merge(item_consumed: consumed) if consumed
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

# The channel-check Action Builder for a Roll Table Reaction (Kesser's
# Gambit), rendered as an HTML fragment the attack panel injects when the
# DM picks a channeler. The DM rolls the Channel check; the Successes +
# chosen dice POST to /encounter/roll_table_reaction.
get '/encounter/roll_table_builder' do
  require_dm!
  combatant = encounter_state.combatant(params[:combatant_id].to_i)
  return encounter_error(404, 'unknown combatant') unless combatant
  ability = params[:ability].to_s
  erb :_action_builder, layout: false, locals: { builder: roll_table_builder_blob(combatant, ability) }
end

# Fire a Roll Table Reaction (encounter_roll_table_stub.md): spend the
# channeler's Combat Pool dice + Mana, roll the table, and report the entry
# with the Channel Successes the channel check produced. Mutates Conditions
# (Mana), so persist its store on success.
post '/encounter/roll_table_reaction' do
  require_dm!
  payload = JSON.parse(request.body.read) rescue nil
  return encounter_error(400, 'invalid JSON payload') unless payload.is_a?(Hash)
  result = encounter_state.use_roll_table_payload(payload)
  if result[:ok]
    # Surface the channel check's modifiers (Competency / Inherent) so the DM can
    # set save TNs against the rolled effect by hand.
    combatant = encounter_state.combatant(payload['combatant_id'].to_i)
    result = result.merge(roll_table_check_info(combatant)) if combatant
    # Only a committed reaction (the Confirm) mutates Mana — a preview / reroll
    # spends nothing.
    Conditions.store.persist! if result[:committed]
  end
  encounter_response(result)
end
