require 'sinatra'
require 'json'
require_relative 'helpers'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false

enable :sessions

helpers CharacterHelpers

def local_request?
  request.ip == "127.0.0.1" || request.ip == "::1" || request.ip == "localhost"
end

before do
  @is_local = local_request?
  @view_as_player = local_request? && session[:view_mode] == 'player'
  @is_local = false if @view_as_player
end

post '/view_mode' do
  redirect '/' unless local_request?
  session[:view_mode] = params[:mode]
  referrer = request.referrer || '/'
  if params[:mode] == 'dm' && referrer =~ /\/notes\/\d+/
    redirect '/notes/0'
  else
    redirect back
  end
end

def load_character_view(character_list, index, route_prefix)
  halt 404, "No characters found" if character_list.empty?
  index = index % character_list.length

  @total_characters = character_list.length
  @prev_index = (index - 1) % character_list.length
  @next_index = (index + 1) % character_list.length

  @character = get_info(character_list[index])
  @compendium = Compendium.new

  @current_index = index
  @route_prefix = route_prefix

  erb :character_sheet
end

get '/combat' do
  redirect '/character/0' unless local_request?
  @combat = Combat.new()
  erb :combat_tracker
end

post '/combat/update/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
  Combat.update(id, {
    'minor_damage' => params[:minor_damage],
    'moderate_damage' => params[:moderate_damage],
    'major_damage' => params[:major_damage],
    'mana' => params[:mana],
    'combat_pool' => params[:combat_pool],
    'saturation' => params[:saturation],
    'temporary_hit_points' => params[:temporary_hit_points]
  }, set_keys: %w[minor_damage moderate_damage major_damage mana combat_pool saturation temporary_hit_points])
  redirect '/combat'
end

post '/combat/sat/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
  Combat.update(id, {saturation: params[:amount]}, set_keys: ['saturation'])
  redirect '/combat'
end

post '/combat/reset_dice' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
  combat.new_turn
  redirect '/combat'
end

post '/combat/action' do
  redirect '/character/0' unless local_request?
  combat = Combat.new
  combat_data = Tools.load_json('combat.json')
  combat_id = params[:id].to_i
  action = params[:combat_action]

  if action == 'attack'
    attacker_combat_id = params[:attacker_combat_id].to_i
    target_combat_id = params[:target_combat_id].to_i
    attacker_dice_spent = params[:attacker_dice_spent].to_i
    defense_dice = params[:defense_dice].to_i
    target_mana_cost = params[:target_mana_cost].to_i
    minor = params[:minor_damage].to_i
    moderate = params[:moderate_damage].to_i
    major = params[:major_damage].to_i

    attacker = combat_data['participants'].find { |p| p['id'] == attacker_combat_id }
    target_participant = combat_data['participants'].find { |p| p['id'] == target_combat_id }
    halt 400, "Attacker not found" unless attacker
    halt 400, "Target not found" unless target_participant

    attacker['combat_pool'] = attacker['combat_pool'].to_i - attacker_dice_spent if attacker_dice_spent > 0
    target_participant['combat_pool'] = target_participant['combat_pool'].to_i - defense_dice if defense_dice > 0
    target_participant['mana'] = target_participant['mana'].to_i - target_mana_cost if target_mana_cost > 0

    incoming_total = minor + moderate + major

    # Temp HP absorbs incoming damage worst-first (major -> moderate -> minor).
    temp_hp = target_participant['temporary_hit_points'].to_i
    absorbed_major = [major, temp_hp].min; temp_hp -= absorbed_major
    absorbed_moderate = [moderate, temp_hp].min; temp_hp -= absorbed_moderate
    absorbed_minor = [minor, temp_hp].min; temp_hp -= absorbed_minor
    target_participant['temporary_hit_points'] = temp_hp
    major -= absorbed_major
    moderate -= absorbed_moderate
    minor -= absorbed_minor

    target_participant['minor_damage'] = target_participant['minor_damage'].to_i + minor
    target_participant['moderate_damage'] = target_participant['moderate_damage'].to_i + moderate
    target_participant['major_damage'] = target_participant['major_damage'].to_i + major

    # Apply per-attack conditions when the hit lands (incoming_total > 0).
    # The weapon used is identified by weapon_item_id sent from the client;
    # the attacker's CharacterSheet.weapon_list includes both carried items
    # and natural weapons (ghoul's bite/claws, etc.).
    if incoming_total > 0 && params[:weapon_item_id] && !params[:weapon_item_id].to_s.empty?
      weapon_item_id = params[:weapon_item_id].to_i
      attacker_char_id = attacker['char_id'] || attacker['id']
      attacker_data = Tools.load_json('characters.json').find { |c| c['id'] == attacker_char_id }
      if attacker_data
        attacker_sheet = CharacterSheet.new(attacker_data)
        weapon = attacker_sheet.weapon_list.find { |w| w['item_id'] == weapon_item_id }
        if weapon
          details = weapon.dig('properties', 'details') || []
          is_ranged = details.include?('ranged')
          is_natural = weapon.dig('properties', 'natural') == true

          target_participant['conditions'] ||= {}
          target_participant['condition_meta'] ||= {}

          # Bleed: melee hit -> damage + weapon's bleed rating.
          unless is_ranged
            weapon_bleed = attacker_sheet.weapon_bleed(weapon)
            weapon_bleed = weapon_bleed.is_a?(Numeric) ? weapon_bleed : 0
            target_participant['conditions']['bleed'] =
              target_participant['conditions']['bleed'].to_i + incoming_total + weapon_bleed
          end

          # Ghoul paralysis: attacker with ghoul_paralysis ability making a
          # natural attack -> damage + attacker's tier. Track the highest
          # ghoul tier that has hit this target; it modifies save TN until
          # the condition decays to 0 (at which point it resets).
          if is_natural && attacker_sheet.race_abilities.include?('ghoul_paralysis')
            target_participant['conditions']['ghoul_paralysis'] =
              target_participant['conditions']['ghoul_paralysis'].to_i + incoming_total + attacker_sheet.tier.to_i
            target_participant['condition_meta']['max_ghoul_tier'] =
              [target_participant['condition_meta']['max_ghoul_tier'].to_i, attacker_sheet.tier.to_i].max
          end
        end
      end
    end

    # Subtract ally dice spent
    ally_data = params[:ally_data] || ''
    ally_data.split(';').each do |entry|
      next if entry.empty?
      aid, adice = entry.split(':').map(&:to_i)
      ally = combat_data['participants'].find { |p| p['id'] == aid }
      ally['combat_pool'] = ally['combat_pool'].to_i - adice if ally && adice > 0
    end

    # Subtract mana from Healing Word casters
    hw_data = params[:healing_word_data] || ''
    hw_data.split(';').each do |entry|
      next if entry.empty?
      hid, hcost = entry.split(':').map(&:to_i)
      healer = combat_data['participants'].find { |p| p['id'] == hid }
      healer['mana'] = healer['mana'].to_i - hcost if healer && hcost > 0
    end

    Tools.save_json('combat.json', combat_data)

    total = minor + moderate + major
    absorbed = absorbed_major + absorbed_moderate + absorbed_minor
    if total > 0 || absorbed > 0
      suffix = absorbed > 0 ? " (#{absorbed} absorbed by temp HP)" : ""
      Combat.add_log("Attack resolved: #{total} damage (#{minor}/#{moderate}/#{major})#{suffix}")
    else
      Combat.add_log("Attack missed")
    end

  elsif action == 'move'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    halt 400, "Not enough dice to move" unless participant['combat_pool'] >= 4

    participant['combat_pool'] -= 4
    Tools.save_json('combat.json', combat_data)

    Combat.add_log("#{character.name} moves")

  elsif action == 'cast'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    halt 400, "Participant not found" unless participant
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    spell_name = params[:spell_name]
    spell_tier = params[:spell_tier].to_i
    mana_cost = spell_tier == 0 ? 1 : (spell_tier * 2 + 2)
    concentration = params[:concentration] == 'true'

    halt 400, "Not enough mana" unless participant['mana'].to_i >= mana_cost

    # Accept either a single target_combat_id or a comma-separated
    # target_combat_ids list (for multi-target spells). Single-target
    # effect branches (cure, ward) use the first id; the generic branch
    # iterates the full list.
    target_ids = if params[:target_combat_ids] && !params[:target_combat_ids].to_s.empty?
      params[:target_combat_ids].to_s.split(',').map { |s| s.strip.to_i }.reject(&:zero?)
    elsif params[:target_combat_id] && !params[:target_combat_id].to_s.empty?
      [params[:target_combat_id].to_i]
    else
      []
    end
    target_combat_id = target_ids.first

    compendium = Compendium.new
    cure = compendium.cure_effects(spell_name)
    ward = compendium.ward_effects(spell_name)

    if ward
      halt 400, "Ward spell requires a target" unless target_combat_id
      target = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target
      target_char_id = target['char_id'] || target['id']
      target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
      halt 400, "Target character not found" unless target_data
      target_character = CharacterSheet.new(target_data)

      current_temp = target['temporary_hit_points'].to_i
      new_temp = [current_temp, ward[:temp_hp]].max
      target['temporary_hit_points'] = new_temp

      participant['mana'] = participant['mana'].to_i - mana_cost
      Tools.save_json('combat.json', combat_data)
      Combat.add_log("#{character.name} casts #{spell_name} on #{target_character.name} (#{mana_cost} mana) - temp HP #{current_temp} -> #{new_temp}")
    elsif cure
      halt 400, "Cure spell requires a target" unless target_combat_id
      target = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target
      target_char_id = target['char_id'] || target['id']
      target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
      halt 400, "Target character not found" unless target_data
      target_character = CharacterSheet.new(target_data)

      max_saturation = target_character.cha
      current_saturation = target['saturation'].to_i
      if current_saturation >= max_saturation
        halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})"
      end

      healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target, cure)

      # Saturation: reduce by target tier, and by 2*caster_tier if caster has improved_healing.
      # Floor at minimum_saturation.
      sat_add = cure[:saturation] - target_character.tier
      sat_add -= 2 * character.tier if character.ability_list.include?("improved_healing")
      sat_add = cure[:minimum_saturation] if sat_add < cure[:minimum_saturation]
      target['saturation'] = current_saturation + sat_add

      participant['mana'] = participant['mana'].to_i - mana_cost
      Tools.save_json('combat.json', combat_data)

      Combat.add_log("#{character.name} casts #{spell_name} on #{target_character.name} (#{mana_cost} mana) - healed #{healed_major}/#{healed_moderate}/#{healed_minor} (major/moderate/minor), +#{sat_add} saturation")
    else
      target_names = []
      target_ids.each do |tid|
        target = combat_data['participants'].find { |p| p['id'] == tid }
        next unless target
        target_char_id = target['char_id'] || target['id']
        target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
        target_names << CharacterSheet.new(target_data).name if target_data
      end

      participant['mana'] = participant['mana'].to_i - mana_cost
      if concentration
        combat_data['active_effects'] ||= []
        combat_data['active_effects'] << {
          'caster_id' => combat_id,
          'caster_name' => character.name,
          'spell_name' => spell_name,
          'spell_tier' => spell_tier,
          'round_cast' => combat_data['round'],
          'target_combat_ids' => target_ids,
          'target_names' => target_names
        }
      end
      Tools.save_json('combat.json', combat_data)
      suffix = target_names.empty? ? "" : " on #{target_names.join(', ')}"
      Combat.add_log("#{character.name} casts #{spell_name}#{suffix} (#{mana_cost} mana)")
    end

  elsif action == 'item'
    user_participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    halt 400, "Participant not found" unless user_participant
    user_char_id = user_participant['char_id'] || user_participant['id']
    user_character_data = Tools.load_json('characters.json').find { |c| c['id'] == user_char_id }
    user_character = CharacterSheet.new(user_character_data)

    item_id = params[:item_id].to_i
    item = user_character.item_list.find { |i| i['item_id'].to_i == item_id }
    halt 400, "Item not found" unless item

    compendium = Compendium.new
    effect = compendium.item_effects(item)
    halt 400, "This item cannot be used" unless effect

    item_target_mode = effect[:target_mode].to_s
    item_target_mode = "single" if item_target_mode.empty?

    # Parse targets. Accept target_combat_ids (comma-separated) for multi-target
    # scrolls, or target_combat_id for the single-target flow. For no-target
    # items we don't require any id; otherwise default to self.
    raw_multi = params[:target_combat_ids].to_s
    target_ids = if !raw_multi.empty?
      raw_multi.split(',').map { |s| s.strip.to_i }.reject(&:zero?)
    elsif params[:target_combat_id] && !params[:target_combat_id].to_s.empty?
      [params[:target_combat_id].to_i]
    elsif item_target_mode == "none"
      []
    else
      [combat_id]
    end

    # Single-target branches (all potions, and scroll cure/ward/mana) use
    # the first target. No-target items skip resolution entirely.
    target_combat_id = target_ids.first
    if item_target_mode == "none"
      target = nil
      target_character = nil
      max_saturation = 0
      current_saturation = 0
      at_max = false
    else
      target = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target
      target_char_id = target['char_id'] || target['id']
      target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
      halt 400, "Target character not found" unless target_data
      target_character = CharacterSheet.new(target_data)
      max_saturation = target_character.cha
      current_saturation = target['saturation'].to_i
      at_max = current_saturation >= max_saturation
    end

    effect_log = ""

    if effect[:kind] == :potion
      # Potions always cause saturation (flat potion rule), so blocked at max.
      halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max

      potion_sat = Compendium.potion_saturation(effect[:item_tier], target_character.tier)

      case effect[:type]
      when :cure
        healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target, effect)
        # Cure spell saturation rules (no improved_healing for potions)
        # PLUS the potion's own saturation on top.
        cure_sat = effect[:saturation] - target_character.tier
        cure_sat = effect[:minimum_saturation] if cure_sat < effect[:minimum_saturation]
        total_sat = cure_sat + potion_sat
        target['saturation'] = current_saturation + total_sat
        effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{total_sat} saturation (#{cure_sat} cure + #{potion_sat} potion)"

      when :mana
        target_max_mana = target_character.mana_max
        current_mana = target['mana'].to_i
        new_mana = [current_mana + effect[:mana], target_max_mana].min
        target['mana'] = new_mana
        target['saturation'] = current_saturation + potion_sat
        effect_log = "mana #{current_mana} -> #{new_mana}, +#{potion_sat} saturation"

      when :ward
        current_temp = target['temporary_hit_points'].to_i
        new_temp = [current_temp, effect[:temp_hp]].max
        target['temporary_hit_points'] = new_temp
        target['saturation'] = current_saturation + potion_sat
        effect_log = "temp HP #{current_temp} -> #{new_temp}, +#{potion_sat} saturation"
      end

    elsif effect[:kind] == :scroll
      # Scrolls act like casting the underlying spell with no mana cost.
      # Full spell saturation rules apply (including improved_healing for cures),
      # and scrolls with unrecognized spell effects are still consumable.
      case effect[:type]
      when :cure
        halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max

        healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target, effect)
        sat_add = effect[:saturation] - target_character.tier
        sat_add -= 2 * user_character.tier if user_character.ability_list.include?("improved_healing")
        sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
        target['saturation'] = current_saturation + sat_add
        effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{sat_add} saturation"

      when :mana
        halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max

        target_max_mana = target_character.mana_max
        current_mana = target['mana'].to_i
        new_mana = [current_mana + effect[:mana], target_max_mana].min
        target['mana'] = new_mana
        # Recharge is universal school, not healing -- improved_healing does not apply.
        sat_add = effect[:saturation] - target_character.tier
        sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
        target['saturation'] = current_saturation + sat_add
        effect_log = "mana #{current_mana} -> #{new_mana}, +#{sat_add} saturation"

      when :ward
        # Ward has no saturation when cast, so no max-sat block.
        current_temp = target['temporary_hit_points'].to_i
        new_temp = [current_temp, effect[:temp_hp]].max
        target['temporary_hit_points'] = new_temp
        effect_log = "temp HP #{current_temp} -> #{new_temp}"

      when :generic
        # Spell effect not yet implemented. Scroll is still consumed.
        # Collect target names (for multi-target scrolls, all selected targets).
        generic_names = []
        target_ids.each do |tid|
          p = combat_data['participants'].find { |x| x['id'] == tid }
          next unless p
          pc_id = p['char_id'] || p['id']
          pd = Tools.load_json('characters.json').find { |c| c['id'] == pc_id }
          generic_names << CharacterSheet.new(pd).name if pd
        end
        suffix = generic_names.empty? ? "" : " on #{generic_names.join(', ')}"
        effect_log = "casts #{effect[:variant_name] || item['name']}#{suffix} (no implemented effect)"
      end
    end

    # Consume one charge. item_ids in equipment.json are ephemeral positional
    # ids (i + 1), so the stored index is simply item_id - 1. Inline character
    # items use negative item_ids and live in characters.json instead.
    if item['item_id'].to_i > 0
      equipment = Tools.load_json('equipment.json')
      stored_idx = item_id - 1
      if stored_idx >= 0 && stored_idx < equipment.length
        stored = equipment[stored_idx]
        stored['quantity'] = (stored['quantity'] || 1) - 1
        equipment.delete_at(stored_idx) if stored['quantity'] <= 0
        Tools.save_json('equipment.json', equipment)
      end
    else
      # Inline item id is -(position + 1), so position is -id - 1.
      characters = Tools.load_json('characters.json')
      owner = characters.find { |c| c['id'] == user_char_id }
      if owner && owner['items']
        inline_idx = -item['item_id'].to_i - 1
        if inline_idx >= 0 && inline_idx < owner['items'].length
          inline = owner['items'][inline_idx]
          inline['quantity'] = (inline['quantity'] || 1) - 1
          owner['items'].delete_at(inline_idx) if inline['quantity'] <= 0
          Tools.save_json('characters.json', characters)
        end
      end
    end

    Tools.save_json('combat.json', combat_data)
    # Single-target branches name `target_character`; the multi-target /
    # no-target scroll-generic branch embeds names (or nothing) in effect_log.
    generic_multi_or_none = effect[:kind] == :scroll && effect[:type] == :generic && target_ids.length != 1
    log_prefix = if generic_multi_or_none || target_character.nil?
      "#{user_character.name} uses #{item['name']}"
    else
      "#{user_character.name} uses #{item['name']} on #{target_character.name}"
    end
    Combat.add_log("#{log_prefix} - #{effect_log}")

  elsif action == 'dismiss_effect'
    effect_index = params[:effect_index].to_i
    combat_data['active_effects'] ||= []
    removed = combat_data['active_effects'].delete_at(effect_index)
    Tools.save_json('combat.json', combat_data)
    Combat.add_log("#{removed['spell_name']} ended") if removed

  elsif action == 'end_turn'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    Combat.add_log("#{character.name} ends turn")
    Combat.advance_turn

  elsif action == 'start_of_turn'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    halt 400, "Participant not found" unless participant
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    log_lines = ["#{character.name} starts turn"]

    # Step 1: decrement rounds_remaining on active_effects targeting this
    # combatant; remove effects whose counter hits 0. Effects with no
    # rounds_remaining field (e.g. concentration spells) are untouched.
    combat_data['active_effects'] ||= []
    combat_data['active_effects'].reject! do |effect|
      next false unless effect['rounds_remaining']
      target_ids = effect['target_combat_ids'] || []
      next false unless target_ids.include?(combat_id)
      effect['rounds_remaining'] = effect['rounds_remaining'].to_i - 1
      if effect['rounds_remaining'] <= 0
        log_lines << "  #{effect['spell_name']} ends on #{character.name}"
        true
      else
        false
      end
    end

    # Step 2: resolve each active condition in insertion order. The client
    # submits save results as `successes_<name>` (integer) for each.
    participant['conditions'] ||= {}
    participant['condition_meta'] ||= {}
    participant['conditions'].keys.each do |cname|
      value = participant['conditions'][cname].to_i
      next if value <= 0
      successes_param = params["successes_#{cname}".to_sym] || params["successes_#{cname}"]
      successes = successes_param.to_i

      case cname
      when 'bleed'
        # 1 point + 1 per 10 severity, reduced by 1 per success, min 0.
        raw_damage = 1 + (value / 10)
        dealt = [raw_damage - successes, 0].max
        if dealt > 0
          temp_hp = participant['temporary_hit_points'].to_i
          absorbed = [dealt, temp_hp].min
          participant['temporary_hit_points'] = temp_hp - absorbed
          remaining = dealt - absorbed
          if remaining > 0
            participant['minor_damage'] = participant['minor_damage'].to_i + remaining
          end
          absorb_suffix = absorbed > 0 ? " (#{absorbed} absorbed by temp HP)" : ""
          log_lines << "  Bleed save (#{successes} successes): #{dealt} minor damage#{absorb_suffix}"
        else
          log_lines << "  Bleed save (#{successes} successes): no damage"
        end
      when 'ghoul_paralysis'
        # Paralysis rounds mirrors the bleed formula:
        # rounds = (1 + severity/10) - successes, floor 0. If any rounds
        # result, add them to the existing Paralyzed effect (stacking) or
        # create a new one if the target isn't already paralyzed.
        raw_rounds = 1 + (value / 10)
        rounds = [raw_rounds - successes, 0].max
        if rounds > 0
          existing = combat_data['active_effects'].find do |e|
            e['spell_name'] == 'Paralyzed' && (e['target_combat_ids'] || []).include?(combat_id)
          end
          if existing
            existing['rounds_remaining'] = existing['rounds_remaining'].to_i + rounds
            log_lines << "  Ghoul paralysis save (#{successes} successes): +#{rounds} paralysis round#{'s' unless rounds == 1} (now #{existing['rounds_remaining']})"
          else
            combat_data['active_effects'] << {
              'caster_id' => nil,
              'caster_name' => 'Ghoul Paralysis',
              'spell_name' => 'Paralyzed',
              'target_combat_ids' => [combat_id],
              'target_names' => [character.name],
              'round_cast' => combat_data['round'],
              'rounds_remaining' => rounds
            }
            log_lines << "  Ghoul paralysis save (#{successes} successes): PARALYZED for #{rounds} round#{'s' unless rounds == 1}"
          end
        else
          log_lines << "  Ghoul paralysis save (#{successes} successes): no paralysis (#{raw_rounds} blocked)"
        end
      else
        log_lines << "  #{cname.tr('_', ' ').capitalize} save (#{successes} successes)"
      end

      # Universal decay: reduce severity by 1 + successes, floor 0.
      new_value = [value - (1 + successes), 0].max
      if new_value <= 0
        participant['conditions'].delete(cname)
        # Clear any meta tied to this condition ending.
        if cname == 'ghoul_paralysis'
          participant['condition_meta'].delete('max_ghoul_tier')
        end
        log_lines << "  #{cname.tr('_', ' ').capitalize} ends"
      else
        participant['conditions'][cname] = new_value
      end
    end

    Tools.save_json('combat.json', combat_data)
    log_lines.each { |line| Combat.add_log(line) }

  end

  redirect '/combat'
end

post '/combat/reroll_init' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
  combat.reroll_init
  redirect '/combat'
end

post '/combat/set_turn/:id' do
  redirect '/character/0' unless local_request?
  Combat.set_current_turn(params[:id].to_i)
  redirect '/combat'
end

get '/' do
  redirect '/character/0'
end

get '/character/:index' do
  character_list = Tools.load_json('characters.json').select { |character| character["group"] == "PC" }
  load_character_view(character_list, params[:index].to_i, '/character')
end

get '/enemies/:index' do
  redirect '/character/0' unless local_request?
  characters = Tools.load_json('characters.json')
  enemy_list = characters.select { |c| c["group"] != "PC" }
  halt 404, "No enemies found" if enemy_list.empty?

  index = params[:index].to_i % enemy_list.length
  @total_characters = enemy_list.length
  @prev_index = (index - 1) % enemy_list.length
  @next_index = (index + 1) % enemy_list.length
  @current_index = index
  @route_prefix = '/enemies'

  @character = get_info(enemy_list[index])
  @compendium = Compendium.new
  @enemy_list = enemy_list.each_with_index.map { |e, i| { index: i, id: e['id'], name: e['name'] } }

  combat_data = Tools.load_json('combat.json')
  @combat_participants = combat_data['participants']

  erb :enemies
end

post '/combat/add_enemy' do
  redirect '/character/0' unless local_request?
  enemy_id = params[:enemy_id].to_i
  combat_data = Tools.load_json('combat.json')
  characters = Tools.load_json('characters.json')

  enemy = characters.find { |c| c['id'] == enemy_id }
  halt 400, "Enemy not found" unless enemy

  # Generate a unique combat ID
  max_id = combat_data['participants'].map { |p| p['id'] }.max || 0
  combat_id = [max_id + 1, enemy_id].max + 1000
  combat_id = max_id + 1 if combat_id <= max_id

  character = CharacterSheet.new(enemy)
  combat_data['participants'] << {
    'id' => combat_id,
    'char_id' => enemy_id,
    'initiative' => '',
    'mana' => character.mana_max,
    'combat_pool' => character.combat_pool,
    'saturation' => 0,
    'minor_damage' => 0,
    'moderate_damage' => 0,
    'major_damage' => 0,
    'temporary_hit_points' => 0
  }
  Tools.save_json('combat.json', combat_data)
  redirect back
end

post '/combat/remove_enemy' do
  redirect '/character/0' unless local_request?
  combat_id = params[:combat_id].to_i
  combat_data = Tools.load_json('combat.json')
  combat_data['participants'].reject! { |p| p['id'] == combat_id }
  Tools.save_json('combat.json', combat_data)
  redirect back
end

post '/combat/clear_enemies' do
  redirect '/character/0' unless local_request?
  characters = Tools.load_json('characters.json')
  pc_ids = characters.select { |c| c['group'] == 'PC' }.map { |c| c['id'] }
  combat_data = Tools.load_json('combat.json')
  combat_data['participants'].select! { |p| pc_ids.include?(p['char_id'] || p['id']) }
  Tools.save_json('combat.json', combat_data)
  redirect back
end

post '/add_note' do
  characters = Tools.load_json('characters.json')
  notes = Tools.load_json('notes.json')

  char_id = params[:owner_id].to_i
  notes << {
    "owner_id" => char_id,
    "note" => params[:note],
    "public" => false,
    "type" => "note"
  }

  Tools.save_json('notes.json', notes)
  char_index = characters.find_index { |char| char['id'].to_i == char_id.to_i }

  redirect "/character/#{char_index}"
end

get '/add_item' do
  redirect '/character/0' unless local_request?
  @characters = Tools.load_json('characters.json')
  @item_tree = Tools.load_json('rules.json')['reference']['item_tree']
  erb :add_item
end

post '/add_item' do
  redirect '/character/0' unless local_request?

  items = Tools.load_json('equipment.json')

  # Build the new item from form params. item_id is not persisted -- it's
  # synthesized from the array position at load time.
  new_item = {
    "owner_id" => params[:owner_id].to_i,
    "name" => params[:name],
    "type" => params[:type],
    "subtype" => params[:subtype],
    "bonus" => params[:bonus].to_i,
    "properties" => {}
  }

  # Add optional fields
  new_item["quantity"] = params[:quantity].to_i if params[:quantity] && !params[:quantity].empty?
  new_item["description"] = params[:description] if params[:description] && !params[:description].empty?
  new_item["equipped"] = params[:equipped] == "true"

  items << new_item
  Tools.save_json('equipment.json', items)

  redirect '/add_item'
end

get '/notes/:viewer_id' do
  viewer_id = params[:viewer_id].to_i

  # Redirect if not local and trying to view DM notes
  redirect '/notes/1' if viewer_id == 0 && !@is_local

  @viewer_id = viewer_id
  @is_dm = viewer_id == 0 && @is_local
  @notes = Tools.load_json('notes.json')
  @characters = Tools.load_json('characters.json')
  @current_chapter = params[:chapter] ? params[:chapter].to_i : nil

  erb :notes_view
end

post '/add_note_entry' do
  notes = Tools.load_json('notes.json')

  new_note = {
    "owner_id" => params[:owner_id].to_i,
    "note" => params[:note],
    "public" => params[:public] == "true"
  }

  new_note["type"] = params[:type] if params[:type] && !params[:type].empty?
  new_note["title"] = params[:title] if params[:title] && !params[:title].empty?
  new_note["tier"] = params[:tier].to_i if params[:tier] && !params[:tier].empty?
  new_note["chapter"] = params[:chapter].to_i if params[:chapter] && !params[:chapter].empty?
  new_note["active"] = true if params[:active] == "true"

  notes << new_note
  Tools.save_json('notes.json', notes)

  redirect "/notes/#{params[:owner_id]}"
end

get '/spells' do
  compendium = Compendium.new
  @spells = compendium.data["spells"].sort_by { |name, _| name.downcase }.to_h
  @spell_schools = compendium.data["spell_schools"] || ["universal", "necromancy", "evocation", "illusion", "enchantment", "divination", "abjuration", "conjuration"]
  @range_labels = compendium.data["range"]
  @all_skills = @spells.values.flat_map { |s| s["skill"] || [] }.uniq.sort
  erb :spell_list
end

get '/spell/:name' do
  compendium = Compendium.new
  @spell_name = params[:name]
  @spell = compendium.data["spells"][@spell_name]
  @tier_index = nil

  unless @spell
    compendium.data["spells"].each do |base_name, spell_data|
      tiers = spell_data["tier"].is_a?(Array) ? spell_data["tier"] : [spell_data["tier"]]
      tiers.each_with_index do |tier_val, idx|
        variant_names = []
        variant_names << "#{spell_data["prefix"][idx]} #{base_name}" if spell_data["prefix"] && spell_data["prefix"][idx]
        variant_names << "#{base_name} #{spell_data["suffix"][idx]}" if spell_data["suffix"] && spell_data["suffix"][idx]
        if variant_names.any? { |v| v == @spell_name }
          @spell = spell_data
          @spell_name = base_name
          @tier_index = idx
          break
        end
      end
      break if @spell
    end
  end

  halt 404, "Spell not found" unless @spell
  @school = @spell["school"] || "universal"
  @range_labels = compendium.data["range"]
  erb :spell_detail
end

post '/spells/add' do
  redirect '/spells' unless local_request?
  compendium_data = Tools.load_json('compendium.json')

  tiers = params[:tiers].split(',').map(&:strip).map(&:to_i)
  tiers = tiers.length == 1 ? tiers.first : tiers

  save_val = params[:save] == "0" ? 0 : params[:save]
  skills = params[:skills].to_s.split(',').map(&:strip).reject(&:empty?)
  items = params[:items].to_s.split(',').map(&:strip).reject(&:empty?)

  compendium_data["spells"][params[:name]] = {
    "tier" => tiers,
    "save" => save_val,
    "school" => params[:school] || "universal",
    "items" => items.empty? ? [] : items,
    "range" => params[:range].to_i,
    "duration" => params[:duration] || "instant",
    "casting_time" => params[:casting_time].to_f,
    "skill" => skills,
    "properties" => [],
    "effect_hash" => {},
    "description" => params[:description]
  }

  Tools.save_json('compendium.json', compendium_data)
  redirect '/spells'
end

get '/store' do
  @store_items = Tools.load_json('store.json')
  @campaign = Tools.load_json('campaign.json')
  @characters = Tools.load_json('characters.json')
  compendium = Compendium.new
  @spell_items = compendium.spell_store_items
  @ammo_items = compendium.ammunition_store_items
  @spell_data = compendium.data["spells"]
  @item_costs = compendium.data["item_costs"]
  @property_costs = compendium.data["property_costs"] || {}
  erb :store
end

post '/purchase/:item_index' do
  store_items = Tools.load_json('store.json')
  campaign = Tools.load_json('campaign.json')
  items = Tools.load_json('equipment.json')

  compendium = Compendium.new
  if params[:item_index] == 'ammo_lookup'
    store_item = compendium.ammunition_store_items.find do |item|
      item['tier'] == params[:tier].to_i &&
      (params[:property].to_s.empty? ? !item['properties'].keys.any? { |k| k != 'consumable' } :
        item['properties'][params[:property].downcase] == true)
    end
    halt 400, "Ammunition not found" unless store_item
  elsif params[:item_index] == 'spell_lookup'
    store_item = compendium.spell_store_items.find do |item|
      item['spell'] == params[:spell_name] &&
      item['subtype'] == params[:item_type] &&
      item['tier'] == params[:tier].to_i
    end
    halt 400, "Spell item not found" unless store_item
  elsif params[:item_index].start_with?('spell_')
    spell_index = params[:item_index].sub('spell_', '').to_i
    store_item = compendium.spell_store_items[spell_index]
  elsif params[:item_index].start_with?('ammo_')
    ammo_index = params[:item_index].sub('ammo_', '').to_i
    store_item = compendium.ammunition_store_items[ammo_index]
  else
    store_item = store_items[params[:item_index].to_i]
  end

  # Build the purchase list: owner_id -> quantity. Scrolls/potions/oils submit a
  # quantities hash (one entry per PC); everything else submits a single owner_id.
  purchases = if params[:quantities].is_a?(Hash)
    params[:quantities].each_with_object({}) do |(oid, qty), acc|
      q = qty.to_i
      acc[oid.to_i] = q if q > 0
    end
  else
    oid = params[:owner_id].to_i
    oid > 0 ? { oid => 1 } : {}
  end

  if purchases.empty?
    redirect '/store?error=insufficient_gold'
    return
  end

  total_qty = purchases.values.sum
  total_cost = store_item['price'] * total_qty

  if campaign['gold'] < total_cost
    redirect '/store?error=insufficient_gold'
    return
  end

  purchases.each do |owner_id, qty|
    existing_item = items.find do |i|
      i['owner_id'] == owner_id &&
      i['name'] == store_item['name'] &&
      i['type'] == store_item['type'] &&
      i['subtype'] == store_item['subtype']
    end

    if existing_item
      existing_item['quantity'] = (existing_item['quantity'] || 1) + qty
    else
      bonus = store_item['bonus']
      if store_item['tier'] && %w[potion oil scroll].include?(store_item['subtype'])
        bonus = store_item['tier']
      end
      new_item = {
        'owner_id' => owner_id,
        'name' => store_item['name'],
        'type' => store_item['type'],
        'subtype' => store_item['subtype'],
        'bonus' => bonus,
        'properties' => store_item['properties'],
        'equipped' => false
      }
      new_item['quantity'] = qty if store_item['properties']['consumable']
      items << new_item
    end
  end

  campaign['gold'] -= total_cost

  Tools.save_json('equipment.json', items)
  Tools.save_json('campaign.json', campaign)

  redirect '/store?success=true'
end

get '/all_characters/:index' do
  redirect '/character/0' unless local_request?
  character_list = Tools.load_json('characters.json')
  load_character_view(character_list, params[:index].to_i, '/all_characters')
end
