require 'rack/test'
require 'json'
require 'cgi'

module Sessions
  # One emulated play session.
  #
  # Every action goes through the same HTTP endpoints the DM's browser
  # calls, in the same order: fetch the Action Builder, pick the options
  # the DM would click, resolve the Rolls the way the page resolves them
  # (scripted dice through the real Check Resolution — see DiceBridge),
  # then POST the payload the page would POST. Nothing reaches into a
  # domain object to shortcut a step; if the wiring between the builder
  # and the resolver breaks, a Session Test breaks with it.
  #
  # See docs/project/session_tests.md.
  class Session
    include Rack::Test::Methods

    DM_ADDR     = '127.0.0.1'.freeze
    PLAYER_ADDR = '192.168.1.50'.freeze

    attr_reader :campaign, :transcript

    def initialize(title, group: nil)
      @campaign   = Campaign.install!
      @transcript = Transcript.new(title, group: group)
    end

    def app
      Sinatra::Application
    end

    def finish!
      @transcript.write!
      @campaign.uninstall!
    end

    # ---------------- identity ----------------

    # A DM request: it originates on the server host, which is the whole
    # of the DM identification rule (CLAUDE.md → "DM vs. player").
    def dm_get(path, params = {})
      header 'Host', 'localhost'
      get path, params, 'REMOTE_ADDR' => DM_ADDR
      last_response
    end

    def dm_post(path, params = {})
      header 'Host', 'localhost'
      post path, params, 'REMOTE_ADDR' => DM_ADDR
      last_response
    end

    def dm_post_json(path, payload)
      header 'Host', 'localhost'
      post path, JSON.generate(payload),
           'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => DM_ADDR
      last_response
    end

    def player_post_json(path, payload)
      header 'Host', 'localhost'
      post path, JSON.generate(payload),
           'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => PLAYER_ADDR
      last_response
    end

    # A player request: any other address on the LAN.
    def player_get(path, params = {})
      header 'Host', 'localhost'
      get path, params, 'REMOTE_ADDR' => PLAYER_ADDR
      last_response
    end

    # ---------------- roster ----------------

    # Resolve a Creature by the name a scenario calls it.
    #
    # Spawned enemies inherit their template's name, so a scenario's own
    # label (spawn_enemy's `as:`) wins, then a Creature already on the
    # Encounter roster, then a plain roster record — the enemy template
    # itself is the last resort.
    def creature_id(name)
      return @aliases[name] if aliases.key?(name)
      matches = Creatures::Dataset.all.values.select { |r| r[:name] == name }
      raise ArgumentError, "no Creature named #{name.inspect} in the test Campaign" if matches.empty?
      on_roster = Encounter.state.combatants.map { |c| c[:creature_id].to_s }
      pick = matches.find { |r| on_roster.include?(r[:id].to_s) } ||
             matches.find { |r| !Array(r[:tags]).include?('enemy_template') } ||
             matches.first
      pick[:id]
    end

    def aliases
      @aliases ||= {}
    end

    def combatant_id(name)
      cid = creature_id(name)
      row = Encounter.state.combatants.find { |c| c[:creature_id].to_s == cid.to_s }
      raise ArgumentError, "#{name} is not on the Encounter roster" unless row
      row[:id]
    end

    def combatant(name)
      Encounter.state.combatant(combatant_id(name))
    end

    # Put a Creature on the Encounter roster the way the DM's sidebar does.
    def add_to_roster(*names)
      names.flatten.each do |name|
        res = dm_post('/encounter/add', creature_id: creature_id(name).to_s)
        raise "could not add #{name}: #{res.body}" unless res.status == 200
      end
      self
    end

    # Spawn an instance from an enemy template and add it to the roster,
    # as the DM's sidebar does. Pass `as:` to name this particular spawn
    # when a scenario fields more than one of the same template. Returns
    # the label the scenario should use from here on.
    def spawn_enemy(template_name, as: nil)
      template_id = Creatures::Dataset.all.values
                                      .select { |r| r[:name] == template_name }
                                      .find { |r| Array(r[:tags]).include?('enemy_template') }
                                      &.dig(:id) || creature_id(template_name)
      res = dm_post('/encounter/spawn_and_add', template_id: template_id.to_s)
      raise "could not spawn #{template_name}: #{res.body}" unless res.status == 200
      new_id = JSON.parse(res.body)['spawned_creature_id']
      label = as || template_name
      aliases[label] = new_id
      transcript.say("The DM spawns #{label} from the #{template_name} template")
      label
    end

    # ---------------- combat ----------------

    # Keep a Player Character off the roster (the sidebar's PC toggle).
    # Needed whenever a scenario wants a smaller party than the campaign
    # has: the Encounter page reconciles every Player Character onto the
    # roster otherwise.
    def exclude_from_combat(*names)
      names.flatten.each do |name|
        dm_post('/encounter/set_pc_active', creature_id: creature_id(name).to_s, active: 'false')
      end
      self
    end

    # Put an excluded Player Character back on the roster.
    def include_in_combat(*names)
      names.flatten.each do |name|
        dm_post('/encounter/set_pc_active', creature_id: creature_id(name).to_s, active: 'true')
      end
      self
    end

    # Advance turns until `name` is the Acting Combatant, the way the DM
    # clicks End Turn around the tracker. Raises rather than looping
    # forever if the Combatant never comes up.
    def take_turn(name)
      want = combatant_id(name)
      return self if Encounter.state.acting_combatant_id == want
      (Encounter.state.combatants.length * (Encounter.state.time_ticks_per_round.to_i + 1) + 2).times do
        advance_turn
        return self if Encounter.state.acting_combatant_id == want
      end
      raise "#{name} never became the Acting Combatant — turn order is " \
            "#{acting_this_tick.join(' → ')}"
    end

    def start_combat
      dm_post('/encounter/start_combat')
      transcript.say("Combat starts — #{roster_summary}")
      self
    end

    def end_combat
      dm_post('/encounter/end_combat')
      transcript.say('Combat ends')
      self
    end

    def advance_turn
      dm_post('/encounter/advance_turn')
      self
    end

    # Everyone on the roster with the Initiative String they rolled.
    def initiative_order
      Encounter.state.combatants.map { |c| creature_name(c[:creature_id]) }
    end

    def roster_summary
      Encounter.state.combatants.map do |c|
        "#{creature_name(c[:creature_id])} (#{c[:initiative_string].to_s.empty? ? 'no init' : c[:initiative_string]})"
      end.join(', ')
    end

    def combat_active?
      Encounter.state.combat_active?
    end

    # ---------------- casting ----------------

    # Cast a Spell exactly as the Cast pane does.
    #
    #   spell         the Spell (Variant) name, e.g. "Standard Ward"
    #   by:           caster Creature name
    #   on:           target Creature name (omit for an object / area /
    #                 self-only Spell)
    #   dice:         the caster's scripted dice
    #   save_dice:    the target's scripted Save / Defense dice
    #   defense:      defense branch key ("save:wis", "dodge", "block",
    #                 "none"); defaults to the only branch offered
    #   dice_count:   how many dice the caster commits (default: the most
    #                 the builder offers, which is what the lead button on
    #                 the page picks)
    #   item:         use the Item pane instead of the Cast pane
    #
    # Returns the parsed resolve_cast response.
    def cast(spell, by:, on: nil, dice: [], save_dice: [], defense: nil,
             dice_count: nil, skill: nil, item: false, commit: true, place: nil)
      caster_id = combatant_id(by)
      blob = builder_blob(item ? "/encounter/item_builder?actor_id=#{caster_id}"
                               : "/encounter/cast_builder?caster_id=#{caster_id}")
      builder = Builder.new(blob)

      option = builder.spell_option(spell)
      raise ArgumentError, "#{by} cannot cast #{spell.inspect} — the Cast pane offers " \
                           "#{builder.spell_names.join(', ')}" unless option
      raise ArgumentError, "#{spell} is offered but not affordable for #{by}" if option['disabled']
      builder.apply(option['patch'])
      key = option['key'] || option['value']

      dice_opt = builder.dice_option(key, count: dice.length.positive? ? dice.length : dice_count, skill: skill)
      builder.apply(dice_opt['patch']) if dice_opt

      target_id = on && combatant_id(on)
      target_opt = builder.target_option(key, target_id: target_id, place: place)
      builder.apply(target_opt['patch']) if target_opt

      defense_key = target_opt && (target_opt['key'] || target_opt['value'])
      defense_opt = builder.defense_option(key, target: defense_key, branch: defense)
      builder.apply(defense_opt['patch']) if defense_opt

      resolved = resolve_rolls(builder, caster: dice, target: save_dice)
      payload = {
        commit: commit,
        spell_name: option['spell_name'] || spell,
        spell: { name: option['spell_name'] || spell },
        caster: { id: caster_id, dice: builder.roll('caster')['dice_count'],
                  speed: builder.roll('caster')['speed'].to_i,
                  successes: resolved.dig('caster', :dois).to_i },
        targets: cast_targets(target_id, resolved, defense_opt)
      }
      payload[:placement] = place if place
      payload[:item] = blob.dig('items', key) if item && blob['items']

      res = dm_post_json('/encounter/resolve_cast', payload)
      body = parse_json(res)
      transcript.action(
        "#{by} casts #{spell}#{on ? " on #{on}" : ''}",
        rolls: transcript_rolls(by, on, resolved),
        outcome: cast_outcome(body)
      )
      body
    end

    # Cast an area Spell: place its footprint on the Atlas, then resolve
    # one Save per Creature caught in it (a Spread Check — the caster is
    # compared against each Opposer independently).
    #
    #   at:         { x:, y: } on the active Map
    #   affecting:  { "<creature name>" => [scripted save dice] }
    def cast_area(spell, by:, at:, affecting: {}, dice: [], dice_count: nil, commit: true)
      caster_id = combatant_id(by)
      blob = builder_blob("/encounter/cast_builder?caster_id=#{caster_id}")
      builder = Builder.new(blob)

      option = builder.spell_option(spell)
      raise ArgumentError, "#{by} cannot cast #{spell.inspect}" unless option
      builder.apply(option['patch'])
      key = option['key'] || option['value']

      dice_opt = builder.dice_option(key, count: dice.length.positive? ? dice.length : dice_count)
      builder.apply(dice_opt['patch']) if dice_opt

      place_opt = builder.target_option(key, place: true)
      raise ArgumentError, "#{spell} is not an area Spell — the Target step offers no placement" unless place_opt
      builder.apply(place_opt['patch'])
      builder.apply(builder.defense_option(key, target: 'place')&.dig('patch'))

      affected_ids = affecting.keys.map { |n| combatant_id(n) }
      save_rolls = area_save_rolls(caster_id, spell, affected_ids)

      specs = [roll_spec(builder.roll('caster'), dice)]
      affecting.each do |name, save_dice|
        cid = combatant_id(name)
        spec = save_rolls["save-#{cid}"]
        raise "#{name} is not in the footprint of #{spell}" unless spec
        specs << spec.merge(dice: save_dice)
      end
      resolved = DiceBridge.resolve(rolls: specs, spread: true)

      payload = {
        commit: commit, spell_name: option['spell_name'] || spell,
        spell: { name: option['spell_name'] || spell },
        caster: { id: caster_id, dice: builder.roll('caster')['dice_count'],
                  speed: builder.roll('caster')['speed'].to_i,
                  successes: resolved.dig('caster', :dois).to_i },
        placement: { x: at[:x], y: at[:y] },
        targets: affecting.keys.map do |name|
          { id: combatant_id(name),
            save: { successes: resolved.dig("save-#{combatant_id(name)}", :dois).to_i } }
        end
      }
      res = dm_post_json('/encounter/resolve_cast', payload)
      body = parse_json(res)
      rolls = { by => resolved['caster'] }
      affecting.each_key { |n| rolls[n] = resolved["save-#{combatant_id(n)}"] }
      transcript.action("#{by} places #{spell} at (#{at[:x]}, #{at[:y]})",
                        rolls: rolls.compact, outcome: cast_outcome(body))
      body
    end

    # A conjured weapon's strike (the Active Spells pane): the same attack
    # pipeline as a weapon attack, naming the Spell that owns the weapon.
    def strike_with(spell, by:, on:, dice: [], defense: 'none', defense_dice: [], commit: true)
      attacker_id = combatant_id(by)
      target_id   = combatant_id(on)
      blob = builder_blob("/encounter/active_spells_builder?attacker_id=#{attacker_id}")
      builder = Builder.new(blob)

      target_opt = builder.target_option(nil, target_id: target_id, step_key: 'target')
      builder.apply(target_opt['patch']) if target_opt

      action = builder.action_option(spell, count: dice.length.positive? ? dice.length : nil)
      raise ArgumentError, "#{by} has no #{spell} strike to make" unless action
      builder.apply(action['patch'])

      defense_opt = builder.defense_option(action['value'], target: target_id, branch: defense)
      builder.apply(defense_opt['patch']) if defense_opt

      resolved = resolve_attack_rolls(builder, attacker: dice, defender: defense_dice, shield: [])
      payload = {
        commit: commit, target_id: target_id,
        weapon_type: action['value'].to_s.split('|').first,
        active_spell_name: spell,
        attacker: { id: attacker_id, dice: builder.roll('attacker')['dice_count'],
                    speed: builder.roll('attacker')['speed'].to_i,
                    successes: resolved.dig('attacker', :dois).to_i },
        defense: defense.to_s == 'none' || defense_dice.empty? ? { choice: 'none' } :
                 { choice: defense.to_s.split(':').first, id: target_id,
                   dice: builder.roll('defender')['dice_count'],
                   speed: builder.roll('defender')['speed'].to_i,
                   successes: resolved.dig('defender', :dois).to_i }
      }
      res = dm_post_json('/encounter/resolve_attack', payload)
      body = parse_json(res)
      rolls = { by => resolved['attacker'] }
      rolls[on] = resolved['defender'] if resolved['defender']
      transcript.action("#{by}'s #{spell} strikes #{on}", rolls: rolls.compact,
                        outcome: attack_outcome(body))
      body
    end

    # ---------------- attacking ----------------

    # Attack as the Attack pane does.
    #
    #   defense:      the target's own Defensive Action branch — "dodge",
    #                 "block", "parry", "ringparry", or "none"
    #   shielded_by:  an ally interposing a Shield of Faith / Shield over
    #                 the target (the pane's Ally Defense step)
    #   shield_dice:  that shield's scripted dice
    #
    # Returns the parsed resolve_attack response.
    def attack(by:, on:, dice: [], defense: 'none', defense_dice: [],
               weapon: nil, shielded_by: nil, shield_dice: [], commit: true)
      attacker_id = combatant_id(by)
      target_id   = combatant_id(on)
      blob = builder_blob("/encounter/attack_builder?attacker_id=#{attacker_id}")
      builder = Builder.new(blob)

      target_opt = builder.target_option(nil, target_id: target_id, step_key: 'target')
      builder.apply(target_opt['patch']) if target_opt

      action = builder.action_option(weapon, count: dice.length.positive? ? dice.length : nil)
      raise ArgumentError, "#{by} has no attack to make" unless action
      builder.apply(action['patch'])
      action_key = action['value']

      defense_opt = builder.defense_option(action_key, target: target_id, branch: defense)
      builder.apply(defense_opt['patch']) if defense_opt

      shield_opt = nil
      if shielded_by
        shield_opt = builder.ally_defense_option(target_id, caster_id: combatant_id(shielded_by),
                                                 count: shield_dice.length)
        raise ArgumentError, "#{shielded_by} is not shielding #{on}" unless shield_opt
        builder.apply(shield_opt['patch'])
      end

      resolved = resolve_attack_rolls(builder, attacker: dice, defender: defense_dice,
                                      shield: shield_dice)
      payload = {
        commit: commit,
        target_id: target_id,
        weapon_type: action_key.to_s.split('|').first,
        attacker: { id: attacker_id, dice: builder.roll('attacker')['dice_count'],
                    speed: builder.roll('attacker')['speed'].to_i,
                    successes: resolved.dig('attacker', :dois).to_i }
      }
      payload[:defense] =
        if defense.to_s == 'none' || defense_dice.empty?
          { choice: 'none' }
        else
          { choice: defense.to_s.split(':').first, id: target_id,
            dice: builder.roll('defender')['dice_count'],
            speed: builder.roll('defender')['speed'].to_i,
            successes: resolved.dig('defender', :dois).to_i }
        end
      if shield_opt
        payload[:shield] = { id: combatant_id(shielded_by),
                             dice: shield_opt['value'].to_s.split('|').last.to_i,
                             successes: resolved.dig('shield', :dois).to_i }
      end

      res = dm_post_json('/encounter/resolve_attack', payload)
      body = parse_json(res)
      rolls = { by => resolved['attacker'] }
      rolls[on] = resolved['defender'] if resolved['defender']
      rolls["#{shielded_by} (shield)"] = resolved['shield'] if resolved['shield']
      transcript.action("#{by} attacks #{on}" \
                        "#{shielded_by ? " — shielded by #{shielded_by}" : ''}",
                        rolls: rolls.compact, outcome: attack_outcome(body))
      body
    end

    # ---------------- out-of-combat actions ----------------

    # Roll a Skill from a Character sheet the way a player does: the sheet
    # serves the compact Roll stub, the player rolls it, and the result is
    # POSTed to the Roll Log so the DM sees the dice.
    def skill_roll(by:, skill:, dice: [])
      cid = creature_id(by)
      res = dm_get('/skill-roll', creature_id: cid, key: skill)
      raise "#{by} cannot roll #{skill} (#{res.status})" unless res.status == 200
      config = JSON.parse(CGI.unescapeHTML(res.body[/data-config='([^']*)'/, 1]))
      meta   = JSON.parse(CGI.unescapeHTML(res.body[/data-meta='([^']*)'/, 1]))
      resolved = DiceBridge.resolve(rolls: [
        { id: 'roll', side: 'supporting',
          base_tn: config['base_tn'] || DiceResolution.config.base_target_number,
          bonus_penalty_list: config['bonus_penalty_list'] || [],
          dice_count: config['dice_count'], dice: dice }
      ])['roll']
      player_post_json('/dm/roll',
                       creature_id: cid, creature_name: by,
                       roll_name: meta['roll_name'] || skill,
                       tn: resolved[:tn], base_tn: config['base_tn'],
                       bonus_penalty_list: config['bonus_penalty_list'],
                       dice_count: config['dice_count'],
                       starting_value: resolved[:starting_value],
                       dice: dice, dois: resolved[:dois],
                       critical_count: resolved[:critical_count])
      transcript.action("#{by} rolls #{meta['roll_name'] || skill}",
                        rolls: { by => resolved },
                        outcome: resolved[:dois] >= 2 ? 'success' : 'failure')
      resolved
    end

    def roll_log
      RollLog.store.recent
    end

    # The DM Page's out-of-combat Round counter.
    def advance_scene_round
      dm_post('/dm/round/next')
      SceneRound.store.round
    end

    def scene_round
      SceneRound.store.round
    end

    # ---------------- afflictions ----------------

    # Resolve one Affliction save by hand, the way the DM confirms a save
    # in the Start of Turn pane. `dois` is the Degree of Individual
    # Success the save rolled.
    def resolve_affliction_save(name, affliction:, dois:)
      res = dm_post('/encounter/resolve_affliction',
                    combatant_id: combatant_id(name), affliction: affliction, dois: dois)
      body = parse_json(res)
      transcript.say("#{name}: #{affliction} save at #{dois} successes → " \
                     "potency #{afflictions(name).dig(affliction, :potency) || 'cleared'}")
      body
    end

    # Run the out-of-combat Affliction relief simulation (the Affliction
    # Relief stub): alternating Constitution saves and Heal channels, round
    # by round, until the Affliction clears. Seeded, so a scenario gets the
    # same run every time.
    def treat_affliction(name, affliction:, seed:, aiders: [], commit: true)
      res = dm_post('/encounter/resolve_affliction_run',
                    combatant_id: combatant_id(name), affliction: affliction,
                    commit: commit.to_s, seed: seed, aiders: JSON.generate(aiders))
      body = parse_json(res)
      result = body['result'] || {}
      transcript.say("#{name} is treated for #{affliction} (seed #{seed}) — " \
                     "#{result['rounds']} rounds, final HP #{result['final_hp']}")
      body
    end

    # Inflict an Affliction directly on a Creature.
    #
    # There is no DM control for this: Afflictions can only be applied by a
    # weapon that carries one (see the Marsh Adder's Bite) or by a Spell.
    # A scenario that needs a disease — nothing in the campaign inflicts
    # one — reaches into Conditions here, and the missing DM control is
    # recorded as a gap in docs/project/session_tests.md.
    def inflict(affliction, on:, potency:, inflicter_tier: 0)
      inst = conditions_for(on)
      inst.inflict_affliction(affliction.to_s, inflicter_tier: inflicter_tier,
                              delta: potency, current_round: absolute_round)
      Conditions.store.persist!
      transcript.say("#{on} contracts #{affliction} (potency #{potency})")
      afflictions(on)[affliction]
    end

    def absolute_round
      ts = timestamp
      (ts[:day_index] || ts['day_index']).to_i * Timekeeping.rounds_per_day +
        (ts[:round_of_day] || ts['round_of_day']).to_i
    end

    # ---------------- the store ----------------

    # Buy through the Store's cart checkout. `lines` are
    # { item:, for:, quantity:, tier: } hashes.
    def buy(lines)
      payload = { lines: Array(lines).map do |ln|
        line = { 'item' => ln[:item], 'recipient_id' => creature_id(ln[:for]).to_s,
                 'quantity' => ln[:quantity] || 1 }
        line['tier'] = ln[:tier] if ln[:tier]
        line['properties'] = ln[:properties] if ln[:properties]
        line
      end }
      res = dm_post_json('/store/checkout', payload)
      body = parse_json(res)
      transcript.say("At the Store: #{body['message'] || body.inspect[0, 120]}")
      body
    end

    # ---------------- time ----------------

    def advance_time(rounds: 0, days: 0)
      dm_post('/chronicle/advance-time', rounds: rounds, days: days)
      transcript.say("Time advances #{days} day(s), #{rounds} round(s) → #{clock}")
      self
    end

    def rest_night
      dm_post('/chronicle/rest-night')
      transcript.say("The party rests for the night → #{clock}")
      self
    end

    def set_time(year:, month:, day:, hour: 8, minute: 0)
      dm_post('/chronicle/set-time', year: year, month: month, day: day,
                                     hour: hour, minute: minute)
      transcript.say("The DM sets the clock → #{clock}")
      self
    end

    def timestamp
      Chronicle.store.timestamp
    end

    def day_index
      timestamp[:day_index] || timestamp['day_index']
    end

    # The campaign clock as the Chronicle shows it.
    def clock
      ts  = timestamp
      day = (ts[:day_index] || ts['day_index']).to_i
      rod = (ts[:round_of_day] || ts['round_of_day']).to_i
      date = Timekeeping.calendar_date(day)
      "day #{day} (#{date[:year]}-#{date[:month]}-#{date[:day_of_month]}, " \
        "#{date[:day_of_week]}) #{Timekeeping.time_of_day(rod)}"
    rescue StandardError
      timestamp.inspect
    end

    def calendar_date
      Timekeeping.calendar_date((timestamp[:day_index] || timestamp['day_index']).to_i)
    end

    def time_of_day
      Timekeeping.time_of_day((timestamp[:round_of_day] || timestamp['round_of_day']).to_i)
    end

    # ---------------- state queries ----------------

    def conditions_for(name)
      Conditions.store.instance_for(creature_id(name))
    end

    def hp_damage(name)
      conditions_for(name).state.hp_damage
    end

    def total_hp_damage(name)
      hp_damage(name).values.sum
    end

    def temp_hp(name)
      conditions_for(name).state.temporary_hit_points
    end

    def mana_spent(name)
      conditions_for(name).state.mana_spent
    end

    def toxicity(name)
      conditions_for(name).state.magic_toxicity
    end

    def effect_names(name)
      conditions_for(name).active_effect_names
    end

    def afflictions(name)
      conditions_for(name).state.afflictions
    end

    def combat_pool(name)
      Encounter.state.combat_pool_remaining(combatant_id(name))
    end

    # The Inventory of a Creature (by name) or of a bare Owner ID
    # ("party", "ground:<location>", "shop:<id>").
    def inventory(owner)
      owner_id = owner.to_s.include?(':') || owner.to_s == 'party' ? owner.to_s
                                                                   : "creature:#{creature_id(owner)}"
      Equipment.instance.get_inventory(owner_id)
    end

    def quantity_of(item, owner:)
      Array(inventory(owner)).select { |s| s.item_type.to_s.casecmp?(item.to_s) }
                             .sum { |s| s.quantity.to_f }
    end

    def gold(owner)
      owner_id = owner.to_s.include?(':') || owner.to_s == 'party' ? owner.to_s
                                                                   : "creature:#{creature_id(owner)}"
      Equipment.instance.get_total_wealth(owner_id)
    end

    # ---------------- internals ----------------

    private

    def creature_name(creature_id)
      rec = Creatures::Dataset.get(creature_id)
      rec ? rec[:name] : "creature #{creature_id}"
    end

    def builder_blob(path)
      res = dm_get(path)
      raise "builder request failed (#{res.status}): #{path}" unless res.status == 200
      match = res.body.match(/data-builder="([^"]*)"/)
      raise "no builder blob in the response for #{path}" unless match
      JSON.parse(CGI.unescapeHTML(match[1]))
    end

    def parse_json(res)
      JSON.parse(res.body)
    rescue JSON::ParserError
      raise "expected JSON, got #{res.status}: #{res.body[0, 200]}"
    end

    # Run every participating Roll through the browser's Check Resolution
    # with the scenario's scripted dice.
    def resolve_rolls(builder, caster:, target:)
      specs = [roll_spec(builder.roll('caster'), caster)]
      t = builder.roll('target')
      specs << roll_spec(t, target) if t && !t['excluded'] && target.any?
      DiceBridge.resolve(rolls: specs)
    end

    # One Save Roll spec per Creature caught in an area Spell's footprint,
    # parsed out of the roll-stub fragment the Cast pane swaps into its
    # dice table.
    def area_save_rolls(caster_id, spell, affected_ids)
      query = { caster_id: caster_id, spell: spell, 'affected' => affected_ids.map(&:to_s) }
      res = dm_get('/encounter/cast_area_rolls', query)
      raise "cast_area_rolls failed (#{res.status})" unless res.status == 200
      res.body.scan(/data-roll-id="([^"]+)"([^>]*)data-config='([^']*)'/).each_with_object({}) do |(id, attrs, cfg), h|
        config = JSON.parse(CGI.unescapeHTML(cfg))
        h[id] = { id: id, side: attrs[/data-side="([^"]+)"/, 1] || 'opposing',
                  base_tn: config['base_tn'] || DiceResolution.config.base_target_number,
                  bonus_penalty_list: config['bonus_penalty_list'] || [],
                  dice_count: config['dice_count'] }
      end
    end

    def resolve_attack_rolls(builder, attacker:, defender:, shield:)
      specs = [roll_spec(builder.roll('attacker'), attacker)]
      d = builder.roll('defender')
      specs << roll_spec(d, defender) if d && !d['excluded'] && defender.any?
      sh = builder.roll('shield')
      specs << roll_spec(sh, shield) if sh && !sh['excluded'] && shield.any?
      DiceBridge.resolve(rolls: specs)
    end

    def attack_outcome(body)
      return 'refused' unless body.is_a?(Hash)
      return body['error'] if body['error']
      bits = []
      bits << body['outcome'] if body['outcome']
      bits << "#{body['damage']} damage" if body['damage']
      bits << "net #{body['net_dos']}" if body['net_dos']
      bits.empty? ? 'resolved' : bits.join(', ')
    end

    def roll_spec(roll, dice)
      { id: roll['id'], side: roll['side'],
        base_tn: roll['base_tn'] || DiceResolution.config.base_target_number,
        bonus_penalty_list: roll['bonus_penalty_list'] || [],
        no_propagate: roll['no_propagate'] || [],
        dice_count: roll['dice_count'], dice: dice }
    end

    def cast_targets(target_id, resolved, defense_opt)
      return [] unless target_id
      branch = defense_opt ? defense_opt['value'].to_s.split('|').first.to_s : ''
      successes = resolved.dig('target', :dois).to_i
      if branch.start_with?('save')
        [{ id: target_id, save: { successes: successes } }]
      elsif %w[dodge block].include?(branch)
        [{ id: target_id, defense: { choice: branch, successes: successes } }]
      elsif branch == 'none'
        [{ id: target_id, defense: { choice: 'none' } }]
      else
        [{ id: target_id }]
      end
    end

    def transcript_rolls(by, on, resolved)
      out = { by => resolved['caster'] }
      out[on] = resolved['target'] if on && resolved['target']
      out.compact
    end

    def cast_outcome(body)
      return 'refused' unless body.is_a?(Hash)
      return body['error'] if body['error']
      parts = []
      parts << "mana #{body['mana']}" if body['mana']
      Array(body['targets']).each do |t|
        parts << "#{t['outcome'] || 'hit'}#{t['damage'] ? " #{t['damage']} damage" : ''}"
      end
      parts.empty? ? 'resolved' : parts.join(', ')
    end
  end

  # The Ruby counterpart of public/js/ui/actionBuilder.js: holds the
  # builder blob's Rolls and applies an option's patch to them, so the
  # Roll a Session Test resolves is the Roll the page would have shown.
  class Builder
    # "Spiritual Weapon", "spiritual_weapon" and "Spiritual Weapon (5)" all
    # name the same action; the blob is inconsistent about which form it
    # uses, so options are matched on a normalized slug.
    def self.slug(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')
    end

    def initialize(blob)
      @blob  = blob
      @rolls = (blob['rolls'] || []).each_with_object({}) { |r, h| h[r['id']] = r.dup }
    end

    def roll(id)
      @rolls[id]
    end

    def step(key)
      Array(@blob['steps']).find { |s| s['key'] == key }
    end

    def spell_names
      Array(step('spell')&.dig('options')).filter_map { |o| o['spell_name'] }
    end

    def spell_option(name)
      Array(step('spell')&.dig('options')).find do |o|
        o['spell_name'] == name || o['summary'] == name || o['label'] == name
      end
    end

    # The Attack pane's "Weapon & dice" step. Its option values are
    # "<weapon>|<dice>", so a scenario picks the weapon and the number of
    # dice it commits in one click, exactly as the DM does.
    def action_option(label, count: nil)
      opts = Array(step('action')&.dig('options')).reject { |o| o['kind'] == 'info' || o['disabled'] }
      if label
        want = Builder.slug(label)
        opts = opts.select do |o|
          [o['value'].to_s.split('|').first, o['summary'], o['label']]
            .compact.any? { |v| Builder.slug(v).include?(want) }
        end
      end
      if count
        exact = opts.find { |o| o['value'].to_s.split('|').last == count.to_s }
        return exact if exact
      end
      opts.first
    end

    # The Ally Defense step: an ally interposing their Shield of Faith /
    # Shield over the target. Values are "shield:<casterCombatantId>|<dice>".
    def ally_defense_option(target_id, caster_id:, count: nil)
      opts = Array(step('ally_defense')&.dig('options_map')&.dig(target_id.to_s))
             .reject { |o| o['kind'] == 'info' }
      opts = opts.select { |o| o['value'].to_s.split('|').first == "shield:#{caster_id}" }
      return nil if opts.empty?
      if count && count.positive?
        exact = opts.find { |o| o['value'].to_s.split('|').last == count.to_s && !o['disabled'] }
        return exact if exact
      end
      opts.reject { |o| o['disabled'] }.first || opts.first
    end

    # The Dice step is keyed by the chosen Spell / action; each option's
    # value is "<key>|<skill>|<count>".
    def dice_option(key, count: nil, skill: nil)
      opts = Array(step('dice')&.dig('options_map')&.dig(key.to_s))
      opts = opts.reject { |o| o['kind'] == 'info' }
      return nil if opts.empty?
      opts = opts.select { |o| o['value'].to_s.split('|')[1] == skill.to_s } if skill
      pick = if count
               opts.find { |o| o['value'].to_s.split('|').last == count.to_s && !o['disabled'] }
             end
      pick || opts.reject { |o| o['disabled'] }.first || opts.first
    end

    def target_option(key, target_id: nil, place: nil, step_key: nil)
      target_step = step('target')
      opts = if step_key || key.nil?
               Array(target_step&.dig('options')) +
                 Array(target_step&.dig('options_map')&.values).flatten
             else
               Array(target_step&.dig('options_map')&.dig(key.to_s))
             end
      return nil if opts.empty?
      return opts.find { |o| o['key'].to_s == 'place' } if place
      if target_id
        found = opts.find { |o| (o['key'] || o['value']).to_s == target_id.to_s }
        return found if found
      end
      opts.find { |o| o['auto'] } || opts.first
    end

    def defense_option(key, target:, branch: nil)
      map = step('defense')&.dig('options_map') || {}
      opts = Array(map["#{target}|#{key}"]).reject { |o| o['kind'] == 'info' }
      return nil if opts.empty?
      if branch
        found = opts.find { |o| o['value'].to_s.split('|').first == branch.to_s && !o['disabled'] }
        return found if found
      end
      opts.find { |o| o['auto'] } || opts.reject { |o| o['disabled'] }.first || opts.first
    end

    # Apply one option's patch — the same five mutations actionBuilder.js
    # understands.
    def apply(patch)
      return self if patch.nil?
      # Same order as actionBuilder.js#_applyPatch.
      mutate(patch['set_dice'])  { |r, p| r['dice_count'] = p['count']; r['_base_dice'] = nil }
      mutate(patch['scale_dice']) do |r, p|
        r['_base_dice'] ||= r['dice_count']
        scaled = (r['_base_dice'].to_i * (p['num'] || 1) / (p['den'] || 1)).floor
        r['dice_count'] = [r['_base_dice'].to_i, [p['min'] || 1, scaled].max].min
      end
      mutate(patch['restore_dice']) do |r, _p|
        r['dice_count'] = r['_base_dice'] if r['_base_dice']
        r['_base_dice'] = nil
      end
      mutate(patch['set_speed'])        { |r, p| r['speed'] = p['speed'] }
      mutate(patch['set_bpl'])          { |r, p| r['bonus_penalty_list'] = p['bonus_penalty_list'] || [] }
      mutate(patch['set_no_propagate']) { |r, p| r['no_propagate'] = p['types'] || [] }
      mutate(patch['set_name'])         { |r, p| r['roll_name'] = p['roll_name'] if p['roll_name'] }
      mutate(patch['set_excluded'])     { |r, p| r['excluded'] = p['excluded'] }
      self
    end

    private

    def mutate(entries)
      Array(entries).each do |p|
        r = @rolls[p['id']]
        yield(r, p) if r
      end
    end
  end
end
