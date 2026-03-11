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

post '/combat/damage/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
  Combat.update(id, params.slice('minor_damage', 'moderate_damage', 'major_damage'))
  redirect '/combat'
end

post '/combat/mana/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
  Combat.update(id, {mana: -1 * params[:amount].to_i})
  redirect '/combat'
end

post '/combat/dice/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
  Combat.update(id, {combat_pool: -1 * params[:amount].to_i})
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
  char_id = params[:id].to_i
  action = params[:combat_action]

  if action == 'attack'
    dice = params[:dice].to_i
    target_turn_id = params[:target_turn_id].to_i
    weapon_item_id = params[:weapon_item_id].to_i
    participant = combat_data['participants'].find { |p| p['id'] == char_id }
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    weapon = character.equipped_list.find { |item| item['item_id'] == weapon_item_id }
    halt 400, "Weapon not found" unless weapon

    speed = character.weapon_speed(weapon)
    max_dice = character.weapon_dice(weapon)
    dice_remaining = participant['combat_pool']

    halt 400, "Invalid dice count" unless dice.is_a?(Integer) && dice >= 2 && dice <= max_dice && dice <= (dice_remaining - speed)

    participant['combat_pool'] -= (dice + speed)

    turn_index = combat.combat_turn_list.index { |ct| ct.character.id == char_id }
    combat_data['current_action'] = 'attack'
    combat_data['current_actor_turn_id'] = turn_index
    combat_data['current_action_tool_id'] = weapon_item_id
    combat_data['target_id'] = target_turn_id
    combat_data['action_params'] = { 'attack_dice' => dice }

    Tools.save_json('combat.json', combat_data)

  elsif action == 'move'
    participant = combat_data['participants'].find { |p| p['id'] == char_id }
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    halt 400, "Not enough dice to move" unless participant['combat_pool'] >= 4

    participant['combat_pool'] -= 4
    Tools.save_json('combat.json', combat_data)

    Combat.add_log("#{character.name} moves")
    Combat.clear_action

  elsif action == 'end_turn'
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    Combat.add_log("#{character.name} ends turn")
    Combat.clear_action
    Combat.advance_turn

  elsif action == 'dodge'
    dice = params[:dice].to_i
    target_char_id = params[:target_char_id].to_i
    participant = combat_data['participants'].find { |p| p['id'] == target_char_id }
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
    character = CharacterSheet.new(character_data)

    max_dice = character.bab_dice
    dice_remaining = participant['combat_pool']

    halt 400, "Invalid dice count" unless dice.is_a?(Integer) && dice >= 2 && dice <= max_dice && dice <= dice_remaining

    participant['combat_pool'] -= dice
    combat_data['current_action'] = 'dodge'

    action_params = combat_data['action_params'] || {}
    action_params['dodge_dice'] = dice
    combat_data['action_params'] = Combat.calculate_damage(
      combat_data['current_actor_turn_id'],
      combat_data['target_id'],
      combat_data['current_action_tool_id'],
      action_params
    )

    Tools.save_json('combat.json', combat_data)
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

  items = Tools.load_json('items.json')

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
  Tools.save_json('items.json', items)

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
  items = Tools.load_json('items.json')

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

  Tools.save_json('items.json', items)
  Tools.save_json('campaign.json', campaign)

  redirect '/store?success=true'
end

get '/all_characters/:index' do
  redirect '/character/0' unless local_request?
  character_list = Tools.load_json('characters.json')
  load_character_view(character_list, params[:index].to_i, '/all_characters')
end
