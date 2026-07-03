# DM Page — the DM-only operations surface (docs/project/menu_layout.md).
# Hosts the Roll Log (every player Skill Roll, so a player cannot silently
# re-roll until they like the result) alongside the DM's out-of-combat tools.

# Record a Roll. Reachable by players (they are not on the loopback address),
# so this must NOT be DM-gated. The compact roll stub sends the rolled dice and
# the computed result; the DM sees the actual dice on the DM Page.
post '/dm/roll' do
  content_type :json
  payload = (JSON.parse(request.body.read) rescue nil)
  halt 400, { ok: false, error: 'invalid payload' }.to_json unless payload.is_a?(Hash)

  entry = RollLog.store.add(
    'creature_id'        => payload['creature_id'],
    'creature_name'      => payload['creature_name'],
    'roll_name'          => payload['roll_name'],
    'ranks'              => payload['ranks'],
    'tn'                 => payload['tn'],
    'base_tn'            => payload['base_tn'],
    'bonus_penalty_list' => payload['bonus_penalty_list'],
    'dice_count'         => payload['dice_count'],
    'starting_value'     => payload['starting_value'],
    'dice'               => payload['dice'],
    'dois'               => payload['dois'],
    'critical_count'     => payload['critical_count'],
    'at'                 => Time.now.to_i
  )
  { ok: true, id: entry['id'] }.to_json
end

# The DM Page — DM only. A player who reaches it is redirected like any other
# DM-only page.
get '/dm' do
  redirect '/character-sheets' unless dm_view?
  @entries     = RollLog.store.recent
  @timestamp   = Chronicle.store.timestamp
  @scene_round = SceneRound.store.round

  # Out-of-combat actions: every Player Character is always a Combatant
  # (reconcile), so the Combat Turn Action panel can drive a selected PC's
  # out-of-combat actions (drink a Potion, use an Item, cast a utility Spell)
  # with Attack / Move / End Turn hidden. The panel is fetched over JS
  # (GET /dm/actor_panel) so picking a Character never reloads the page.
  reconcile_player_combatants!
  @dm_actors = dm_actor_options

  # Party overview: the Downtime PC Card per Player Character (the compact
  # status cards shown at the top of the Encounter page during downtime).
  @conditions_catalog = Conditions::Catalog.load
  @downtime_cards     = downtime_cards(:dm, nil)
  erb :dm
end

# The out-of-combat Turn Action panel for one Player Character, fetched by the
# actor picker's JavaScript so selecting a Character never reloads the page.
get '/dm/actor_panel' do
  halt 403 unless dm_view?
  reconcile_player_combatants!
  ctx = dm_actor_context(params[:actor_id].to_i)
  halt 404 unless ctx
  erb :_turn_action, layout: false, locals: ctx.merge(out_of_combat: true)
end

# The out-of-combat Skill action panel: pick a Skill, then (for an opposed
# Skill) multi-select target(s). The roll reuses the Check Resolution Stub via
# /dm/skill_check with this one actor Supporting and the targets Opposing.
get '/dm/skill_panel' do
  halt 403 unless dm_view?
  reconcile_player_combatants!
  actor = encounter_state.combatant(params[:actor_id].to_i)
  halt 404 unless actor && creature_is_pc?(actor[:creature_id])
  acc = Creatures.lookup(actor[:creature_id]) rescue nil
  @actor_id = actor[:id]
  @skills   = (CreatureSheet.all_skills(acc) rescue []).map do |s|
    { key: s[:key], name: s[:name], bonus: s[:bonus].to_i, opposed: opposed_skill?(s[:key]) }
  end
  @targets  = encounter_state.combatants.reject { |c| c[:id] == actor[:id] }
                             .map { |c| { combatant_id: c[:id], name: tracker_name(c) } }
  erb :_dm_skill_panel, layout: false
end

# The "Multiple" group action: pick several Characters (anyone on Initiative),
# then Skill or Item. This renders the selection panel; the roll / apply steps
# are fetched from the sub-routes below.
get '/dm/multiple' do
  halt 403 unless dm_view?
  reconcile_player_combatants!
  @combatants = dm_combatant_options
  @skills     = dm_all_skill_options
  erb :_dm_multiple, layout: false
end

# An opposed Skill Check for one or more actors: every actor rolls the Skill
# (Supporting) and every target rolls the opposed Skill (Opposing). Shared by
# the Skill action (one actor) and the Multiple group action (several).
# Rendered through the Check Resolution Stub; the host reads each side's
# Successes and shows the best-vs-worst pairings.
get '/dm/skill_check' do
  halt 403 unless dm_view?
  reconcile_player_combatants!
  skill = params[:skill].to_s
  opp   = opposed_skill_for(skill) || skill
  supporting = combatant_skill_rolls(Array(params[:actors]), skill, side: 'supporting', prefix: 'actor')
  opposing   = combatant_skill_rolls(Array(params[:targets]), opp,   side: 'opposing', prefix: 'target')
  halt 404 if supporting.empty?
  erb :_check_stub, layout: false, locals: { check: { supporting: supporting, opposing: opposing } }
end

# The no-roll consumables every selected Character carries (the intersection),
# for the Multiple group Item action. Only Potions / Scrolls whose spell needs
# no roll (invisibility, disguise, …) are offered — not healing or combat items.
get '/dm/multiple/items' do
  halt 403 unless dm_view?
  reconcile_player_combatants!
  @items = dm_group_item_options(Array(params[:actors]))
  erb :_dm_multiple_items, layout: false
end

# Preview one Item for the selected Characters before it is applied: the Magic
# Toxicity each Character will take (a Potion imposes Item-Form Toxicity; a
# Scroll imposes none). Rendered with a Confirm button that commits the use.
get '/dm/multiple/item_preview' do
  halt 403 unless dm_view?
  reconcile_player_combatants!
  @item_type = params[:item_type].to_s
  @rows = Array(params[:actors]).filter_map { |cid| group_item_toxicity(cid.to_i, @item_type) }
  erb :_dm_multiple_item_confirm, layout: false
end

# Apply one no-roll Item to every selected Character — each drinks their own
# copy (self, no roll) and one is subtracted. Reuses the same cast resolution
# the single-character Item action uses, per Character.
post '/dm/multiple/use_item' do
  halt 403 unless dm_view?
  content_type :json
  reconcile_player_combatants!
  payload   = (JSON.parse(request.body.read) rescue {})
  item_type = payload['item_type'].to_s
  results = Array(payload['actors']).filter_map { |cid| apply_group_item(cid.to_i, item_type) }
  Conditions.store.persist!
  { ok: true, results: results }.to_json
end

helpers do
  # Opposed Skills: only these ask for a target (each maps to the Skill the
  # target rolls). A Skill that is not listed here is unopposed — the Skill
  # action rolls it with no target (Heal, Nature, Athletics, …). The social /
  # stealth contests are symmetric; Sleight of Hand is opposed by Perception.
  OPPOSED_SKILLS = {
    'deception'       => 'sense_motive',
    'sense_motive'    => 'deception',
    'stealth'         => 'perception',
    'perception'      => 'stealth',
    'sleight_of_hand' => 'perception'
  }.freeze

  def opposed_skill?(skill)
    OPPOSED_SKILLS.key?(skill.to_s)
  end

  def opposed_skill_for(skill)
    OPPOSED_SKILLS[skill.to_s]
  end

  # ---- Multiple (group action) ---------------------------------------------

  # Everyone on Initiative — every Combatant — as { combatant_id:, name: }.
  def dm_combatant_options
    encounter_state.combatants.map { |c| { combatant_id: c[:id], name: tracker_name(c) } }
  end

  # Every concrete (rollable) Skill, humanized, for the group Skill picker.
  def dm_all_skill_options
    Proficiencies.skills.keys.map(&:to_s).reject { |k| k.end_with?('_') }.sort.map do |key|
      { key: key, name: CreatureSheet.pretty_skill_name(key) }
    end
  end

  # A Skill Roll (Check Resolution Stub shape) per Combatant id in `ids`, each
  # rolling `skill`. Rolls are given unique ids (`<prefix>-<combatant_id>`) and
  # the given side so the aggregate net nets Supporting against Opposing.
  def combatant_skill_rolls(ids, skill, side:, prefix:)
    Array(ids).filter_map do |cid|
      c   = encounter_state.combatant(cid.to_i) or next
      acc = Creatures.lookup(c[:creature_id]) rescue nil
      sr  = acc && (CreatureSheet.skill_roll(acc, skill) rescue nil)
      next unless sr
      sr.merge(id: "#{prefix}-#{c[:id]}", side: side)
    end
  end

  # A consumable's spell needs a roll to use — an attack roll, a Save the
  # drinker/target must make, a Damage Type, or a channelled casting check
  # (Heal's bleed reduction) — so it is a combat / healing item, not a no-roll
  # self-buff. An *observer* Save (invisibility's Blindspot — onlookers roll a
  # Wisdom save later to see through it) is not a roll the drinker makes, so it
  # does not count. Mirrors the single-character Item action's own roll gate.
  def item_cast_requires_roll?(spell)
    v   = spell_variant_definition(spell)
    bname = (spell_base_axis(spell).first rescue nil)
    raw = (Abilities.catalog.ability(spell) rescue nil) ||
          (bname && (Abilities.catalog.ability(bname) rescue nil)) || {}
    channel_mode    = v.dig('channel', 'mode').to_s
    fills_reservoir = %w[reservoir auto].include?(channel_mode) &&
                      v.dig('reservoir', 'fill', 'source').to_s == 'channel_dice'
    channel_check   = !!(v.dig('channel', 'effect_hash', 'bleed_reduction') ||
                         raw.dig('channel', 'effect_hash', 'bleed_reduction'))
    saves = Array(v['save']).reject do |s|
      (s.is_a?(Hash) ? (s['save_target'] || s[:save_target]) : nil).to_s == 'observers'
    end
    !fills_reservoir &&
      !!(v['attack_roll'] || saves.first || Array(v['damage_type']).compact.first || channel_check)
  end

  # A consumable eligible for the group Item action: a no-roll self-buff
  # (invisibility, disguise, darkvision, blur, expeditious retreat, …). It must
  # neither require a roll nor restore/harm HP, temp HP, or Mana — so Healing
  # (Heal, Ward) and combat items are excluded, matching the DM's request that
  # this is only for utility buffs, not healing or combat.
  def group_item_eligible?(spell, tier = nil)
    return false if item_cast_requires_roll?(spell)
    resolved = (Abilities.resolve_spell(spell, tier: tier) rescue nil)
    return true unless resolved
    return false if resolved[:polarity] == :forced
    # A heal / temp-HP / mana / damage consumption Effect means it touches HP or
    # Mana — not the pure Active-Effect buff this action is for.
    Array(resolved[:effects]).empty?
  end

  # The no-roll Potions / Scrolls every selected Character carries (intersection),
  # as { item_type:, display: }.
  def dm_group_item_options(actor_ids)
    creature_ids = Array(actor_ids).filter_map do |cid|
      c = encounter_state.combatant(cid.to_i); c && c[:creature_id]
    end
    return [] if creature_ids.empty?
    per_owner = creature_ids.map do |crid|
      (consumable_spell_items(crid) rescue [])
        .select { |it| group_item_eligible?(it[:spell], it[:tier]) }
        .map { |it| it[:item_type] }.uniq
    end
    common = per_owner.reduce(:&) || []
    common.sort.map { |it| { item_type: it, display: it } }
  end

  # The Magic Toxicity a Character would take from one no-roll Item, for the
  # confirm preview: a Potion imposes its Item-Form Toxicity (scaled down when
  # the drinker's Tier is below the Item's), a Scroll imposes none. Nil when the
  # Character does not carry the Item.
  def group_item_toxicity(combatant_id, item_type)
    c  = encounter_state.combatant(combatant_id) or return nil
    it = (consumable_spell_items(c[:creature_id]) rescue []).find { |x| x[:item_type] == item_type }
    return nil if it.nil? || !group_item_eligible?(it[:spell], it[:tier])
    acc = Creatures.lookup(c[:creature_id]) rescue nil
    tox =
      if it[:form].to_s == 'potion'
        (Equipment.instance.item_form_toxicity(item_tier: it[:tier].to_i, target_tier: (acc&.tier rescue nil)) rescue 0)
      else
        0
      end
    { name: (acc&.name rescue "Creature ##{c[:creature_id]}"), toxicity: tox.to_i }
  end

  # Apply one no-roll Item to a Character (self, no roll), reusing the same cast
  # resolution the single-character Item action uses — so a buff Item's Effects
  # (invisibility, disguise) and its Item-Form Toxicity are applied — then
  # subtract one. Nil when the Character doesn't carry it.
  def apply_group_item(combatant_id, item_type)
    c  = encounter_state.combatant(combatant_id) or return nil
    it = (consumable_spell_items(c[:creature_id]) rescue []).find { |x| x[:item_type] == item_type }
    return nil if it.nil? || !group_item_eligible?(it[:spell], it[:tier])

    payload = {
      'commit'     => true,
      'spell_name' => it[:spell],
      'caster'     => { 'id' => combatant_id, 'dice' => 0, 'speed' => 0, 'successes' => 0 },
      'targets'    => [{ 'id' => combatant_id }],
      'item'       => { 'ref' => it[:ref], 'owner_id' => it[:owner_id], 'form' => it[:form], 'tier' => it[:tier] }
    }
    enrich_cast_payload!(payload)
    # enrich_cast_payload! only derives modifier / consumption / area Effects; a
    # self-buff Spell's named Active Effect (Blur's `blurred`, an invisibility
    # Potion's `blindspot`) is not built. Inject those onto the (self) target so
    # resolve routes them through apply_named_effect like any other Effect.
    buff = self_buff_effects(it[:spell])
    Array(payload['targets']).each { |t| t['effects'] = Array(t['effects']) + buff } unless buff.empty?
    result = encounter_state.resolve_cast_payload(payload)
    consume_cast_item!(payload) if result[:committed]
    acc = Creatures.lookup(c[:creature_id]) rescue nil
    { name: (acc&.name rescue "Creature ##{c[:creature_id]}"), item: item_type }
  rescue StandardError
    nil
  end

  # The named Active Effects a no-roll self-buff Item confers on the drinker: a
  # Spell's plain `effects:` list (Blur → `blurred`) plus the fail Effect of any
  # Save its *observers* roll (an invisibility Potion → `blindspot`). A Save the
  # drinker rolls is already excluded by group_item_eligible?, so only these
  # self-applied buffs remain. Returned as resolve-ready Effect Hashes.
  def self_buff_effects(spell)
    v = spell_variant_definition(spell)
    names = Array(v['effects']).map(&:to_s)
    Array(v['save']).each do |s|
      next unless s.is_a?(Hash)
      next unless (s['save_target'] || s[:save_target]).to_s == 'observers'
      names << (s['fail'] || s[:fail]).to_s
    end
    names.reject { |n| n.empty? || n == '0' }.uniq.map { |n| { 'kind' => 'effect', 'name' => n } }
  end

  # Player-Character Combatants, as { combatant_id:, creature_id:, name: },
  # for the out-of-combat action selector.
  def dm_actor_options
    encounter_state.combatants.select { |c| creature_is_pc?(c[:creature_id]) }.map do |c|
      { combatant_id: c[:id], creature_id: c[:creature_id], name: tracker_name(c) }
    end
  end

  # Assemble the locals the Turn Action panel needs to run a chosen Combatant's
  # actions outside Combat. Returns nil for an unknown / non-PC Combatant.
  def dm_actor_context(actor_id)
    combatant = encounter_state.combatant(actor_id)
    return nil unless combatant && creature_is_pc?(combatant[:creature_id])

    cid = combatant[:creature_id]
    {
      acting:            build_tracker_row(combatant, nil),
      dead:              (encounter_state.creature_dead?(actor_id) rescue false),
      saves:             (start_of_turn_saves(combatant) rescue []),
      main_actions:      (encounter_state.main_actions_remaining(actor_id) rescue -1),
      special_options:   (encounter_state.special_options(actor_id) rescue []),
      has_spells:        dm_actor_has_spells?(cid),
      has_items:         dm_actor_has_items?(cid),
      has_active_spells: (active_spell_strikes(combatant).any? rescue false)
    }
  end

  def dm_actor_has_spells?(creature_id)
    acc = Creatures.lookup(creature_id) rescue nil
    knows = acc ? (CreatureSheet.spells(acc) rescue []).any? { |g| Array(g[:names]).any? } : false
    knows || (granted_spell_items(creature_id).any? rescue false)
  end

  def dm_actor_has_items?(creature_id)
    (consumable_spell_items(creature_id).any? ||
     granted_spell_items(creature_id).any?) rescue false
  end
end

# Clear the whole Roll Log (DM only).
post '/dm/clear' do
  halt 403 unless dm_view?
  RollLog.store.clear!
  redirect '/dm'
end

# Scene Round tracker (out-of-combat "round like Combat"). Advancing a Round
# also ticks the Chronicle clock forward one Round, matching a Combat Round.
post '/dm/round/next' do
  halt 403 unless dm_view?
  SceneRound.store.next!
  Chronicle.store.advance_time(rounds: SceneRound::ROUNDS_PER_STEP)
  redirect '/dm'
end

post '/dm/round/reset' do
  halt 403 unless dm_view?
  SceneRound.store.reset!
  redirect '/dm'
end
