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

# --- Downtime ---------------------------------------------------------------

# Locate (or create) the combat.json participant record for a PC. Downtime
# reads and writes the same per-character state used during combat so the
# current HP / mana / saturation stays consistent across screens.
def downtime_find_or_create_participant(combat_data, character)
  char_id = character.id
  participant = (combat_data['participants'] ||= []).find { |p| (p['char_id'] || p['id']) == char_id }
  return participant if participant
  max_id = combat_data['participants'].map { |p| p['id'].to_i }.max || 0
  participant = {
    'id' => [max_id + 1, char_id].max,
    'char_id' => char_id,
    'initiative' => '',
    'mana' => character.mana_max,
    'combat_pool' => character.combat_pool,
    'saturation' => 0,
    'minor_damage' => 0,
    'moderate_damage' => 0,
    'major_damage' => 0,
    'temporary_hit_points' => 0
  }
  combat_data['participants'] << participant
  participant
end

# Flattened list of spell variants a character knows that resolve to a given
# base spell (e.g., "Cure" -> ["Cure Lesser Wounds", ...]).
def downtime_known_variants(character, compendium, base_name)
  (character.spell_list || []).flatten.select do |spell_name|
    resolved = compendium.resolve_spell_variant(spell_name)
    resolved && resolved[0] == base_name
  end
end

get '/downtime' do
  characters = Tools.load_json('characters.json')
  @campaign = Tools.load_json('campaign.json')
  @compendium = Compendium.new
  @pcs = characters.select { |c| c['group'] == 'PC' }.map { |c| CharacterSheet.new(c) }
  @services = @compendium.data['spellcasting_services'] || []

  # Per-PC rows: who can cast Cure / Surgery and what healing consumables they own.
  @cure_casters = @pcs.select { |pc| downtime_known_variants(pc, @compendium, 'Cure').any? }
  @surgery_casters = @pcs.select { |pc| downtime_known_variants(pc, @compendium, 'Standard Surgery').any? }

  # Consumable owner map: char_id -> [items]. Restricted to Cure potions/scrolls
  # and Standard Surgery scrolls per the downtime spec.
  @consumable_owners = {}
  @pcs.each do |pc|
    items = pc.item_list.select do |i|
      effect = @compendium.item_effects(i)
      next false unless effect
      effect[:type] == :cure || effect[:base_name] == 'Standard Surgery'
    end
    @consumable_owners[pc.id] = items unless items.empty?
  end

  erb :downtime
end

post '/downtime/cast' do
  compendium = Compendium.new
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')

  # The Cure form bundles caster + spell into a single combined field; the
  # Surgery form submits caster_id and a fixed spell_name directly.
  if params[:caster_spell].to_s.include?('|')
    caster_id_str, spell_name = params[:caster_spell].to_s.split('|', 2)
    caster_id = caster_id_str.to_i
  else
    caster_id = params[:caster_id].to_i
    spell_name = params[:spell_name].to_s
  end
  target_id = params[:target_id].to_i

  caster_data = characters.find { |c| c['id'] == caster_id }
  target_data = characters.find { |c| c['id'] == target_id }
  halt 400, "Caster not found" unless caster_data
  halt 400, "Target not found" unless target_data
  caster = CharacterSheet.new(caster_data)
  target_char = CharacterSheet.new(target_data)

  caster_p = downtime_find_or_create_participant(combat_data, caster)
  target_p = downtime_find_or_create_participant(combat_data, target_char)

  resolved = compendium.resolve_spell_variant(spell_name)
  halt 400, "Unknown spell" unless resolved
  _base, _spell_data, _idx, tier_val = resolved
  mana_cost = tier_val.to_i == 0 ? 1 : (tier_val.to_i * 2 + 2)
  halt 400, "Not enough mana" unless caster_p['mana'].to_i >= mana_cost

  if resolved[0] == 'Standard Surgery'
    successes = params[:successes].to_i
    halt 400, "Surgery requires non-negative successes" if successes < 0

    # Start of spell: target loses all temp HP and gains moderate = 2 * major.
    major_before = target_p['major_damage'].to_i
    target_p['moderate_damage'] = target_p['moderate_damage'].to_i + (2 * major_before)
    target_p['temporary_hit_points'] = 0

    healed_major = [successes, major_before].min
    target_p['major_damage'] = major_before - healed_major

    # Saturation: 10 per major cured, with a minimum of 5 per major cured.
    # improved_healing reduces saturation by 2 * caster_tier. Min is never
    # reducible below the (5 * successes) floor.
    per = 10
    min_per = 5
    base_sat = per * healed_major
    min_sat = min_per * healed_major
    sat_add = base_sat
    sat_add -= 2 * caster.tier if caster.ability_list.include?('improved_healing')
    sat_add = min_sat if sat_add < min_sat
    target_p['saturation'] = target_p['saturation'].to_i + sat_add

    caster_p['mana'] = caster_p['mana'].to_i - mana_cost
    Tools.save_json('combat.json', combat_data)
    Combat.add_log("#{caster.name} casts #{spell_name} on #{target_char.name} (#{mana_cost} mana) - cured #{healed_major} major (+2*#{major_before} moderate), +#{sat_add} saturation")
    redirect '/downtime'
  end

  cure = compendium.cure_effects(spell_name)
  halt 400, "Spell not supported in downtime" unless cure

  max_saturation = target_char.cha
  current_saturation = target_p['saturation'].to_i
  halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if current_saturation >= max_saturation

  healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target_p, cure)
  sat_add = cure[:saturation] - target_char.tier
  sat_add -= 2 * caster.tier if caster.ability_list.include?('improved_healing')
  sat_add = cure[:minimum_saturation] if sat_add < cure[:minimum_saturation]
  target_p['saturation'] = current_saturation + sat_add

  caster_p['mana'] = caster_p['mana'].to_i - mana_cost
  Tools.save_json('combat.json', combat_data)
  Combat.add_log("#{caster.name} casts #{spell_name} on #{target_char.name} (#{mana_cost} mana) - healed #{healed_major}/#{healed_moderate}/#{healed_minor} (major/moderate/minor), +#{sat_add} saturation")
  redirect '/downtime'
end

post '/downtime/use_item' do
  compendium = Compendium.new
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')

  if params[:owner_item].to_s.include?('|')
    owner_id_str, item_id_str = params[:owner_item].to_s.split('|', 2)
    owner_id = owner_id_str.to_i
    item_id = item_id_str.to_i
  else
    owner_id = params[:owner_id].to_i
    item_id = params[:item_id].to_i
  end
  target_id = params[:target_id].to_i

  owner_data = characters.find { |c| c['id'] == owner_id }
  target_data = characters.find { |c| c['id'] == target_id }
  halt 400, "Owner not found" unless owner_data
  halt 400, "Target not found" unless target_data
  owner = CharacterSheet.new(owner_data)
  target_char = CharacterSheet.new(target_data)

  item = owner.item_list.find { |i| i['item_id'].to_i == item_id }
  halt 400, "Item not found" unless item
  effect = compendium.item_effects(item)
  halt 400, "This item cannot be used" unless effect

  target_p = downtime_find_or_create_participant(combat_data, target_char)
  max_saturation = target_char.cha
  current_saturation = target_p['saturation'].to_i
  at_max = current_saturation >= max_saturation
  effect_log = ''

  if effect[:kind] == :potion
    halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max
    potion_sat = Compendium.potion_saturation(effect[:item_tier], target_char.tier)
    case effect[:type]
    when :cure
      healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target_p, effect)
      cure_sat = effect[:saturation] - target_char.tier
      cure_sat = effect[:minimum_saturation] if cure_sat < effect[:minimum_saturation]
      total_sat = cure_sat + potion_sat
      target_p['saturation'] = current_saturation + total_sat
      effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{total_sat} saturation (#{cure_sat} cure + #{potion_sat} potion)"
    when :mana
      target_max_mana = target_char.mana_max
      current_mana = target_p['mana'].to_i
      new_mana = [current_mana + effect[:mana], target_max_mana].min
      target_p['mana'] = new_mana
      target_p['saturation'] = current_saturation + potion_sat
      effect_log = "mana #{current_mana} -> #{new_mana}, +#{potion_sat} saturation"
    when :ward
      current_temp = target_p['temporary_hit_points'].to_i
      new_temp = [current_temp, effect[:temp_hp]].max
      target_p['temporary_hit_points'] = new_temp
      target_p['saturation'] = current_saturation + potion_sat
      effect_log = "temp HP #{current_temp} -> #{new_temp}, +#{potion_sat} saturation"
    end
  elsif effect[:kind] == :scroll
    case effect[:type]
    when :cure
      halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max
      healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target_p, effect)
      sat_add = effect[:saturation] - target_char.tier
      sat_add -= 2 * owner.tier if owner.ability_list.include?('improved_healing')
      sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
      target_p['saturation'] = current_saturation + sat_add
      effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{sat_add} saturation"
    when :mana
      halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max
      target_max_mana = target_char.mana_max
      current_mana = target_p['mana'].to_i
      new_mana = [current_mana + effect[:mana], target_max_mana].min
      target_p['mana'] = new_mana
      sat_add = effect[:saturation] - target_char.tier
      sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
      target_p['saturation'] = current_saturation + sat_add
      effect_log = "mana #{current_mana} -> #{new_mana}, +#{sat_add} saturation"
    when :ward
      current_temp = target_p['temporary_hit_points'].to_i
      new_temp = [current_temp, effect[:temp_hp]].max
      target_p['temporary_hit_points'] = new_temp
      effect_log = "temp HP #{current_temp} -> #{new_temp}"
    when :generic
      effect_log = "used #{effect[:variant_name] || item['name']} (no implemented effect)"
    end
  end

  # Consume one charge (same bookkeeping as combat /item).
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
    chars = Tools.load_json('characters.json')
    owner_rec = chars.find { |c| c['id'] == owner_id }
    if owner_rec && owner_rec['items']
      inline_idx = -item['item_id'].to_i - 1
      if inline_idx >= 0 && inline_idx < owner_rec['items'].length
        inline = owner_rec['items'][inline_idx]
        inline['quantity'] = (inline['quantity'] || 1) - 1
        owner_rec['items'].delete_at(inline_idx) if inline['quantity'] <= 0
        Tools.save_json('characters.json', chars)
      end
    end
  end

  Tools.save_json('combat.json', combat_data)
  Combat.add_log("#{owner.name} uses #{item['name']} on #{target_char.name} - #{effect_log}")
  redirect '/downtime'
end

post '/downtime/service' do
  redirect '/downtime' unless local_request?
  compendium = Compendium.new
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')
  campaign = Tools.load_json('campaign.json')

  service_index = params[:service_index].to_i
  target_id = params[:target_id].to_i
  services = compendium.data['spellcasting_services'] || []
  service = services[service_index]
  halt 400, "Service not found" unless service

  target_data = characters.find { |c| c['id'] == target_id }
  halt 400, "Target not found" unless target_data
  target_char = CharacterSheet.new(target_data)
  target_p = downtime_find_or_create_participant(combat_data, target_char)

  cost = service['cost'].to_i
  halt 400, "Not enough gold (have #{campaign['gold']}, need #{cost})" if campaign['gold'].to_i < cost

  cure = compendium.cure_effects(service['spell'])
  halt 400, "Service spell is not a cure" unless cure

  max_saturation = target_char.cha
  current_saturation = target_p['saturation'].to_i
  halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if current_saturation >= max_saturation

  healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target_p, cure)
  sat_add = cure[:saturation] - target_char.tier
  # Cleric casters always have improved_healing (class ability at level 1);
  # druids do not. Any other class is treated as having no improved_healing.
  sat_add -= 2 * service['tier'].to_i if service['class'].to_s == 'cleric'
  sat_add = cure[:minimum_saturation] if sat_add < cure[:minimum_saturation]
  target_p['saturation'] = current_saturation + sat_add

  campaign['gold'] = campaign['gold'].to_i - cost
  Tools.save_json('combat.json', combat_data)
  Tools.save_json('campaign.json', campaign)
  label = "#{service['spell']} (#{service['title']})"
  Combat.add_log("#{target_char.name} paid #{cost}g for #{label} service - healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{sat_add} saturation")
  redirect '/downtime'
end

# Number of recovery periods a `days` span covers for a given unit. The
# "week"/"month" thresholds only kick in once the party has rested a full
# 7 / 28 days -- partial weeks or months yield zero week/month benefit (per
# the campaign rules). Hours count as `days * 24` since a day is always
# more than 24 hours of rest.
def downtime_period_count(days, unit)
  case unit.to_s
  when 'hour'  then days * 24
  when 'day'   then days
  when 'week'  then days >= 7  ? (days / 7)  : 0
  when 'month' then days >= 28 ? (days / 28) : 0
  else 0
  end
end

post '/downtime/rest' do
  redirect '/downtime' unless local_request?
  rules = Tools.load_json('rules.json')
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')

  mode = params[:mode].to_s
  days = params[:days].to_i
  halt 400, "Days must be positive" if days <= 0
  use_high = mode == 'long_term_recovery'

  heal_rate = rules['advancement']['natural']['heal_rate']
  pc_list = characters.select { |c| c['group'] == 'PC' }

  summary_lines = []
  pc_list.each do |char_data|
    character = CharacterSheet.new(char_data)
    participant = downtime_find_or_create_participant(combat_data, character)
    tier = character.tier

    # Per-PC heal rows = 3 entries (minor / moderate / major), each [low, high, unit].
    row_base = tier * 3
    rows = [heal_rate[row_base], heal_rate[row_base + 1], heal_rate[row_base + 2]]
    keys = %w[minor_damage moderate_damage major_damage]
    healed = [0, 0, 0]
    rows.each_with_index do |row, i|
      next unless row
      low, high, unit = row
      per = use_high ? high.to_i : low.to_i
      periods = downtime_period_count(days, unit)
      amt = per * periods
      before = participant[keys[i]].to_i
      after = [before - amt, 0].max
      healed[i] = before - after
      participant[keys[i]] = after
    end

    # Mana regen: floor(mana_max/4) per day, clamped to mana_max.
    mana_per_day = (character.mana_max.to_i / 4).to_i
    new_mana = [participant['mana'].to_i + mana_per_day * days, character.mana_max.to_i].min
    mana_gained = new_mana - participant['mana'].to_i
    participant['mana'] = new_mana

    # Saturation: floor(cha/4) per day, floored at 0.
    sat_per_day = (character.cha.to_i / 4).to_i
    sat_before = participant['saturation'].to_i
    sat_after = [sat_before - sat_per_day * days, 0].max
    sat_lost = sat_before - sat_after
    participant['saturation'] = sat_after

    summary_lines << "#{character.name}: -#{healed[0]}/#{healed[1]}/#{healed[2]} damage, +#{mana_gained} mana, -#{sat_lost} saturation"
  end

  Tools.save_json('combat.json', combat_data)
  label = use_high ? 'Long-term recovery' : 'Pass time'
  Combat.add_log("#{label} for #{days} day#{'s' if days != 1}: #{summary_lines.join('; ')}")
  redirect '/downtime'
end

get '/all_characters/:index' do
  redirect '/character/0' unless local_request?
  character_list = Tools.load_json('characters.json')
  load_character_view(character_list, params[:index].to_i, '/all_characters')
end
