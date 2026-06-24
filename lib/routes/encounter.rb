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

  @phase = @encounter_state.phase

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

  def loot_pile_location
    id = Atlas.state.active_map_id
    id.nil? ? 'loot' : "map_#{id}"
  end

  def combat_pile_owner
    "ground:#{loot_pile_location}"
  end

  def post_combat_rows
    cat  = Equipment.catalog
    inst = Equipment.instance
    rows = encounter_state.combatants.filter_map do |c|
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next unless acc
      next if Array(acc.tags).include?('player_character')
      inv = inst.get_inventory("creature:#{c[:creature_id]}")
      { combatant_id: c[:id],
        creature_id:  c[:creature_id],
        name:         tracker_name(c),
        npc:          ((acc.group rescue nil).to_s == 'npc'),
        loot_table:   acc.record[:loot_table],
        loot:         inv.map { |s| { name: CreatureSheet.item_display_name(s, cat), quantity: s.quantity } } }
    end
    rows.sort_by.with_index { |r, i| [r[:npc] ? 0 : 1, i] }
  end

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

  def loot_pile_view(pile_owner_id)
    return nil if pile_owner_id.nil?
    inst  = Equipment.instance
    stacks = inst.get_inventory(pile_owner_id)
    return nil if stacks.nil? || stacks.empty?
    cat = Equipment.catalog
    rows = stacks.each_with_index.map do |stack, i|
      { ref:      i,
        name:     CreatureSheet.item_display_name(stack, cat),
        icon:     item_icon_web_path(stack.item_type),
        quantity: stack.quantity }
    end
    { owner_id: pile_owner_id, rows: rows }
  end

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

  def combat_creature?(creature_id)
    combat_creature_options.any? { |c| c[:id].to_s == creature_id.to_s }
  end

  def encounter_row_snapshot(creature_id)
    {
      creature_id: creature_id.to_s,
      copy_count:  encounter_state.copy_count(creature_id),
      in_combat:   encounter_state.includes_creature?(creature_id),
      pc_excluded: encounter_state.pc_excluded?(creature_id)
    }
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

  def urgent_action_groups
    encounter_state.combatants.filter_map do |c|
      saves = start_of_turn_saves(c)
      next nil if saves.empty?
      { combatant_id: c[:id], creature_id: c[:creature_id],
        name: tracker_name(c), is_pc: creature_is_pc?(c[:creature_id]),
        saves: saves }
    end
  end

  def affliction_relief_groups
    aiders = heal_aider_candidates
    encounter_state.combatants.filter_map do |c|
      acc  = (Creatures.lookup(c[:creature_id]) rescue nil)
      inst = Conditions.store.instance_for(c[:creature_id])
      afflictions = inst.state.afflictions.filter_map do |name, entry|
        rule = (inst.catalog.affliction(name) rescue nil)
        next nil unless rule && rule['effect']
        next nil unless (rule['save_frequency'] || 'round').to_s == 'round'
        relief_affliction_blob(acc, inst, name, rule, entry)
      end
      next nil if afflictions.empty?
      { combatant_id: c[:id], creature_id: c[:creature_id],
        name: tracker_name(c), is_pc: creature_is_pc?(c[:creature_id]),
        afflictions: afflictions, aiders: aiders }
    end
  end

  def relief_affliction_blob(acc, inst, name, rule, entry)
    attr = (rule['save'] || 'con').to_s
    ri   = roll_inputs_for(acc, "#{attr}_save", attribute_override: attr.to_sym)
    save_mods = []
    save_mods << ri[:competency_modifier] if ri[:competency_modifier]
    if acc
      category = (rule['category'] || 'other').to_s
      CreatureModifiers.save_modifiers(acc, attr, descriptors: [category]).each { |p| save_mods << p }
    end
    { name: name, category: (rule['category'] || 'other').to_s,
      potency: entry[:potency].to_i, save_attr: attr,
      save: { save_dice: ri[:dice_cap].to_i, die_size: DiceResolution.config.die_size,
              save_modifiers: save_mods, potency_divisor: inst.catalog.potency_divisor,
              creature_tier: (acc&.tier rescue 0) || 0,
              inflicter_tier: entry[:inflicting_tier].to_i } }
  end

  def heal_aider_candidates
    encounter_state.combatants.filter_map do |c|
      acc   = (Creatures.lookup(c[:creature_id]) rescue nil) or next nil
      tiers = heal_caster_tiers(acc)
      next nil if tiers.empty?
      ri = roll_inputs_for(acc, 'healing')
      { creature_id: c[:creature_id], name: tracker_name(c), tiers: tiers,
        heal_dice: ri[:dice_cap].to_i, channeling: aider_channeling_heal?(c) }
    end
  end

  def heal_caster_tiers(acc)
    return [] unless acc
    cap  = (acc.tier rescue 0).to_i
    keys = (acc.granted_abilities rescue []).map { |g| g[:name] }
    keys.filter_map do |k|
      info = CreatureSheet.spell_info(k)
      info[:tier] if info && info[:base].to_s.casecmp?('Heal') && info[:tier].to_i <= cap
    end.uniq.sort
  end

  def aider_channeling_heal?(combatant)
    Array(combatant[:concentration]).any? do |e|
      ((e[:spell_name] || e['spell_name']).to_s.casecmp?('Heal'))
    end
  rescue StandardError
    false
  end

  ROLL_CRITICAL_MODIFIER = 2
  ROLL_FAILURE_MODIFIER  = -1
  def roll_affliction_save_dois(save)
    potency        = save[:affliction][:potency].to_i
    divisor        = save[:potency_divisor].to_i
    creature_tier  = save[:creature][:tier].to_i
    inflicter_tier = save[:affliction][:inflicter_tier].to_i
    potency_penalty = divisor.positive? ? potency / divisor : 0

    list = Array(save[:save_modifiers]).map do |m|
      m.is_a?(Array) ? m : [m[:type] || m['type'], m[:amount] || m['amount']]
    end
    list << ['Inherent', creature_tier] if creature_tier.positive?
    list << ['Competency', -potency_penalty] if potency_penalty.positive?
    list << ['Inherent', -inflicter_tier]

    calc = DiceResolution.compute_target_number(list)
    tn   = calc[:tn]
    die  = save[:die_size].to_i
    dice = Array.new(save[:save_dice].to_i) { rand(1..die) }
    calc[:starting_value] + dice.sum do |v|
      if    v == die then ROLL_CRITICAL_MODIFIER
      elsif v == 1   then ROLL_FAILURE_MODIFIER
      elsif v >= tn  then 1
      else 0
      end
    end
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

  def active_spell_strikes(combatant)
    Array(combatant[:concentration]).select { |e| e[:mode] == 'auto' && e[:reservoir].to_i.positive? }
  end

  def attack_builder_blob(attacker, active_spells: false)
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

    weapons = active_spells ? [] : equipped_weapons(attacker[:creature_id]).map do |w|
      attr = w[:ranged] ? :dex : :str
      ri   = roll_inputs_for(acc, 'martial', attribute_override: attr)
      w.merge(dice_cap: ri[:dice_cap].to_i, competency: ri[:competency_modifier])
    end

    if active_spells
      active_spell_strikes(attacker).each do |sw|
        weapons << { item_type: 'spiritual_weapon', display_name: sw[:spell_name].to_s, ranged: false,
                     speed: 0, damage_types: ['force'], threshold: 0, bleed: 0, base_damage: 0,
                     dice_cap: sw[:reservoir].to_i, competency: nil }
      end
    end

    atk_tier = (acc&.tier rescue nil)

    targets = encounter_state.combatants.reject { |c| c[:id] == attacker[:id] }.map do |c|
      tacc = Creatures.lookup(c[:creature_id]) rescue nil
      tname = tracker_name(c)
      { id: c[:id], creature_id: c[:creature_id], name: tname,
        display_name: tname + target_status_suffix(c[:id], c[:creature_id]),
        unaware: encounter_state.unaware?(c[:id]),
        flatfooted_immune: flatfooted_immune?(tacc),
        helpless: !(encounter_state.creature_can_act?(c[:id]) rescue true),
        dying: (encounter_state.creature_dying?(c[:id]) rescue false),
        is_pc: creature_is_pc?(c[:creature_id]),
        category: (creature_is_pc?(c[:creature_id]) ? 'pc' : (((tacc&.group rescue nil) == 'npc') ? 'npc' : 'enemy')),
        tier: (tacc&.tier rescue 0) || 0,
        pool: (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0,
        martial: roll_inputs_for(tacc, 'martial',   attribute_override: :str),
        dodge:   roll_inputs_for(tacc, 'dex_save', attribute_override: :dex),
        parry_weapons: equipped_melee_weapons(c[:creature_id]),
        has_shield:    equipped_shield?(c[:creature_id]),
        ring_parry:    ring_parry_available?(c[:creature_id]),
        abilities: ((tacc&.granted_abilities rescue nil) || []).map { |g| g[:name] },
        mana_left: combatant_mana_left(c[:creature_id], tacc),
        raging:    creature_raging?(c[:creature_id]) }
    end

    rolls = [
      { id: 'attacker', side: 'supporting', creature_name: tracker_name(attacker),
        roll_name: 'Attack', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 2, speed: 0, excluded: false },
      { id: 'defender', side: 'opposing', creature_name: '—',
        roll_name: 'Defense', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true },
      { id: 'shield', side: 'opposing', creature_name: '—',
        roll_name: 'Shield of Faith', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true }
    ]

    shields = {}
    encounter_state.granted_actions.select { |g| g[:defends] }.each do |g|
      cc = encounter_state.combatant(g[:combatant_id]) or next
      source = (g[:dice_source] || 'reservoir').to_s
      available =
        if source == 'combat_pool'
          (encounter_state.combat_pool_remaining(g[:combatant_id]) rescue 0).to_i
        else
          res = Array(cc[:concentration]).find { |e| e[:mode] == 'reservoir' && e[:spell_name].to_s == g[:spell_name].to_s }
          res ? res[:reservoir].to_i : 0
        end
      next unless available >= 2
      cacc = Creatures.lookup(cc[:creature_id]) rescue nil
      shield_skill = cacc ? (cast_skill_for(cacc, nil, g[:spell_name]) rescue nil) : nil
      shield_comp  = shield_skill ? roll_inputs_for(cacc, shield_skill)[:competency_modifier] : nil
      shields[g[:defends]] = { caster_id: g[:combatant_id], caster_name: tracker_name(cc),
                               available: available, dice_source: source, dice_cap: g[:dice_cap].to_i,
                               tier: (cacc&.tier rescue nil), spell_name: g[:spell_name].to_s,
                               bonus: g[:shield_bonus].to_i, competency: shield_comp }
    end

    attacker_pc   = creature_is_pc?(attacker[:creature_id])
    enemy_targets = targets.select { |t| t[:is_pc] != attacker_pc }
    enemy_targets = enemy_targets.reject { |t| encounter_state.creature_dying?(t[:id]) rescue false }
    enemy_targets = order_targets_by_distance(attacker, enemy_targets)
    header_targets = enemy_targets.first(5)
    target_step = { key: 'target', label: 'Target',
                    header_options: header_targets.map { |t| { value: t[:id], label: t[:display_name] } },
                    options: target_options(encounter_state.combatants.reject { |c| c[:id] == attacker[:id] },
                                            roll_id: 'defender') }

    action_opts = []
    action_quick = []
    weapons.each do |w|
      cap   = w[:dice_cap]
      speed = [w[:speed].to_i, 0].max
      disp  = w[:display_name]
      grp   = w[:item_type]
      bpl   = w[:competency] ? [w[:competency]] : []
      set_atk = lambda do |dice|
        { set_dice: [{ id: 'attacker', count: dice }], set_speed: [{ id: 'attacker', speed: speed }],
          set_bpl: [{ id: 'attacker', bonus_penalty_list: bpl }] }
      end
      free = w[:item_type] == 'spiritual_weapon'
      g = dice_count_group(prefix: w[:item_type], key: w[:item_type], group: grp, min: 2, max: cap,
                           aff: ->(n) { free || speed + n <= atk_pool }, patch: set_atk,
                           summary: ->(n) { "#{disp} — #{n} dice" }, lead_label: "#{disp} (speed #{speed})",
                           header_label: disp, info: (bpl.empty? ? 'no bonuses' : fmt_mods.call(bpl)))
      action_opts.concat(g[:body])
      action_quick << g[:header]
    end
    action_step = { key: 'action', label: 'Weapon & dice', options: action_opts, header_options: action_quick }

    defense_map = {}
    defense_header_map = {}
    targets.each do |t|
      weapons.each do |w|
        comp = w[:competency] ? [w[:competency]] : []
        atk_tier_none = Encounter::Attack.attacker_tier_bonuses(
          attacker_tier: atk_tier, defender_tier: t[:tier], tier_advantage: w[:tier_advantage],
          inherent_table: inh_table, no_defense: true
        )
        def_tier = Encounter::Attack.defender_tier_bonuses(defender_tier: t[:tier], inherent_table: inh_table)
        atk_tier_def = Encounter::Attack.attacker_tier_bonuses(
          attacker_tier: atk_tier, defender_tier: t[:tier], tier_advantage: w[:tier_advantage],
          inherent_table: inh_table, no_defense: false
        )
        atk_none_bpl     = comp + atk_tier_none + Encounter::Attack.attacker_bonuses(
          flatfooted: !t[:flatfooted_immune], unaware: t[:unaware] && !t[:flatfooted_immune], helpless: t[:helpless])
        opts = [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                  patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_none_bpl }],
                           restore_dice: [{ id: 'attacker' }],
                           set_excluded: [{ id: 'defender', excluded: true }] } }]
        headers = [{ value: 'none', label: 'No defense' }]
        branches = []
        unless t[:helpless]
          branches << { key: 'dodge', group: 'dodge', name: 'Dodge', inputs: t[:dodge], speed: 0 }
          if t[:has_shield]
            branches << { key: 'block', group: 'block', name: 'Block', inputs: t[:martial], speed: 0 }
          end
          unless w[:ranged]
            t[:parry_weapons].each do |pw|
              branches << { key: "parry:#{pw[:item_type]}", group: "parry:#{pw[:item_type]}",
                            name: "Parry with #{pw[:display_name]}", inputs: t[:martial],
                            speed: [pw[:speed].to_i, 0].max }
            end
            if t[:ring_parry]
              t[:parry_weapons].each do |pw|
                branches << { key: "ringparry:#{pw[:item_type]}", group: "ringparry:#{pw[:item_type]}",
                              name: "Ring of Parry (#{pw[:display_name]})", inputs: t[:martial],
                              speed: 0, free: true }
              end
            end
          end
        end

        branches.each do |b|
          di    = b[:inputs]
          dcmp  = (di[:competency_modifier] ? [di[:competency_modifier]] : []) + def_tier
          cap   = di[:dice_cap].to_i
          dspd  = b[:speed]
          atk_branch_bpl = comp + atk_tier_def + Encounter::Attack.attacker_bonuses(
            flatfooted: (b[:key] != 'dodge') && !t[:flatfooted_immune], unaware: false, helpless: t[:helpless])
          def_no_prop = b[:key] == 'dodge' ? ['Competency'] : []
          mk = lambda do |dice, label, disabled|
            { value: "#{b[:key]}|#{dice}", group: b[:group], label: label,
              summary: "#{b[:name]} — #{dice} dice", disabled: disabled,
              patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_branch_bpl },
                                 { id: 'defender', bonus_penalty_list: dcmp }],
                       set_no_propagate: [{ id: 'defender', types: def_no_prop }],
                       restore_dice: [{ id: 'attacker' }],
                       set_dice:  [{ id: 'defender', count: dice }],
                       set_speed: [{ id: 'defender', speed: dspd }],
                       set_name:  [{ id: 'defender', roll_name: b[:name] }],
                       set_excluded: [{ id: 'defender', excluded: false }] } }
          end
          if b[:free]
            opts << mk.call(cap, "#{b[:name]} — #{cap} dice, free", cap < 1)
            headers << { value: "#{b[:key]}|#{cap}", label: b[:name], disabled: cap < 1 }
            opts << { kind: 'info', group: b[:group], value: "#{b[:group]}|info",
                      label: (dcmp.empty? ? 'no Combat Pool' : "#{fmt_mods.call(dcmp)} · no Combat Pool") }
            next
          end
          name_label = "#{b[:name]} (speed #{dspd})"
          aff_max = (2..cap).select { |n| dspd + n <= t[:pool] }.max
          opts << mk.call(aff_max || cap, name_label, aff_max.nil?)
          (2..cap).each { |n| opts << mk.call(n, n.to_s, dspd + n > t[:pool]) }
          hmin = Encounter::Config.reaction_action_minimum
          headers << { value: "#{b[:key]}|#{hmin}", label: b[:name],
                       disabled: (hmin > cap || dspd + hmin > t[:pool]) }
          opts << { kind: 'info', group: b[:group], value: "#{b[:group]}|info",
                    label: (dcmp.empty? ? 'no bonuses' : fmt_mods.call(dcmp)) }
        end
        if t[:abilities].include?('Better Lucky Than Good')
          bl_cost = reaction_mana_cost('Better Lucky Than Good')
          bl_cost = 4 if bl_cost.zero?
          bl_afford = t[:mana_left].nil? || t[:mana_left] >= bl_cost
          opts << { value: 'better_lucky', group: 'better_lucky',
                    label: "Better Lucky Than Good (#{bl_cost} mana)",
                    summary: 'Better Lucky Than Good', disabled: !bl_afford,
                    patch: { set_bpl: [{ id: 'attacker', bonus_penalty_list: atk_none_bpl }],
                             scale_dice: [{ id: 'attacker', num: 1, den: 2, min: 3 }],
                             set_excluded: [{ id: 'defender', excluded: true }] } }
          headers << { value: 'better_lucky', label: 'Better Lucky', disabled: !bl_afford }
        end
        defense_map["#{t[:id]}|#{w[:item_type]}"] = opts
        defense_header_map["#{t[:id]}|#{w[:item_type]}"] = headers
      end
    end
    defense_step = { key: 'defense', label: 'Target&rsquo;s defense',
                     options_by: %w[target action], options_map: defense_map,
                     header_options_by: %w[target action], header_options_map: defense_header_map }

    ally_defense_map = {}
    ally_defense_header_map = {}
    shields.each do |target_id, sh|
      dcap = sh[:dice_cap].to_i.positive? ? sh[:dice_cap].to_i : sh[:available]
      cap  = [sh[:available], dcap].min
      dice_word = sh[:dice_source] == 'combat_pool' ? 'Combat Pool' : 'Reservoir'
      sh_bpl = []
      sh_bpl << sh[:competency] if sh[:competency]
      sh_bpl << ['Inherent', Encounter::Attack.inherent_amount(inh_table, sh[:tier].to_i)]
      sh_bpl << ['Guidance', sh[:bonus].to_i] if sh[:bonus].to_i.positive?
      shield_patch = lambda do |dice|
        { set_dice: [{ id: 'shield', count: dice }],
          set_bpl:  [{ id: 'shield', bonus_penalty_list: sh_bpl }],
          set_name: [{ id: 'shield', creature_name: sh[:caster_name], roll_name: sh[:spell_name] }],
          set_excluded: [{ id: 'shield', excluded: false }] }
      end
      bonus_note = sh[:bonus].to_i.positive? ? " (+#{sh[:bonus].to_i})" : ''
      g = dice_count_group(prefix: "shield:#{sh[:caster_id]}", group: 'shield', min: 2, max: cap,
                           aff: ->(_n) { true }, patch: shield_patch, header_label: sh[:spell_name],
                           summary: ->(n) { "#{sh[:spell_name]} (#{sh[:caster_name]}) — #{n} dice" },
                           info: "#{sh[:spell_name]}#{bonus_note} by #{sh[:caster_name]} — up to #{cap} #{dice_word} dice")
      ally_defense_map["#{target_id}"] =
        [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
           patch: { set_excluded: [{ id: 'shield', excluded: true }] } }] + g[:body]
      ally_defense_header_map["#{target_id}"] = [{ value: 'none', label: 'No defense' }, g[:header]]
    end
    ally_defense_step = { key: 'ally_defense', label: 'Ally Defense',
                          options_by: %w[target], options_map: ally_defense_map,
                          header_options_by: %w[target], header_options_map: ally_defense_header_map }

    steps = [target_step, action_step, defense_step, ally_defense_step]

    steps.concat(luck_steps(actor_id: attacker[:id],
                            targets: [{ roll_id: 'attacker', label: tracker_name(attacker) },
                                      { roll_id: 'defender', label: 'Defender' },
                                      { roll_id: 'shield', label: 'Ally shield' }]))

    { title: "#{tracker_name(attacker)} attacks", stub_id: "attack-#{attacker[:id]}",
      rolls: rolls, steps: steps }
  end

  def luck_steps(actor_id:, targets:)
    steps = []
    encounter_state.combatants.each do |c|
      next if c[:id] == actor_id # a Reaction can't fire on your own action
      entry = Array(c[:concentration]).find do |e|
        e[:mode] == 'reservoir' && e[:reservoir].to_i.positive? && luck_reservoir?(e)
      end
      next unless entry
      steps << luck_step("#{c[:id]}", c[:id], tracker_name(c), entry[:reservoir].to_i,
                         bard_has_unsettling_words?(c[:creature_id]), targets)
    end
    if encounter_state.dm_luck_points.to_i.positive?
      steps << luck_step('dm', nil, 'DM', encounter_state.dm_luck_points.to_i, true, targets)
    end
    steps
  end

  def luck_reservoir?(entry)
    v = resolve_named_spell(entry[:spell_name])
    v.dig('reservoir', 'discharge', 'defends').to_s.empty?
  rescue StandardError
    true
  end

  def luck_step(sid, source_id, label, amount, penalty, targets)
    { key: "luck:#{sid}", label: 'Luck', dynamic: 'luck', heading: label,
      header_options: [{ value: "#{sid}|none", label: 'No luck' }],
      luck: { source: { id: source_id, sid: sid, label: label, amount: amount, penalty: penalty },
              targets: targets } }
  end

  def creature_is_pc?(creature_id)
    acc = Creatures.lookup(creature_id) rescue nil
    !!(acc && Array(acc.tags).include?('player_character'))
  rescue StandardError
    false
  end

  def bard_has_unsettling_words?(creature_id)
    acc = Creatures.lookup(creature_id) rescue nil
    return false unless acc.respond_to?(:granted_abilities)
    acc.granted_abilities.any? { |g| g[:name].to_s == 'unsettling_words' }
  rescue StandardError
    false
  end

  def enrich_attack_payload!(payload)
    enrich_attack_reactions!(payload)

    sh = payload['shield']
    if sh.is_a?(Hash) && sh['id']
      g = encounter_state.granted_actions.find { |x| x[:combatant_id] == sh['id'] && x[:defends] }
      if g
        sh['spell_name']  = g[:spell_name].to_s
        sh['dice_source'] = (g[:dice_source] || 'reservoir').to_s
      end
    end

    wt  = payload['weapon_type']
    atk = payload['attacker'] || {}
    return unless wt && atk['id']
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

  POST_ROLL_REACTIONS = {
    'danger_sense'    => 'Danger Sense',
    'primal_tenacity' => 'Primal Tenacity'
  }.freeze

  def attach_defender_reactions(result, payload)
    return result if result[:ok] == false
    return result unless result[:damage].to_i.positive?
    choice = (payload['defense'] || {})['choice'].to_s
    return result unless choice.empty? || choice == 'none'
    c   = encounter_state.combatant(payload['target_id'].to_i) or return result
    acc = Creatures.lookup(c[:creature_id]) rescue nil
    abilities = (acc&.granted_abilities rescue []).map { |g| g[:name] }
    mana_left = combatant_mana_left(c[:creature_id], acc)
    raging    = creature_raging?(c[:creature_id])
    avail = POST_ROLL_REACTIONS.filter_map do |key, name|
      next unless abilities.include?(name)
      next if name == 'Primal Tenacity' && !raging
      cost = reaction_mana_cost(name); cost = 4 if cost.zero?
      next unless mana_left.nil? || mana_left >= cost
      mod = Array((Abilities.catalog.ability(name) rescue nil)&.dig('modifiers')).first || {}
      { key: key, name: name, mana_cost: cost, label: "#{name} (#{cost} mana)",
        target: mod['target'].to_s, type: mod['type'].to_s, amount: mod['add'].to_i }
    end
    result.merge(defender_reactions_available: avail)
  end

  def enrich_attack_reactions!(payload)
    dfn = payload['defense']
    if dfn.is_a?(Hash) && dfn['choice'].to_s == 'better_lucky'
      cost = reaction_mana_cost('Better Lucky Than Good')
      dfn['mana_cost'] = cost.zero? ? 4 : cost
    end
    keys = Array(payload['defender_reactions'])
    return if keys.empty?
    payload['defender_reactions'] = keys.filter_map do |key|
      name = POST_ROLL_REACTIONS[key.to_s] or next
      mod  = Array((Abilities.catalog.ability(name) rescue nil)&.dig('modifiers')).first || {}
      cost = reaction_mana_cost(name)
      { 'key' => key.to_s, 'name' => name, 'mana_cost' => (cost.zero? ? 4 : cost),
        'target' => mod['target'].to_s, 'type' => mod['type'].to_s, 'amount' => mod['add'].to_i }
    end
  end

  def cast_builder_blob(caster)
    acc        = Creatures.lookup(caster[:creature_id]) rescue nil
    pool       = (encounter_state.combat_pool_remaining(caster[:id]) rescue 0) || 0
    mana_max   = (acc&.max_mana rescue nil)
    mana_spent = (Conditions.store.instance_for(caster[:creature_id]).state.mana_spent rescue 0)
    mana_left  = mana_max ? [mana_max - mana_spent, 0].max : nil

    spells = (known_spell_castables(acc, pool, mana_left) +
              granted_item_castables(caster, acc, pool, mana_left))
             .reject { |sp| sp[:long_cast] }

    build_cast_blob(caster: caster, acc: acc, spells: spells, pool: pool,
                    title: "#{tracker_name(caster)} casts", stub_id: "cast-#{caster[:id]}")
  end

  def item_builder_blob(actor)
    acc        = Creatures.lookup(actor[:creature_id]) rescue nil
    pool       = (encounter_state.combat_pool_remaining(actor[:id]) rescue 0) || 0
    mana_max   = (acc&.max_mana rescue nil)
    mana_spent = (Conditions.store.instance_for(actor[:creature_id]).state.mana_spent rescue 0)
    mana_left  = mana_max ? [mana_max - mana_spent, 0].max : nil
    spells = (consumable_castables(actor, acc, pool) +
              granted_item_castables(actor, acc, pool, mana_left))
             .reject { |sp| sp[:long_cast] }
    build_cast_blob(caster: actor, acc: acc, spells: spells, pool: pool,
                    title: "#{tracker_name(actor)} uses an item", stub_id: "item-#{actor[:id]}",
                    spell_label: 'Item', cast_verb: 'Use')
  end

  # The Combatant's known Spells as castable descriptors (the Cast list).
  def known_spell_castables(acc, pool, mana_left)
    (CreatureSheet.spells(acc) rescue []).flat_map do |g|
      cost = mana_cost_for_tier(g[:tier])
      Array(g[:names]).map do |name|
        v     = (Abilities.lookup(name) rescue nil) || {}
        skill = cast_skill_for(acc, v, name)
        castable_descriptor(acc, name, g[:tier], pool, mana_left, skill: skill, mana_cost: cost)
      end
    end
  end

  def granted_item_castables(caster, acc, pool, mana_left)
    known = (CreatureSheet.spells(acc) rescue []).flat_map { |g| Array(g[:names]).map(&:to_s) }
    granted_spell_items(caster[:creature_id]).filter_map do |it|
      vname = spell_variant_name(it[:spell], it[:tier])
      next if known.include?(vname)
      v    = (Abilities.lookup(vname) rescue nil) || {}
      cost = mana_cost_for_tier(it[:tier])
      castable_descriptor(acc, vname, it[:tier], pool, mana_left,
                          skill_options: item_skill_options(v, acc), mana_cost: cost)
    end
  end

  def spell_variant_name(spell, tier)
    CreatureSheet.spell_variant_name(spell, tier)
  end

  def item_display_with_variant(stack, cat, _spell, _tier)
    CreatureSheet.item_display_name(stack, cat)
  end

  def consumable_castables(actor, acc, pool)
    consumable_spell_items(actor[:creature_id]).map do |it|
      v = (Abilities.lookup(it[:spell]) rescue nil) || {}
      castable_descriptor(acc, it[:spell], it[:tier], pool, nil,
                          mana_cost: 0, key: "item:#{it[:ref]}", display: it[:display],
                          item: it, self_only: it[:form] == 'potion',
                          quantity: it[:quantity], skill_options: item_skill_options(v, acc))
    end
  end

  def item_cast_skill(variant)
    (Array(variant && variant['skills']).first || 'evocation').to_s
  end

  def item_skill_options(variant, acc = nil)
    listed = Array(variant && variant['skills']).map(&:to_s).flat_map do |s|
      next [s] unless s.end_with?('_')
      resolved = acc ? resolve_skill_family(acc, s) : s
      resolved.to_s.end_with?('_') ? [] : [resolved.to_s]
    end
    (listed + ['evocation']).uniq
  end

  def castable_descriptor(acc, name, tier, pool, mana_left, skill: nil, mana_cost:,
                          key: nil, display: nil, item: nil, self_only: false,
                          skill_options: nil, quantity: nil)
    v   = (Abilities.lookup(name) rescue nil) || {}
    bname = (spell_base_axis(name).first rescue nil) if name
    v = ((Abilities.lookup(bname) rescue nil) || {}) if v.empty? && bname
    raw  = (Abilities.catalog.ability(name) rescue nil) || (bname && Abilities.catalog.ability(bname) rescue nil) || {}
    ra   = raw['area']
    area = ra.is_a?(Array) ? ra.find { |x| x.is_a?(Hash) } : ra
    act  = (Abilities.resolve_activation(v) rescue nil)
    channel_mode = v.dig('channel', 'mode').to_s
    fills_reservoir = %w[reservoir auto].include?(channel_mode) &&
                      v.dig('reservoir', 'fill', 'source').to_s == 'channel_dice'
    # A channel that scales an effect with casting successes (e.g. Heal's
    # bleed_reduction = spell_tier*2*success) needs a real casting check rolled.
    channel_check = !!(v.dig('channel', 'effect_hash', 'bleed_reduction') ||
                       raw.dig('channel', 'effect_hash', 'bleed_reduction'))
    requires_roll = !fills_reservoir &&
                    !!(v['attack_roll'] || Array(v['save']).first || Array(v['damage_type']).compact.first || channel_check)

    candidate_skills = (skill_options || [skill]).compact
    candidate_skills = ['evocation'] if candidate_skills.empty?
    skopts = candidate_skills.uniq.map do |sk|
      r = roll_inputs_for(acc, sk)
      comp = r[:competency_modifier]
      { skill: sk, label: Encounter::Special.pretty_skill(sk),
        dice_cap: r[:dice_cap].to_i, competency: comp, bonus: (comp ? comp[1].to_i : 0) }
    end
    skopts.sort_by! { |o| [-o[:dice_cap], -o[:bonus]] }
    skopts = [skopts.first] if !requires_roll && skopts.any?
    primary = skopts.first || { skill: 'evocation', dice_cap: 0, competency: nil }

    action_min = Encounter::Special.action_cost(act && act[:alias])
    target_rank = (acc&.ranks_for(primary[:skill]) rescue 0).to_i
    multi_max   = if Array(v['save']).first || v['attack_roll']
                    multi_target_max(v['target'], target_rank)
                  end
    { name: name, key: (key || name), display: (display || name),
      tier: tier, mana_cost: mana_cost, skill: primary[:skill], skill_options: skopts,
      dice_cap: primary[:dice_cap], competency: primary[:competency],
      damage_type: Array(v['damage_type']).compact.first, school: v['school'],
      attack_roll: (fills_reservoir ? false : !!v['attack_roll']), save: (fills_reservoir ? nil : Array(v['save']).first),
      area: (area.is_a?(Hash) ? area : nil),
      multi_max: multi_max,
      requires_roll: requires_roll,
      reservoir: fills_reservoir,
      action_min: action_min,
      long_cast: !!(act && act[:kind].to_s == 'real_time' && act[:minutes].to_i >= 1),
      affordable: mana_left.nil? || mana_cost <= mana_left,
      item: item, self_only: self_only || v['target'].to_s == 'self', quantity: quantity }
  end

  def multi_target_max(target, rank)
    return nil if target.nil?
    s = target.to_s
    return nil if %w[self object 1].include?(s)
    n = (Abilities.resolver.resolve_target({ 'target' => target }, rank: rank) rescue nil)
    n = n.to_i if n.is_a?(Numeric)
    (n.is_a?(Integer) && n > 1) ? n : nil
  end

  def granted_spell_items(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.each_with_index.flat_map do |s, i|
      next [] unless s.equipped
      defn = cat.definition_of(s.item_type) || {}
      next [] unless defn['grants_spell']
      form = item_form_of(s.item_type, defn)
      display = CreatureSheet.item_display_name(s, cat)
      granted_spell_names(s, defn).map do |spell|
        { ref: i, item_type: s.item_type, display: display,
          spell: spell, tier: granted_spell_tier(spell, s.tier), form: form }
      end
    end
  end

  def ring_parry_item(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.each_with_index do |s, i|
      next unless s.equipped
      defn = cat.definition_of(s.item_type) || {}
      return { ref: i, stack: s } if defn['grants_parry']
    end
    nil
  end

  def ring_parry_available?(creature_id)
    it = ring_parry_item(creature_id) or return false
    used = it[:stack].parry_used_day
    used.nil? || used.to_i < encounter_state.current_day_index
  end

  def consume_ring_parry!(creature_id)
    it = ring_parry_item(creature_id) or return
    Equipment.instance.set_parry_used_day(equipment_owner(creature_id), it[:ref],
                                          encounter_state.current_day_index)
  end

  def granted_spell_names(stack, defn)
    names = defn['spells'].is_a?(Array) ? defn['spells'] : [stack.stored_spell || defn['spell']]
    names.compact.map(&:to_s)
  end

  def granted_spell_tier(spell, stack_tier)
    t = ((Abilities.catalog.ability(spell) rescue nil) || {})['tier']
    t.is_a?(Array) || t.nil? ? stack_tier : t
  end

  def consumable_spell_items(creature_id)
    cat   = Equipment.catalog
    owner = equipment_owner(creature_id)
    inv   = (Equipment.instance.get_inventory(owner) rescue [])
    inv.each_with_index.filter_map do |s, i|
      next unless s.quantity.to_i.positive?
      next unless cat.category_of(s.item_type) == 'Consumable'
      defn  = cat.definition_of(s.item_type) || {}
      spell = s.stored_spell || defn['spell']
      next unless spell
      form = item_form_of(s.item_type, defn)
      next unless %w[potion scroll].include?(form)
      { ref: i, owner_id: owner, item_type: s.item_type,
        display: item_display_with_variant(s, cat, spell, s.tier),
        spell: spell, tier: s.tier, form: form, quantity: s.quantity }
    end
  end

  def item_form_of(item_type, defn)
    return defn['form'].to_s if defn && defn['form']
    n = item_type.to_s.downcase
    return 'potion' if n.include?('potion')
    return 'oil'    if n.include?('oil')
    return 'scroll' if n.include?('scroll')
    return 'wand'   if n.include?('wand')
    return 'ring'   if n.include?('ring')
    ''
  end

  def build_cast_blob(caster:, acc:, spells:, pool:, title:, stub_id:, spell_label: 'Spell', cast_verb: 'Cast')
    die     = DiceResolution.config.die_size
    base_tn = DiceResolution.config.base_target_number

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
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 2, speed: 0, excluded: false },
      { id: 'target', side: 'opposing', creature_name: '—',
        roll_name: 'Defense', die_size: die, tn: base_tn, starting_value: 0,
        base_tn: base_tn, bonus_penalty_list: [], dice_count: 0, speed: 0, excluded: true }
    ]

    has_skill_step = spells.any? { |sp| Array(sp[:skill_options]).size > 1 }

    inh_table  = (Creatures::Config.tier_minimum_inherent_bonus rescue [])
    caster_inh = Encounter::Attack.inherent_amount(inh_table, ((acc&.tier rescue nil) || 0))
    spell_opts = []
    spells.group_by { |sp| sp[:tier].to_i }.sort_by { |tier, _| tier }.each_with_index do |(tier, group_spells), gi|
      hdr = "tier-#{tier}-h"
      grp = "tier-#{tier}"
      br  = gi.zero? ? '' : '<br>'
      spell_opts << { kind: 'info', group: hdr, value: "#{hdr}|label", label: %(#{br}<span class="cb-tier-head tier-#{tier}">Tier #{tier}</span>) }
      group_spells.each do |sp|
        patch = { set_speed: [{ id: 'caster', speed: 0 }],
                  set_name:  [{ id: 'caster', roll_name: "#{cast_verb} #{sp[:display]}" }] }
        unless has_skill_step
          bpl = []
          bpl << sp[:competency] if sp[:competency]
          bpl << ['Inherent', caster_inh]
          bpl << ['Guidance', sp[:tier].to_i] if sp[:tier].to_i.positive?
          patch[:set_bpl] = [{ id: 'caster', bonus_penalty_list: bpl }]
        end
        button = sp[:quantity].to_i > 1 ? "#{sp[:display]} ×#{sp[:quantity]}" : sp[:display]
        spell_opts << { value: sp[:key], key: sp[:key], group: grp,
                        label: button, summary: sp[:display],
                        disabled: !sp[:affordable],
                        spell_name: sp[:name],
                        cast: { roll: sp[:requires_roll], reservoir: sp[:reservoir] },
                        patch: patch }
      end
    end
    spell_step = { key: 'spell', label: spell_label, options: spell_opts }

    dice_map = {}
    header_map = {}
    spells.each do |sp|
      variants = has_skill_step ? Array(sp[:skill_options]) :
                 [{ skill: sp[:skill], label: Encounter::Special.pretty_skill(sp[:skill]),
                    dice_cap: sp[:dice_cap], competency: sp[:competency] }]
      body   = []
      header = []
      variants.each_with_index do |so, idx|
        cap = so[:dice_cap].to_i
        min = sp[:action_min].to_i
        set = lambda do |n|
          patch = { set_dice: [{ id: 'caster', count: n }] }
          if has_skill_step
            bpl = []
            bpl << so[:competency] if so[:competency]
            bpl << ['Inherent', caster_inh]
            bpl << ['Guidance', sp[:tier].to_i] if sp[:tier].to_i.positive?
            patch[:set_bpl] = [{ id: 'caster', bonus_penalty_list: bpl }]
          end
          patch
        end
        grp    = "dice-#{so[:skill]}"
        prefix = "#{sp[:key]}|#{so[:skill]}"
        if sp[:requires_roll] || sp[:reservoir]
          if cap < min
            body << { kind: 'info', group: grp, value: "#{prefix}|none", label: "#{so[:label]} — no dice available" }
            next
          end
          g = dice_count_group(prefix: prefix, group: grp, min: min, max: cap,
                               aff: ->(n) { n <= pool }, patch: set,
                               summary: ->(n) { "#{so[:label]} — #{n} dice" },
                               lead_label: so[:label],
                               header_label: so[:label])
          body.concat(g[:body])
          # Only the primary (highest-prowess) skill goes on the top bar.
          header << g[:header] if idx.zero?
        else
          affordable = min <= pool
          opt = { value: "#{prefix}|#{min}", key: min, group: grp,
                  label: "#{min} dice", summary: "#{min} dice",
                  disabled: !affordable, patch: set.call(min) }
          opt[:auto] = true if affordable && variants.size == 1
          body.concat([opt])
        end
      end
      dice_map[sp[:key]]   = body
      header_map[sp[:key]] = header
    end
    dice_step = { key: 'dice', label: 'Dice', options_by: %w[spell], options_map: dice_map,
                  header_options_by: %w[spell], header_options_map: header_map, no_summary: true }

    combatant_target_opts = target_options(encounter_state.combatants, roll_id: 'target', self_id: caster[:id])
    self_combatant   = encounter_state.combatant(caster[:id])
    self_target_opts = self_combatant ? target_options([self_combatant], roll_id: 'target', self_id: caster[:id]).map { |o| o.merge(auto: true) } : []
    target_map = {}
    spells.each do |sp|
      target_map[sp[:key]] =
        if sp[:area]
          [{ value: 'place', key: 'place', group: 'place', label: 'Place on the map',
             summary: 'Place the spell effect on the Atlas',
             place: { shape: sp[:area]['shape'], size: sp[:area]['size'], save: !!sp[:save] } }]
        elsif sp[:self_only]
          self_target_opts
        else
          combatant_target_opts
        end
    end
    multi_map = spells.each_with_object({}) { |sp, h| h[sp[:key]] = sp[:multi_max] if sp[:multi_max] }
    target_step = { key: 'target', label: 'Target', options_by: %w[spell], options_map: target_map,
                    multi_by: %w[spell], multi_map: multi_map }

    defense_map = {}
    targets.each do |t|
      spells.each do |sp|
        opts = []
        def_inh = Encounter::Attack.defender_tier_bonuses(defender_tier: t[:tier], inherent_table: inh_table)
        caster_bpl = []
        caster_bpl << sp[:competency] if sp[:competency]
        caster_bpl << ['Inherent', caster_inh]
        caster_bpl << ['Guidance', sp[:tier].to_i] if sp[:tier].to_i.positive?
        if sp[:attack_roll]
          # No defense: the target does not roll, so nothing propagates
          none_bpl = caster_bpl + def_inh.map { |type, amt| [type, -amt] }
          opts << { value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                    patch: { set_bpl: [{ id: 'caster', bonus_penalty_list: none_bpl }],
                             set_excluded: [{ id: 'target', excluded: true }] } }
          opts.concat(cast_defense_branch('dodge', 'Dodge', t[:dodge], speed: 0, save: false, pool: t[:pool],
                                          extra_bpl: def_inh, caster_bpl: caster_bpl))
          opts.concat(cast_defense_branch('block', 'Block', t[:martial], speed: 0, save: false, pool: t[:pool],
                                          extra_bpl: def_inh, caster_bpl: caster_bpl)) if t[:has_shield]
        elsif sp[:save]
          attr = sp[:save]['attribute'].to_s
          tacc  = Creatures.lookup(t[:creature_id]) rescue nil
          extra = tacc ? CreatureModifiers.save_modifiers(tacc, attr, descriptors: [sp[:school]].compact) : []
          opts.concat(cast_defense_branch("save:#{attr}", "#{attr_label(attr)} save",
                                          t[:saves][attr.to_sym] || t[:dodge], speed: 0, save: true,
                                          pool: t[:pool], extra_bpl: extra + def_inh, caster_bpl: caster_bpl))
        end
        defense_map["#{t[:id]}|#{sp[:key]}"] = opts
      end
    end
    spells.select { |sp| sp[:area] }.each do |sp|
      defense_map["place|#{sp[:key]}"] = [
        { value: 'area', key: 'area', group: 'area', label: 'Resolve in the area',
          summary: 'Apply to the creatures in the footprint',
          patch: { set_excluded: [{ id: 'target', excluded: true }] } }
      ]
    end
    defense_step = { key: 'defense', label: 'Target&rsquo;s defense', options_by: %w[target spell], options_map: defense_map }

    steps = [spell_step, dice_step, target_step, defense_step].compact
    steps.concat(luck_steps(actor_id: caster[:id],
                            targets: [{ roll_id: 'caster', label: tracker_name(caster) },
                                      { roll_id: 'target', label: 'Defender' }]))

    blob = { title: title, stub_id: stub_id, rolls: rolls, steps: steps }
    items = spells.select { |sp| sp[:item] }.each_with_object({}) { |sp, h| h[sp[:key]] = sp[:item] }
    blob[:items] = items unless items.empty?
    blob
  end

  def cast_defense_branch(key, name, inputs, speed:, save:, pool:, extra_bpl: [], caster_bpl: nil)
    di   = inputs || { dice_cap: 0 }
    dcmp = di[:competency_modifier] ? [di[:competency_modifier]] : []
    dcmp += Array(extra_bpl)
    cap  = di[:dice_cap].to_i
    mk = lambda do |dice, label, disabled|
      # A rolled defense restores the caster's base list (sheds the No-defense
      # injection); the target's own Inherent crosses via propagation instead.
      set_bpl = [{ id: 'target', bonus_penalty_list: dcmp }]
      set_bpl.unshift({ id: 'caster', bonus_penalty_list: caster_bpl }) if caster_bpl
      { value: "#{key}|#{dice}", group: key, label: label, summary: "#{name} — #{dice} dice", disabled: disabled,
        patch: { set_bpl: set_bpl,
                 set_dice: [{ id: 'target', count: dice }],
                 set_speed: [{ id: 'target', speed: speed }],
                 set_name: [{ id: 'target', roll_name: name }],
                 set_excluded: [{ id: 'target', excluded: false }] } }
    end
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

  CLASS_CASTING_SKILL = { 'cleric' => 'invocation', 'bard' => 'perform_' }.freeze

  def cast_skill_for(acc, variant, spell_name)
    default = Encounter::Cast::DEFAULT_CAST_SKILL
    klass = spell_source_classes(acc)[spell_name.to_s]
    cs = klass && class_casting_skill(acc, klass)
    cs || (Array((variant || {})['skills']).first || default)
  end

  def spell_source_classes(acc)
    map = {}
    (acc&.granted_abilities rescue []).each do |g|
      src = g[:source].to_s
      next unless src.start_with?('class:')
      info = (CreatureSheet.spell_info(g[:name]) rescue nil) or next
      map[info[:name]] ||= src.sub('class:', '')
    end
    map
  end

  def class_casting_skill(acc, class_key)
    skill = CLASS_CASTING_SKILL[class_key.to_s] or return nil
    resolved = resolve_skill_family(acc, skill)
    resolved.to_s.end_with?('_') ? nil : resolved
  end

  def resolve_skill_family(acc, skill)
    return skill unless skill.to_s.end_with?('_')
    (acc&.trained_skills rescue []).find { |s| s.start_with?(skill) } || skill
  end

  def combatant_mana_left(creature_id, acc)
    mana_max = (acc&.max_mana rescue nil)
    return nil unless mana_max
    spent = (Conditions.store.instance_for(creature_id).state.mana_spent rescue 0)
    [mana_max - spent, 0].max
  end

  def creature_raging?(creature_id)
    (Conditions.store.instance_for(creature_id).active_effect_names rescue []).include?('rage')
  rescue StandardError
    false
  end

  def reaction_mana_cost(ability_name)
    cost = (Abilities.lookup(ability_name)&.dig('mana_cost') rescue nil)
    cost ||= (Abilities.catalog.ability(ability_name)&.dig('mana_cost') rescue nil)
    cost.to_i
  end

  def equipped_granted_abilities(creature_id)
    cat = Equipment.catalog
    inv = (Equipment.instance.get_inventory(equipment_owner(creature_id)) rescue [])
    inv.select(&:equipped).flat_map do |s|
      it = cat.item_type(s.item_type)
      Array(it && it[:definition] && it[:definition]['grants']).map do |g|
        (g.is_a?(Hash) ? g['ability'] : g).to_s
      end
    end.reject(&:empty?).uniq
  rescue StandardError
    []
  end

  def roll_table_reaction_for(acc, creature_id)
    equipped_granted_abilities(creature_id).each do |name|
      table = Abilities.roll_table_for(name) or next
      return { ability: name, table: table, source: 'item', skill: 'evocation' }
    end
    (acc&.granted_abilities rescue []).each do |g|
      table = Abilities.roll_table_for(g[:name]) or next
      skill = g[:source].to_s.start_with?('class:') ? 'invocation' : 'evocation'
      return { ability: g[:name], table: table, source: 'class', skill: skill }
    end
    nil
  end

  def roll_table_reaction_channelers(attacker_id)
    rmin = Encounter::Config.reaction_action_minimum
    encounter_state.combatants.filter_map do |c|
      next if c[:id] == attacker_id
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      next unless acc
      found = roll_table_reaction_for(acc, c[:creature_id]) or next
      pool  = (encounter_state.combat_pool_remaining(c[:id]) rescue 0) || 0
      ri    = roll_inputs_for(acc, found[:skill])
      cost  = reaction_mana_cost(found[:ability])
      mana_left = combatant_mana_left(c[:creature_id], acc)
      afford_pool = pool >= rmin
      afford_mana = mana_left.nil? || mana_left >= cost
      { combatant_id: c[:id], name: tracker_name(c), ability: found[:ability],
        table: found[:table], source: found[:source], skill: found[:skill],
        skill_label: Encounter::Special.pretty_skill(found[:skill]), dice_cap: ri[:dice_cap].to_i,
        mana_cost: cost, pool: pool,
        disabled: !(afford_pool && afford_mana),
        disabled_reason: (!afford_pool ? 'not enough Combat Pool' : (!afford_mana ? 'not enough Mana' : nil)) }
    end
  end

  def roll_table_channel_info(acc, creature_id)
    found = roll_table_reaction_for(acc, creature_id) || { skill: 'evocation' }
    ri    = roll_inputs_for(acc, found[:skill])
    bpl   = []
    bpl << ri[:competency_modifier] if ri[:competency_modifier]
    tier  = (acc&.tier rescue nil)
    bpl << ['Inherent', tier.to_i] if tier.to_i.positive?
    { skill: found[:skill], dice_cap: ri[:dice_cap].to_i, tier: tier, bpl: bpl }
  end

  def roll_table_check_info(combatant)
    acc  = Creatures.lookup(combatant[:creature_id]) rescue nil
    info = roll_table_channel_info(acc, combatant[:creature_id])
    { skill_label: Encounter::Special.pretty_skill(info[:skill]),
      modifiers: info[:bpl].map { |type, amt| { type: type.to_s, amount: amt.to_i } } }
  end

  def roll_table_builder_blob(combatant, ability_name)
    acc     = Creatures.lookup(combatant[:creature_id]) rescue nil
    die     = DiceResolution.config.die_size
    base_tn = DiceResolution.config.base_target_number
    pool    = (encounter_state.combat_pool_remaining(combatant[:id]) rescue 0) || 0
    rmin    = Encounter::Config.reaction_action_minimum
    info    = roll_table_channel_info(acc, combatant[:creature_id])
    skill   = info[:skill]
    bpl     = info[:bpl]
    tier    = info[:tier]

    rolls = [{ id: 'channel', side: 'supporting', creature_name: tracker_name(combatant),
               roll_name: ability_name, die_size: die, tn: base_tn, starting_value: 0,
               base_tn: base_tn, bonus_penalty_list: bpl, dice_count: rmin, speed: 0, excluded: false,
               tier: tier }]

    upper = info[:dice_cap].positive? ? [info[:dice_cap], pool].min : pool
    upper = [upper, rmin].max
    set   = ->(n) { { set_dice: [{ id: 'channel', count: n }] } }
    label = Encounter::Special.pretty_skill(skill)
    opts  = [{ value: upper, key: 'dice', group: 'dice', label: label,
               summary: "#{label} — #{upper} dice", patch: set.call(upper) }]
    (rmin..upper).each { |n| opts << { value: n, key: 'dice', group: 'dice', label: n.to_s,
                                       summary: "#{n} dice", patch: set.call(n) } }
    steps = [{ key: 'dice', label: 'Channel dice', options: opts,
               header_options: [{ value: upper, label: label }] }]

    { title: "#{tracker_name(combatant)} — #{ability_name}",
      stub_id: "roll-table-#{combatant[:id]}", rolls: rolls, steps: steps }
  end

  def spell_base_axis(name)
    info = (CreatureSheet.spell_info(name) rescue nil)
    return [info[:base], info[:axis].to_i] if info && info[:base]
    [name.to_s, 0]
  end

  def resolve_named_spell(name)
    base, axis = spell_base_axis(name)
    (Abilities.lookup(base, axis_index: axis) rescue nil) || {}
  rescue StandardError
    {}
  end

  def dice_count_group(prefix:, group:, min:, max:, aff:, patch:, summary:,
                       header_label:, info: nil, key: nil, lead_label: nil, header_min: false)
    aff_max = (min..max).select { |n| aff.call(n) }.max
    opt = lambda do |dice, label, disabled|
      o = { value: "#{prefix}|#{dice}", group: group, label: label,
            summary: summary.call(dice), disabled: disabled, patch: patch.call(dice) }
      o[:key] = key unless key.nil?
      o
    end
    body = []
    body << opt.call(aff_max || max, lead_label, aff_max.nil?) if lead_label
    (min..max).each { |n| body << opt.call(n, n.to_s, !aff.call(n)) }
    # Optional trailing note (e.g. an Attack's weapon bonuses). Omitted when empty.
    body << { kind: 'info', group: group, value: "#{group}|info", label: info } if info && !info.to_s.empty?
    hdice = header_min ? min : (aff_max || max)
    { body: body, header: { value: "#{prefix}|#{hdice}", label: header_label,
                            disabled: (header_min ? !aff.call(min) : aff_max.nil?) } }
  end

  def spell_defends_spec(v)
    return { block_dice: 'reservoir' } if v.dig('reservoir', 'discharge', 'defends').to_s == 'target'
    d = v['defends']
    return { block_dice: (d['block_dice'] || 'combat_pool').to_s } if d.is_a?(Hash)
    { block_dice: 'combat_pool' } if d.to_s == 'target'
  end

  # The per-Tier Mana Cost (abilities_config.yaml → Mana Cost Per Tier).
  def mana_cost_for_tier(tier)
    tbl = (Abilities.catalog.config.mana_cost_per_tier rescue {})
    (tbl[tier] || tbl[tier.to_s] || tbl[tier.to_i] || 0).to_i
  end

  def enrich_cast_payload!(payload)
    spell  = (payload['spell'] ||= {})
    spell['name'] ||= payload['spell_name']
    caster = payload['caster'] || {}
    # A constructed per-Tier name ("Standard Shield") resolves to its base
    # catalog key + Tier axis so every Abilities lookup below succeeds.
    base_name, = spell_base_axis(spell['name']) if spell['name']

    if (item = payload['item']) && spell['name']
      spell['mana_cost'] = 0
      spell['cast_skill'] ||= item_cast_skill(resolve_named_spell(spell['name']))
      if item['form'].to_s == 'potion'
        ccomb = (encounter_state.combatant(caster['id'].to_i) rescue nil)
        cacc  = ccomb && (Creatures.lookup(ccomb[:creature_id]) rescue nil)
        spell['toxicity'] = (Equipment.instance.item_form_toxicity(
          item_tier: item['tier'].to_i, target_tier: (cacc&.tier rescue nil)) rescue 0)
      end
    end

    # Resolve the caster's own Casting Skill (a Cleric's Invocation) so the
    # casting check rolls that Skill, not the Spell's generic `arcana` default.
    if spell['cast_skill'].nil? && caster['id'] && spell['name']
      ccomb = (encounter_state.combatant(caster['id'].to_i) rescue nil)
      cacc  = ccomb && (Creatures.lookup(ccomb[:creature_id]) rescue nil)
      variant = resolve_named_spell(spell['name'])
      spell['cast_skill'] = cast_skill_for(cacc, variant, spell['name']) if cacc
    end

    if spell['tier'].nil? && spell['name']
      info = (CreatureSheet.spell_info(spell['name']) rescue nil)
      spell['tier'] = info[:tier] if info
    end
    spell['mana_cost'] ||= mana_cost_for_tier(spell['tier']) unless spell['tier'].nil?

    if spell['bleed_reduction'].nil? && base_name
      raw_v   = (Abilities.catalog.ability(base_name) rescue nil) || {}
      formula = raw_v.dig('channel', 'effect_hash', 'bleed_reduction')
      if formula
        tier       = spell['tier'].to_i
        tier_value = tier.zero? ? 0.5 : tier
        succ       = (caster['successes'] || 0).to_i
        amt        = (Abilities::Formula.evaluate(formula.to_s, 'tier' => tier_value, 'success' => succ) rescue 0)
        spell['bleed_reduction'] = [amt.floor, 0].max
      end
    end

    if Abilities.respond_to?(:resolve_spell) && spell['name']
      resolved = (Abilities.resolve_spell(base_name, tier: spell['tier']) rescue nil)
      apply_resolved_spell!(payload, resolved) if resolved
    end
    spell['cast_skill'] ||= Encounter::Cast::DEFAULT_CAST_SKILL
  end

  def apply_resolved_spell!(payload, resolved)
    r = (resolved.transform_keys(&:to_s) rescue {})
    spell = (payload['spell'] ||= {})
    spell['polarity'] = r['polarity'] unless r['polarity'].nil?

    variant = resolve_named_spell(spell['name'])
    spell['cast_skill'] ||= (Array(variant && variant['skills']).first || Encounter::Cast::DEFAULT_CAST_SKILL)

    effects = cast_effects_from_consumption(r['effects'])
    spell['duration'] ||= variant['duration'] if variant && variant['duration']
    spell['temp_hp_condition'] = 'ward' if (spell_base_axis(spell['name']).first rescue nil) == 'Ward'
    if variant && variant['duration']
      effects = effects.map { |e| e['kind'] == 'temp_hp' ? e.merge('duration' => variant['duration']) : e }
    end
    if variant && Array(variant['modifiers']).any?
      effects += [{ 'kind' => 'modifiers', 'modifiers' => variant['modifiers'],
                    'duration' => variant['duration'] }]
    end

    base_name, = spell_base_axis(spell['name']) if spell['name']
    raw_entry = (Abilities.catalog.ability(base_name) rescue nil) || variant || {}
    raw_area  = raw_entry['area']
    area_hash = raw_area.is_a?(Array) ? raw_area.find { |x| x.is_a?(Hash) } : raw_area
    if area_hash.is_a?(Hash) && (oe = Array(area_hash['on_enter']).first)
      fx = oe['fail'].to_s
      effects += [{ 'kind' => 'effect', 'name' => fx }] unless fx.empty? || fx == '0'
    end
    Array(payload['targets']).each { |t| t['effects'] = effects }

    if area_hash.is_a?(Hash)
      spell['area'] = area_hash
      spell['duration'] = variant['duration'] || raw_entry['duration']
    end

    reservoir_channel = %w[reservoir auto].include?((variant && variant.dig('channel', 'mode')).to_s) &&
                        (variant && variant.dig('reservoir', 'fill', 'source')).to_s == 'channel_dice'

    if variant && variant['attack_roll'] && !reservoir_channel
      spell['attack_roll'] = true
      spell['damage_type'] ||= Array(variant['damage_type']).compact.first
      spell['casting_attribute'] ||= (Proficiencies.attribute_for(spell['cast_skill']) || :cha).to_s
    elsif variant && Array(variant['damage_type']).compact.any? && effects.none? { |e| e['kind'] == 'damage' }
      spell['default_damage'] = true
      spell['damage_type'] ||= Array(variant['damage_type']).compact.first
      spell['casting_attribute'] ||= (Proficiencies.attribute_for(spell['cast_skill']) || :cha).to_s
    end

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

  def place_spell_area_zone!(payload)
    spell = payload['spell'] || {}
    area  = spell['area']
    return nil unless area.is_a?(Hash)
    map_id = Atlas.state.active_map_id
    return nil unless map_id
    caster = payload['caster'] || {}
    source_id = "encounter:zone:#{spell['name']}:#{caster['id']}"
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

  def expire_caster_zones!(combatant_id)
    round = encounter_state.current_round or return []
    removed = Conditions.store.expire_zone_effects_for(combatant_id, round)
    removed.each { |z| Atlas.state.remove_zone(z[:atlas_zone_id]) if z[:atlas_zone_id] }
    removed.map { |z| z[:source_id] }
  end

  def begin_turn_side_effects!(combatant_id)
    expire_caster_zones!(combatant_id)
    Conditions.store.persist!
  end

  def grant_defend_reaction!(payload)
    spell = payload['spell'] || {}
    v = resolve_named_spell(spell['name'])
    spec = spell_defends_spec(v) or return
    caster = payload['caster'] || {}
    ally = Array(payload['targets']).first or return
    # The block rolls up to the caster's Dice Cap in the casting skill; each die
    # spends one Reservoir die (Shield of Faith) or one Combat Pool die (Shield).
    skill = (spell['cast_skill'] || Encounter::Cast::DEFAULT_CAST_SKILL).to_s
    cacc  = (Creatures.lookup(combatant_for_id_creature(caster['id'])) rescue nil)
    cap   = (roll_inputs_for(cacc, skill)[:dice_cap].to_i rescue 0)
    # Replace any prior shield from the same caster+spell on a new cast.
    encounter_state.revoke_action { |g| g[:source] == spell['name'].to_s && g[:combatant_id] == caster['id'] }
    encounter_state.grant_action({ combatant_id: caster['id'], name: spell['name'], source: spell['name'],
                                   spell_name: spell['name'], defends: ally['id'],
                                   cast_skill: skill, dice_cap: cap,
                                   dice_source: spec[:block_dice],
                                   shield_bonus: v['shield_bonus'].to_i })
    # Show the protected ally a visible "shielded" condition (the caster still
    # controls the block). Refreshed each cast.
    apply_shielded_condition(ally['id'], spell['name'].to_s)
  end

  def consume_cast_item!(payload)
    item  = payload['item'] or return nil
    owner = item['owner_id']
    ref   = item['ref']
    return nil if owner.nil? || ref.nil?
    inst = Equipment.instance
    inst.remove_item(owner, ref.to_i, quantity: 1)
    inst.cleanup(owner)
    item['display'] || item['item_type']
  end

  # Mark the shielded Combatant with the `shielded` named effect for display.
  def apply_shielded_condition(combatant_id, source_name)
    c = encounter_state.combatant(combatant_id.to_i) or return
    inst = Conditions.store.instance_for(c[:creature_id])
    inst.apply_named_effect('shielded', source_id: "shield:#{source_name}") if inst.respond_to?(:apply_named_effect)
  rescue StandardError
    nil
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

    dice_for = lambda do |skill_label, dice_cap|
      upper = (check_channel && dice_cap.to_i.positive?) ? [dice_cap.to_i, pool].min : pool
      upper = [upper, min].max
      set   = ->(n) { { set_dice: [{ id: 'performance', count: n }] } }
      opts  = [{ value: upper, key: 'dice', group: 'dice', label: skill_label,
                 summary: "#{skill_label} — #{upper} dice", patch: set.call(upper) }]
      (min..upper).each { |n| opts << { value: n, key: 'dice', group: 'dice', label: n.to_s,
                                        summary: "#{n} dice", patch: set.call(n) } }
      { options: opts, header: { value: upper, label: skill_label } }
    end

    steps = []
    perform_skill = nil
    if check_channel && skills.length > 1
      # Several trained Performance skills — ask which (its Competency rides the
      # Roll; its Dice Cap bounds the choice-dependent Dice step).
      perf_opts = skills.map do |s|
        { value: s[:key], key: s[:key], label: s[:label], summary: s[:label],
          patch: { set_bpl: [{ id: 'performance',
                               bonus_penalty_list: ([s[:competency]] + Array(s[:modifiers])).compact }] } }
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
      rolls[0][:bonus_penalty_list] = skill ? ([skill[:competency]] + Array(skill[:modifiers])).compact : []
      d = dice_for.call((skill ? skill[:label] : ability_name), skill ? skill[:dice_cap] : 0)
      steps << { key: 'dice', label: 'Channel dice', options: d[:options], header_options: [d[:header]] }
    end

    steps.concat(luck_steps(actor_id: combatant[:id],
                            targets: [{ roll_id: 'performance', label: tracker_name(combatant) }]))

    { title: "#{tracker_name(combatant)} — #{ability_name}", stub_id: "special-#{combatant[:id]}",
      reservoir_ratio: ratio, perform_skill: perform_skill, rolls: rolls, steps: steps }
  end

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
  redirect back || '/encounter'
end

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
