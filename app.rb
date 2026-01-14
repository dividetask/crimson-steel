require 'sinatra'
require 'json'
require_relative 'helpers'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')

helpers CharacterHelpers

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
	Combat.update(id, {combat_pool:  -1 * params[:amount].to_i})
  redirect '/combat'
end

post '/combat/sat/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
	Combat.update(id, {saturation: params[:amount]})
  redirect '/combat'
end

post '/combat/reset_dice' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
	combat.new_turn
  redirect '/combat'
end

post '/combat/reroll_init' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
	combat.reroll_init
  redirect '/combat'
end

def local_request?
  request.ip == "127.0.0.1" || request.ip == "::1" || request.ip == "localhost"
end

get '/' do
  redirect '/character/0'
end

get '/character/:index' do
  character_list = Tools.load_json('characters.json').select { |character| character["group"] == "PC" }

  halt 404, "No characters found" if character_list.empty?
  index = params[:index].to_i

  # Wrap around if index is out of bounds
  index = index % character_list.length

  @total_characters = character_list.length
  @prev_index = (index - 1) % character_list.length
  @next_index = (index + 1) % character_list.length

  @character = get_info(character_list[index])
	@compendium = Compendium.new

  @current_index = index
  @route_prefix = '/character'

  erb :character_sheet
end

post '/add_note' do
  characters = Tools.load_json('characters.json')
  notes = Tools.load_json('notes.json')
  
  char_id = params[:owner_id].to_i
  notes << {
    "owner_id" => char_id,
    "note" => params[:note]
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
  redirect '/notes/1' if viewer_id == 0 && !local_request?
  
  @viewer_id = viewer_id
  @is_dm = viewer_id == 0 && local_request?
  @notes = Tools.load_json('notes.json')
  @characters = Tools.load_json('characters.json')
  
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
  
  notes << new_note
  Tools.save_json('notes.json', notes)
  
  redirect "/notes/#{params[:owner_id]}"
end


get '/all_characters/:index' do
  redirect '/character/0' unless local_request?
  character_list = Tools.load_json('characters.json')

  halt 404, "No characters found" if character_list.empty?
  index = params[:index].to_i

  # Wrap around if index is out of bounds
  index = index % character_list.length

  @total_characters = character_list.length
  @prev_index = (index - 1) % character_list.length
  @next_index = (index + 1) % character_list.length

  @character = get_info(character_list[index])
	@compendium = Compendium.new

  @current_index = index
  @route_prefix = '/all_characters'

  erb :character_sheet
end
