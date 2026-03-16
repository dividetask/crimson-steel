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
    'saturation' => params[:saturation]
  }, set_keys: %w[minor_damage moderate_damage major_damage mana combat_pool saturation])
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
    Combat.add_log("Attack resolved: #{total} damage (#{minor}/#{moderate}/#{major})") if total > 0
    Combat.add_log("Attack missed") if total == 0

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

    participant['mana'] = participant['mana'].to_i - mana_cost
    if concentration
      combat_data['active_effects'] ||= []
      combat_data['active_effects'] << {
        'caster_id' => combat_id,
        'caster_name' => character.name,
        'spell_name' => spell_name,
        'spell_tier' => spell_tier,
        'round_cast' => combat_data['round']
      }
    end
    Tools.save_json('combat.json', combat_data)
    Combat.add_log("#{character.name} casts #{spell_name} (#{mana_cost} mana)")

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
    'major_damage' => 0
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

  # Build the new item from form params
  new_item = {
    "item_id" => Tools.next_item_id,
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
  @spells = compendium.data["spells"]
  @spell_schools = compendium.data["spell_schools"] || ["universal", "necromancy", "evocation", "illusion", "enchantment", "divination", "abjuration", "conjuration"]
  @range_labels = compendium.data["range"]
  @all_skills = @spells.values.flat_map { |s| s["skill"] || [] }.uniq.sort
  erb :spell_list
end

get '/spell/:name' do
  compendium = Compendium.new
  @spell_name = params[:name]
  @spell = compendium.data["spells"][@spell_name]
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

  owner_id = params[:owner_id].to_i
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

  # Check if enough gold
  if campaign['gold'] < store_item['price']
    redirect '/store?error=insufficient_gold'
    return
  end

  # Check if item already exists for this owner
  existing_item = items.find do |i|
    i['owner_id'] == owner_id &&
    i['name'] == store_item['name'] &&
    i['type'] == store_item['type'] &&
    i['subtype'] == store_item['subtype']
  end

  if existing_item
    # Increase quantity
    existing_item['quantity'] = (existing_item['quantity'] || 1) + 1
  else
    # Add new item
    bonus = store_item['bonus']
    if store_item['tier'] && %w[potion oil scroll].include?(store_item['subtype'])
      bonus = store_item['tier']
    end
    new_item = {
      'item_id' => Tools.next_item_id,
      'owner_id' => owner_id,
      'name' => store_item['name'],
      'type' => store_item['type'],
      'subtype' => store_item['subtype'],
      'bonus' => bonus,
      'properties' => store_item['properties'],
      'equipped' => false
    }
    new_item['quantity'] = 1 if store_item['properties']['consumable']
    items << new_item
  end

  # Deduct gold
  campaign['gold'] -= store_item['price']

  Tools.save_json('equipment.json', items)
  Tools.save_json('campaign.json', campaign)

  redirect '/store?success=true'
end

get '/all_characters/:index' do
  redirect '/character/0' unless local_request?
  character_list = Tools.load_json('characters.json')
  load_character_view(character_list, params[:index].to_i, '/all_characters')
end
